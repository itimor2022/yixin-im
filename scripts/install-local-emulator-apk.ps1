#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$DeviceId = "127.0.0.1:7555",
    [string]$ApkPath = "build\app\outputs\flutter-apk\app-release.apk",
    [string]$PackageName = "com.genericim.ma100",
    [switch]$ClearData,
    [switch]$SetupReverse = $true,
    [switch]$Launch = $true
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    throw "adb not found: $adb"
}

# reverse 让模拟器内的 127.0.0.1:8080 访问开发机同端口服务。
if ($SetupReverse) {
    Write-Host "Setting adb reverse tcp:8080 -> tcp:8080 for $DeviceId"
    & $adb -s $DeviceId reverse tcp:8080 tcp:8080
    if ($LASTEXITCODE -ne 0) {
        throw "adb reverse failed with exit code $LASTEXITCODE"
    }
}

$resolvedApk = Resolve-Path $ApkPath
# 使用 -r 保留应用数据进行覆盖安装；ClearData 可显式请求干净状态。
Write-Host "Installing $resolvedApk to $DeviceId"
& $adb -s $DeviceId install -r $resolvedApk.Path
if ($LASTEXITCODE -ne 0) {
    throw "adb install failed with exit code $LASTEXITCODE"
}

if ($ClearData) {
    & $adb -s $DeviceId shell pm clear $PackageName
}

# monkey 只发送一个 launcher 事件，不执行随机压力操作。
if ($Launch) {
    & $adb -s $DeviceId shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1
}
