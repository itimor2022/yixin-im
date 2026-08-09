<#
.SYNOPSIS
在 Android 真机验证退出登录后的账号状态和本地隔离。

.DESCRIPTION
通过 UIAutomator 执行设置页退出，保存操作前后 UI/截图，并检查应用回到
未登录入口。脚本会结束当前登录会话并清理账号私有运行时状态，目标账号
必须具备可再次登录的凭据。

.PARAMETER DeviceId
执行退出流程的 ADB 设备。

.PARAMETER OutputDir
保存 UI dump、截图和断言结果的目录。

.EXAMPLE
pwsh -File scripts/p0_real_device_logout.ps1 -DeviceId emulator-5554
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.app",
    [string]$OutputDir = "artifacts/account-isolation-p0-device-smoke/logout"
)

$ErrorActionPreference = "Stop"

function Get-AdbCommand {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe") }
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe") }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe") }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Could not find adb."
}

function Get-UiDump {
    param([string]$Name)

    $remote = "/sdcard/$Name.xml"
    & $adb -s $DeviceId shell uiautomator dump $remote | Out-Null
    $local = Join-Path $resolvedOutputDir "$Name.xml"
    & $adb -s $DeviceId pull $remote $local | Out-Null
    return Get-Content -Raw -Encoding utf8 -LiteralPath $local
}

function Get-Center {
    param([string]$Bounds)

    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { throw "Invalid bounds: $Bounds" }
    return @(
        [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2),
        [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    )
}

function Find-Node {
    param(
        [string]$XmlText,
        [string]$Label,
        [int]$MaximumWidth = 1200,
        [int]$MaximumBottom = [int]::MaxValue
    )

    foreach ($match in [regex]::Matches($XmlText, '<node\b[^>]*>')) {
        $node = $match.Value
        if ($node -notmatch ('package="' + [regex]::Escape($PackageName) + '"')) { continue }
        $descriptionMatch = [regex]::Match($node, 'content-desc="([^"]*)"')
        if (-not $descriptionMatch.Success) { continue }
        $description = [System.Net.WebUtility]::HtmlDecode($descriptionMatch.Groups[1].Value)
        if (-not $description.StartsWith($Label, [System.StringComparison]::Ordinal)) { continue }
        if ($node -notmatch 'clickable="true"') { continue }
        $boundsMatch = [regex]::Match($node, 'bounds="([^"]+)"')
        if (-not $boundsMatch.Success) { continue }
        $coordinateMatch = [regex]::Match($boundsMatch.Groups[1].Value, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        if (-not $coordinateMatch.Success) { continue }
        $width = [int]$coordinateMatch.Groups[3].Value - [int]$coordinateMatch.Groups[1].Value
        if ($width -gt $MaximumWidth) { continue }
        $bottom = [int]$coordinateMatch.Groups[4].Value
        if ($bottom -gt $MaximumBottom) { continue }
        return $boundsMatch.Groups[1].Value
    }
    return $null
}

function Tap-Bounds {
    param([string]$Bounds)

    $center = Get-Center -Bounds $Bounds
    & $adb -s $DeviceId shell input tap $center[0] $center[1] | Out-Null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $repoRoot $OutputDir
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$adb = Get-AdbCommand
$online = (& $adb devices) -join "`n"
if ($online -notmatch "(?m)^$([regex]::Escape($DeviceId))\s+device$") {
    throw "Device '$DeviceId' is not online."
}

& $adb -s $DeviceId logcat -c
& $adb -s $DeviceId shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 2

$devicesBounds = $null
for ($attempt = 0; $attempt -lt 4; $attempt++) {
    $xml = Get-UiDump -Name ("01-navigation-{0:D2}" -f $attempt)

    # Close an in-app browser/custom portal before navigating. KEYCODE_BACK can
    # otherwise leave the app and make the script tap the system Settings icon.
    $closeBounds = Find-Node -XmlText $xml -Label "关闭" -MaximumWidth 400
    if ($closeBounds) {
        Tap-Bounds -Bounds $closeBounds
        Start-Sleep -Seconds 2
        continue
    }

    # A partially clipped row can overlap Flutter's persistent bottom tab bar.
    # Tapping that stale semantic bound opens the tab below it instead of the
    # Devices page, so only accept a row that is fully above the navigation bar.
    $devicesBounds = Find-Node -XmlText $xml -Label "设备" -MaximumBottom 2300
    if ($devicesBounds) { break }

    $settingsBounds = Find-Node -XmlText $xml -Label "设置" -MaximumWidth 400
    if ($settingsBounds) {
        Tap-Bounds -Bounds $settingsBounds
        Start-Sleep -Seconds 2
        break
    }

    & $adb -s $DeviceId shell input keyevent KEYCODE_BACK | Out-Null
    Start-Sleep -Seconds 1
}

$xml = Get-UiDump -Name "02-settings"
$devicesBounds = Find-Node -XmlText $xml -Label "设备" -MaximumBottom 2300
if (-not $devicesBounds) {
    & $adb -s $DeviceId shell input swipe 600 2100 600 900 500 | Out-Null
    Start-Sleep -Seconds 1
    $xml = Get-UiDump -Name "02-settings-scrolled"
    $devicesBounds = Find-Node -XmlText $xml -Label "设备" -MaximumBottom 2300
}
if (-not $devicesBounds) { throw "Devices entry was not found." }
Tap-Bounds -Bounds $devicesBounds
Start-Sleep -Seconds 2

$logoutBounds = $null
for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $xml = Get-UiDump -Name ("03-devices-{0:D2}" -f $attempt)
    $logoutBounds = Find-Node -XmlText $xml -Label "退出登录"
    if ($logoutBounds) { break }
    & $adb -s $DeviceId shell input swipe 600 2200 600 500 350 | Out-Null
    Start-Sleep -Milliseconds 300
}
if (-not $logoutBounds) { throw "Logout entry was not found." }
Tap-Bounds -Bounds $logoutBounds
Start-Sleep -Seconds 1

$xml = Get-UiDump -Name "04-logout-confirm"
$confirmBounds = Find-Node -XmlText $xml -Label "退出登录" -MaximumWidth 600
if (-not $confirmBounds) { throw "Logout confirmation button was not found." }
Tap-Bounds -Bounds $confirmBounds

$deadline = (Get-Date).AddSeconds(30)
$loginXml = ""
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $loginXml = Get-UiDump -Name "05-after-logout"
    if ($loginXml.Contains('content-desc="登录您的账号"')) { break }
}
if (-not $loginXml.Contains('content-desc="登录您的账号"')) {
    throw "Login page was not reached after logout."
}

$remoteScreenshot = "/sdcard/p0-after-logout.png"
$screenshotPath = Join-Path $resolvedOutputDir "05-after-logout.png"
& $adb -s $DeviceId shell screencap -p $remoteScreenshot | Out-Null
& $adb -s $DeviceId pull $remoteScreenshot $screenshotPath | Out-Null

$fatal = & $adb -s $DeviceId logcat -d -v time |
    Select-String -Pattern 'FATAL EXCEPTION|ANR in com\.genericim\.app|IsarError|E/flutter'
if ($fatal) {
    throw "Fatal log detected during logout:`n$($fatal.Line -join "`n")"
}

Write-Host "P0 real-device logout passed." -ForegroundColor Green
Write-Host "Evidence: $resolvedOutputDir"
