<#
.SYNOPSIS
构建 Flutter Windows Release 并使用 Inno Setup 生成安装程序。

.DESCRIPTION
从 pubspec.yaml 读取版本，将服务地址写入 Flutter 构建，再复制运行时依赖并调用
Inno Setup。使用 -SkipBuild 时复用现有 build/windows 产物，调用方需保证地址和版本一致。

.PARAMETER SkipBuild
跳过 Flutter Windows 构建，只重新打包当前 Release 目录。

.PARAMETER InnoSetupCompiler
ISCC.exe 路径；为空时从常见安装目录探测。

.PARAMETER OutputDir
最终安装程序输出目录。

.EXAMPLE
pwsh -File scripts/build_windows_installer.ps1 -OutputDir dist/windows-installer
#>
param(
    [switch]$SkipBuild,
    [string]$OutputDir = "dist/windows-installer",
    [string]$InnoSetupCompiler = "",
    [string]$ServerUrl = "",
    [string]$WsUrl = "",
    [string]$BootstrapUrl = "",
    [string]$BootstrapUrls = "",
    [string]$PublicH5Url = "",
    [string]$PubHostedUrl = "https://pub.flutter-io.cn"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RepoRoot {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent $PSCommandPath
    }
    if (-not $scriptDir) {
        throw "Could not determine script directory."
    }
    return (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Get-AppVersionInfo {
    param([string]$PubspecPath)

    $versionLine = Select-String -Path $PubspecPath -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' | Select-Object -First 1
    if (-not $versionLine) {
        throw "Could not parse version from pubspec.yaml."
    }

    return @{
        Version = $versionLine.Matches[0].Groups[1].Value
        Build   = $versionLine.Matches[0].Groups[2].Value
    }
}

function Get-InnoSetupCompiler {
    param([string]$PreferredPath)

    if ($PreferredPath -and (Test-Path $PreferredPath)) {
        return (Resolve-Path $PreferredPath).Path
    }

    $command = Get-Command iscc -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $registryEntries = Get-ItemProperty `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', `
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Inno Setup*' }

    foreach ($entry in $registryEntries) {
        if ($entry.InstallLocation) {
            $registryPath = Join-Path $entry.InstallLocation 'ISCC.exe'
            if (Test-Path $registryPath) {
                return $registryPath
            }
        }

        if ($entry.UninstallString -match '\"([A-Za-z]:\\.+?)\\unins\d+\.exe\"') {
            $registryPath = Join-Path $Matches[1] 'ISCC.exe'
            if (Test-Path $registryPath) {
                return $registryPath
            }
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe',
        'D:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'D:\Program Files\Inno Setup 6\ISCC.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Could not find ISCC.exe. Install Inno Setup 6 or pass -InnoSetupCompiler."
}

function Ensure-FirebaseCppSdk {
    param([string]$RepoRoot)

    $pluginCmake = Join-Path $RepoRoot "windows/flutter/ephemeral/.plugin_symlinks/firebase_core/windows/CMakeLists.txt"
    if (-not (Test-Path $pluginCmake)) {
        return
    }

    if ($env:FIREBASE_CPP_SDK_DIR) {
        $currentVersionHeader = Join-Path $env:FIREBASE_CPP_SDK_DIR "include/firebase/version.h"
        if (Test-Path $currentVersionHeader) {
            return
        }
    }

    $firebaseSdkVersion = "12.7.0"
    $content = Get-Content -Path $pluginCmake -Raw -Encoding utf8
    if ($content -match 'set\(FIREBASE_SDK_VERSION "([^"]+)"\)') {
        $firebaseSdkVersion = $Matches[1]
    }

    $buildX64Dir = Join-Path $RepoRoot "build/windows/x64"
    $extractRoot = Join-Path $buildX64Dir "extracted"
    $sdkDirCandidates = @(
        (Join-Path $extractRoot "firebase_cpp_sdk"),
        (Join-Path $extractRoot "firebase_cpp_sdk_windows")
    )
    foreach ($candidate in $sdkDirCandidates) {
        $candidateVersionHeader = Join-Path $candidate "include/firebase/version.h"
        if (Test-Path $candidateVersionHeader) {
            $env:FIREBASE_CPP_SDK_DIR = $candidate
            return
        }
    }

    $zipPath = Join-Path $buildX64Dir "firebase_cpp_sdk_$firebaseSdkVersion.zip"
    $zipUrl = "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_$firebaseSdkVersion.zip"
    $localZipCandidates = @(
        "E:\Intel\firebase_cpp_sdk_$firebaseSdkVersion.zip",
        "E:\Intel\firebase_cpp_sdk_windows_$firebaseSdkVersion.zip"
    )

    New-Item -ItemType Directory -Force -Path $buildX64Dir | Out-Null

    $localZipPath = $localZipCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($localZipPath) {
        $shouldCopyLocal = -not (Test-Path $zipPath)
        if (-not $shouldCopyLocal) {
            $localZipLength = (Get-Item -LiteralPath $localZipPath).Length
            $buildZipLength = (Get-Item -LiteralPath $zipPath).Length
            $shouldCopyLocal = $localZipLength -ne $buildZipLength
        }
        if ($shouldCopyLocal) {
            Write-Step "Copying Firebase C++ SDK $firebaseSdkVersion from local cache"
            Copy-Item -LiteralPath $localZipPath -Destination $zipPath -Force
        }
    }
    elseif (-not (Test-Path $zipPath)) {
        Write-Step "Downloading Firebase C++ SDK $firebaseSdkVersion"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
    }

    if (Test-Path $extractRoot) {
        Remove-Item -Recurse -Force $extractRoot
    }

    Write-Step "Extracting Firebase C++ SDK"
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractRoot
    }
    catch {
        Write-Host "Expand-Archive failed, retrying with tar..." -ForegroundColor Yellow
        & tar -xf $zipPath -C $extractRoot
        if ($LASTEXITCODE -ne 0) {
            throw
        }
    }

    $sdkDir = $null
    foreach ($candidate in $sdkDirCandidates) {
        $candidateVersionHeader = Join-Path $candidate "include/firebase/version.h"
        if (Test-Path $candidateVersionHeader) {
            $sdkDir = $candidate
            break
        }
    }

    if (-not $sdkDir) {
        $foundDirs = Get-ChildItem -Path $extractRoot -Directory -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
        throw "Firebase C++ SDK extracted, but version header was not found under expected paths. Found directories: $($foundDirs -join ', ')"
    }

    $env:FIREBASE_CPP_SDK_DIR = $sdkDir
}

$repoRoot = Get-RepoRoot
Set-Location $repoRoot

Write-Step "Check source mojibake"
& (Join-Path $repoRoot "scripts\check-mojibake.ps1")

$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$versionInfo = Get-AppVersionInfo -PubspecPath $pubspecPath
$exeName = "genericim.exe"

Write-Step "Installing Flutter dependencies"
if (-not [string]::IsNullOrWhiteSpace($PubHostedUrl)) {
    $env:PUB_HOSTED_URL = $PubHostedUrl
}
flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed with exit code $LASTEXITCODE"
}

if (-not $SkipBuild) {
    Ensure-FirebaseCppSdk -RepoRoot $repoRoot

    Write-Step "Building Windows release"
    $flutterBuildArgs = @(
        "build",
        "windows",
        "--release"
    )
    if (-not [string]::IsNullOrWhiteSpace($ServerUrl)) {
        $flutterBuildArgs += "--dart-define=GENERIC_IM_SERVER_URL=$($ServerUrl.TrimEnd('/'))"
    }
    if (-not [string]::IsNullOrWhiteSpace($WsUrl)) {
        $flutterBuildArgs += "--dart-define=GENERIC_IM_WS_URL=$($WsUrl.TrimEnd('/'))"
    }
    if (-not [string]::IsNullOrWhiteSpace($BootstrapUrl)) {
        $flutterBuildArgs += "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$($BootstrapUrl.Trim())"
    }
    if (-not [string]::IsNullOrWhiteSpace($BootstrapUrls)) {
        $flutterBuildArgs += "--dart-define=GENERIC_IM_BOOTSTRAP_URLS=$($BootstrapUrls.Trim())"
    }
    if (-not [string]::IsNullOrWhiteSpace($PublicH5Url)) {
        $flutterBuildArgs += "--dart-define=GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))"
    }

    flutter @flutterBuildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build windows failed with exit code $LASTEXITCODE"
    }
}

$releaseDir = Join-Path $repoRoot "build/windows/x64/runner/Release"
$exePath = Join-Path $releaseDir $exeName
if (-not (Test-Path $exePath)) {
    throw "Windows release output not found: $exePath"
}

$issPath = Join-Path $repoRoot "windows/installer/generic_im_setup.iss"
if (-not (Test-Path $issPath)) {
    throw "Inno Setup script not found: $issPath"
}

$resolvedOutputDir = Join-Path $repoRoot $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$iscc = Get-InnoSetupCompiler -PreferredPath $InnoSetupCompiler

Write-Step "Building Windows installer"
& $iscc `
    "/DMyAppVersion=$($versionInfo.Version)" `
    "/DMyAppExeName=$exeName" `
    "/DSourceDir=$releaseDir" `
    "/DOutputDir=$resolvedOutputDir" `
    $issPath

Write-Host ""
Write-Host "Installer build completed:" -ForegroundColor Green
Get-ChildItem -Path $resolvedOutputDir -Filter "*.exe" | Select-Object FullName, Length, LastWriteTime
