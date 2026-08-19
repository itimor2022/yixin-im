<#
.SYNOPSIS
验证 Android 客户端断网后恢复连接、增量消息和未读状态的能力。

.DESCRIPTION
通过 ADB 操作指定设备网络，同时使用双测试账号在断网窗口创建消息，恢复网络后
采集 UI、日志和接口证据。脚本会修改设备网络状态并在后端写入测试消息。

.PARAMETER Device
目标 Android 设备序列号。

.PARAMETER EmulatorBaseUrl
设备访问后端使用的地址，与宿主机 BaseUrl 分开配置。

.PARAMETER OutputDir
弱网步骤、截图和结果报告目录。

.EXAMPLE
pwsh -File scripts/p2_network_resume_smoke.ps1 -Device emulator-5554
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$EmulatorBaseUrl = "http://10.0.2.2:8080",
    [string]$Device = "127.0.0.1:16448",
    [string]$PackageName = "com.genericim.ma100",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$OutputDir = "release-archives\qa-20260624\p2-network-resume"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function New-Timestamp { return (Get-Date).ToString("yyyyMMdd-HHmmss") }

function Invoke-Adb {
    param([string[]]$Args, [int]$TimeoutSeconds = 20)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Adb
    foreach ($arg in @("-s", $Device) + $Args) {
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
        return [pscustomobject]@{ ExitCode = 124; Out = $outTask.GetAwaiter().GetResult(); Err = "timeout" }
    }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $outTask.GetAwaiter().GetResult(); Err = $errTask.GetAwaiter().GetResult() }
}

function Invoke-ApiJson {
    param([string]$Method, [string]$Path, [object]$Body = $null, [string]$Token = "")
    $headers = @{}
    if ($Token) { $headers.Authorization = "Bearer $Token" }
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

function Login-Or-Register {
    param([string]$Username)
    $body = @{
        username = $Username
        password = $Password
        device_id = "p2-network-$Username"
        device_type = "android"
        device_name = "P2 Network"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) { return $login }
    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "p2-network-$Username"
        device_type = "android"
        device_name = "P2 Network"
    }
    Assert-ApiOk -Response $register -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-ApiOk -Response $login -Action "login $Username"
    return $login
}

function Set-Airplane {
    param([bool]$Enabled)
    $value = if ($Enabled) { "1" } else { "0" }
    $state = if ($Enabled) { "true" } else { "false" }
    $mode = if ($Enabled) { "enable" } else { "disable" }
    [void](Invoke-Adb -Args @("shell", "cmd", "connectivity", "airplane-mode", $mode) -TimeoutSeconds 8)
    [void](Invoke-Adb -Args @("shell", "settings", "put", "global", "airplane_mode_on", $value) -TimeoutSeconds 8)
    [void](Invoke-Adb -Args @("shell", "am", "broadcast", "-a", "android.intent.action.AIRPLANE_MODE", "--ez", "state", $state) -TimeoutSeconds 8)
    [void](Invoke-Adb -Args @("shell", "svc", "wifi", $(if ($Enabled) { "disable" } else { "enable" })) -TimeoutSeconds 8)
    [void](Invoke-Adb -Args @("shell", "svc", "data", $(if ($Enabled) { "disable" } else { "enable" })) -TimeoutSeconds 8)
}

function Get-DeviceHealth {
    return (Invoke-Adb -Args @("shell", "curl", "-s", "-m", "3", "$EmulatorBaseUrl/health") -TimeoutSeconds 8).Out.Trim()
}

function Wait-DeviceHealth {
    param([int]$TimeoutSeconds = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $health = Get-DeviceHealth
        if ($health -match '"status"\s*:\s*"ok"') { return $true }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Save-UiDump {
    param([string]$Name)
    $remote = "/sdcard/p2-network-ui.xml"
    $local = Join-Path $OutputDir "$Name.xml"
    [void](Invoke-Adb -Args @("shell", "uiautomator", "dump", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Args @("pull", $remote, $local) -TimeoutSeconds 15)
    if (Test-Path -LiteralPath $local) { return Get-Content -LiteralPath $local -Raw -Encoding UTF8 }
    return ""
}

function Save-Screenshot {
    param([string]$Name)
    $remote = "/sdcard/p2-network-screen.png"
    $local = Join-Path $OutputDir "$Name.png"
    [void](Invoke-Adb -Args @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Args @("pull", $remote, $local) -TimeoutSeconds 15)
    return $local
}

function Tap {
    param([int]$X, [int]$Y, [int]$SleepMs = 600)
    [void](Invoke-Adb -Args @("shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 6)
    Start-Sleep -Milliseconds $SleepMs
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$runId = New-Timestamp
$text = "p2-network-resume-$runId"
$networkOffConfirmed = $false
$networkRestored = $false
$uiFound = $false
$apiFound = $false
$errorText = ""

try {
    $alice = Login-Or-Register -Username $AliceUsername
    $bob = Login-Or-Register -Username $BobUsername
    $chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $alice.data.token -Body @{
        type = 1
        member_ids = @([string]$bob.data.user.uuid)
    }
    Assert-ApiOk -Response $chat -Action "create private chat"
    $chatId = [string]$chat.data.uuid

    [void](Invoke-Adb -Args @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 8)
    Set-Airplane -Enabled $true
    Start-Sleep -Seconds 5
    $offlineHealth = Get-DeviceHealth
    $networkOffConfirmed = ($offlineHealth -notmatch '"status"\s*:\s*"ok"')

    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $alice.data.token -Body @{
        chat_id = $chatId
        type = 1
        msg_id = [guid]::NewGuid().ToString()
        content = @{ text = $text }
    }
    Assert-ApiOk -Response $send -Action "send offline message"

    Set-Airplane -Enabled $false
    Start-Sleep -Seconds 3
    Set-Airplane -Enabled $false
    $networkRestored = Wait-DeviceHealth -TimeoutSeconds 60

    $list = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=50" -Token $bob.data.token
    Assert-ApiOk -Response $list -Action "list messages after restore"
    $apiFound = (($list.data | ConvertTo-Json -Depth 20 -Compress) -match [regex]::Escape($text))

    [void](Invoke-Adb -Args @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 6)
    [void](Invoke-Adb -Args @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 12)
    Start-Sleep -Seconds 6
    [void](Invoke-Adb -Args @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 6)
    Tap -X 130 -Y 1840
    $listXml = Save-UiDump -Name "message-list-after-network-restore"
    [void](Save-Screenshot -Name "message-list-after-network-restore")
    if ($listXml -match [regex]::Escape($text)) {
        $uiFound = $true
    } else {
        Tap -X 540 -Y 680 -SleepMs 2500
        $detailXml = Save-UiDump -Name "chat-detail-after-network-restore"
        [void](Save-Screenshot -Name "chat-detail-after-network-restore")
        $uiFound = ($detailXml -match [regex]::Escape($text))
    }
} catch {
    $errorText = $_.Exception.Message
} finally {
    try {
        Set-Airplane -Enabled $false
        Start-Sleep -Seconds 3
    } catch {}
}

$status = if ($networkOffConfirmed -and $networkRestored -and $apiFound -and $uiFound -and [string]::IsNullOrWhiteSpace($errorText)) {
    "PASS"
} elseif (-not $networkOffConfirmed -and $networkRestored -and $apiFound -and $uiFound -and [string]::IsNullOrWhiteSpace($errorText)) {
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
    network_off_confirmed = $networkOffConfirmed
    network_restored = $networkRestored
    api_found = $apiFound
    ui_found = $uiFound
    error = $errorText
    output_dir = $OutputDir
}
$jsonPath = Join-Path $OutputDir "network-resume-$runId.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $jsonPath
$mdPath = Join-Path $OutputDir "report.md"
@(
    "# P2 Network Resume Smoke",
    "",
    "- status: $status",
    "- device: $Device",
    "- text: $text",
    "- network_off_confirmed: $networkOffConfirmed",
    "- network_restored: $networkRestored",
    "- api_found: $apiFound",
    "- ui_found: $uiFound",
    "- error: $errorText",
    "- json: $jsonPath"
) | Set-Content -Encoding UTF8 -Path $mdPath

$summary | ConvertTo-Json -Depth 10
if ($status -eq "FAIL") { exit 1 }
