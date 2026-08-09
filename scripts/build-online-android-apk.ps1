#Requires -Version 7.0
<#
.SYNOPSIS
构建固化线上 REST、WebSocket、Bootstrap 和 H5 地址的 Android APK。

.DESCRIPTION
复用本地模拟器构建脚本的统一流程，但启用 ProductionArm64 并清空模拟器回环地址，
随后将新产物归档为线上 APK。构建完成后仍需运行端点检查确认没有 localhost/10.0.2.2。

.PARAMETER ServerUrl
线上 REST 服务根地址。

.PARAMETER OutputRoot
归档 APK、校验信息和构建记录的目录。

.PARAMETER DisableReleaseShrink
关闭 Release 压缩，仅用于定位构建问题，不建议用于正式交付。

.EXAMPLE
pwsh -File scripts/build-online-android-apk.ps1 -OutputRoot artifacts
#>
[CmdletBinding()]
param(
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$BootstrapUrl = "https://api.example.com/api/v1/client/bootstrap",
    [string]$PublicH5Url = "https://h5.example.com",
    [string]$OutputRoot = "artifacts",
    [switch]$DisableReleaseShrink,
    [switch]$DisableSplashImage
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$before = @()
$localRoot = Join-Path $repoRoot "artifacts"
if (Test-Path -LiteralPath $localRoot) {
    $before = @(Get-ChildItem -LiteralPath $localRoot -Directory -Filter "local-emulator-apk-*" | Select-Object -ExpandProperty FullName)
}

& (Join-Path $PSScriptRoot "build-local-emulator-apk.ps1") `
    -ServerUrl $ServerUrl `
    -WsUrl $WsUrl `
    -BootstrapUrl $BootstrapUrl `
    -PublicH5Url $PublicH5Url `
    -AndroidLoopbackHost "" `
    -ProductionArm64 `
    -SkipPub `
    -DisableReleaseShrink:$DisableReleaseShrink.IsPresent `
    -DisableSplashImage:$DisableSplashImage.IsPresent

if ($LASTEXITCODE -ne 0) {
    throw "Online Android APK build failed with exit code $LASTEXITCODE"
}

$after = @(Get-ChildItem -LiteralPath $localRoot -Directory -Filter "local-emulator-apk-*" | Sort-Object LastWriteTime -Descending)
$sourceDir = $after | Where-Object { $before -notcontains $_.FullName } | Select-Object -First 1
if ($null -eq $sourceDir) {
    $sourceDir = $after | Select-Object -First 1
}
if ($null -eq $sourceDir) {
    throw "No APK artifact directory was produced."
}

$sourceApk = Join-Path $sourceDir.FullName "genericim-local-emulator-release.apk"
if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Built APK was not found: $sourceApk"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactDir = Join-Path $repoRoot (Join-Path $OutputRoot "online-android-apk-$timestamp")
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$artifactApk = Join-Path $artifactDir "genericim-online-release.apk"
Copy-Item -LiteralPath $sourceApk -Destination $artifactApk -Force
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifactApk

Write-Host "Online APK: $artifactApk"
Write-Host "Server URL: $ServerUrl"
Write-Host "WS URL: $WsUrl"
Write-Host "Bootstrap URL: $BootstrapUrl"
Write-Host "Public H5 URL: $PublicH5Url"
Write-Host "SHA256: $($hash.Hash)"
