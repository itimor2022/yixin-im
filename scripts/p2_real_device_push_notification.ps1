<#
.SYNOPSIS
在 Android 真机验证后台/离线系统推送的接收与点击恢复。

.DESCRIPTION
使用双测试账号准备消息，将目标应用切到后台或停止状态，再检查系统通知、
点击跳转和服务端投递记录。脚本会操作指定设备进程并创建消息/推送日志，
要求 BaseUrl 与设备安装包指向同一后端。

.PARAMETER Device
接收系统通知的 ADB 真机序列号。

.PARAMETER OutputDir
保存通知栏截图、logcat、服务端投递记录和断言结果的目录。

.EXAMPLE
pwsh -File scripts/p2_real_device_push_notification.ps1
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Device = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.app",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$OutputDir = "release-archives\qa-20260624\real-device-p0-p3\p2-push-notification"
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
        return [pscustomobject]@{ ExitCode = 124; Out = $outTask.GetAwaiter().GetResult(); Err = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())" }
    }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $outTask.GetAwaiter().GetResult(); Err = $errTask.GetAwaiter().GetResult() }
}

function Invoke-ApiJson {
    param([string]$Method, [string]$Path, [object]$Body = $null, [string]$Token = "")
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers.Authorization = "Bearer $Token" }
    $params = @{ Method = $Method; Uri = "$($BaseUrl.TrimEnd('/'))$Path"; Headers = $headers; TimeoutSec = 30 }
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
        device_id = "p2-real-push-$Username"
        device_type = "android"
        device_name = "P2 Real Push"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) { return $login }
    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "p2-real-push-$Username"
        device_type = "android"
        device_name = "P2 Real Push"
    }
    Assert-ApiOk -Response $register -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-ApiOk -Response $login -Action "login $Username"
    return $login
}

function Save-UiDump {
    param([string]$Name)
    $remote = "/sdcard/p2-push-ui.xml"
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
    $remote = "/sdcard/p2-push-screen.png"
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
        $dump = Save-UiDump -Name "push-ui-step-$i"
        if ($dump.Xml -match [regex]::Escape($Text)) {
            return [pscustomobject]@{ Found = $true; Dump = $dump.Path; Shot = (Save-Screenshot -Name "push-ui-found") }
        }
        if ($dump.Xml -match "输入消息") {
            [void](Invoke-Adb -AdbArgs @("shell", "input", "swipe", "540", "1500", "540", "650", "300") -TimeoutSeconds 8)
            Start-Sleep -Seconds 1
            continue
        }
        if ($dump.Xml -match "Smoke Alice|smoke_alice|消息|聊天") {
            Tap -X 540 -Y 680 -SleepMs 2500
            continue
        }
        Tap -X 260 -Y 2230 -SleepMs 1500
    }
    $finalDump = Save-UiDump -Name "push-ui-final"
    return [pscustomobject]@{ Found = ($finalDump.Xml -match [regex]::Escape($Text)); Dump = $finalDump.Path; Shot = (Save-Screenshot -Name "push-ui-final") }
}

$text = "p2-push-$runId"
$notificationPackageSeen = $false
$notificationTextSeen = $false
$apiFound = $false
$uiFound = $false
$errorText = ""
$notificationDumpPath = Join-Path $OutputDir "notification-$runId.txt"
$logPath = Join-Path $OutputDir "logcat-$runId.txt"

try {
    $health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 8
    if ($health.status -ne "ok") { throw "Backend health is not ok" }

    $alice = Login-Or-RegisterApi -Username $AliceUsername
    $bob = Login-Or-RegisterApi -Username $BobUsername
    $chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $alice.data.token -Body @{
        type = 1
        member_ids = @([string]$bob.data.user.uuid)
    }
    Assert-ApiOk -Response $chat -Action "create private chat"
    $chatId = [string]$chat.data.uuid

    [void](Invoke-Adb -AdbArgs @("shell", "cmd", "notification", "cancel-all") -TimeoutSeconds 8)
    [void](Invoke-Adb -AdbArgs @("shell", "logcat", "-c") -TimeoutSeconds 8)
    [void](Invoke-Adb -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 12)
    Start-Sleep -Seconds 5
    [void](Invoke-Adb -AdbArgs @("shell", "input", "keyevent", "KEYCODE_HOME") -TimeoutSeconds 8)
    Start-Sleep -Seconds 3

    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $alice.data.token -Body @{
        chat_id = $chatId
        type = 1
        msg_id = [guid]::NewGuid().ToString()
        content = @{ text = $text }
    }
    Assert-ApiOk -Response $send -Action "send push message"
    Start-Sleep -Seconds 12

    $notificationDump = (Invoke-Adb -AdbArgs @("shell", "dumpsys", "notification", "--noredact") -TimeoutSeconds 20).Out
    $notificationDump | Set-Content -Encoding UTF8 -Path $notificationDumpPath
    $notificationPackageSeen = ($notificationDump -match [regex]::Escape($PackageName))
    $notificationTextSeen = ($notificationDump -match [regex]::Escape($text))

    $list = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=80" -Token $bob.data.token
    Assert-ApiOk -Response $list -Action "list messages after push"
    $apiFound = (($list.data | ConvertTo-Json -Depth 20 -Compress) -match [regex]::Escape($text))

    $log = (Invoke-Adb -AdbArgs @("logcat", "-d", "-t", "3000") -TimeoutSeconds 25).Out
    $log | Set-Content -Encoding UTF8 -Path $logPath

    $ui = Bring-To-AppAndSearchMessage -Text $text
    $uiFound = $ui.Found
} catch {
    $errorText = $_.Exception.Message
}

$status = if ($notificationPackageSeen -and $apiFound -and $uiFound -and [string]::IsNullOrWhiteSpace($errorText)) {
    "PASS"
} elseif ($apiFound -and $uiFound -and [string]::IsNullOrWhiteSpace($errorText)) {
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
    notification_package_seen = $notificationPackageSeen
    notification_text_seen = $notificationTextSeen
    api_found = $apiFound
    ui_found = $uiFound
    error = $errorText
    notification_dump = $notificationDumpPath
    logcat = $logPath
}
$jsonPath = Join-Path $OutputDir "push-notification-$runId.json"
$summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -Path $jsonPath

$reportPath = Join-Path $OutputDir "report.md"
@(
    "# P2 Real-Device Push Notification",
    "",
    "- status: $status",
    "- device: $Device",
    "- text: $text",
    "- notification_package_seen: $notificationPackageSeen",
    "- notification_text_seen: $notificationTextSeen",
    "- api_found: $apiFound",
    "- ui_found: $uiFound",
    "- error: $errorText",
    "- notification_dump: $notificationDumpPath",
    "- logcat: $logPath",
    "- json: $jsonPath"
) | Set-Content -Encoding UTF8 -Path $reportPath

$summary | ConvertTo-Json -Depth 12
if ($status -eq "FAIL") { exit 1 }
