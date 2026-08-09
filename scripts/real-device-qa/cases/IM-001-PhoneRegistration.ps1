<#
.SYNOPSIS
采集并验证 IM-001 手机号注册真机流程。

.DESCRIPTION
使用公共 QA 库选择设备，打开注册入口并按用例步骤保存 UI 层级和截图。
脚本只负责真机交互证据；验证码服务和可用测试手机号必须由环境预先准备，
不得输入真实用户手机号。

.PARAMETER Serial
执行注册流程的 ADB 设备。

.PARAMETER OutputDir
保存每个步骤 UI XML 和截图的目录。

.EXAMPLE
pwsh -File scripts/real-device-qa/cases/IM-001-PhoneRegistration.ps1 -Serial emulator-5554
#>
param(
    [string]$Serial = "",
    [string]$PackageName = "com.genericim.app",
    [string]$Adb = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

$qaRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $qaRoot "QaCommon.ps1")

$repoRoot = Get-QaRepositoryRoot
$adbPath = Resolve-QaAdbPath -Adb $Adb
$device = Select-QaDevice -Devices @(Get-QaDevices -Adb $adbPath) -Serial $Serial
$Serial = $device.Serial
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "artifacts\real-device-qa\IM-001-phone-registration-$runId"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Save-AdbSnapshot {
    param([Parameter(Mandatory)][string]$Name)

    $remoteXml = "/sdcard/im001-$runId-$Name.xml"
    $remotePng = "/sdcard/im001-$runId-$Name.png"
    $localXml = Join-Path $OutputDir "$Name.xml"
    $localPng = Join-Path $OutputDir "$Name.png"
    $dump = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @(
        "shell", "uiautomator", "dump", $remoteXml
    ) -TimeoutSeconds 30
    if ($dump.ExitCode -ne 0) { throw "uiautomator dump '$Name' failed: $($dump.StdErr)" }
    $pullXml = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("pull", $remoteXml, $localXml) -TimeoutSeconds 30
    if ($pullXml.ExitCode -ne 0) { throw "pulling hierarchy '$Name' failed: $($pullXml.StdErr)" }
    $screen = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @(
        "shell", "screencap", "-p", $remotePng
    ) -TimeoutSeconds 30
    if ($screen.ExitCode -ne 0) { throw "screenshot '$Name' failed: $($screen.StdErr)" }
    $pullPng = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("pull", $remotePng, $localPng) -TimeoutSeconds 30
    if ($pullPng.ExitCode -ne 0) { throw "pulling screenshot '$Name' failed: $($pullPng.StdErr)" }
    return [pscustomobject]@{
        hierarchy = $localXml
        screenshot = $localPng
        xml = Get-Content -LiteralPath $localXml -Raw -Encoding utf8
    }
}

function Find-ClickableBounds {
    param(
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][string]$Description
    )
    foreach ($match in [regex]::Matches($Xml, '<node\b[^>]*>')) {
        $node = $match.Value
        if ($node -notmatch 'clickable="true"') { continue }
        $descriptionMatch = [regex]::Match($node, 'content-desc="([^"]*)"')
        if (-not $descriptionMatch.Success) { continue }
        $actual = [System.Net.WebUtility]::HtmlDecode($descriptionMatch.Groups[1].Value)
        if ($actual -ne $Description) { continue }
        $boundsMatch = [regex]::Match($node, 'bounds="([^"]+)"')
        if ($boundsMatch.Success -and $boundsMatch.Groups[1].Value -ne "[0,0][0,0]") {
            return $boundsMatch.Groups[1].Value
        }
    }
    return $null
}

function Tap-Bounds {
    param([Parameter(Mandatory)][string]$Bounds)
    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { throw "invalid bounds: $Bounds" }
    $x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
    $y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    $tap = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("shell", "input", "tap", "$x", "$y")
    if ($tap.ExitCode -ne 0) { throw "ADB tap failed: $($tap.StdErr)" }
}

$startedAt = Get-Date
$logoutEvidence = Join-Path $OutputDir "logout"
$initialSnapshot = Save-AdbSnapshot -Name "00-initial"
if (-not $initialSnapshot.xml.Contains("登录您的账号")) {
    $logoutScript = Join-Path $repoRoot "scripts\p0_real_device_logout.ps1"
    $pwsh = Join-Path $PSHOME "pwsh.exe"
    $logout = Invoke-QaProcess -FilePath $pwsh -Arguments @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $logoutScript,
        "-DeviceId", $Serial,
        "-PackageName", $PackageName,
        "-OutputDir", $logoutEvidence
    ) -TimeoutSeconds 180
    $logout.StdOut | Set-Content -LiteralPath (Join-Path $OutputDir "logout.stdout.txt") -Encoding utf8
    $logout.StdErr | Set-Content -LiteralPath (Join-Path $OutputDir "logout.stderr.txt") -Encoding utf8
    if ($logout.ExitCode -ne 0) {
        throw "unable to reach login page before IM-001: $($logout.StdOut) $($logout.StdErr)"
    }
}

$loginSnapshot = Save-AdbSnapshot -Name "01-login-page"
$registerBounds = Find-ClickableBounds -Xml $loginSnapshot.xml -Description "立即注册"
for ($attempt = 1; -not $registerBounds -and $attempt -le 3; $attempt++) {
    $swipe = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @(
        "shell", "input", "swipe", "600", "2200", "600", "900", "500"
    )
    if ($swipe.ExitCode -ne 0) { throw "scrolling the login page failed: $($swipe.StdErr)" }
    Start-Sleep -Seconds 1
    $loginSnapshot = Save-AdbSnapshot -Name ("01-login-page-scrolled-{0:D2}" -f $attempt)
    $registerBounds = Find-ClickableBounds -Xml $loginSnapshot.xml -Description "立即注册"
}
if (-not $registerBounds) { throw "the real-device login page did not expose the '立即注册' action" }
Tap-Bounds -Bounds $registerBounds
Start-Sleep -Seconds 2
$registerSnapshot = Save-AdbSnapshot -Name "02-register-page"
$registerXmlPath = [string]$registerSnapshot.hierarchy
$registerXml = [string]$registerSnapshot.xml

$phoneMarkers = @("手机号", "手机号码", "Phone number", "Mobile number")
$verificationMarkers = @("短信验证码", "验证码", "获取验证码", "发送验证码", "SMS code", "Verification code")
$passwordMarkers = @("密码", "Password")
$accountMarkers = @("用户名", "登录账号", "Create Your Account", "创建账号")

function Find-Markers {
    param([string[]]$Markers)
    return @($Markers | Where-Object { $registerXml.Contains($_, [System.StringComparison]::OrdinalIgnoreCase) })
}

$foundPhone = @(Find-Markers -Markers $phoneMarkers)
$foundVerification = @(Find-Markers -Markers $verificationMarkers)
$foundPassword = @(Find-Markers -Markers $passwordMarkers)
$foundAccount = @(Find-Markers -Markers $accountMarkers)
$phoneRegistrationFieldsAvailable = $foundPhone.Count -gt 0 -and $foundVerification.Count -gt 0 -and $foundPassword.Count -gt 0

$caseResult = [ordered]@{
    case_id = "IM-001"
    name = "手机号注册"
    status = if ($phoneRegistrationFieldsAvailable) { "READY_FOR_SMS" } else { "FAIL" }
    started_at = $startedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    ended_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    device = $Serial
    package = $PackageName
    actions = @(
        "确保当前测试账号已退出",
        "确认到达登录您的账号页面",
        "点击立即注册",
        "检查注册首屏的手机号、短信验证码和密码控件"
    )
    assertions = [ordered]@{
        login_page_reached = $true
        register_page_opened = $registerXml.Contains("注册账号")
        phone_field_marker_found = $foundPhone
        verification_code_marker_found = $foundVerification
        password_marker_found = $foundPassword
        username_account_marker_found = $foundAccount
        phone_registration_fields_available = $phoneRegistrationFieldsAvailable
    }
    failure_boundary = if ($phoneRegistrationFieldsAvailable) {
        "Phone/SMS fields are visible; a controlled SMS test number and code are required for submission."
    } else {
        "The real-device registration flow exposes username/password registration but no phone-number or SMS verification-code controls, so a legal phone registration cannot be performed."
    }
    evidence = [ordered]@{
        output_directory = $OutputDir
        login_screenshot = Join-Path $OutputDir "01-login-page.png"
        login_hierarchy = Join-Path $OutputDir "01-login-page.xml"
        register_screenshot = [string]$registerSnapshot.screenshot
        register_hierarchy = $registerXmlPath
        logout_evidence = $logoutEvidence
    }
}
$resultPath = Join-Path $OutputDir "case-result.json"
$caseResult | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $resultPath -Encoding utf8
$caseResult | ConvertTo-Json -Depth 15

# IM-001 is not passed merely because the generic username registration page opens.
if (-not $phoneRegistrationFieldsAvailable) { exit 1 }

# Do not send an SMS to an uncontrolled/random phone number. If the product later
# exposes the required controls, rerun this case with an approved test number/code.
exit 2
