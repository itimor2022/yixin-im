<#
.SYNOPSIS
在 Android 真机验证 E2EE 密钥恢复请求、批准和导入流程。

.DESCRIPTION
通过 UIAutomator 在指定设备执行单个恢复角色动作并保存 XML/截图证据。
Request、Approve、Import 通常需要不同设备或预先准备的账号状态；脚本会
改变目标账号的恢复会话或本地密钥状态，只能使用专用测试账号。

.PARAMETER DeviceId
执行本次恢复操作的 ADB 设备。

.PARAMETER Operation
本设备承担的恢复步骤，Unsupported 用于验证不支持平台提示。

.PARAMETER OutputDir
保存 UI dump、截图和断言结果的目录。

.EXAMPLE
pwsh -File scripts/p2_real_device_e2ee_recovery.ps1 -DeviceId emulator-5554 -Operation Request
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [Parameter(Mandatory = $true)]
    [ValidateSet("Request", "Approve", "Import", "Unsupported")]
    [string]$Operation,
    [string]$PackageName = "com.genericim.app",
    [string]$OutputDir = "artifacts/p2-device-smoke"
)

$ErrorActionPreference = "Stop"

function Get-AdbCommand {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"),
        (Get-Command adb -ErrorAction SilentlyContinue).Source
    )
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

function Find-Node {
    param(
        [string]$XmlText,
        [string]$Label,
        [int]$MaximumWidth = 1200
    )

    foreach ($match in [regex]::Matches($XmlText, '<node\b[^>]*>')) {
        $node = $match.Value
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
        if ($width -le $MaximumWidth) { return $boundsMatch.Groups[1].Value }
    }
    return $null
}

function Tap-Bounds {
    param([string]$Bounds)

    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { throw "Invalid bounds: $Bounds" }
    $x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
    $y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    & $adb -s $DeviceId shell input tap $x $y | Out-Null
}

function Save-Screenshot {
    param([string]$Name)

    $remote = "/sdcard/$Name.png"
    & $adb -s $DeviceId shell screencap -p $remote | Out-Null
    & $adb -s $DeviceId pull $remote (Join-Path $resolvedOutputDir "$Name.png") | Out-Null
}

function Open-DevicesPage {
    & $adb -s $DeviceId shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 3
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $xml = Get-UiDump -Name ("01-navigation-{0:D2}" -f $attempt)
        if ($xml.Contains('content-desc="链接新设备"') -or $xml.Contains('content-desc="LINK NEW DEVICE"')) {
            return $xml
        }

        $devicesBounds = Find-Node -XmlText $xml -Label "设备"
        if ($devicesBounds) {
            $coordinateMatch = [regex]::Match($devicesBounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
            if ($coordinateMatch.Success -and [int]$coordinateMatch.Groups[4].Value -gt 2250) {
                & $adb -s $DeviceId shell input swipe 600 2100 600 1100 350 | Out-Null
                Start-Sleep -Seconds 1
                continue
            }
            Tap-Bounds -Bounds $devicesBounds
            Start-Sleep -Seconds 3
            continue
        }

        $settingsBounds = Find-Node -XmlText $xml -Label "设置" -MaximumWidth 400
        if ($settingsBounds) {
            Tap-Bounds -Bounds $settingsBounds
            Start-Sleep -Seconds 2
            continue
        }

        & $adb -s $DeviceId shell input keyevent KEYCODE_BACK | Out-Null
        Start-Sleep -Seconds 1
    }
    throw "Could not navigate to Devices page."
}

function Find-RecoveryEntry {
    param([string]$Label)

    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $xml = Get-UiDump -Name ("02-recovery-{0:D2}" -f $attempt)
        $bounds = Find-Node -XmlText $xml -Label $Label
        if ($bounds) { return @{ Xml = $xml; Bounds = $bounds } }
        & $adb -s $DeviceId shell input swipe 600 2150 600 600 400 | Out-Null
        Start-Sleep -Milliseconds 500
    }
    throw "Recovery entry '$Label' was not found."
}

function Test-RecoveryEntryAbsentAfterReload {
    param([string]$Label)

    & $adb -s $DeviceId shell am force-stop $PackageName | Out-Null
    Start-Sleep -Seconds 1
    $null = Open-DevicesPage
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $xml = Get-UiDump -Name ("05-import-reload-{0:D2}" -f $attempt)
        if (Find-Node -XmlText $xml -Label $Label) { return $false }
        if ($xml.Contains("没有可用旧设备、没有备份或旧密钥已重置时")) {
            return $true
        }
        & $adb -s $DeviceId shell input swipe 600 2150 600 600 400 | Out-Null
        Start-Sleep -Milliseconds 500
    }
    throw "Could not reach the recovery section after reloading the app."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $repoRoot $OutputDir
}
$resolvedOutputDir = Join-Path $resolvedOutputDir "$DeviceId-$Operation"
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$adb = Get-AdbCommand
$online = (& $adb devices) -join "`n"
if ($online -notmatch "(?m)^$([regex]::Escape($DeviceId))\s+device$") {
    throw "Device '$DeviceId' is not online."
}

& $adb -s $DeviceId logcat -c
$null = Open-DevicesPage

$targetLabel = switch ($Operation) {
    "Request" { "申请从旧设备恢复" }
    "Approve" { "批准 " }
    "Import" { "导入已批准的恢复身份" }
    "Unsupported" { "加密消息恢复暂不可用" }
}
$entry = Find-RecoveryEntry -Label $targetLabel
Save-Screenshot -Name "03-before-$($Operation.ToLowerInvariant())"
Tap-Bounds -Bounds $entry.Bounds
Start-Sleep -Seconds 2

if ($Operation -eq "Request" -or $Operation -eq "Approve") {
    $xml = Get-UiDump -Name "04-confirm"
    $confirmLabel = if ($Operation -eq "Request") { "发出请求" } else { "批准" }
    $confirmBounds = Find-Node -XmlText $xml -Label $confirmLabel -MaximumWidth 700
    if (-not $confirmBounds) { throw "Confirmation '$confirmLabel' was not found." }
    Tap-Bounds -Bounds $confirmBounds
}

$success = $false
if ($Operation -eq "Import") {
    # Snackbar text is intentionally short-lived and can disappear before
    # uiautomator captures it. Reloading proves that the server-side request
    # was consumed and that the app survives a process restart after the
    # recovered identity was durably written.
    Start-Sleep -Seconds 4
    $success = Test-RecoveryEntryAbsentAfterReload -Label $targetLabel
} else {
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $xml = Get-UiDump -Name "05-after-operation"
        switch ($Operation) {
            "Request" {
                $success = $xml.Contains("等待旧设备批准")
            }
            "Approve" {
                $success = -not $xml.Contains("批准 ")
            }
            "Unsupported" {
                $success = $xml.Contains("加密消息恢复暂不可用") -and
                    $xml.Contains("当前服务器版本不支持，请先升级服务端") -and
                    -not $xml.Contains("Exception:")
            }
        }
        if ($success) { break }
    }
}
if (-not $success) { throw "$Operation did not reach its expected UI state." }

Save-Screenshot -Name "05-after-operation"
$logPath = Join-Path $resolvedOutputDir "logcat.txt"
& $adb -s $DeviceId logcat -d -v time | Set-Content -Encoding utf8 -LiteralPath $logPath
$fatal = Get-Content -Encoding utf8 -LiteralPath $logPath |
    Select-String -Pattern 'FATAL EXCEPTION|ANR in com\.genericim\.app|IsarError|Unhandled Exception'
if ($fatal) {
    throw "Fatal log detected during $Operation`:`n$($fatal.Line -join "`n")"
}

Write-Host "P2 E2EE real-device operation passed: $Operation" -ForegroundColor Green
Write-Host "Evidence: $resolvedOutputDir"
