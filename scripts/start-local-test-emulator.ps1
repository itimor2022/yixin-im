#Requires -Version 7.0
<#
.SYNOPSIS
启动指定 Android AVD，并按需安装本地测试 APK。

.DESCRIPTION
复用已经在线的模拟器，否则隐藏启动指定 AVD，等待 sys.boot_completed 后
安装 APK。脚本只选择 emulator-* 设备，不会主动操作已连接的物理设备。

.PARAMETER AvdId
Android Virtual Device 名称。

.PARAMETER ApkPath
待安装 APK；相对路径按仓库根目录解析。

.PARAMETER BootTimeoutSeconds
等待模拟器完成启动的最长秒数。

.PARAMETER SkipInstall
只确保模拟器在线，不安装 APK。

.EXAMPLE
pwsh -File scripts/start-local-test-emulator.ps1 -AvdId GenericIMCacheTest_API36 -SkipInstall
#>
[CmdletBinding()]
param(
    [string]$AvdId = "GenericIMCacheTest_API36",
    [string]$ApkPath = "artifacts\local-real-device-apk-20260717-223424\genericim-local-real-device-release.apk",
    [string]$PackageName = "com.genericim.ma100",
    [int]$BootTimeoutSeconds = 300,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$emulator = Join-Path $env:LOCALAPPDATA "Android\Sdk\emulator\emulator.exe"
$resolvedApk = if ([System.IO.Path]::IsPathRooted($ApkPath)) {
    [System.IO.Path]::GetFullPath($ApkPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ApkPath))
}

foreach ($path in @($adb, $emulator)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required Android tool not found: $path"
    }
}
if (-not $SkipInstall -and -not (Test-Path -LiteralPath $resolvedApk)) {
    throw "APK not found: $resolvedApk"
}

function Get-EmulatorSerial {
    foreach ($line in (& $adb devices)) {
        if ($line -match "^(emulator-\d+)\s+device$") {
            return $Matches[1]
        }
    }
    return $null
}

$serial = Get-EmulatorSerial
if (-not $serial) {
    # 禁止快照写回，避免一次测试产生的登录态污染后续冷启动验收。
    Start-Process -FilePath $emulator -ArgumentList @(
        "-avd", $AvdId,
        "-netdelay", "none",
        "-netspeed", "full",
        "-no-snapshot-save"
    ) -WindowStyle Hidden | Out-Null
}

$deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
do {
    Start-Sleep -Seconds 3
    $serial = Get-EmulatorSerial
    if ($serial) {
        $boot = ((& $adb -s $serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
        if ($boot -eq "1") {
            break
        }
    }
} while ((Get-Date) -lt $deadline)

if (-not $serial) {
    throw "No emulator became available within $BootTimeoutSeconds seconds"
}
$boot = ((& $adb -s $serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
if ($boot -ne "1") {
    throw "Emulator did not finish booting: $serial"
}

if (-not $SkipInstall) {
    & $adb -s $serial install -r $resolvedApk
    if ($LASTEXITCODE -ne 0) {
        throw "adb install failed with exit code $LASTEXITCODE"
    }
}

& $adb -s $serial reverse tcp:8080 tcp:8080
if ($LASTEXITCODE -ne 0) {
    throw "adb reverse for local Docker API failed"
}
& $adb -s $serial shell am force-stop $PackageName
& $adb -s $serial shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "App launch failed with exit code $LASTEXITCODE"
}

[ordered]@{
    status = "PASS"
    serial = $serial
    avd = $AvdId
    apk = $resolvedApk
    package = $PackageName
    api_reverse = "tcp:8080 -> tcp:8080"
} | ConvertTo-Json -Depth 4
