<#
.SYNOPSIS
在持续 Logcat 监控下运行一个真机 QA 子脚本。

.DESCRIPTION
选择唯一目标设备，先启动独立日志采集器并等待 ReadyFile，再运行 TestScript。
结束或异常时通过 StopFile 收尾采集器，并汇总测试与日志进程输出。会清空目标
设备 Logcat 缓冲，只适用于本轮独占的 QA 设备。

.PARAMETER TestScript
需要在监控窗口内运行的 PowerShell 测试脚本。

.PARAMETER TestArguments
原样传递给测试脚本的参数数组。

.PARAMETER TestTimeoutSeconds
测试进程最长运行时间，超时后会终止进程并继续收集日志证据。

.EXAMPLE
pwsh -File scripts/real-device-qa/Invoke-RealDeviceQaSession.ps1 -TestScript scripts/real-device-qa/cases/IM-001-PhoneRegistration.ps1
#>
param(
    [Parameter(Mandatory)][string]$TestScript,
    [string[]]$TestArguments = @(),
    [string]$Serial = "",
    [string]$PackageName = "com.genericim.app",
    [string]$Adb = "",
    [string]$OutputDir = "",
    [ValidateRange(1, 43200)][int]$TestTimeoutSeconds = 10800
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

$repoRoot = Get-QaRepositoryRoot
$adbPath = Resolve-QaAdbPath -Adb $Adb
$device = Select-QaDevice -Devices @(Get-QaDevices -Adb $adbPath) -Serial $Serial
$Serial = $device.Serial
$resolvedTestScript = (Resolve-Path -LiteralPath $TestScript).Path
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "artifacts\real-device-qa\session-$runId"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$readyFile = Join-Path $OutputDir "logcat.ready.json"
$stopFile = Join-Path $OutputDir "logcat.stop"
$loggerStdout = Join-Path $OutputDir "logger.stdout.txt"
$loggerStderr = Join-Path $OutputDir "logger.stderr.txt"
$testStdout = Join-Path $OutputDir "test.stdout.txt"
$testStderr = Join-Path $OutputDir "test.stderr.txt"
$logDir = Join-Path $OutputDir "logcat"
$pwsh = Join-Path $PSHOME "pwsh.exe"
if (-not (Test-Path -LiteralPath $pwsh)) { throw "pwsh.exe not found under $PSHOME" }

$loggerPsi = [System.Diagnostics.ProcessStartInfo]::new()
$loggerPsi.FileName = $pwsh
$loggerPsi.UseShellExecute = $false
$loggerPsi.RedirectStandardOutput = $true
$loggerPsi.RedirectStandardError = $true
$loggerPsi.CreateNoWindow = $true
foreach ($argument in @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $PSScriptRoot "Start-RealDeviceLogcat.ps1"),
    "-Serial", $Serial, "-PackageName", $PackageName, "-Adb", $adbPath,
    "-OutputDir", $logDir, "-ReadyFile", $readyFile, "-StopFile", $stopFile,
    "-ClearBuffer"
)) { [void]$loggerPsi.ArgumentList.Add($argument) }
$logger = [System.Diagnostics.Process]::Start($loggerPsi)
$loggerOutTask = $logger.StandardOutput.ReadToEndAsync()
$loggerErrTask = $logger.StandardError.ReadToEndAsync()

$testExitCode = 125
$testTimedOut = $false
$sessionError = ""
$testStartedAt = Get-Date
try {
    $readyDeadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $readyFile)) {
        if ($logger.HasExited) { throw "Logcat monitor exited before becoming ready." }
        if ((Get-Date) -ge $readyDeadline) { throw "Timed out waiting for Logcat monitor readiness." }
        Start-Sleep -Milliseconds 250
    }

    $testPsi = [System.Diagnostics.ProcessStartInfo]::new()
    $testPsi.FileName = $pwsh
    $testPsi.UseShellExecute = $false
    $testPsi.RedirectStandardOutput = $true
    $testPsi.RedirectStandardError = $true
    $testPsi.CreateNoWindow = $true
    foreach ($argument in @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedTestScript
    ) + @($TestArguments)) { [void]$testPsi.ArgumentList.Add($argument) }
    $testProcess = [System.Diagnostics.Process]::Start($testPsi)
    $testOutTask = $testProcess.StandardOutput.ReadToEndAsync()
    $testErrTask = $testProcess.StandardError.ReadToEndAsync()
    if (-not $testProcess.WaitForExit($TestTimeoutSeconds * 1000)) {
        $testTimedOut = $true
        try { $testProcess.Kill($true) } catch {}
        $testProcess.WaitForExit()
    }
    $testExitCode = if ($testTimedOut) { 124 } else { $testProcess.ExitCode }
    $testOutTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $testStdout -Encoding utf8
    $testErrTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $testStderr -Encoding utf8
} catch {
    $sessionError = $_.Exception.Message
} finally {
    "stop" | Set-Content -LiteralPath $stopFile -Encoding ascii
    if (-not $logger.WaitForExit(20000)) {
        try { $logger.Kill($true) } catch {}
        $logger.WaitForExit()
    }
    $loggerOutTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $loggerStdout -Encoding utf8
    $loggerErrTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $loggerStderr -Encoding utf8
}

$logSummaryPath = Join-Path $logDir "summary.json"
$logSummary = if (Test-Path -LiteralPath $logSummaryPath) {
    Get-Content -LiteralPath $logSummaryPath -Raw -Encoding utf8 | ConvertFrom-Json
} else { $null }
$severeCount = if ($logSummary) { [int]$logSummary.severe_count } else { -1 }
$status = if (
    $testExitCode -eq 0 -and
    $severeCount -eq 0 -and
    [string]::IsNullOrWhiteSpace($sessionError)
) { "PASS" } else { "FAIL" }

$summary = [ordered]@{
    status = $status
    started_at = $testStartedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    ended_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    device = $Serial
    package = $PackageName
    test_script = $resolvedTestScript
    test_arguments = @($TestArguments)
    test_exit_code = $testExitCode
    test_timed_out = $testTimedOut
    severe_log_event_count = $severeCount
    log_event_counts = if ($logSummary) { $logSummary.counts } else { $null }
    error = $sessionError
    output_directory = $OutputDir
}
$summaryPath = Join-Path $OutputDir "session-summary.json"
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8
$summary | ConvertTo-Json -Depth 12
if ($status -eq "FAIL") { exit 1 }
