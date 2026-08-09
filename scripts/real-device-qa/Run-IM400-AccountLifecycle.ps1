param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$OutputDir = 'artifacts/real-device-qa/local-docker-dual-device-20260717/account-lifecycle-api'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Arguments = @(
    'scripts/real-device-qa/run_im400_account_lifecycle_api.py',
    '--base-url', $BaseUrl,
    '--output-dir', $OutputDir
)

Push-Location $RepoRoot
try {
    python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Account lifecycle validation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
