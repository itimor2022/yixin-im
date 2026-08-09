param(
    [string]$Serial = "",
    [string]$PackageName = "com.genericim.app",
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

$repoRoot = Get-QaRepositoryRoot
$adbPath = Resolve-QaAdbPath -Adb $Adb
$device = Select-QaDevice -Devices @(Get-QaDevices -Adb $adbPath) -Serial $Serial
$Serial = $device.Serial
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$outputDir = Join-Path $repoRoot "artifacts\real-device-qa\logcat-self-test-$runId"
$readyFile = Join-Path $outputDir "ready.json"
$stopFile = Join-Path $outputDir "stop"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# 使用独立 pwsh 进程运行监控器，模拟正式 QA 会话中的后台采集方式。
$pwsh = Join-Path $PSHOME "pwsh.exe"
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $pwsh
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($argument in @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $PSScriptRoot "Start-RealDeviceLogcat.ps1"),
    "-Serial", $Serial, "-PackageName", $PackageName, "-Adb", $adbPath,
    "-OutputDir", $outputDir, "-ReadyFile", $readyFile, "-StopFile", $stopFile,
    "-ClearBuffer"
)) { [void]$psi.ArgumentList.Add($argument) }
$monitor = [System.Diagnostics.Process]::Start($psi)
$stdoutTask = $monitor.StandardOutput.ReadToEndAsync()
$stderrTask = $monitor.StandardError.ReadToEndAsync()

try {
    # ready 文件是父子进程的启动屏障，确保测试日志不会早于 logcat 监听器写入。
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $readyFile)) {
        if ($monitor.HasExited) { throw "Logcat monitor exited during self-test startup." }
        if ((Get-Date) -ge $deadline) { throw "Logcat monitor self-test readiness timed out." }
        Start-Sleep -Milliseconds 250
    }

    [void](Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @(
        "shell", "log", "-p", "e", "-t", "GenericIMQaSelfTest",
        "$PackageName WebSocket disconnected: SocketException QA_SYNTHETIC"
    ))
    [void](Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @(
        "shell", "log", "-p", "e", "-t", "GenericIMQaSelfTest",
        "$PackageName FATAL EXCEPTION QA_SYNTHETIC"
    ))
    Start-Sleep -Seconds 2
} finally {
    # 无论注入日志是否成功，都要通知监控器收尾并保存标准输出，避免残留后台进程。
    "stop" | Set-Content -LiteralPath $stopFile -Encoding ascii
    if (-not $monitor.WaitForExit(15000)) {
        try { $monitor.Kill($true) } catch {}
        $monitor.WaitForExit()
    }
    $stdoutTask.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $outputDir "monitor.stdout.txt") -Encoding utf8
    $stderrTask.GetAwaiter().GetResult() | Set-Content -LiteralPath (Join-Path $outputDir "monitor.stderr.txt") -Encoding utf8
}

$summaryPath = Join-Path $outputDir "summary.json"
if (-not (Test-Path -LiteralPath $summaryPath)) { throw "Logcat self-test did not produce summary.json" }
$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding utf8 | ConvertFrom-Json
# 自检只关心两类合成标记是否分别落入连接异常和崩溃计数。
$socketDetected = [int]$summary.counts.IM_SOCKET -ge 1
$crashDetected = [int]$summary.counts.CRASH -ge 1
$passed = $socketDetected -and $crashDetected

# Synthetic markers should not leak into the next real test session.
[void](Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("logcat", "-c") -TimeoutSeconds 15)

$result = [ordered]@{
    passed = $passed
    device = $Serial
    socket_detected = $socketDetected
    crash_detected = $crashDetected
    counts = $summary.counts
    evidence = $outputDir
}
$result | ConvertTo-Json -Depth 10
if (-not $passed) { exit 1 }
