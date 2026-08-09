[CmdletBinding()]
param(
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$PublicH5Url = "https://h5.example.com",
    [string]$OutputDir = "artifacts\GenericIM-quick-link-windows"
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutter = "D:\flutter\bin\flutter.bat"
$iscc = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path -LiteralPath $flutter)) { throw "Flutter SDK was not found: $flutter" }
if (-not (Test-Path -LiteralPath $iscc)) { throw "Inno Setup was not found: $iscc" }

$firebaseSdk = Join-Path $repo "build\windows\x64\extracted\firebase_cpp_sdk"
if (-not (Test-Path -LiteralPath (Join-Path $firebaseSdk "include\firebase\version.h"))) {
    throw "Firebase C++ SDK cache is missing: $firebaseSdk"
}
$env:FIREBASE_CPP_SDK_DIR = $firebaseSdk

Push-Location $repo
try {
    $buildArgs = @(
        "build", "windows", "--release",
        "--dart-define=GENERIC_IM_SERVER_URL=$($ServerUrl.TrimEnd('/'))",
        "--dart-define=GENERIC_IM_WS_URL=$($WsUrl.TrimEnd('/'))",
        "--dart-define=GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))",
        "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$($ServerUrl.TrimEnd('/'))/api/v1/client/bootstrap"
    )
    & $flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows build failed with exit code $LASTEXITCODE"
    }

    $releaseDir = Join-Path $repo "build\windows\x64\runner\Release"
    $exe = Join-Path $releaseDir "genericim.exe"
    if (-not (Test-Path -LiteralPath $exe)) { throw "Windows executable was not produced." }

    $resolvedOutput = Join-Path $repo $OutputDir
    New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
    $iss = Join-Path $repo "windows\installer\generic_im_setup.iss"
    $isccArgs = @(
        "/DMyAppVersion=5.0.0",
        "/DMyAppExeName=genericim.exe",
        "/DSourceDir=$releaseDir",
        "/DOutputDir=$resolvedOutput",
        $iss
    )
    & $iscc @isccArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Windows installer build failed with exit code $LASTEXITCODE"
    }

    $installer = Get-ChildItem -LiteralPath $resolvedOutput -Filter "*.exe" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $installer) { throw "Windows installer was not produced." }
    Write-Host "Windows quick-link installer: $($installer.FullName)"
    Write-Host "SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $installer.FullName).Hash)"
}
finally {
    Pop-Location
    Remove-Item Env:\FIREBASE_CPP_SDK_DIR -ErrorAction SilentlyContinue
}
