#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$OutputDir = "dist/windows-installer",
    [string]$InnoSetupCompiler = "",
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$BootstrapUrl = "",
    [string]$PublicH5Url = "",
    [string]$PubHostedUrl = "https://pub.flutter-io.cn"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
    throw "ServerUrl is required. Example: -ServerUrl https://api.example.com"
}
if ([string]::IsNullOrWhiteSpace($WsUrl)) {
    throw "WsUrl is required. Example: -WsUrl wss://api.example.com/api/v1/ws"
}
# 未显式提供时，从服务根地址推导客户端引导配置端点。
if ([string]::IsNullOrWhiteSpace($BootstrapUrl)) {
    $BootstrapUrl = "$($ServerUrl.TrimEnd('/'))/api/v1/client/bootstrap"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

# 底层脚本负责 Flutter 构建和 Inno Setup，本层固定线上端点参数。
& (Join-Path $PSScriptRoot "build_windows_installer.ps1") `
    -SkipBuild:$SkipBuild.IsPresent `
    -OutputDir $OutputDir `
    -InnoSetupCompiler $InnoSetupCompiler `
    -ServerUrl $ServerUrl `
    -WsUrl $WsUrl `
    -BootstrapUrl $BootstrapUrl `
    -PublicH5Url $PublicH5Url `
    -PubHostedUrl $PubHostedUrl

if ($LASTEXITCODE -ne 0) {
    throw "Online Windows installer build failed with exit code $LASTEXITCODE"
}

$releaseDir = Join-Path $repoRoot "build/windows/x64/runner/Release"
# 打包完成后扫描 Release 目录，确认编译产物没有遗漏目标端点。
& (Join-Path $PSScriptRoot "verify-online-endpoints.ps1") `
    -Path $releaseDir `
    -ServerUrl $ServerUrl `
    -WsUrl $WsUrl `
    -BootstrapUrl $BootstrapUrl `
    -AllowLoopback

if ($LASTEXITCODE -ne 0) {
    throw "Online Windows endpoint verification failed with exit code $LASTEXITCODE"
}

Write-Host "Online Windows endpoint verification completed."
