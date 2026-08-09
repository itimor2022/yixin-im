#Requires -Version 7.0
<#
.SYNOPSIS
构建包含 Windows 运行前置组件的线上兼容安装程序。

.DESCRIPTION
检查 Release 目录和服务地址，验证前置安装包的 Microsoft 数字签名，再通过
Inno Setup 生成安装器。脚本不会下载未知前置组件；PrerequisiteDir 中的文件
必须由可信渠道提前准备。

.PARAMETER ReleaseDir
已经构建完成的 Flutter Windows Release 目录。

.PARAMETER PrerequisiteDir
需要随安装器分发的 Microsoft 前置组件目录。

.PARAMETER InnoSetupCompiler
ISCC.exe 路径；为空时从常见安装位置解析。

.EXAMPLE
pwsh -File scripts/build-online-windows-compatible-installer.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputDir = "artifacts/windows-compatible-installer",
    [string]$ReleaseDir = "build/windows/x64/runner/Release",
    [string]$PrerequisiteDir = "artifacts/windows-prerequisites",
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$BootstrapUrl = "https://api.example.com/api/v1/client/bootstrap",
    [string]$PublicH5Url = "https://h5.example.com",
    [string]$InnoSetupCompiler = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $RepoRoot $Path
}

function Get-InnoSetupCompiler {
    param([string]$PreferredPath)

    $candidates = @(
        $PreferredPath,
        (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Could not find ISCC.exe. Install Inno Setup 6 or pass -InnoSetupCompiler."
}

function Assert-MicrosoftSignature {
    param([Parameter(Mandatory = $true)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Prerequisite signature is not valid: $Path ($($signature.Status))"
    }
    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch "Microsoft Corporation") {
        throw "Prerequisite is not signed by Microsoft Corporation: $Path"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedReleaseDir = Resolve-RepoPath -RepoRoot $repoRoot -Path $ReleaseDir
$resolvedOutputDir = Resolve-RepoPath -RepoRoot $repoRoot -Path $OutputDir
$resolvedPrerequisiteDir = Resolve-RepoPath -RepoRoot $repoRoot -Path $PrerequisiteDir
$appExe = Join-Path $resolvedReleaseDir "genericim.exe"
$issPath = Join-Path $repoRoot "windows\installer\generic_im_compatible_setup.iss"

if (-not (Test-Path -LiteralPath $appExe)) {
    throw "Windows release output is missing: $appExe. Build the online Windows release first."
}

& (Join-Path $PSScriptRoot "verify-online-endpoints.ps1") `
    -Path $resolvedReleaseDir `
    -ServerUrl $ServerUrl `
    -WsUrl $WsUrl `
    -BootstrapUrl $BootstrapUrl `
    -AllowLoopback

$h5Match = & rg -a -l -F $PublicH5Url $resolvedReleaseDir 2>$null
if (-not $h5Match) {
    throw "Windows release output is missing the public H5 endpoint: $PublicH5Url"
}

New-Item -ItemType Directory -Force -Path $resolvedPrerequisiteDir, $resolvedOutputDir | Out-Null
$vcRedist = Join-Path $resolvedPrerequisiteDir "vc_redist.x64.exe"
$webView2Bootstrapper = Join-Path $resolvedPrerequisiteDir "MicrosoftEdgeWebview2Setup.exe"

if (-not (Test-Path -LiteralPath $vcRedist)) {
    Write-Host "Downloading Microsoft Visual C++ x64 Redistributable..."
    Invoke-WebRequest -Uri "https://aka.ms/vc14/vc_redist.x64.exe" -OutFile $vcRedist
}
if (-not (Test-Path -LiteralPath $webView2Bootstrapper)) {
    Write-Host "Downloading Microsoft Edge WebView2 Evergreen Bootstrapper..."
    Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $webView2Bootstrapper
}

Assert-MicrosoftSignature -Path $vcRedist
Assert-MicrosoftSignature -Path $webView2Bootstrapper

$versionLine = Select-String -Path (Join-Path $repoRoot "pubspec.yaml") `
    -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' |
    Select-Object -First 1
if (-not $versionLine) {
    throw "Could not parse version from pubspec.yaml."
}
$version = $versionLine.Matches[0].Groups[1].Value
$iscc = Get-InnoSetupCompiler -PreferredPath $InnoSetupCompiler

& $iscc `
    "/DMyAppVersion=$version" `
    "/DMyAppExeName=genericim.exe" `
    "/DSourceDir=$resolvedReleaseDir" `
    "/DOutputDir=$resolvedOutputDir" `
    "/DVCRedistPath=$vcRedist" `
    "/DWebView2BootstrapperPath=$webView2Bootstrapper" `
    $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Compatible installer compilation failed with exit code $LASTEXITCODE"
}

$installer = Get-ChildItem -LiteralPath $resolvedOutputDir `
    -Filter "GenericIM-Windows-Compatible-Setup-$version.exe" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $installer) {
    throw "Compatible installer was not produced in $resolvedOutputDir"
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $installer.FullName
"$($hash.Hash.ToLowerInvariant())  $($installer.Name)" |
    Set-Content -LiteralPath "$($installer.FullName).sha256.txt" -Encoding ascii

Write-Host "Compatible Windows installer: $($installer.FullName)"
Write-Host "Windows support: Windows 10/11 x64; Windows 11 ARM64 is allowed through x64 emulation but still requires device testing"
Write-Host "Bundled prerequisite: Microsoft Visual C++ x64 Redistributable"
Write-Host "Bundled prerequisite: Microsoft Edge WebView2 Evergreen Bootstrapper"
Write-Host "SHA256: $($hash.Hash)"
