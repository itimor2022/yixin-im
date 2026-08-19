<#
.SYNOPSIS
验证 Android 系统通知总开关与应用内通知状态的联动。

.DESCRIPTION
打开目标包的系统通知设置，读取并切换总开关，再回到应用检查状态同步并保存
UI/截图证据。脚本会改变设备系统设置；无论测试成功与否都应确认开关已恢复
到运行前状态。

.PARAMETER DeviceId
被修改系统通知权限的 ADB 设备。

.PARAMETER OutputDir
保存切换前后系统页和应用页证据的目录。

.EXAMPLE
pwsh -File scripts/real-device-qa/Test-IM350-SystemNotificationToggle.ps1 -DeviceId emulator-5554
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.ma100",
    [string]$OutputDir = "artifacts/real-device-qa/im350-system-toggle"
)

$ErrorActionPreference = "Stop"

function Get-Adb {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "adb.exe not found"
}

function Invoke-Adb {
    param([string[]]$Arguments)
    $output = & $script:Adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): adb $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Save-Ui {
    param([string]$Name)
    $remoteXml = "/sdcard/$Name.xml"
    $remotePng = "/sdcard/$Name.png"
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "uiautomator", "dump", $remoteXml) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "screencap", "-p", $remotePng) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remoteXml, (Join-Path $script:RunDir "$Name.xml")) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remotePng, (Join-Path $script:RunDir "$Name.png")) | Out-Null
    return [xml](Get-Content -LiteralPath (Join-Path $script:RunDir "$Name.xml") -Raw -Encoding utf8)
}

function Get-MasterToggle {
    param([xml]$Document)
    $node = $Document.SelectNodes(
        '//node[(@class="android.widget.CheckBox" or @class="android.widget.Switch") and @clickable="true"]'
    ) | Select-Object -First 1
    if (-not $node) { throw "System notification master toggle not found" }
    $match = [regex]::Match($node.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid toggle bounds: $($node.bounds)" }
    return [pscustomobject]@{
        Checked = $node.checked -eq "true"
        X = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        Y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Open-SystemNotificationSettings {
    Invoke-Adb -Arguments @(
        "-s", $DeviceId, "shell", "am", "start",
        "-a", "android.settings.APP_NOTIFICATION_SETTINGS",
        "--es", "android.provider.extra.APP_PACKAGE", $PackageName
    ) | Out-Null
    Start-Sleep -Seconds 3
}

function Tap-Description {
    param([string]$Description, [string]$EvidenceName)
    $document = Save-Ui -Name $EvidenceName
    $node = $document.SelectSingleNode("//node[@content-desc='$Description']")
    if (-not $node) { throw "App node not found: $Description" }
    $match = [regex]::Match($node.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid app node bounds: $($node.bounds)" }
    $x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
    $y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "tap", "$x", "$y") | Out-Null
    Start-Sleep -Seconds 2
}

function Open-AppNotificationPage {
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "force-stop", $PackageName) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "force-stop", "com.android.settings") | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "keyevent", "KEYCODE_HOME") | Out-Null
    Start-Sleep -Seconds 1
    $launchResult = Invoke-Adb -Arguments @(
        "-s", $DeviceId, "shell", "am", "start", "-S", "-W", "-n",
        "$PackageName/.MainActivity"
    )
    $launchResult | Set-Content -LiteralPath (Join-Path $script:RunDir "app-launch.txt") -Encoding utf8
    Start-Sleep -Seconds 4
    $windowState = Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "dumpsys", "window")
    $windowState | Set-Content -LiteralPath (Join-Path $script:RunDir "app-launch-window.txt") -Encoding utf8
    if (($windowState -join "`n") -notmatch "mCurrentFocus=.*$([regex]::Escape($PackageName))/") {
        throw "App did not reach foreground after explicit MainActivity launch"
    }
    Tap-Description -Description "设置" -EvidenceName "navigation-home"
    Tap-Description -Description "通知和声音" -EvidenceName "navigation-settings"
}

$script:Adb = Get-Adb
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedOutput = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
$script:RunDir = Join-Path $resolvedOutput (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $script:RunDir | Out-Null

$devices = Invoke-Adb -Arguments @("devices", "-l")
if (-not ($devices | Where-Object { $_ -match "^$([regex]::Escape($DeviceId))\s+device\b" })) {
    throw "Device $DeviceId is not online"
}

$restored = $false
try {
    Open-SystemNotificationSettings
    $before = Get-MasterToggle -Document (Save-Ui -Name "01-system-enabled")
    if (-not $before.Checked) { throw "Notifications were already disabled before IM-350" }

    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "tap", "$($before.X)", "$($before.Y)") | Out-Null
    Start-Sleep -Seconds 2
    $disabled = Get-MasterToggle -Document (Save-Ui -Name "02-system-disabled")
    if ($disabled.Checked) { throw "System notification toggle did not turn off" }

    Open-AppNotificationPage
    $appXml = Save-Ui -Name "03-app-denied-state"
    $raw = $appXml.OuterXml
    if ($raw -notmatch '未允许，点击去开启|已关闭，点击去系统设置开启') {
        throw "App did not reflect the disabled system notification state"
    }
} finally {
    Open-SystemNotificationSettings
    $current = Get-MasterToggle -Document (Save-Ui -Name "04-system-before-restore")
    if (-not $current.Checked) {
        Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "tap", "$($current.X)", "$($current.Y)") | Out-Null
        Start-Sleep -Seconds 2
    }
    $restoredState = Get-MasterToggle -Document (Save-Ui -Name "05-system-restored")
    $restored = $restoredState.Checked
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "keyevent", "KEYCODE_BACK") | Out-Null
}

if (-not $restored) { throw "System notification permission was not restored" }

Open-AppNotificationPage
$restoredAppXml = Save-Ui -Name "06-app-restored-state"
$appRestored = $restoredAppXml.OuterXml -match '已允许'
if (-not $appRestored) {
    throw "App did not refresh to the allowed state after system notification restoration"
}

$summary = [ordered]@{
    case_id = "IM-350"
    status = "PASS"
    device_id = $DeviceId
    system_toggle_disabled = $true
    app_denied_state_visible = $true
    system_toggle_restored = $restored
    app_allowed_state_visible_after_restore = $appRestored
    output_dir = $script:RunDir
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:RunDir "summary.json") -Encoding utf8
$summary | ConvertTo-Json -Depth 4
