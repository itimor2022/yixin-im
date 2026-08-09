param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$OutputDir = 'artifacts/real-device-qa/local-docker-dual-device-20260717/privacy-activity-api'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Dart = 'D:\flutter\bin\dart.bat'

Push-Location $RepoRoot
try {
    & $Dart run scripts/real-device-qa/run_im400_privacy_activity.dart $BaseUrl $OutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "Privacy activity validation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
