#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$PublicH5Url = "https://h5.example.com",
    [string]$OutputRoot = "artifacts"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactRoot = Join-Path $repoRoot "artifacts"
# 记录构建前目录快照，随后只接受本次命令新创建的产物目录。
$before = @()
if (Test-Path -LiteralPath $artifactRoot) {
    $before = @(Get-ChildItem -LiteralPath $artifactRoot -Directory -Filter "online-android-apk-*" |
        Select-Object -ExpandProperty FullName)
}

# 客户测试包强调快速验证，因此关闭 release shrink 以缩短构建并保留诊断信息。
& (Join-Path $PSScriptRoot "build-online-android-apk.ps1") `
    -ServerUrl $ServerUrl `
    -WsUrl $WsUrl `
    -PublicH5Url $PublicH5Url `
    -DisableReleaseShrink

# 通过前后目录差集定位本次产物，避免误复制历史 APK。
$newArtifact = Get-ChildItem -LiteralPath $artifactRoot -Directory -Filter "online-android-apk-*" |
    Where-Object { $before -notcontains $_.FullName } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $newArtifact) {
    throw "GenericIM build did not create a new Android artifact"
}

$sourceApk = Join-Path $newArtifact.FullName "genericim-online-release.apk"
if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
    throw "Built APK was not found: $sourceApk"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputDir = Join-Path $repoRoot (Join-Path $OutputRoot "customer-genericim-android-test-$stamp")
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$apk = Join-Path $outputDir "GenericIM-customer-test.apk"
Copy-Item -LiteralPath $sourceApk -Destination $apk -Force

# 输出 SHA256，便于交付双方确认传输后的文件与本地构建一致。
Write-Host "[OK] GenericIM customer Android test APK created"
Write-Host "  APK:    $apk"
Write-Host "  SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash)"
