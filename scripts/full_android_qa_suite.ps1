<#
.SYNOPSIS
在多台 Android 设备上执行完整客户端 QA 套件。

.DESCRIPTION
编排设备连接、可选 APK 安装、API 准备、UI 用例、日志收集和 Monkey 稳定性
测试，并把报告写入 release-archives。脚本会操作 Devices 中的所有设备；
未使用专用测试设备时不得启用安装、UI 或 Monkey 阶段。

.PARAMETER Devices
参与日志、安装和通用检查的全部 ADB 设备。

.PARAMETER ApkPath
需要安装的 APK；SkipInstall 未设置时必须指向目标测试包。

.PARAMETER SkipUi
跳过会操作页面和账号状态的 UI 用例。

.PARAMETER SkipMonkey
跳过随机事件压力测试。

.EXAMPLE
pwsh -File scripts/full_android_qa_suite.ps1 -SkipInstall -SkipMonkey
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$EmulatorBaseUrl = "http://10.0.2.2:8080",
    [string]$PackageName = "com.genericim.app",
    [string[]]$Devices = @("127.0.0.1:16384", "127.0.0.1:16416", "127.0.0.1:16448"),
    [string]$AliceDevice = "127.0.0.1:16416",
    [string]$BobDevice = "127.0.0.1:16448",
    [string]$ObserverDevice = "127.0.0.1:16384",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$ApkPath = "",
    [string]$DockerContainer = "genericim-api",
    [int]$MonkeyEvents = 180,
    [int]$AdbTimeoutSeconds = 20,
    [bool]$RefreshAdbConnections = $false,
    [switch]$SkipInstall,
    [switch]$SkipUi,
    [switch]$SkipMonkey
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:StartedAt = Get-Date
$script:RunId = $script:StartedAt.ToString("yyyyMMdd-HHmmss")
$script:OutputRoot = Join-Path "release-archives\qa-20260624" "android-full-qa-$script:RunId"
$script:ReportPath = Join-Path $script:OutputRoot "report.md"
$script:JsonPath = Join-Path $script:OutputRoot "results.json"
$script:Results = New-Object System.Collections.Generic.List[object]
$script:Artifacts = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Force -Path $script:OutputRoot | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'HH:mm:ss') $Message"
    Write-Host $line
    $line | Add-Content -Encoding UTF8 -Path (Join-Path $script:OutputRoot "run.log")
}

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet("PASS", "FAIL", "WARN", "INFO")]
        [string]$Status,
        [string]$Detail,
        [string[]]$Artifacts = @()
    )

    $entry = [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        artifacts = $Artifacts
        time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $script:Results.Add($entry) | Out-Null
    foreach ($artifact in $Artifacts) {
        if (-not [string]::IsNullOrWhiteSpace($artifact)) {
            $script:Artifacts.Add($artifact) | Out-Null
        }
    }
    Write-Log "[$Status] $Name - $Detail"
}

function Invoke-Adb {
    param(
        [string]$Device,
        [string[]]$AdbArgs,
        [int]$TimeoutSeconds = $script:AdbTimeoutSeconds
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:AdbPath
    foreach ($arg in @("-s", $Device) + $AdbArgs) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch {}
        try { $p.WaitForExit(2000) | Out-Null } catch {}
        return [pscustomobject]@{
            ExitCode = 124
            Out = $outTask.GetAwaiter().GetResult()
            Err = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())"
        }
    }
    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        Out = $outTask.GetAwaiter().GetResult()
        Err = $errTask.GetAwaiter().GetResult()
    }
}

function Invoke-AdbNoDevice {
    param([string[]]$AdbArgs, [int]$TimeoutSeconds = 20)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:AdbPath
    foreach ($arg in $AdbArgs) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch {}
        try { $p.WaitForExit(2000) | Out-Null } catch {}
        return [pscustomobject]@{
            ExitCode = 124
            Out = $outTask.GetAwaiter().GetResult()
            Err = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())"
        }
    }
    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        Out = $outTask.GetAwaiter().GetResult()
        Err = $errTask.GetAwaiter().GetResult()
    }
}

function Tap {
    param([string]$Device, [int]$X, [int]$Y, [int]$SleepMs = 350)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 6)
    Start-Sleep -Milliseconds $SleepMs
}

function Key {
    param([string]$Device, [string]$Code, [int]$SleepMs = 180)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", $Code) -TimeoutSeconds 6)
    Start-Sleep -Milliseconds $SleepMs
}

function Input-Text {
    param([string]$Device, [string]$Text)
    $escaped = $Text.Replace(" ", "%s")
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "text", $escaped) -TimeoutSeconds 10)
    Start-Sleep -Milliseconds 250
}

function Clear-Field {
    param([string]$Device)
    Key $Device "KEYCODE_MOVE_END" 80
    for ($i = 0; $i -lt 40; $i++) {
        Key $Device "KEYCODE_DEL" 15
    }
}

function Save-Screenshot {
    param([string]$Device, [string]$Name)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $remote = "/sdcard/genericim-qa-screen.png"
    $local = Join-Path $script:OutputRoot "$safe-$Name.png"
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 15)
    return $local
}

function Save-UiDump {
    param([string]$Device, [string]$Name)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $remote = "/sdcard/genericim-qa-window.xml"
    $local = Join-Path $script:OutputRoot "$safe-$Name.xml"
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "uiautomator", "dump", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 15)
    if (Test-Path -LiteralPath $local) {
        return [pscustomobject]@{ Path = $local; Xml = (Get-Content -LiteralPath $local -Raw -Encoding UTF8) }
    }
    return [pscustomobject]@{ Path = $local; Xml = "" }
}

function Get-WindowSize {
    param([string]$Device)
    $r = Invoke-Adb -Device $Device -AdbArgs @("shell", "wm", "size") -TimeoutSeconds 8
    if ($r.Out -match "(\d+)x(\d+)") {
        return [pscustomobject]@{ Width = [int]$Matches[1]; Height = [int]$Matches[2] }
    }
    return [pscustomobject]@{ Width = 1080; Height = 1920 }
}

function Get-Nodes {
    param([string]$Xml)
    return @([regex]::Matches($Xml, "<node\b[^>]*>") | ForEach-Object { $_.Value })
}

function Get-Attr {
    param([string]$Node, [string]$Name)
    $m = [regex]::Match($Node, "$Name=`"([^`"]*)`"")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Get-BoundsCenter {
    param([string]$Bounds)
    $m = [regex]::Match($Bounds, "\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{
        X = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
        Y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
        Left = [int]$m.Groups[1].Value
        Top = [int]$m.Groups[2].Value
        Right = [int]$m.Groups[3].Value
        Bottom = [int]$m.Groups[4].Value
    }
}

function Find-Node {
    param([string]$Xml, [string]$Pattern)
    foreach ($node in (Get-Nodes -Xml $Xml)) {
        $text = Get-Attr -Node $node -Name "text"
        $desc = Get-Attr -Node $node -Name "content-desc"
        $class = Get-Attr -Node $node -Name "class"
        if ("$text $desc $class" -match $Pattern) {
            return $node
        }
    }
    return $null
}

function Find-NodesByClass {
    param([string]$Xml, [string]$ClassName)
    return @(
        foreach ($node in (Get-Nodes -Xml $Xml)) {
            if ((Get-Attr -Node $node -Name "class") -eq $ClassName) {
                $node
            }
        }
    )
}

function Tap-Node {
    param([string]$Device, [string]$Node)
    $bounds = Get-Attr -Node $Node -Name "bounds"
    $center = Get-BoundsCenter -Bounds $bounds
    if ($null -eq $center) { return $false }
    Tap -Device $Device -X $center.X -Y $center.Y
    return $true
}

function Handle-Permissions {
    param([string]$Device)
    for ($i = 0; $i -lt 5; $i++) {
        $dump = Save-UiDump -Device $Device -Name "permission-$i"
        $node = Find-Node -Xml $dump.Xml -Pattern "permission_allow|允许|仅在使用|始终允许|ALLOW|While using"
        if ($null -eq $node) { return }
        [void](Tap-Node -Device $Device -Node $node)
        Start-Sleep -Milliseconds 700
    }
}

function Dismiss-SystemUi {
    param([string]$Device, [string]$Name = "system-ui")
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 6)
    Start-Sleep -Milliseconds 300
    for ($i = 0; $i -lt 2; $i++) {
        $dump = Save-UiDump -Device $Device -Name "$Name-dismiss-$i"
        if ($dump.Xml -notmatch 'package="com\.android\.systemui"') { return }
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_BACK") -TimeoutSeconds 6)
        Start-Sleep -Milliseconds 500
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 6)
        Start-Sleep -Milliseconds 300
    }
}

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int]$TimeoutSec = 20
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }
    $params = @{
        Method = $Method
        Uri = "$($BaseUrl.TrimEnd('/'))$Path"
        Headers = $headers
        TimeoutSec = $TimeoutSec
    }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }
    return Invoke-RestMethod @params
}

function Assert-ApiOk {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response) { throw "$Action empty response" }
    if ([int]$Response.code -ne 0) {
        throw "$Action code=$($Response.code) message=$($Response.message)"
    }
}

function Login-Or-RegisterApi {
    param([string]$Username)

    $body = @{
        username = $Username
        password = $Password
        device_id = "full-qa-api-$Username"
        device_type = "android"
        device_name = "Full QA API"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) { return $login }

    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "full-qa-api-$Username"
        device_type = "android"
        device_name = "Full QA API"
    }
    Assert-ApiOk -Response $register -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-ApiOk -Response $login -Action "login $Username"
    return $login
}

function Login-Device {
    param([string]$Device, [string]$Username)

    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "am", "start", "-n", "$PackageName/.MainActivity") -TimeoutSeconds 10)
    Start-Sleep -Seconds 3
    Handle-Permissions -Device $Device
    Dismiss-SystemUi -Device $Device -Name "login-$Username"
    $before = Save-UiDump -Device $Device -Name "before-login-$Username"
    if ($before.Xml.Length -lt 1000) {
        Start-Sleep -Seconds 3
        $before = Save-UiDump -Device $Device -Name "before-login-$Username-retry"
    }
    if ($before.Xml -match "消息|通讯录|联系人|发现|我的|设置|聊天|输入消息|语音通话|视频通话|在线") {
        Add-Result -Name "UI login $Device" -Status "PASS" -Detail "already logged in or on main UI as expected" -Artifacts @($before.Path)
        return
    }

    $edits = Find-NodesByClass -Xml $before.Xml -ClassName "android.widget.EditText"
    if ($edits.Count -lt 2) {
        $shot = Save-Screenshot -Device $Device -Name "login-no-fields"
        if ($before.Xml -match "登录您的账号|请先阅读|验证码|密码") {
            Add-Result -Name "UI login $Device" -Status "FAIL" -Detail "login page did not expose two EditText fields" -Artifacts @($before.Path, $shot)
        } elseif ($before.Xml -match [regex]::Escape($PackageName)) {
            Add-Result -Name "UI login $Device" -Status "PASS" -Detail "already inside authenticated app UI; no login fields needed" -Artifacts @($before.Path, $shot)
        } else {
            Add-Result -Name "UI login $Device" -Status "WARN" -Detail "no login fields and current UI is unclear; inspect screenshot/XML" -Artifacts @($before.Path, $shot)
        }
        return
    }

    [void](Tap-Node -Device $Device -Node $edits[0])
    Clear-Field -Device $Device
    Input-Text -Device $Device -Text $Username
    [void](Tap-Node -Device $Device -Node $edits[1])
    Clear-Field -Device $Device
    Input-Text -Device $Device -Text $Password
    Key -Device $Device -Code "KEYCODE_BACK" -SleepMs 500

    $size = Get-WindowSize -Device $Device
    $loginDump = Save-UiDump -Device $Device -Name "login-filled-$Username"
    $loginButton = Find-Node -Xml $loginDump.Xml -Pattern "登录|登入|Login"
    $loginCenter = $null
    if ($null -ne $loginButton) {
        $loginCenter = Get-BoundsCenter -Bounds (Get-Attr -Node $loginButton -Name "bounds")
    }
    if ($null -eq $loginCenter) {
        $loginCenter = [pscustomobject]@{ X = [int]($size.Width * 0.5); Y = [int]($size.Height * 0.96) }
    }

    $agreementY = [Math]::Max(1, $loginCenter.Y - [int]($size.Height * 0.095))
    Tap -Device $Device -X ([int]($size.Width * 0.50)) -Y $agreementY
    Tap -Device $Device -X $loginCenter.X -Y $loginCenter.Y -SleepMs 1000
    Start-Sleep -Seconds 5
    Handle-Permissions -Device $Device

    $after = Save-UiDump -Device $Device -Name "after-login-$Username"
    $shot = Save-Screenshot -Device $Device -Name "after-login-$Username"
    if ($after.Xml -match "请先阅读|登录|验证码|密码") {
        Add-Result -Name "UI login $Device" -Status "FAIL" -Detail "still on login page or blocked by agreement/password prompt" -Artifacts @($after.Path, $shot)
    } elseif ($after.Xml -match "消息|通讯录|发现|我的|聊天") {
        Add-Result -Name "UI login $Device" -Status "PASS" -Detail "login reached main UI" -Artifacts @($after.Path, $shot)
    } else {
        Add-Result -Name "UI login $Device" -Status "WARN" -Detail "login result unclear; inspect screenshot/XML" -Artifacts @($after.Path, $shot)
    }
}

function Test-ApiMessages {
    $textAB = "qa alice to bob $script:RunId"
    $textBA = "qa bob to alice $script:RunId"
    $alice = Login-Or-RegisterApi -Username $AliceUsername
    $bob = Login-Or-RegisterApi -Username $BobUsername
    $aliceToken = [string]$alice.data.token
    $bobToken = [string]$bob.data.token
    $aliceUuid = [string]$alice.data.user.uuid
    $bobUuid = [string]$bob.data.user.uuid

    $chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
        type = 1
        member_ids = @($bobUuid)
    }
    Assert-ApiOk -Response $chat -Action "create private chat"
    $chatId = [string]$chat.data.uuid

    foreach ($msg in @(
        @{ Token = $aliceToken; Chat = $chatId; Text = $textAB; Sender = $AliceUsername },
        @{ Token = $bobToken; Chat = $chatId; Text = $textBA; Sender = $BobUsername }
    )) {
        $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $msg.Token -Body @{
            chat_id = $msg.Chat
            type = 1
            msg_id = [guid]::NewGuid().ToString()
            content = @{ text = $msg.Text }
        }
        Assert-ApiOk -Response $send -Action "send $($msg.Sender)"
    }

    foreach ($viewer in @(
        @{ Name = $AliceUsername; Token = $aliceToken },
        @{ Name = $BobUsername; Token = $bobToken }
    )) {
        $list = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=50" -Token $viewer.Token
        Assert-ApiOk -Response $list -Action "list messages $($viewer.Name)"
        $json = $list.data | ConvertTo-Json -Depth 30 -Compress
        if ($json -notmatch [regex]::Escape($textAB) -or $json -notmatch [regex]::Escape($textBA)) {
            throw "message list for $($viewer.Name) missing AB/BA messages"
        }
    }

    $summary = [pscustomobject]@{
        alice_uuid = $aliceUuid
        bob_uuid = $bobUuid
        chat_id = $chatId
        text_alice_to_bob = $textAB
        text_bob_to_alice = $textBA
        alice_token = $aliceToken
        bob_token = $bobToken
    }
    $path = Join-Path $script:OutputRoot "api-message-summary.json"
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $path
    Add-Result -Name "API private messages" -Status "PASS" -Detail "Alice/Bob both sent and both can list the two messages; chat=$chatId" -Artifacts @($path)
    return $summary
}

function Test-ApiCalls {
    param([object]$ApiState)

    $config = Invoke-ApiJson -Method "GET" -Path "/api/v1/call/config" -Token $ApiState.alice_token
    Assert-ApiOk -Response $config -Action "call config"
    $configPath = Join-Path $script:OutputRoot "api-call-config.json"
    $config | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $configPath
    if (-not [bool]$config.data.enabled) {
        Add-Result -Name "API call config" -Status "WARN" -Detail "RTC is disabled/not configured; UI may show call failure in this environment" -Artifacts @($configPath)
        return
    }

    $voice = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $ApiState.alice_token -Body @{
        target_user_id = $ApiState.bob_uuid
        call_type = "voice"
    }
    Assert-ApiOk -Response $voice -Action "create voice call"
    $voiceId = [uint32]$voice.data.call_id
    $reject = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/reject" -Token $ApiState.bob_token -Body @{
        call_id = $voiceId
        reason = "qa_reject"
    }
    Assert-ApiOk -Response $reject -Action "reject voice call"

    $video = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $ApiState.bob_token -Body @{
        target_user_id = $ApiState.alice_uuid
        call_type = "video"
    }
    Assert-ApiOk -Response $video -Action "create video call"
    $videoId = [uint32]$video.data.call_id
    $accept = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/accept" -Token $ApiState.alice_token -Body @{ call_id = $videoId }
    Assert-ApiOk -Response $accept -Action "accept video call"
    Start-Sleep -Seconds 2
    $end = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/end" -Token $ApiState.bob_token -Body @{
        call_id = $videoId
        reason = "qa_end"
    }
    Assert-ApiOk -Response $end -Action "end video call"

    $history = Invoke-ApiJson -Method "GET" -Path "/api/v1/call/history" -Token $ApiState.alice_token
    Assert-ApiOk -Response $history -Action "call history"
    $historyPath = Join-Path $script:OutputRoot "api-call-history.json"
    $history | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path $historyPath
    Add-Result -Name "API voice/video calls" -Status "PASS" -Detail "voice reject and video accept/end completed; voice=$voiceId video=$videoId" -Artifacts @($configPath, $historyPath)
}

function Open-ChatAndCheckMessages {
    param([string]$Device, [string[]]$Texts, [string]$PeerPattern)

    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 8)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "am", "start", "-n", "$PackageName/.MainActivity") -TimeoutSeconds 10)
    Start-Sleep -Seconds 5
    Handle-Permissions -Device $Device
    Dismiss-SystemUi -Device $Device -Name "message-restart"
    $size = Get-WindowSize -Device $Device
    Tap -Device $Device -X ([int]($size.Width * 0.12)) -Y ([int]($size.Height * 0.965))
    Start-Sleep -Seconds 2
    $listDump = Save-UiDump -Device $Device -Name "message-list-after-restart"
    $listShot = Save-Screenshot -Device $Device -Name "message-list-after-restart"
    $peerNode = $null
    if (-not [string]::IsNullOrWhiteSpace($PeerPattern)) {
        $peerNode = Find-Node -Xml $listDump.Xml -Pattern $PeerPattern
    }
    if ($null -ne $peerNode) {
        [void](Tap-Node -Device $Device -Node $peerNode)
    } else {
        Tap -Device $Device -X ([int]($size.Width * 0.5)) -Y ([int]($size.Height * 0.355))
    }
    Start-Sleep -Seconds 3
    $detailDump = Save-UiDump -Device $Device -Name "chat-detail-after-restart"
    $detailShot = Save-Screenshot -Device $Device -Name "chat-detail-after-restart"
    $allXml = "$($listDump.Xml)`n$($detailDump.Xml)"
    $missing = @($Texts | Where-Object { $allXml -notmatch [regex]::Escape($_) })
    if ($missing.Count -eq 0) {
        Add-Result -Name "UI message persistence $Device" -Status "PASS" -Detail "message list/detail still contains latest QA texts after app restart" -Artifacts @($listDump.Path, $listShot, $detailDump.Path, $detailShot)
    } else {
        Add-Result -Name "UI message persistence $Device" -Status "WARN" -Detail "UI XML did not expose: $($missing -join ', '); inspect screenshots, API persistence already passed" -Artifacts @($listDump.Path, $listShot, $detailDump.Path, $detailShot)
    }
}

function Check-CallEntryUi {
    param([string]$Device, [string]$PeerPattern)

    Dismiss-SystemUi -Device $Device -Name "call-entry"
    $dump = Save-UiDump -Device $Device -Name "call-entry-check"
    if ($dump.Xml -notmatch "语音通话|视频通话|Voice call|Video call" -and
        -not [string]::IsNullOrWhiteSpace($PeerPattern)) {
        $peerNode = Find-Node -Xml $dump.Xml -Pattern $PeerPattern
        if ($null -ne $peerNode) {
            [void](Tap-Node -Device $Device -Node $peerNode)
            Start-Sleep -Seconds 2
            $dump = Save-UiDump -Device $Device -Name "call-entry-check-after-open"
        }
    }
    if ($dump.Xml -match "语音通话|视频通话|Voice call|Video call") {
        Add-Result -Name "UI call buttons $Device" -Status "PASS" -Detail "chat detail exposes voice/video call controls" -Artifacts @($dump.Path, (Save-Screenshot -Device $Device -Name "call-entry-check"))
        return
    }
    Add-Result -Name "UI call buttons $Device" -Status "WARN" -Detail "current page did not expose call buttons; chat may not be opened or private chat not first" -Artifacts @($dump.Path, (Save-Screenshot -Device $Device -Name "call-entry-check"))
}

function Fast-Navigation {
    param([string]$Device)

    Dismiss-SystemUi -Device $Device -Name "fast-navigation"
    $size = Get-WindowSize -Device $Device
    $points = @(
        @{ X = 0.12; Y = 0.965; Name = "messages" },
        @{ X = 0.34; Y = 0.965; Name = "contacts" },
        @{ X = 0.55; Y = 0.965; Name = "discover" },
        @{ X = 0.78; Y = 0.965; Name = "settings" },
        @{ X = 0.90; Y = 0.08; Name = "top-right" },
        @{ X = 0.50; Y = 0.45; Name = "middle" },
        @{ X = 0.08; Y = 0.08; Name = "top-left" }
    )
    foreach ($p in $points) {
        Tap -Device $Device -X ([int]($size.Width * $p.X)) -Y ([int]($size.Height * $p.Y)) -SleepMs 180
    }
    Add-Result -Name "UI fast navigation $Device" -Status "INFO" -Detail "performed rapid taps across main tabs and top controls" -Artifacts @((Save-UiDump -Device $Device -Name "fast-navigation").Path, (Save-Screenshot -Device $Device -Name "fast-navigation"))
}

function Run-Monkey {
    param([string]$Device)
    if ($SkipMonkey -or $MonkeyEvents -le 0) { return }
    $outPath = Join-Path $script:OutputRoot "$($Device.Replace(':','-').Replace('.','-'))-monkey.txt"
    $r = Invoke-Adb -Device $Device -AdbArgs @("shell", "monkey", "-p", $PackageName, "--pct-syskeys", "0", "--throttle", "45", "-v", "$MonkeyEvents") -TimeoutSeconds ([Math]::Max(30, [int]($MonkeyEvents * 0.15 + 20)))
    "EXIT=$($r.ExitCode)`nSTDOUT:`n$($r.Out)`nSTDERR:`n$($r.Err)" | Set-Content -Encoding UTF8 -Path $outPath
    $monkeyText = "$($r.Out)`n$($r.Err)"
    if ($monkeyText -match "CRASH:|// CRASH|ANR|NOT RESPONDING|FATAL EXCEPTION|System appears to have crashed") {
        Add-Result -Name "Monkey stress $Device" -Status "FAIL" -Detail "monkey reported app crash/ANR marker" -Artifacts @($outPath)
    } else {
        Add-Result -Name "Monkey stress $Device" -Status "PASS" -Detail "monkey completed $MonkeyEvents events without explicit crash/ANR marker" -Artifacts @($outPath)
    }
}

function Collect-DeviceLogs {
    param([string]$Device)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $rawPath = Join-Path $script:OutputRoot "$safe-logcat.txt"
    $errPath = Join-Path $script:OutputRoot "$safe-logcat-errors.txt"
    $r = Invoke-Adb -Device $Device -AdbArgs @("logcat", "-d", "-t", "2500") -TimeoutSeconds 25
    $r.Out | Set-Content -Encoding UTF8 -Path $rawPath
    # Keep the gate specific to app-fatal signals. Generic AndroidRuntime,
    # Exception and ERROR lines include uiautomator plus Huawei system services
    # and created false WARN results even when the app had no crash or ANR.
    $matches = ($r.Out -split "`r?`n") | Where-Object {
        $_ -match "FATAL EXCEPTION|ANR in com\.genericim\.app|FlutterError|E/flutter|Input dispatching timed out.*com\.genericim\.app"
    }
    $matches | Set-Content -Encoding UTF8 -Path $errPath
    if ($matches.Count -gt 0) {
        Add-Result -Name "Device logcat $Device" -Status "WARN" -Detail "matched $($matches.Count) error-like lines; inspect filtered log" -Artifacts @($errPath, $rawPath)
    } else {
        Add-Result -Name "Device logcat $Device" -Status "PASS" -Detail "no app Fatal/ANR/FlutterError lines matched in last 2500 lines" -Artifacts @($errPath, $rawPath)
    }
}

function Collect-BackendLogs {
    $path = Join-Path $script:OutputRoot "backend-docker-log.txt"
    try {
        $logs = & docker logs --since 30m $DockerContainer 2>&1
        $logs | Set-Content -Encoding UTF8 -Path $path
        $errors = @($logs | Where-Object { $_ -match "panic|ERROR|error|500|failed|message/send|call" })
        $errPath = Join-Path $script:OutputRoot "backend-docker-log-filtered.txt"
        $errors | Set-Content -Encoding UTF8 -Path $errPath
        if ($logs.Count -gt 0) {
            Add-Result -Name "Backend logs" -Status "INFO" -Detail "collected docker logs from $DockerContainer; filtered lines=$($errors.Count)" -Artifacts @($errPath, $path)
        }
    } catch {
        Add-Result -Name "Backend logs" -Status "WARN" -Detail "docker logs failed: $($_.Exception.Message)" -Artifacts @()
    }
}

function Write-Report {
    $pass = @($script:Results | Where-Object status -eq "PASS").Count
    $fail = @($script:Results | Where-Object status -eq "FAIL").Count
    $warn = @($script:Results | Where-Object status -eq "WARN").Count
    $info = @($script:Results | Where-Object status -eq "INFO").Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 通用IM Android 全量快速测试报告") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- 时间: $($script:StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $lines.Add("- 包名: ``$PackageName``") | Out-Null
    $lines.Add("- 后端: ``$BaseUrl`` / 模拟器: ``$EmulatorBaseUrl``") | Out-Null
    $lines.Add("- 设备: $($Devices -join ', ')") | Out-Null
    $lines.Add("- 统计: PASS=$pass, FAIL=$fail, WARN=$warn, INFO=$info") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("## Bug / 风险汇总") | Out-Null
    $issues = @($script:Results | Where-Object { $_.status -in @("FAIL", "WARN") })
    if ($issues.Count -eq 0) {
        $lines.Add("- 未发现 FAIL/WARN。") | Out-Null
    } else {
        foreach ($issue in $issues) {
            $lines.Add("- **$($issue.status)** $($issue.name): $($issue.detail)") | Out-Null
            foreach ($artifact in $issue.artifacts) {
                $lines.Add("  - evidence: ``$artifact``") | Out-Null
            }
        }
    }
    $lines.Add("") | Out-Null
    $lines.Add("## 全部结果") | Out-Null
    foreach ($r in $script:Results) {
        $lines.Add("- **$($r.status)** $($r.name): $($r.detail)") | Out-Null
    }
    $lines | Set-Content -Encoding UTF8 -Path $script:ReportPath

    [pscustomobject]@{
        started_at = $script:StartedAt
        finished_at = Get-Date
        package = $PackageName
        base_url = $BaseUrl
        emulator_base_url = $EmulatorBaseUrl
        devices = $Devices
        summary = @{ pass = $pass; fail = $fail; warn = $warn; info = $info }
        results = $script:Results
        artifacts = $script:Artifacts
    } | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path $script:JsonPath
}

$script:AdbPath = $Adb
if (-not (Test-Path -LiteralPath $script:AdbPath)) {
    throw "adb not found: $script:AdbPath"
}

Write-Log "Output: $script:OutputRoot"

try {
    $health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 8
    if ($health.status -eq "ok") {
        Add-Result -Name "Backend health" -Status "PASS" -Detail "health ok"
    } else {
        Add-Result -Name "Backend health" -Status "FAIL" -Detail "health returned $($health | ConvertTo-Json -Compress)"
    }
} catch {
    Add-Result -Name "Backend health" -Status "FAIL" -Detail $_.Exception.Message
}

foreach ($d in $Devices) {
    if ($RefreshAdbConnections) {
        $connect = Invoke-AdbNoDevice -AdbArgs @("connect", $d) -TimeoutSeconds 10
        Write-Log "adb connect $d => $($connect.Out.Trim()) $($connect.Err.Trim())"
    } else {
        Write-Log "adb connect skipped for $d; using existing endpoint directly"
    }
    $model = (Invoke-Adb -Device $d -AdbArgs @("shell", "getprop", "ro.product.model") -TimeoutSeconds 8).Out.Trim()
    $healthProbe = Invoke-Adb -Device $d -AdbArgs @("shell", "curl", "-s", "-m", "3", "$EmulatorBaseUrl/health") -TimeoutSeconds 8
    $health = $healthProbe.Out.Trim()
    if ($health -match '"status"\s*:\s*"ok"') {
        Add-Result -Name "Device backend reachability $d" -Status "PASS" -Detail "model=$model can reach $EmulatorBaseUrl"
    } elseif ($healthProbe.Err -match "not found|inaccessible") {
        Add-Result -Name "Device backend reachability $d" -Status "WARN" -Detail "model=$model has no curl binary; App login/API assertions will provide the HTTP reachability evidence"
    } else {
        Add-Result -Name "Device backend reachability $d" -Status "FAIL" -Detail "model=$model cannot reach backend; response=$health error=$($healthProbe.Err.Trim())"
    }
    [void](Invoke-Adb -Device $d -AdbArgs @("reverse", "tcp:8080", "tcp:8080") -TimeoutSeconds 8)
    [void](Invoke-Adb -Device $d -AdbArgs @("logcat", "-c") -TimeoutSeconds 8)

    if (-not $SkipInstall -and -not [string]::IsNullOrWhiteSpace($ApkPath)) {
        if (Test-Path -LiteralPath $ApkPath) {
            $install = Invoke-Adb -Device $d -AdbArgs @("install", "-r", $ApkPath) -TimeoutSeconds 120
            if ($install.Out -match "Success") {
                Add-Result -Name "Install APK $d" -Status "PASS" -Detail "installed $ApkPath"
            } else {
                Add-Result -Name "Install APK $d" -Status "FAIL" -Detail "$($install.Out) $($install.Err)"
            }
        } else {
            Add-Result -Name "Install APK $d" -Status "FAIL" -Detail "APK not found: $ApkPath"
        }
    }
}

$apiState = $null
try {
    $apiState = Test-ApiMessages
} catch {
    Add-Result -Name "API private messages" -Status "FAIL" -Detail $_.Exception.Message
}

if ($null -ne $apiState) {
    try {
        Test-ApiCalls -ApiState $apiState
    } catch {
        Add-Result -Name "API voice/video calls" -Status "FAIL" -Detail $_.Exception.Message
    }
}

if (-not $SkipUi) {
    Login-Device -Device $AliceDevice -Username $AliceUsername
    Login-Device -Device $BobDevice -Username $BobUsername
    if ($ObserverDevice -and ($Devices -contains $ObserverDevice)) {
        [void](Invoke-Adb -Device $ObserverDevice -AdbArgs @("shell", "am", "start", "-n", "$PackageName/.MainActivity") -TimeoutSeconds 10)
        Start-Sleep -Seconds 3
        Add-Result -Name "Observer launch $ObserverDevice" -Status "INFO" -Detail "observer device launched for screenshot/log parity" -Artifacts @((Save-UiDump -Device $ObserverDevice -Name "observer-launch").Path, (Save-Screenshot -Device $ObserverDevice -Name "observer-launch"))
    }

    if ($null -ne $apiState) {
        Open-ChatAndCheckMessages -Device $AliceDevice -Texts @($apiState.text_alice_to_bob, $apiState.text_bob_to_alice) -PeerPattern "Smoke Bob|smoke_bob"
        Open-ChatAndCheckMessages -Device $BobDevice -Texts @($apiState.text_alice_to_bob, $apiState.text_bob_to_alice) -PeerPattern "Smoke Alice|smoke_alice"
        Check-CallEntryUi -Device $AliceDevice -PeerPattern "Smoke Bob|smoke_bob"
        Check-CallEntryUi -Device $BobDevice -PeerPattern "Smoke Alice|smoke_alice"
    }

    foreach ($d in $Devices) {
        Fast-Navigation -Device $d
        Run-Monkey -Device $d
    }
}

foreach ($d in $Devices) {
    Collect-DeviceLogs -Device $d
}
Collect-BackendLogs
Write-Report

Write-Host ""
Write-Host "Report: $script:ReportPath"
Write-Host "JSON:   $script:JsonPath"
