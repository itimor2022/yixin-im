<#
.SYNOPSIS
执行 Android P3 核心消息、弱网恢复和设备侧连通性 smoke。

.DESCRIPTION
使用双测试账号准备 API 数据，并按需操作 Android 设备验证消息、未读和弱网恢复。
启用 -ForceNetworkToggle 时会切换设备网络，可能中断设备上其他正在运行的任务。

.PARAMETER SkipDevice
只执行后端断言，不操作 Android 设备。

.PARAMETER SkipWeakNetwork
跳过网络中断与恢复场景。

.PARAMETER ForceNetworkToggle
允许脚本主动切换设备网络状态。

.EXAMPLE
pwsh -File scripts/p3_android_core_smoke.ps1 -Device emulator-5554 -SkipWeakNetwork
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Adb = "",
    [string]$Device = "",
    [string]$PackageName = "com.genericim.app",
    [string]$DeviceHealthUrl = "",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$OutputDir = "",
    [switch]$SkipDevice,
    [switch]$SkipWeakNetwork,
    [switch]$ForceNetworkToggle
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:BaseUrl = $BaseUrl.TrimEnd("/")
$script:RunId = (Get-Date).ToString("yyyyMMdd-HHmmss")
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = "artifacts\qa-reports\p3-android-core-smoke-$script:RunId"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = "",
        [object]$Artifacts = @(),
        [object]$Assertions = @{}
    )
    $script:Results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        artifacts = @($Artifacts)
        assertions = $Assertions
    }) | Out-Null
}

function Join-ApiUrl {
    param([string]$Path)
    return "$script:BaseUrl$Path"
}

function ConvertTo-CompactJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 40 -Compress)
}

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int]$TimeoutSec = 30
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Method = $Method
        Uri = (Join-ApiUrl -Path $Path)
        Headers = $headers
        TimeoutSec = $TimeoutSec
    }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }

    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            return Invoke-RestMethod @params
        } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $detail = "$detail $($_.ErrorDetails.Message)"
            }
            if ($detail -match '"code"\s*:\s*429' -or $detail -match '\b429\b') {
                Start-Sleep -Seconds ([Math]::Min(20, $attempt * 3))
                continue
            }
            throw "$Method $Path failed: $detail"
        }
    }
    throw "$Method $Path failed after retries"
}

function Assert-ApiOk {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response) {
        throw "$Action failed: empty response"
    }
    if ([int]$Response.code -ne 0) {
        throw "$Action failed: code=$($Response.code) message=$($Response.message)"
    }
}

function New-LoginBody {
    param([string]$Username, [string]$DeviceSuffix)
    return @{
        username = $Username
        password = $Password
        device_id = "p3-core-smoke-$DeviceSuffix-$Username"
        device_type = "android"
        device_name = "P3 Core Smoke"
    }
}

function Login-Or-Register {
    param([string]$Username, [string]$DeviceSuffix)

    $body = New-LoginBody -Username $Username -DeviceSuffix $DeviceSuffix
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) {
        return $login
    }

    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "p3-core-smoke-$DeviceSuffix-$Username"
        device_type = "android"
        device_name = "P3 Core Smoke"
    }
    Assert-ApiOk -Response $register -Action "register $Username"

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-ApiOk -Response $login -Action "login $Username"
    return $login
}

function Find-MessageByMsgId {
    param([object[]]$Messages, [string]$MsgId)
    foreach ($message in @($Messages)) {
        if ([string]$message.msg_id -eq $MsgId) {
            return $message
        }
    }
    return $null
}

function Wait-ForMessageStatus {
    param(
        [string]$Token,
        [string]$ChatId,
        [string]$MsgId,
        [int]$MinStatus,
        [int]$TimeoutSeconds = 12
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $list = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($ChatId))&limit=80" -Token $Token
        Assert-ApiOk -Response $list -Action "list messages for status"
        $message = Find-MessageByMsgId -Messages @($list.data) -MsgId $MsgId
        if ($null -ne $message -and [int]$message.status -ge $MinStatus) {
            return $message
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    $lastStatus = if ($null -ne $message) { [string]$message.status } else { "missing" }
    throw "message $MsgId did not reach status >= $MinStatus, last=$lastStatus"
}

function New-TestWavFile {
    param([string]$Path, [int]$DurationMs = 800)

    $sampleRate = 8000
    $channels = 1
    $bitsPerSample = 16
    $samples = [int]($sampleRate * $DurationMs / 1000)
    $dataSize = $samples * $channels * ($bitsPerSample / 8)
    $byteRate = $sampleRate * $channels * ($bitsPerSample / 8)
    $blockAlign = $channels * ($bitsPerSample / 8)

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
        $writer.Write([int](36 + $dataSize))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
        $writer.Write([int]16)
        $writer.Write([int16]1)
        $writer.Write([int16]$channels)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]$byteRate)
        $writer.Write([int16]$blockAlign)
        $writer.Write([int16]$bitsPerSample)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
        $writer.Write([int]$dataSize)
        for ($i = 0; $i -lt $samples; $i++) {
            $phase = 2.0 * [Math]::PI * 440.0 * $i / $sampleRate
            $sample = [int16]([Math]::Sin($phase) * 1800)
            $writer.Write($sample)
        }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Invoke-UploadVoice {
    param([string]$Token, [string]$FilePath, [int]$DurationMs)

    $headers = @{ Authorization = "Bearer $Token" }
    try {
        return Invoke-RestMethod `
            -Method Post `
            -Uri (Join-ApiUrl -Path "/api/v1/upload/voice") `
            -Headers $headers `
            -Form @{ file = Get-Item -LiteralPath $FilePath; duration = "$DurationMs" } `
            -TimeoutSec 45
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = "$detail $($_.ErrorDetails.Message)"
        }
        throw "upload voice failed: $detail"
    }
}

function Resolve-MediaUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return ""
    }
    if ($Url -match '^https?://') {
        return $Url
    }
    if ($Url.StartsWith("/")) {
        return "$script:BaseUrl$Url"
    }
    return "$script:BaseUrl/$Url"
}

function Test-ApiCoreSmoke {
    $apiState = [ordered]@{}

    $health = Invoke-RestMethod -Uri (Join-ApiUrl -Path "/health") -TimeoutSec 10
    if ([string]$health.status -ne "ok") {
        throw "backend health is not ok: $(ConvertTo-CompactJson -Value $health)"
    }
    Add-Result -Name "backend health" -Status "PASS" -Detail "Health endpoint returned ok."

    $alice = Login-Or-Register -Username $AliceUsername -DeviceSuffix "alice"
    $bob = Login-Or-Register -Username $BobUsername -DeviceSuffix "bob"
    $aliceToken = [string]$alice.data.token
    $bobToken = [string]$bob.data.token
    $aliceUUID = [string]$alice.data.user.uuid
    $bobUUID = [string]$bob.data.user.uuid
    if ([string]::IsNullOrWhiteSpace($aliceToken) -or [string]::IsNullOrWhiteSpace($bobToken)) {
        throw "login did not return both tokens"
    }
    Add-Result -Name "api login" -Status "PASS" -Detail "Alice and Bob login/register succeeded." -Assertions @{
        alice_uuid = $aliceUUID
        bob_uuid = $bobUUID
    }

    $chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
        type = 1
        member_ids = @($bobUUID)
    }
    Assert-ApiOk -Response $chat -Action "create private chat"
    $chatId = [string]$chat.data.uuid
    if ([string]::IsNullOrWhiteSpace($chatId)) {
        throw "create private chat did not return data.uuid"
    }
    Add-Result -Name "private chat" -Status "PASS" -Detail "Private chat ready: $chatId"

    $textMsgId = [guid]::NewGuid().ToString()
    $text = "p3 text $script:RunId"
    $sendText = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = $chatId
        type = 1
        msg_id = $textMsgId
        content = @{ text = $text }
    }
    Assert-ApiOk -Response $sendText -Action "send text message"

    $bobList = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=80" -Token $bobToken
    Assert-ApiOk -Response $bobList -Action "bob list text message"
    $bobTextMessage = Find-MessageByMsgId -Messages @($bobList.data) -MsgId $textMsgId
    if ($null -eq $bobTextMessage -or [string]$bobTextMessage.content.text -ne $text) {
        throw "Bob message list did not include Alice text message."
    }
    Add-Result -Name "text message" -Status "PASS" -Detail "Alice sent text and Bob listed it." -Assertions @{
        message_id = $textMsgId
        seq = [int]$bobTextMessage.seq
    }

    $delivered = Wait-ForMessageStatus -Token $aliceToken -ChatId $chatId -MsgId $textMsgId -MinStatus 2
    Add-Result -Name "delivered status" -Status "PASS" -Detail "Bob listing the chat upgraded Alice message to delivered." -Assertions @{
        message_id = $textMsgId
        status = [int]$delivered.status
    }

    $read = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/read" -Token $bobToken -Body @{
        chat_id = $chatId
        msg_seq = [int]$bobTextMessage.seq
    }
    Assert-ApiOk -Response $read -Action "bob mark text read"
    $readMessage = Wait-ForMessageStatus -Token $aliceToken -ChatId $chatId -MsgId $textMsgId -MinStatus 3
    Add-Result -Name "read status" -Status "PASS" -Detail "Bob read receipt upgraded Alice message to read." -Assertions @{
        message_id = $textMsgId
        status = [int]$readMessage.status
    }

    $voiceFile = Join-Path $OutputDir "p3-smoke-voice.wav"
    New-TestWavFile -Path $voiceFile -DurationMs 800
    $upload = Invoke-UploadVoice -Token $aliceToken -FilePath $voiceFile -DurationMs 800
    Assert-ApiOk -Response $upload -Action "upload voice"
    $voiceUrl = [string]$upload.data.url
    $voiceSize = [int64]$upload.data.size
    if ([string]::IsNullOrWhiteSpace($voiceUrl) -or $voiceSize -le 0) {
        throw "voice upload response is missing url/size"
    }

    $resolvedVoiceUrl = Resolve-MediaUrl -Url $voiceUrl
    $voiceProbePath = Join-Path $OutputDir "voice-download-headers.txt"
    try {
        $voiceResponse = Invoke-WebRequest -Uri $resolvedVoiceUrl -Method Get -TimeoutSec 20
        "status=$([int]$voiceResponse.StatusCode)`nlength=$($voiceResponse.RawContentLength)`nurl=$resolvedVoiceUrl" |
            Set-Content -Encoding UTF8 -LiteralPath $voiceProbePath
    } catch {
        throw "uploaded voice URL is not downloadable: $($_.Exception.Message)"
    }

    $voiceMsgId = [guid]::NewGuid().ToString()
    $sendVoice = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = $chatId
        type = 4
        msg_id = $voiceMsgId
        content = @{
            voice = @{
                url = $voiceUrl
                duration = 800
                size = $voiceSize
            }
        }
    }
    Assert-ApiOk -Response $sendVoice -Action "send voice message"

    $bobVoiceList = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=80" -Token $bobToken
    Assert-ApiOk -Response $bobVoiceList -Action "bob list voice message"
    $bobVoiceMessage = Find-MessageByMsgId -Messages @($bobVoiceList.data) -MsgId $voiceMsgId
    if ($null -eq $bobVoiceMessage -or [string]$bobVoiceMessage.content.voice.url -ne $voiceUrl) {
        throw "Bob message list did not include Alice voice message."
    }
    Add-Result -Name "voice upload and message" -Status "PASS" -Detail "Voice file uploaded, downloaded, sent, and listed by Bob." -Artifacts @($voiceFile, $voiceProbePath) -Assertions @{
        message_id = $voiceMsgId
        url = $voiceUrl
        size = $voiceSize
        duration = 800
    }

    $apiState["alice_token"] = $aliceToken
    $apiState["bob_token"] = $bobToken
    $apiState["alice_uuid"] = $aliceUUID
    $apiState["bob_uuid"] = $bobUUID
    $apiState["chat_id"] = $chatId
    $apiState["text_message_id"] = $textMsgId
    $apiState["voice_message_id"] = $voiceMsgId
    $apiState["text"] = $text
    return [pscustomobject]$apiState
}

function Invoke-Process {
    param([string]$FileName, [string[]]$Arguments, [int]$TimeoutSeconds = 30)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    foreach ($arg in $Arguments) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($psi)
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        return [pscustomobject]@{
            ExitCode = 124
            Out = $outTask.GetAwaiter().GetResult()
            Err = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())"
        }
    }
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Out = $outTask.GetAwaiter().GetResult()
        Err = $errTask.GetAwaiter().GetResult()
    }
}

function Get-AdbCommand {
    if (-not [string]::IsNullOrWhiteSpace($Adb) -and (Test-Path -LiteralPath $Adb)) {
        return (Resolve-Path -LiteralPath $Adb).Path
    }

    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @()
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe") }
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe") }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe") }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return ""
}

function Resolve-Device {
    param([string]$AdbPath)
    $devices = Invoke-Process -FileName $AdbPath -Arguments @("devices") -TimeoutSeconds 15
    if ($devices.ExitCode -ne 0) {
        throw "adb devices failed: $($devices.Err)"
    }
    $online = @(
        ($devices.Out -split "`r?`n") |
            Where-Object { $_ -match "\tdevice$" } |
            ForEach-Object { ($_ -split "\s+")[0] }
    )
    if (-not [string]::IsNullOrWhiteSpace($Device)) {
        if ($online -contains $Device) {
            return $Device
        }
        throw "device '$Device' is not online. Online devices: $($online -join ', ')"
    }
    if ($online.Count -eq 0) {
        throw "no online Android device"
    }
    return $online[0]
}

function Invoke-Adb {
    param([string]$AdbPath, [string]$Serial, [string[]]$AdbArgs, [int]$TimeoutSeconds = 30)
    return Invoke-Process -FileName $AdbPath -Arguments (@("-s", $Serial) + $AdbArgs) -TimeoutSeconds $TimeoutSeconds
}

function Save-DeviceText {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Text | Set-Content -Encoding UTF8 -LiteralPath $Path
    return $Path
}

function Save-UiDump {
    param([string]$AdbPath, [string]$Serial, [string]$Name)
    $remote = "/sdcard/$Name.xml"
    $local = Join-Path $OutputDir "$Name.xml"
    [void](Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("shell", "uiautomator", "dump", $remote) -TimeoutSeconds 20)
    [void](Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 20)
    return $local
}

function Save-Screenshot {
    param([string]$AdbPath, [string]$Serial, [string]$Name)
    $remote = "/sdcard/$Name.png"
    $local = Join-Path $OutputDir "$Name.png"
    [void](Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("shell", "screencap", "-p", $remote) -TimeoutSeconds 20)
    [void](Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 20)
    return $local
}

function Test-DeviceHealth {
    param([string]$AdbPath, [string]$Serial, [string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }
    $probe = Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("shell", "curl", "-s", "-m", "4", $Url) -TimeoutSeconds 10
    if ($probe.ExitCode -ne 0) {
        return $null
    }
    return ($probe.Out -match '"status"\s*:\s*"ok"' -or $probe.Out -match '"status"\s*:\s*"?ok"?')
}

function Wait-DeviceHealth {
    param([string]$AdbPath, [string]$Serial, [string]$Url, [bool]$Expected, [int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $health = Test-DeviceHealth -AdbPath $AdbPath -Serial $Serial -Url $Url
        if ($null -ne $health -and $health -eq $Expected) {
            return $true
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Set-DeviceNetwork {
    param([string]$AdbPath, [string]$Serial, [bool]$Enabled)
    $mode = if ($Enabled) { "enable" } else { "disable" }
    [void](Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("shell", "svc", "wifi", $mode) -TimeoutSeconds 10)
    [void](Invoke-Adb -AdbPath $AdbPath -Serial $Serial -AdbArgs @("shell", "svc", "data", $mode) -TimeoutSeconds 10)
}

function Test-DeviceSmoke {
    param([object]$ApiState)

    if ($SkipDevice) {
        Add-Result -Name "device smoke" -Status "WARN" -Detail "Skipped by -SkipDevice."
        return
    }

    $adbPath = Get-AdbCommand
    if ([string]::IsNullOrWhiteSpace($adbPath)) {
        Add-Result -Name "device smoke" -Status "WARN" -Detail "adb not found; API smoke still completed."
        return
    }

    try {
        $serial = Resolve-Device -AdbPath $adbPath
        $manufacturer = (Invoke-Adb -AdbPath $adbPath -Serial $serial -AdbArgs @("shell", "getprop", "ro.product.manufacturer")).Out.Trim()
        $model = (Invoke-Adb -AdbPath $adbPath -Serial $serial -AdbArgs @("shell", "getprop", "ro.product.model")).Out.Trim()
        $android = (Invoke-Adb -AdbPath $adbPath -Serial $serial -AdbArgs @("shell", "getprop", "ro.build.version.release")).Out.Trim()
        $deviceInfoPath = Join-Path $OutputDir "device-info.json"
        [pscustomobject]@{
            serial = $serial
            manufacturer = $manufacturer
            model = $model
            android = $android
        } | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $deviceInfoPath

        [void](Invoke-Adb -AdbPath $adbPath -Serial $serial -AdbArgs @("shell", "logcat", "-c") -TimeoutSeconds 10)
        [void](Invoke-Adb -AdbPath $adbPath -Serial $serial -AdbArgs @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 10)
        [void](Invoke-Adb -AdbPath $adbPath -Serial $serial -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 15)
        Start-Sleep -Seconds 6
        $screen = Save-Screenshot -AdbPath $adbPath -Serial $serial -Name "device-launch-$script:RunId"
        $ui = Save-UiDump -AdbPath $adbPath -Serial $serial -Name "device-launch-$script:RunId"
        Add-Result -Name "device launch" -Status "PASS" -Detail "$manufacturer $model Android $android launched $PackageName." -Artifacts @($deviceInfoPath, $screen, $ui)

        if ($SkipWeakNetwork) {
            Add-Result -Name "weak network resume" -Status "WARN" -Detail "Skipped by -SkipWeakNetwork."
            return
        }
        if ([string]::IsNullOrWhiteSpace($DeviceHealthUrl)) {
            Add-Result -Name "weak network resume" -Status "WARN" -Detail "DeviceHealthUrl not provided; pass a device-reachable /health URL for network restore checks."
            return
        }
        if ($serial -match ':' -and -not $ForceNetworkToggle) {
            Add-Result -Name "weak network resume" -Status "WARN" -Detail "Device serial looks like TCP adb; network toggle skipped unless -ForceNetworkToggle is set."
            return
        }

        $initialHealth = Test-DeviceHealth -AdbPath $adbPath -Serial $serial -Url $DeviceHealthUrl
        if ($initialHealth -ne $true) {
            Add-Result -Name "weak network resume" -Status "WARN" -Detail "Device could not reach DeviceHealthUrl before toggle: $DeviceHealthUrl"
            return
        }

        $networkMessageText = "p3 weak network $script:RunId"
        $networkMsgId = [guid]::NewGuid().ToString()
        $offConfirmed = $false
        $restored = $false
        try {
            Set-DeviceNetwork -AdbPath $adbPath -Serial $serial -Enabled $false
            $offConfirmed = Wait-DeviceHealth -AdbPath $adbPath -Serial $serial -Url $DeviceHealthUrl -Expected $false -TimeoutSeconds 45

            $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token ([string]$ApiState.alice_token) -Body @{
                chat_id = [string]$ApiState.chat_id
                type = 1
                msg_id = $networkMsgId
                content = @{ text = $networkMessageText }
            }
            Assert-ApiOk -Response $send -Action "send weak network message"

            Set-DeviceNetwork -AdbPath $adbPath -Serial $serial -Enabled $true
            Start-Sleep -Seconds 3
            Set-DeviceNetwork -AdbPath $adbPath -Serial $serial -Enabled $true
            $restored = Wait-DeviceHealth -AdbPath $adbPath -Serial $serial -Url $DeviceHealthUrl -Expected $true -TimeoutSeconds 75
        } finally {
            try {
                Set-DeviceNetwork -AdbPath $adbPath -Serial $serial -Enabled $true
            } catch {}
        }

        $bobList = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString([string]$ApiState.chat_id))&limit=100" -Token ([string]$ApiState.bob_token)
        Assert-ApiOk -Response $bobList -Action "bob list weak network message"
        $apiVisible = ((ConvertTo-CompactJson -Value $bobList.data) -match [regex]::Escape($networkMessageText))
        $afterScreen = Save-Screenshot -AdbPath $adbPath -Serial $serial -Name "device-after-network-$script:RunId"
        $afterUi = Save-UiDump -AdbPath $adbPath -Serial $serial -Name "device-after-network-$script:RunId"

        $status = if ($offConfirmed -and $restored -and $apiVisible) { "PASS" } else { "FAIL" }
        Add-Result -Name "weak network resume" -Status $status -Detail "Network toggled off/on and API-visible message checked." -Artifacts @($afterScreen, $afterUi) -Assertions @{
            device_health_url = $DeviceHealthUrl
            network_off_confirmed = $offConfirmed
            network_restored = $restored
            api_message_visible = $apiVisible
            message_id = $networkMsgId
        }
    } catch {
        Add-Result -Name "device smoke" -Status "WARN" -Detail $_.Exception.Message
    }
}

$apiState = $null
$topLevelError = ""
try {
    $apiState = Test-ApiCoreSmoke
    Test-DeviceSmoke -ApiState $apiState
} catch {
    $topLevelError = $_.Exception.Message
    Add-Result -Name "p3 core smoke" -Status "FAIL" -Detail $topLevelError
}

$failed = @($script:Results | Where-Object { $_.status -eq "FAIL" })
$warned = @($script:Results | Where-Object { $_.status -eq "WARN" })
$overall = if ($failed.Count -gt 0) { "FAIL" } elseif ($warned.Count -gt 0) { "WARN" } else { "PASS" }

$reportApiState = $null
if ($null -ne $apiState) {
    $reportApiState = [ordered]@{
        alice_uuid = [string]$apiState.alice_uuid
        bob_uuid = [string]$apiState.bob_uuid
        chat_id = [string]$apiState.chat_id
        text_message_id = [string]$apiState.text_message_id
        voice_message_id = [string]$apiState.voice_message_id
        text = [string]$apiState.text
    }
}

$summary = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    run_id = $script:RunId
    status = $overall
    base_url = $script:BaseUrl
    package_name = $PackageName
    device = $Device
    device_health_url = $DeviceHealthUrl
    output_dir = $OutputDir
    api = $reportApiState
    error = $topLevelError
    results = @($script:Results.ToArray())
}

$jsonPath = Join-Path $OutputDir "p3-android-core-smoke-$script:RunId.json"
$summary | ConvertTo-Json -Depth 60 | Set-Content -Encoding UTF8 -LiteralPath $jsonPath

$mdPath = Join-Path $OutputDir "p3-android-core-smoke-$script:RunId.md"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# P3 Android Core Smoke") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- status: $overall") | Out-Null
$lines.Add("- run_id: $script:RunId") | Out-Null
$lines.Add("- base_url: $script:BaseUrl") | Out-Null
$lines.Add("- package_name: $PackageName") | Out-Null
$lines.Add("- output_dir: $OutputDir") | Out-Null
$lines.Add("- json: $jsonPath") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Results") | Out-Null
foreach ($result in $script:Results) {
    $lines.Add("- [$($result.status)] $($result.name): $($result.detail)") | Out-Null
}
$lines | Set-Content -Encoding UTF8 -LiteralPath $mdPath

$summary | ConvertTo-Json -Depth 60
if ($overall -eq "FAIL") {
    exit 1
}
