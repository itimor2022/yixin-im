<#
.SYNOPSIS
Builds the supported Flutter Web H5/PC delivery package.
#>
param(
    [string]$OutputRoot = "artifacts",
    [string]$PackageName = "genericim-flutter-web-online-dist",
    [string]$ApiUrl = "http://127.0.0.1:8080",
    [string]$WsUrl = "ws://127.0.0.1:8080/api/v1/ws",
    [string]$BootstrapUrl = "http://127.0.0.1:8080/api/v1/client/bootstrap",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$webDir = Join-Path $repo "build\web"
$outRoot = Join-Path $repo $OutputRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $outRoot "$PackageName-$stamp"
$zipPath = Join-Path $outRoot "$PackageName-$stamp.zip"
$previewScript = Join-Path $PSScriptRoot "start-web-local-preview.ps1"

if (-not $NoBuild) {
    & $previewScript `
        -Port 5185 `
        -ApiUrl $ApiUrl `
        -WsUrl $WsUrl `
        -BootstrapUrl $BootstrapUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Web build failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $webDir "index.html"))) {
    throw "Missing Flutter Web build: $webDir"
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Copy-Item -Path (Join-Path $webDir "*") -Destination $outDir -Recurse -Force
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath -Force

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
"$($hash.Hash)  $($hash.Path)" |
    Set-Content -LiteralPath (Join-Path $outDir "SHA256SUMS.txt") -Encoding ASCII

Write-Host "Flutter Web package created:"
Write-Host "  Directory: $outDir"
Write-Host "  Zip:       $zipPath"
Write-Host "  SHA256:    $($hash.Hash)"
