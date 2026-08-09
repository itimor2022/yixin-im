<#
.SYNOPSIS
在单台 Android 设备执行 IM-400 剩余的登录、恢复和后台场景。

.DESCRIPTION
可选安装 APK，驱动应用完成多项单设备 UI 检查，并保存分场景证据。
脚本会启动/停止应用、切换前后台并可能改变登录态；目标设备应为可重置
的专用 QA 设备。

.PARAMETER ApkPath
可选待安装 APK；为空时复用设备当前安装版本。

.PARAMETER BackgroundSeconds
后台恢复场景保持应用在后台的秒数。

.EXAMPLE
pwsh -File scripts/real-device-qa/Run-IM400-RemainingSingleDevice.ps1 -DeviceId emulator-5554
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.app",
    [string]$ApkPath = "",
    [string]$OutputDir = "artifacts/real-device-qa/im400-remaining-single-device",
    [int]$BackgroundSeconds = 8
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-Adb {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"),
        "C:\Android\platform-tools\adb.exe",
        "D:\Android\Sdk\platform-tools\adb.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
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

function Save-UiEvidence {
    param(
        [string]$Prefix,
        [string]$Directory
    )

    $remoteXml = "/sdcard/$Prefix.xml"
    $remotePng = "/sdcard/$Prefix.png"
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "uiautomator", "dump", $remoteXml) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "screencap", "-p", $remotePng) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remoteXml, (Join-Path $Directory "$Prefix.xml")) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remotePng, (Join-Path $Directory "$Prefix.png")) | Out-Null
}

$repoRoot = Get-RepoRoot
$script:Adb = Get-Adb
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $repoRoot $OutputDir
}
$runDir = Join-Path $resolvedOutput $timestamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$devices = Invoke-Adb -Arguments @("devices", "-l")
$deviceLine = $devices | Where-Object { $_ -match "^$([regex]::Escape($DeviceId))\s+device\b" }
if (-not $deviceLine) {
    throw "Device $DeviceId is not online.`n$($devices -join "`n")"
}

if ($ApkPath) {
    $resolvedApk = if ([System.IO.Path]::IsPathRooted($ApkPath)) {
        $ApkPath
    } else {
        Join-Path $repoRoot $ApkPath
    }
    if (-not (Test-Path -LiteralPath $resolvedApk)) {
        throw "APK not found: $resolvedApk"
    }
    $expectedApkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedApk).Hash
} else {
    $resolvedApk = $null
    $expectedApkHash = $null
}

$packageDump = Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "dumpsys", "package", $PackageName)
$packageDump | Set-Content -Encoding utf8 -LiteralPath (Join-Path $runDir "00-package.txt")
$versionName = (($packageDump | Select-String -Pattern "versionName=(\S+)" | Select-Object -First 1).Matches.Groups[1].Value)
$versionCodeLine = ($packageDump | Select-String -Pattern "versionCode=" | Select-Object -First 1).Line.Trim()

$remotePathLine = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "pm", "path", $PackageName) | Select-Object -First 1)
if (-not $remotePathLine.StartsWith("package:")) {
    throw "Installed package path not found: $remotePathLine"
}
$remoteBaseApk = $remotePathLine.Substring("package:".Length).Trim()
$installedApk = Join-Path $runDir "installed-base.apk"
Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remoteBaseApk, $installedApk) | Out-Null
$installedApkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedApk).Hash

Invoke-Adb -Arguments @("-s", $DeviceId, "logcat", "-c") | Out-Null
Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "force-stop", $PackageName) | Out-Null
Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") | Out-Null
Start-Sleep -Seconds 10
Save-UiEvidence -Prefix "01-cold-start" -Directory $runDir

$pidAfterColdStart = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "pidof", $PackageName) | Select-Object -First 1).Trim()
if (-not $pidAfterColdStart) {
    throw "App process is not running after cold start"
}

Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "keyevent", "KEYCODE_HOME") | Out-Null
Start-Sleep -Seconds $BackgroundSeconds
Save-UiEvidence -Prefix "02-background" -Directory $runDir

Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") | Out-Null
Start-Sleep -Seconds 8
Save-UiEvidence -Prefix "03-resumed" -Directory $runDir

$pidAfterResume = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "pidof", $PackageName) | Select-Object -First 1).Trim()
$logcat = Invoke-Adb -Arguments @("-s", $DeviceId, "logcat", "-d", "-v", "time")
$logcatPath = Join-Path $runDir "04-logcat.txt"
$logcat | Set-Content -Encoding utf8 -LiteralPath $logcatPath

$fatalPattern = "FATAL EXCEPTION|ANR in $([regex]::Escape($PackageName))|E/flutter\s*\(|FlutterError"
$fatalMatches = @($logcat | Select-String -Pattern $fatalPattern)
$summary = [ordered]@{
    device_id = $DeviceId
    device = $deviceLine.Trim()
    package = $PackageName
    version_name = $versionName
    version_code = $versionCodeLine
    expected_apk = $resolvedApk
    expected_apk_sha256 = $expectedApkHash
    installed_base_apk_sha256 = $installedApkHash
    installed_apk_matches_expected = if ($expectedApkHash) { $installedApkHash -eq $expectedApkHash } else { $null }
    cold_start_pid = $pidAfterColdStart
    resumed_pid = $pidAfterResume
    process_survived_background_resume = [bool]$pidAfterResume
    fatal_anr_flutter_error_count = $fatalMatches.Count
    output_dir = $runDir
}
$summaryPath = Join-Path $runDir "summary.json"
$summary | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath $summaryPath
$summary | ConvertTo-Json -Depth 4

if (-not $pidAfterResume) {
    throw "App process is not running after resume"
}
if ($fatalMatches.Count -gt 0) {
    throw "Crash/ANR/Flutter errors detected. See $logcatPath"
}
