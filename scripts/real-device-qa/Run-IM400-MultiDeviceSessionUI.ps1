param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Apk = 'artifacts\local-real-device-apk-20260718-071835\genericim-local-real-device-release.apk',
    [string]$Target = 'emulator-5554',
    [string]$Actor = '8MY0220C17006781',
    [string]$Smoke = 'UQG5T20915006269',
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$OutputDir = 'artifacts/real-device-qa/multidevice-session-ui'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Arguments = @(
    'scripts/real-device-qa/run_im400_multidevice_session_ui.py',
    '--adb', $Adb,
    '--apk', $Apk,
    '--target', $Target,
    '--actor', $Actor,
    '--smoke', $Smoke,
    '--base-url', $BaseUrl,
    '--output-dir', $OutputDir
)

Push-Location $RepoRoot
try {
    python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Multi-device session UI validation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
