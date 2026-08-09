param(
    [string]$Repo = ".",
    [string]$ArtifactsRoot = "artifacts",
    [string]$Baseline = "artifacts/real-device-qa/im400-two-device-resume-20260715/results.json",
    [string]$Metadata = "artifacts/real-device-qa/im400-full-20260717-232818/results.json",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmm"
    $OutputDir = "artifacts/real-device-qa/im400-current-evidence-$stamp"
}

$qaArgs = @(
    "scripts/real-device-qa/build_im400_current_evidence_report.py",
    "--repo", $Repo,
    "--baseline", $Baseline,
    "--metadata", $Metadata,
    "--artifacts-root", $ArtifactsRoot,
    "--output-dir", $OutputDir
)

python @qaArgs
if ($LASTEXITCODE -ne 0) {
    throw "IM400 evidence report failed with exit code $LASTEXITCODE"
}

Write-Output "REPORT_DIR=$OutputDir"
