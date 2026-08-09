param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Device = 'emulator-5554',
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$OutputDir = 'artifacts/real-device-qa/banned-login-ui'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Arguments = @(
    'scripts/real-device-qa/run_im400_banned_login_ui.py',
    '--adb', $Adb,
    '--device', $Device,
    '--base-url', $BaseUrl,
    '--output-dir', $OutputDir
)

Push-Location $RepoRoot
try {
    python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Banned login UI validation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
