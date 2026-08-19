param(
    [string]$Serial = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.ma100",
    [string]$Backend = "https://api.example.com",
    [string]$Adb = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required. Use pwsh."
}

$repoRoot = Get-QaRepositoryRoot
$adbPath = Resolve-QaAdbPath -Adb $Adb
$devices = @(Get-QaDevices -Adb $adbPath)
$device = Select-QaDevice -Devices $devices -Serial $Serial
$Serial = $device.Serial
$python = Resolve-QaPythonPath -VenvPath (Join-Path $repoRoot ".tools\real-device-qa")
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "artifacts\real-device-qa\im400-full-$runId"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$logDir = Join-Path $OutputDir "logcat"
$readyFile = Join-Path $OutputDir "logcat-ready.json"
$stopFile = Join-Path $OutputDir "logcat-stop.signal"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$pwsh = "pwsh"
if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) { throw "pwsh wrapper not found: $pwsh" }

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $pwsh
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($argument in @(
    "-NoLogo", "-NoProfile", "-File", (Join-Path $PSScriptRoot "Start-RealDeviceLogcat.ps1"),
    "-Serial", $Serial, "-PackageName", $PackageName, "-Adb", $adbPath,
    "-OutputDir", $logDir, "-ReadyFile", $readyFile, "-StopFile", $stopFile,
    "-ClearBuffer"
)) { [void]$psi.ArgumentList.Add($argument) }
$logProcess = [System.Diagnostics.Process]::Start($psi)
$stdoutTask = $logProcess.StandardOutput.ReadToEndAsync()
$stderrTask = $logProcess.StandardError.ReadToEndAsync()

$deadline = (Get-Date).AddSeconds(20)
while (-not (Test-Path -LiteralPath $readyFile)) {
    if ($logProcess.HasExited) {
        throw "Logcat monitor exited early: $($stderrTask.GetAwaiter().GetResult())"
    }
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for Logcat monitor readiness." }
    Start-Sleep -Milliseconds 250
}

Write-Host "[QA400] Output: $OutputDir"
Write-Host "[QA400] Continuous Logcat monitor is ready."
$runnerExit = 1
try {
    $runnerArgs = @(
        (Join-Path $PSScriptRoot "run_im400_full.py"),
        "--repo", $repoRoot,
        "--run-dir", $OutputDir,
        "--adb", $adbPath,
        "--serial", $Serial,
        "--package", $PackageName,
        "--backend", $Backend
    )
    & $python @runnerArgs
    $runnerExit = $LASTEXITCODE
} finally {
    New-Item -ItemType File -Force -Path $stopFile | Out-Null
    if (-not $logProcess.WaitForExit(15000)) {
        try { $logProcess.Kill($true) } catch {}
    }
    $logStdout = $stdoutTask.GetAwaiter().GetResult()
    $logStderr = $stderrTask.GetAwaiter().GetResult()
    $logStdout | Set-Content -LiteralPath (Join-Path $OutputDir "logcat-monitor.stdout.log") -Encoding utf8
    $logStderr | Set-Content -LiteralPath (Join-Path $OutputDir "logcat-monitor.stderr.log") -Encoding utf8
}

if ($runnerExit -ne 0) { throw "IM400 Python runner failed with exit code $runnerExit" }

$summaryPath = Join-Path $logDir "summary.json"
$finalArgs = @(
    (Join-Path $PSScriptRoot "run_im400_full.py"),
    "--repo", $repoRoot,
    "--run-dir", $OutputDir,
    "--adb", $adbPath,
    "--serial", $Serial,
    "--package", $PackageName,
    "--backend", $Backend,
    "--finalize",
    "--log-summary", $summaryPath
)
& $python @finalArgs
if ($LASTEXITCODE -ne 0) { throw "IM400 report finalization failed with exit code $LASTEXITCODE" }

$results = Get-Content -LiteralPath (Join-Path $OutputDir "results.json") -Raw -Encoding utf8 | ConvertFrom-Json
if ($results.cases.Count -ne 400) { throw "Expected 400 case results, found $($results.cases.Count)" }
if ((@($results.cases.case_id | Sort-Object -Unique)).Count -ne 400) { throw "Case IDs are not unique." }
Write-Host "[QA400] PASS=$($results.summary.PASS) FAIL=$($results.summary.FAIL) SKIP=$($results.summary.SKIP) BLOCKED=$($results.summary.BLOCKED)"
Write-Host "[QA400] Report: $(Join-Path $OutputDir 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md')"
