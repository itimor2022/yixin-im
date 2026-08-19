<#
.SYNOPSIS
验证系统时区变化后会话时间无需重启即可刷新。

.DESCRIPTION
记录目标会话时间，修改 Android 系统时区，重新前台应用并比较展示结果。
脚本会改变整台设备的系统时区；测试结束后必须恢复原时区，否则会污染后续
日志时间、Token 判断和 UI 用例。

.PARAMETER TargetTimeZone
测试阶段切换到的 Android/IANA 时区标识。

.PARAMETER ConversationName
用于读取时间标签的预置会话名称。

.EXAMPLE
pwsh -File scripts/real-device-qa/Test-IM380-TimeZoneRefresh.ps1 -DeviceId emulator-5554
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.ma100",
    [string]$ConversationName = "Smoke Alice",
    [string]$TargetTimeZone = "America/Los_Angeles",
    [string]$OutputDir = "artifacts/real-device-qa/im380-timezone-refresh"
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

function Get-ConversationTimestamp {
    param([xml]$Document)
    $node = $Document.SelectNodes('//node[@content-desc!=""]') |
        Where-Object {
            $lines = @($_.'content-desc' -split "`r?`n" | Where-Object { $_.Trim() })
            $lines.Count -ge 4 -and $lines[1].Trim() -eq $ConversationName
        } |
        Select-Object -First 1
    if (-not $node) { throw "Conversation row not found: $ConversationName" }
    $parts = @($node.'content-desc' -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return $parts[2]
}

function Bring-AppToForeground {
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "start", "-W", "-n", "$PackageName/.MainActivity") | Out-Null
    Start-Sleep -Seconds 6
}

function Set-TimeZone {
    param([string]$TimeZone)
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "cmd", "alarm", "set-timezone", $TimeZone) | Out-Null
    Start-Sleep -Seconds 2
    $actual = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "getprop", "persist.sys.timezone") | Select-Object -First 1).Trim()
    if ($actual -ne $TimeZone) { throw "Time zone did not change: expected=$TimeZone actual=$actual" }
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

$originalTimeZone = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "getprop", "persist.sys.timezone") | Select-Object -First 1).Trim()
$originalAutoTimeZone = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "settings", "get", "global", "auto_time_zone") | Select-Object -First 1).Trim()
$restored = $false
$beforeTimestamp = $null
$shiftedTimestamp = $null
$restoredTimestamp = $null

try {
    Bring-AppToForeground
    $beforeTimestamp = Get-ConversationTimestamp -Document (Save-Ui -Name "01-before-shift")

    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "keyevent", "KEYCODE_HOME") | Out-Null
    Start-Sleep -Seconds 2
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "settings", "put", "global", "auto_time_zone", "0") | Out-Null
    Set-TimeZone -TimeZone $TargetTimeZone
    Bring-AppToForeground
    $shiftedTimestamp = Get-ConversationTimestamp -Document (Save-Ui -Name "02-target-zone")
    if ($shiftedTimestamp -eq $beforeTimestamp) {
        throw "Conversation timestamp did not refresh after time zone change"
    }
} finally {
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "keyevent", "KEYCODE_HOME") | Out-Null
    Start-Sleep -Seconds 1
    Set-TimeZone -TimeZone $originalTimeZone
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "settings", "put", "global", "auto_time_zone", $originalAutoTimeZone) | Out-Null
    $actualTimeZone = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "getprop", "persist.sys.timezone") | Select-Object -First 1).Trim()
    $actualAutoTimeZone = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "settings", "get", "global", "auto_time_zone") | Select-Object -First 1).Trim()
    $restored = $actualTimeZone -eq $originalTimeZone -and $actualAutoTimeZone -eq $originalAutoTimeZone
}

if (-not $restored) { throw "Original time zone settings were not restored" }

Bring-AppToForeground
$restoredTimestamp = Get-ConversationTimestamp -Document (Save-Ui -Name "03-restored-zone")
if ($restoredTimestamp -ne $beforeTimestamp) {
    throw "Conversation timestamp did not return to its original label"
}

$summary = [ordered]@{
    case_id = "IM-380"
    status = "PASS"
    device_id = $DeviceId
    conversation = $ConversationName
    original_time_zone = $originalTimeZone
    target_time_zone = $TargetTimeZone
    original_auto_time_zone = $originalAutoTimeZone
    timestamp_before = $beforeTimestamp
    timestamp_in_target_zone = $shiftedTimestamp
    timestamp_after_restore = $restoredTimestamp
    original_system_settings_restored = $restored
    output_dir = $script:RunDir
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:RunDir "summary.json") -Encoding utf8
$summary | ConvertTo-Json -Depth 4
