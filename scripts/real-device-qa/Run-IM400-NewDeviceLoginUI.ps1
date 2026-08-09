param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [Parameter(Mandatory = $true)]
    [string]$Apk,
    [string]$Target = '8MY0220C17006781',
    [string]$Actor = 'UQG5T20915006269',
    [string]$Smoke = 'emulator-5554',
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$OutputDir = 'artifacts/real-device-qa/new-device-login-ui'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$arguments = @(
    'scripts/real-device-qa/run_im400_new_device_login_ui.py'
    '--adb', $Adb
    '--apk', $Apk
    '--target', $Target
    '--actor', $Actor
    '--smoke', $Smoke
    '--base-url', $BaseUrl
    '--output-dir', $OutputDir
)

Push-Location $RepoRoot
try {
    python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "New-device login UI validation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
