<#
.SYNOPSIS
验证 Android 真机断网、恢复网络后的登录态和消息补同步。

.DESCRIPTION
通过 ADB 操作指定真机的网络与应用生命周期，同时使用宿主机 API 准备对端
消息，检查恢复后 WebSocket 重连和历史补洞。脚本会改变设备网络状态；
异常退出时应人工确认 Wi-Fi/移动网络已恢复。

.PARAMETER DeviceBaseUrl
真机可访问的后端局域网地址，不能使用 localhost 或模拟器专用 10.0.2.2。

.PARAMETER Device
被操作网络状态和应用进程的 ADB 真机序列号。

.PARAMETER OutputDir
保存断网前后截图、日志和断言结果的目录。

.EXAMPLE
pwsh -File scripts/p2_real_device_network_resume.ps1 -DeviceBaseUrl http://192.168.1.20:8080
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$DeviceBaseUrl = "http://192.168.1.100:8080",
    [string]$Device = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.ma100",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$OutputDir = "release-archives\qa-20260624\real-device-p0-p3\p2-network-resume"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$runId = (Get-Date).ToString("yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Invoke-Adb {
    param([string[]]$AdbArgs, [int]$TimeoutSeconds = 20)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Adb
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

function Invoke-ApiJson {
    param([string]$Method, [string]$Path, [object]$Body = $null, [string]$Token = "")
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }
    $params = @{
        Method = $Method
        Uri = "$($BaseUrl.TrimEnd('/'))$Path"
        Headers = $headers
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try { return Invoke-RestMethod @params } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = "$detail $($_.ErrorDetails.Message)" }
            if ($detail -match '"code"\s*:\s*429' -or $detail -match '\b429\b') {
                Start-Sleep -Seconds ([Math]::Min(30, $attempt * 3))
                continue
            }
            throw
        }
    }
    throw "$Method $Path failed after retries"
}

function Assert-ApiOk {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        throw "$Action failed: $($Response | ConvertTo-Json -Depth 8 -Compress)"
    }
}

function Login-Or-RegisterApi {
    param([string]$Username)
    $body = @{
        username = $Username
        password = $Password
        device_id = "p2-real-network-$Username"
        device_type = "android"
        device_name = "P2 Real Network"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) { return $login }
    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "p2-real-network-$Username"
        device_type = "android"
        device_name = "P2 Real Network"
    }
    Assert-ApiOk -Response $register -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-ApiOk -Response $login -Action "login $Username"
    return $login
}

function Test-DeviceHostReachable {
    $hostName = ([uri]$DeviceBaseUrl).Host
    $ping = Invoke-Adb -AdbArgs @("shell", "ping", "-c", "1", "-W", "2", $hostName) -TimeoutSeconds 8
    return ($ping.Out -match "1 received|0% packet loss")
}

function Set-DeviceNetwork {
    param([bool]$Enabled)
    $mode = if ($Enabled) { "enable" } else { "disable" }
    [void](Invoke-Adb -AdbArgs @("shell", "svc", "wifi", $mode) -TimeoutSeconds 8)
    [void](Invoke-Adb -AdbArgs @("shell", "svc", "data", $mode) -TimeoutSeconds 8)
}

function Wait-DeviceReachable {
    param([bool]$Expected, [int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $reachable = Test-DeviceHostReachable
        if ($reachable -eq $Expected) { return $true }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Save-UiDump {
    param([string]$Name)
    $remote = "/sdcard/p2-real-network-ui.xml"
    $local = Join-Path $OutputDir "$Name.xml"
    [void](Invoke-Adb -AdbArgs @("shell", "uiautomator", "dump", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 15)
    if (Test-Path -LiteralPath $local) {
        return [pscustomobject]@{ Path = $local; Xml = (Get-Content -LiteralPath $local -Raw -Encoding UTF8) }
    }
    return [pscustomobject]@{ Path = $local; Xml = "" }
}

function Save-Screenshot {
    param([string]$Name)
    $remote = "/sdcard/p2-real-network-screen.png"
    $local = Join-Path $OutputDir "$Name.png"
    [void](Invoke-Adb -AdbArgs @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 15)
    return $local
}

function Tap {
    param([int]$X, [int]$Y, [int]$SleepMs = 700)
    [void](Invoke-Adb -AdbArgs @("shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 6)
    Start-Sleep -Milliseconds $SleepMs
}

function Bring-To-AppAndSearchMessage {
    param([string]$Text)
    [void](Invoke-Adb -AdbArgs @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 6)
    [void](Invoke-Adb -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 12)
    Start-Sleep -Seconds 6
    for ($i = 0; $i -lt 8; $i++) {
        $dump = Save-UiDump -Name "network-resume-step-$i"
        if ($dump.Xml -match [regex]::Escape($Text)) {
            return [pscustomobject]@{ Found = $true; Dump = $dump.Path; Shot = (Save-Screenshot -Name "network-resume-found") }
        }
        if ($dump.Xml -match "输入消息") {
            [void](Invoke-Adb -AdbArgs @("shell", "input", "swipe", "540", "1500", "540", "650", "300") -TimeoutSeconds 8)
            Start-Sleep -Seconds 1
            continue
        }
        if ($dump.Xml -match "Smoke Alice|smoke_alice|p2-network|消息|聊天") {
            Tap -X 540 -Y 680 -SleepMs 2500
            continue
        }
        Tap -X 260 -Y 2230 -SleepMs 1500
    }
    $finalDump = Save-UiDump -Name "network-resume-final"
    return [pscustomobject]@{ Found = ($finalDump.Xml -match [regex]::Escape($Text)); Dump = $finalDump.Path; Shot = (Save-Screenshot -Name "network-resume-final") }
}

$text = "p2-real-network-$runId"
$networkOffConfirmed = $false
$networkRestored = $false
$apiFound = $false
$uiFound = $false
$errorText = ""
$initialReachable = $false

try {
    $health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 8
    if ($health.status -ne "ok") { throw "Backend health is not ok" }
    $initialReachable = Test-DeviceHostReachable

    $alice = Login-Or-RegisterApi -Username $AliceUsername
    $bob = Login-Or-RegisterApi -Username $BobUsername
    $chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $alice.data.token -Body @{
        type = 1
        member_ids = @([string]$bob.data.user.uuid)
    }
    Assert-ApiOk -Response $chat -Action "create private chat"
    $chatId = [string]$chat.data.uuid

    [void](Invoke-Adb -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 8)
    Set-DeviceNetwork -Enabled $false
    $networkOffConfirmed = Wait-DeviceReachable -Expected $false -TimeoutSeconds 45

    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $alice.data.token -Body @{
        chat_id = $chatId
        type = 1
        msg_id = [guid]::NewGuid().ToString()
        content = @{ text = $text }
    }
    Assert-ApiOk -Response $send -Action "send network-resume message"

    Set-DeviceNetwork -Enabled $true
    Start-Sleep -Seconds 3
    Set-DeviceNetwork -Enabled $true
    $networkRestored = Wait-DeviceReachable -Expected $true -TimeoutSeconds 75

    $list = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=80" -Token $bob.data.token
    Assert-ApiOk -Response $list -Action "list messages after restore"
    $apiFound = (($list.data | ConvertTo-Json -Depth 20 -Compress) -match [regex]::Escape($text))

    $ui = Bring-To-AppAndSearchMessage -Text $text
    $uiFound = $ui.Found
} catch {
    $errorText = $_.Exception.Message
} finally {
    try {
        Set-DeviceNetwork -Enabled $true
        Start-Sleep -Seconds 3
    } catch {}
}

$status = if ($initialReachable -and $networkOffConfirmed -and $networkRestored -and $apiFound -and $uiFound -and [string]::IsNullOrWhiteSpace($errorText)) {
    "PASS"
} elseif ($initialReachable -and $networkRestored -and $apiFound -and $uiFound -and [string]::IsNullOrWhiteSpace($errorText)) {
    "WARN"
} else {
    "FAIL"
}

$summary = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    status = $status
    device = $Device
    package = $PackageName
    text = $text
    initial_reachable = $initialReachable
    network_off_confirmed = $networkOffConfirmed
    network_restored = $networkRestored
    api_found = $apiFound
    ui_found = $uiFound
    error = $errorText
    output_dir = $OutputDir
}
$jsonPath = Join-Path $OutputDir "network-resume-$runId.json"
$summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -Path $jsonPath

$reportPath = Join-Path $OutputDir "report.md"
@(
    "# P2 Real-Device Network Resume",
    "",
    "- status: $status",
    "- device: $Device",
    "- text: $text",
    "- initial_reachable: $initialReachable",
    "- network_off_confirmed: $networkOffConfirmed",
    "- network_restored: $networkRestored",
    "- api_found: $apiFound",
    "- ui_found: $uiFound",
    "- error: $errorText",
    "- json: $jsonPath"
) | Set-Content -Encoding UTF8 -Path $reportPath

$summary | ConvertTo-Json -Depth 12
if ($status -eq "FAIL") { exit 1 }
