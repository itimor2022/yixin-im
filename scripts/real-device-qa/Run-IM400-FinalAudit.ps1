param(
    [Parameter(Mandatory)][string]$RunDir,
    [string]$Serial = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.app",
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

$repoRoot = Get-QaRepositoryRoot
$RunDir = [System.IO.Path]::GetFullPath($RunDir)
$adbPath = Resolve-QaAdbPath -Adb $Adb
$python = Resolve-QaPythonPath -VenvPath (Join-Path $repoRoot ".tools\real-device-qa")
$logDir = Join-Path $RunDir "logcat-supplement"
$ready = Join-Path $RunDir "logcat-supplement-ready.json"
$stop = Join-Path $RunDir "logcat-supplement-stop.signal"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Remove-Item -LiteralPath $ready, $stop -Force -ErrorAction SilentlyContinue

$pwsh = "pwsh"
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $pwsh
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($argument in @(
    "-NoLogo", "-NoProfile", "-File", (Join-Path $PSScriptRoot "Start-RealDeviceLogcat.ps1"),
    "-Serial", $Serial, "-PackageName", $PackageName, "-Adb", $adbPath,
    "-OutputDir", $logDir, "-ReadyFile", $ready, "-StopFile", $stop, "-ClearBuffer"
)) { [void]$psi.ArgumentList.Add($argument) }
$monitor = [System.Diagnostics.Process]::Start($psi)
$outTask = $monitor.StandardOutput.ReadToEndAsync()
$errTask = $monitor.StandardError.ReadToEndAsync()
$deadline = (Get-Date).AddSeconds(20)
while (-not (Test-Path -LiteralPath $ready)) {
    if ($monitor.HasExited) { throw "Supplemental Logcat monitor exited early." }
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for supplemental Logcat monitor." }
    Start-Sleep -Milliseconds 250
}

try {
    $args = @(
        (Join-Path $PSScriptRoot "run_im400_full.py"),
        "--repo", $repoRoot, "--run-dir", $RunDir, "--adb", $adbPath,
        "--serial", $Serial, "--package", $PackageName, "--audit-final"
    )
    & $python @args
    if ($LASTEXITCODE -ne 0) { throw "Final audit runner failed with exit code $LASTEXITCODE" }
} finally {
    New-Item -ItemType File -Force -Path $stop | Out-Null
    if (-not $monitor.WaitForExit(15000)) { try { $monitor.Kill($true) } catch {} }
    $outTask.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $RunDir "logcat-supplement.stdout.log") -Encoding utf8
    $errTask.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $RunDir "logcat-supplement.stderr.log") -Encoding utf8
}

$primary = Get-Content -LiteralPath (Join-Path $RunDir "logcat\summary.json") -Raw -Encoding utf8 | ConvertFrom-Json
$supplement = Get-Content -LiteralPath (Join-Path $logDir "summary.json") -Raw -Encoding utf8 | ConvertFrom-Json
$combined = [ordered]@{
    started_at = $primary.started_at
    ended_at = $supplement.ended_at
    stop_reason = "primary-and-supplement-complete"
    device = $Serial
    package = $PackageName
    event_count = [int]$primary.event_count + [int]$supplement.event_count
    severe_count = [int]$primary.severe_count + [int]$supplement.severe_count
    counts = [ordered]@{
        CRASH = [int]$primary.counts.CRASH + [int]$supplement.counts.CRASH
        ANR = [int]$primary.counts.ANR + [int]$supplement.counts.ANR
        FATAL = [int]$primary.counts.FATAL + [int]$supplement.counts.FATAL
        EXCEPTION = [int]$primary.counts.EXCEPTION + [int]$supplement.counts.EXCEPTION
        IM_SOCKET = [int]$primary.counts.IM_SOCKET + [int]$supplement.counts.IM_SOCKET
    }
    primary_summary = "logcat/summary.json"
    supplemental_summary = "logcat-supplement/summary.json"
}
$combinedPath = Join-Path $RunDir "combined-logcat-summary.json"
$combined | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $combinedPath -Encoding utf8

$finalArgs = @(
    (Join-Path $PSScriptRoot "run_im400_full.py"),
    "--repo", $repoRoot, "--run-dir", $RunDir, "--adb", $adbPath,
    "--serial", $Serial, "--package", $PackageName, "--finalize", "--log-summary", $combinedPath
)
& $python @finalArgs
if ($LASTEXITCODE -ne 0) { throw "Final report regeneration failed with exit code $LASTEXITCODE" }

$result = Get-Content -LiteralPath (Join-Path $RunDir "results.json") -Raw -Encoding utf8 | ConvertFrom-Json
Write-Host "[QA400-AUDIT] PASS=$($result.summary.PASS) FAIL=$($result.summary.FAIL) SKIP=$($result.summary.SKIP) BLOCKED=$($result.summary.BLOCKED)"
Write-Host "[QA400-AUDIT] Report=$(Join-Path $RunDir 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md')"
