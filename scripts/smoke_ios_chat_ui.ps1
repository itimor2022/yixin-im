<#
.SYNOPSIS
在 iOS 模拟器执行双账号私聊消息可见性 smoke。

.DESCRIPTION
通过本地 API 准备 Alice/Bob 账号和唯一消息，构建或复用 Runner.app，
安装到已启动模拟器后执行 UI 流程并保存截图。默认会重置模拟器 Keychain，
可能清除该模拟器内其他通用IM测试登录态。

.PARAMETER Flutter
macOS Flutter 可执行文件路径。

.PARAMETER Device
目标 iOS 模拟器 UDID；booted 表示当前已启动设备。

.PARAMETER SkipBuild
复用已有 iOS 模拟器构建，调用方需确认端点与当前后端一致。

.PARAMETER SkipKeychainReset
保留 Keychain；已有凭据可能影响登录断言。

.EXAMPLE
pwsh -File scripts/smoke_ios_chat_ui.ps1 -Device booted -SkipBuild
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$WsUrl = "ws://127.0.0.1:8080/api/v1/ws",
    [string]$Flutter = "/Users/dongtengxiao/development/flutter/bin/flutter",
    [string]$Device = "booted",
    [string]$BundleId = "com.genericim.app",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$MessageText = "",
    [string]$ScreenshotPath = "/tmp/genericim_ios_chat_ui_smoke.png",
    [switch]$SkipBuild,
    [switch]$SkipKeychainReset
)

$ErrorActionPreference = "Stop"

function Join-ApiUrl {
    param([string]$Root, [string]$Path)
    return "$($Root.TrimEnd('/'))$Path"
}

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Method = $Method
        Uri = (Join-ApiUrl -Root $BaseUrl -Path $Path)
        Headers = $headers
        TimeoutSec = 20
    }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = "$detail $($_.ErrorDetails.Message)"
        }
        throw "$Method $Path failed: $detail"
    }
}

function Assert-Ok {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        throw "$Action failed: code=$($Response.code) message=$($Response.message)"
    }
}

function New-LoginBody {
    param([string]$Username)
    return @{
        username = $Username
        password = $Password
        device_id = "codex-ios-ui-smoke-$Username"
        device_type = "ios"
        device_name = "Codex iOS UI Smoke"
    }
}

function Login-OrRegister {
    param([string]$Username)

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body (New-LoginBody -Username $Username)
    if ([int]$login.code -eq 0) {
        return $login
    }

    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "codex-ios-ui-smoke-$Username"
        device_type = "ios"
        device_name = "Codex iOS UI Smoke"
    }
    Assert-Ok -Response $register -Action "register $Username"

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body (New-LoginBody -Username $Username)
    Assert-Ok -Response $login -Action "login $Username"
    return $login
}

function Invoke-Xcrun {
    param([string[]]$SimctlArgs, [switch]$AllowFailure)

    & xcrun @SimctlArgs
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "xcrun $($SimctlArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-FlutterDeviceId {
    if ($Device -ne "booted") {
        return $Device
    }

    $raw = (& xcrun simctl list devices booted -j) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "xcrun simctl list devices booted failed with exit code $LASTEXITCODE"
    }

    $json = $raw | ConvertFrom-Json
    foreach ($runtime in $json.devices.PSObject.Properties) {
        foreach ($sim in @($runtime.Value)) {
            if ($sim.state -eq "Booted" -and -not [string]::IsNullOrWhiteSpace($sim.udid)) {
                return [string]$sim.udid
            }
        }
    }

    throw "No booted iOS simulator found."
}

function Test-MessageContainsText {
    param([object]$Message, [string]$Text)
    if ($null -eq $Message) {
        return $false
    }
    $serialized = $Message | ConvertTo-Json -Depth 30 -Compress
    return $serialized.Contains($Text)
}

if ([string]::IsNullOrWhiteSpace($MessageText)) {
    $MessageText = "codex ios ui smoke $(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
if (-not [string]::IsNullOrWhiteSpace($ScreenshotPath) -and (Test-Path $ScreenshotPath)) {
    Remove-Item -Force $ScreenshotPath
}

$health = Invoke-RestMethod -Uri (Join-ApiUrl -Root $BaseUrl -Path "/health") -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok: $($health | ConvertTo-Json -Compress)"
}

$aliceLogin = Login-OrRegister -Username $AliceUsername
$bobLogin = Login-OrRegister -Username $BobUsername

$aliceToken = [string]$aliceLogin.data.token
$bobUuid = [string]$bobLogin.data.user.uuid
if ([string]::IsNullOrWhiteSpace($aliceToken) -or [string]::IsNullOrWhiteSpace($bobUuid)) {
    throw "Login response did not include token/user UUID."
}

$chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-Ok -Response $chat -Action "create private chat"
$chatId = [string]$chat.data.uuid

Invoke-Xcrun -SimctlArgs @("simctl", "terminate", $Device, $BundleId) -AllowFailure
Invoke-Xcrun -SimctlArgs @("simctl", "uninstall", $Device, $BundleId) -AllowFailure
if (-not $SkipKeychainReset) {
    Invoke-Xcrun -SimctlArgs @("simctl", "keychain", $Device, "reset")
}
Invoke-Xcrun -SimctlArgs @("simctl", "privacy", $Device, "reset", "all") -AllowFailure

$flutterDeviceId = Get-FlutterDeviceId
$flutterArgs = @("test")
if ($SkipBuild) {
    $flutterArgs += "--no-pub"
}
$flutterArgs += @(
    "integration_test/ios_chat_ui_smoke_test.dart",
    "-d", $flutterDeviceId,
    "--dart-define=GENERIC_IM_SMOKE_TEST=true",
    "--dart-define=GENERIC_IM_SERVER_URL=$BaseUrl",
    "--dart-define=GENERIC_IM_WS_URL=$WsUrl",
    "--dart-define=GENERIC_IM_SMOKE_ALICE_USERNAME=$AliceUsername",
    "--dart-define=GENERIC_IM_SMOKE_PASSWORD=$Password",
    "--dart-define=GENERIC_IM_SMOKE_CHAT_ID=$chatId",
    "--dart-define=GENERIC_IM_SMOKE_CHAT_NAME=$BobUsername",
    "--dart-define=GENERIC_IM_SMOKE_MESSAGE=$MessageText"
)

& $Flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    throw "flutter integration smoke test failed with exit code $LASTEXITCODE"
}

$messagesPath = "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=20"
$messages = Invoke-ApiJson -Method "GET" -Path $messagesPath -Token $aliceToken
Assert-Ok -Response $messages -Action "verify UI sent message"
$matched = @($messages.data | Where-Object { Test-MessageContainsText -Message $_ -Text $MessageText } | Select-Object -First 1)
if ($matched.Count -eq 0) {
    throw "UI smoke finished, but the sent text was not found in /message/list: $MessageText"
}

$summary = [pscustomobject]@{
    base_url = $BaseUrl
    ws_url = $WsUrl
    flutter_device = $flutterDeviceId
    alice = $AliceUsername
    bob = $BobUsername
    chat_id = $chatId
    message_text = $MessageText
    message_verified = $true
    ui_test = "integration_test/ios_chat_ui_smoke_test.dart"
    screenshot = "integration_test:ios_chat_ui_smoke"
}

$summary | ConvertTo-Json -Depth 10
