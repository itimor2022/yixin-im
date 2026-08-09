param(
    [string]$DeviceA = "8MY0220C17006781",
    [string]$DeviceB = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.app",
    [string]$Adb = "",
    [string]$OutputDir = "artifacts\real-device-qa\im400-two-device-resume-20260715",
    [string]$SourceResults = "artifacts\real-device-qa\im400-full-verified-20260715-0111\results.json",
    [string]$ChatTitle = "通用IM官方体验群",
    [switch]$CurrentChat
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

$repoRoot = Get-QaRepositoryRoot
$adbPath = Resolve-QaAdbPath -Adb $Adb
$python = Resolve-QaPythonPath -VenvPath (Join-Path $repoRoot ".tools\real-device-qa")
$OutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDir))
}
$SourceResults = if ([System.IO.Path]::IsPathRooted($SourceResults)) {
    [System.IO.Path]::GetFullPath($SourceResults)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $SourceResults))
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$devices = @(Get-QaDevices -Adb $adbPath)
foreach ($serial in @($DeviceA, $DeviceB)) {
    [void](Select-QaDevice -Devices $devices -Serial $serial)
}

$pwsh = "pwsh"
$monitors = @()
foreach ($serial in @($DeviceA, $DeviceB)) {
    $logDir = Join-Path $OutputDir "logcat-$serial"
    $ready = Join-Path $OutputDir "logcat-$serial-ready.json"
    $stop = Join-Path $OutputDir "logcat-$serial-stop.signal"
    Remove-Item -LiteralPath $ready, $stop -Force -ErrorAction SilentlyContinue
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in @(
        "-NoLogo", "-NoProfile", "-File", (Join-Path $PSScriptRoot "Start-RealDeviceLogcat.ps1"),
        "-Serial", $serial, "-PackageName", $PackageName, "-Adb", $adbPath,
        "-OutputDir", $logDir, "-ReadyFile", $ready, "-StopFile", $stop, "-ClearBuffer"
    )) { [void]$psi.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($psi)
    $monitors += [pscustomobject]@{
        Serial = $serial; Process = $process; Ready = $ready; Stop = $stop
        OutTask = $process.StandardOutput.ReadToEndAsync(); ErrTask = $process.StandardError.ReadToEndAsync()
    }
}

$deadline = (Get-Date).AddSeconds(25)
foreach ($monitor in $monitors) {
    while (-not (Test-Path -LiteralPath $monitor.Ready)) {
        if ($monitor.Process.HasExited) { throw "Logcat monitor exited early for $($monitor.Serial)." }
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for Logcat monitor $($monitor.Serial)." }
        Start-Sleep -Milliseconds 250
    }
}

try {
    $runnerArgs = @(
        (Join-Path $PSScriptRoot "run_im400_dual_resume.py"),
        "--repo", $repoRoot, "--run-dir", $OutputDir, "--source-results", $SourceResults,
        "--adb", $adbPath, "--device-a", $DeviceA, "--device-b", $DeviceB, "--package", $PackageName,
        "--chat-title", $ChatTitle
    )
    if ($CurrentChat) { $runnerArgs += "--current-chat" }
    & $python @runnerArgs
    if ($LASTEXITCODE -ne 0) { throw "Dual-device runner failed with exit code $LASTEXITCODE" }
} finally {
    foreach ($monitor in $monitors) { New-Item -ItemType File -Force -Path $monitor.Stop | Out-Null }
    foreach ($monitor in $monitors) {
        if (-not $monitor.Process.WaitForExit(15000)) { try { $monitor.Process.Kill($true) } catch {} }
        $monitor.OutTask.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $OutputDir "logcat-$($monitor.Serial).stdout.log") -Encoding utf8
        $monitor.ErrTask.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $OutputDir "logcat-$($monitor.Serial).stderr.log") -Encoding utf8
    }
}

$summaries = foreach ($serial in @($DeviceA, $DeviceB)) {
    Get-Content -LiteralPath (Join-Path $OutputDir "logcat-$serial\summary.json") -Raw -Encoding utf8 | ConvertFrom-Json
}
$combined = [ordered]@{
    started_at = ($summaries | Select-Object -First 1).started_at
    ended_at = ($summaries | Select-Object -Last 1).ended_at
    stop_reason = "dual-device-resume-complete"
    device = "$DeviceA,$DeviceB"
    package = $PackageName
    event_count = [int](($summaries | Measure-Object event_count -Sum).Sum)
    severe_count = [int](($summaries | Measure-Object severe_count -Sum).Sum)
    counts = [ordered]@{}
}
foreach ($key in @("CRASH", "ANR", "FATAL", "EXCEPTION", "IM_SOCKET")) {
    $combined.counts[$key] = [int](($summaries | ForEach-Object { $_.counts.$key } | Measure-Object -Sum).Sum)
}
$combinedPath = Join-Path $OutputDir "dual-logcat-summary.json"
$combined | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $combinedPath -Encoding utf8

$finalArgs = @(
    (Join-Path $PSScriptRoot "run_im400_dual_resume.py"),
    "--repo", $repoRoot, "--run-dir", $OutputDir, "--source-results", $SourceResults,
    "--adb", $adbPath, "--device-a", $DeviceA, "--device-b", $DeviceB,
    "--package", $PackageName, "--chat-title", $ChatTitle, "--finalize-log", $combinedPath
)
if ($CurrentChat) { $finalArgs += "--current-chat" }
& $python @finalArgs
if ($LASTEXITCODE -ne 0) { throw "Dual-device report finalization failed." }

$result = Get-Content -LiteralPath (Join-Path $OutputDir "results.json") -Raw -Encoding utf8 | ConvertFrom-Json
Write-Host "[DUAL] PASS=$($result.summary.PASS) FAIL=$($result.summary.FAIL) SKIP=$($result.summary.SKIP) BLOCKED=$($result.summary.BLOCKED)"
Write-Host "[DUAL] Report=$(Join-Path $OutputDir 'IM_400_FULL_REAL_DEVICE_TEST_REPORT.md')"
