<#
.SYNOPSIS
持续采集指定 Android 真机的应用相关 Logcat 和严重事件。

.DESCRIPTION
选择目标设备后保存原始日志、过滤日志、事件 JSONL、ANR 摘要和最终统计。
DurationSeconds、StopFile 或外部终止决定采集结束；ClearBuffer 会删除设备
当前 Logcat 缓冲，排查历史问题时不应启用。

.PARAMETER DurationSeconds
自动停止前的秒数；0 表示持续运行直到 StopFile 或进程终止。

.PARAMETER FailOnSevere
发现 Crash、ANR 或 Fatal 后以失败状态退出，供自动化门禁使用。

.PARAMETER ReadyFile
采集就绪后创建的同步文件，供启动测试的另一个进程等待。

.EXAMPLE
pwsh -File scripts/real-device-qa/Start-RealDeviceLogcat.ps1 -Serial emulator-5554 -DurationSeconds 120
#>
param(
    [string]$Serial = "",
    [string]$PackageName = "com.genericim.app",
    [string]$Adb = "",
    [string]$OutputDir = "",
    [ValidateRange(0, 86400)][int]$DurationSeconds = 0,
    [switch]$ClearBuffer,
    [string]$ReadyFile = "",
    [string]$StopFile = "",
    [switch]$FailOnSevere
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
$safeSerial = $Serial -replace '[^A-Za-z0-9._-]', '_'
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "artifacts\real-device-qa\logcat-$runId-$safeSerial"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$rawPath = Join-Path $OutputDir "logcat-raw.log"
$filteredPath = Join-Path $OutputDir "logcat-filtered.log"
$eventsPath = Join-Path $OutputDir "events.jsonl"
$summaryPath = Join-Path $OutputDir "summary.json"
$lastAnrPath = Join-Path $OutputDir "last-anr.txt"
$startedAt = Get-Date
$deadline = if ($DurationSeconds -gt 0) { $startedAt.AddSeconds($DurationSeconds) } else { [datetime]::MaxValue }

if ($ClearBuffer) {
    $clear = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("logcat", "-c") -TimeoutSeconds 15
    if ($clear.ExitCode -ne 0) { throw "unable to clear Logcat: $($clear.StdErr)" }
}

$knownPids = [System.Collections.Generic.HashSet[string]]::new()
$counts = [ordered]@{
    CRASH = 0
    ANR = 0
    FATAL = 0
    EXCEPTION = 0
    IM_SOCKET = 0
}
$eventCount = 0
$severeCount = 0
$nextPidRefresh = [datetime]::MinValue
$utf8 = [System.Text.UTF8Encoding]::new($false)
$rawWriter = [System.IO.StreamWriter]::new($rawPath, $false, $utf8)
$filteredWriter = [System.IO.StreamWriter]::new($filteredPath, $false, $utf8)
$eventsWriter = [System.IO.StreamWriter]::new($eventsPath, $false, $utf8)
$rawWriter.AutoFlush = $true
$filteredWriter.AutoFlush = $true
$eventsWriter.AutoFlush = $true
$contextPid = ""
$contextRemaining = 0
$ring = [System.Collections.Generic.Queue[string]]::new()

function Update-AppPids {
    $pidResult = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("shell", "pidof", $PackageName) -TimeoutSeconds 8
    if ($pidResult.ExitCode -eq 0) {
        foreach ($value in ($pidResult.StdOut.Trim() -split "\s+")) {
            if ($value -match "^\d+$") { [void]$knownPids.Add($value) }
        }
    }
}

function Get-LinePid {
    param([string]$Line)
    if ($Line -match '^\s*\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+(?:\S+\s+)?(?<pid>\d+)\s+(?<tid>\d+)\s+[VDIWEF]\s+') {
        return $Matches.pid
    }
    return ""
}

function Get-EventCategory {
    param(
        [string]$Line,
        [bool]$AppRelated
    )

    $escapedPackage = [regex]::Escape($PackageName)
    if ($Line -match "(?i)(ANR in\s+$escapedPackage|am_anr.*$escapedPackage|Input dispatching timed out.*$escapedPackage)") {
        return "ANR"
    }
    if ($AppRelated -and $Line -match '(?i)(FATAL EXCEPTION|Fatal signal\s+(?:6|11)|SIGSEGV|SIGABRT|am_crash|// CRASH|\bCRASH:)') {
        return "CRASH"
    }
    if ($AppRelated -and $Line -match '(?i)(SocketException|WebSocketException|HandshakeException|EOFException|connection reset by peer|broken pipe|failed host lookup|network is unreachable|software caused connection abort|(?:web\s*socket|socket|connection|channel|heartbeat|ping|pong).{0,140}(?:disconnect(?:ed)?|closed|closing|reset|refused|abort(?:ed)?|timeout|timed out|failure|failed|error|not connected|unreachable))') {
        return "IM_SOCKET"
    }
    if ($AppRelated -and $Line -match '(?i)(\bFATAL\b|AndroidRuntime.*\bF\b|Process has died)') {
        return "FATAL"
    }
    if ($AppRelated -and $Line -match '(?i)(Unhandled Exception|FlutterError|E/flutter|(?:java|javax|kotlin|dart|io)\.[\w.$]+(?:Exception|Error)|\b(?:LateInitializationError|NoSuchMethodError|RangeError|StateError|AssertionError|FormatException|TimeoutException)\b)') {
        return "EXCEPTION"
    }
    return ""
}

function Write-DetectedEvent {
    param(
        [string]$Category,
        [string]$Line,
        [string]$LinePid
    )

    $script:eventCount++
    $script:counts[$Category] = [int]$script:counts[$Category] + 1
    $severity = if ($Category -in @("CRASH", "ANR", "FATAL")) { "severe" } else { "review" }
    if ($severity -eq "severe") { $script:severeCount++ }
    $event = [ordered]@{
        sequence = $script:eventCount
        observed_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
        device = $Serial
        package = $PackageName
        category = $Category
        severity = $severity
        pid = $LinePid
        line = $Line
    }
    $script:eventsWriter.WriteLine(($event | ConvertTo-Json -Compress))
    $script:filteredWriter.WriteLine("[$($event.observed_at)] [$severity] [$Category] $Line")
    $color = if ($severity -eq "severe") { "Red" } elseif ($Category -eq "IM_SOCKET") { "Yellow" } else { "DarkYellow" }
    Write-Host "[$Category] $Line" -ForegroundColor $color
}

Update-AppPids

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $adbPath
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($argument in @(
    "-s", $Serial, "logcat", "-v", "threadtime",
    "-b", "main", "-b", "system", "-b", "crash"
)) { [void]$psi.ArgumentList.Add($argument) }
$process = [System.Diagnostics.Process]::Start($psi)
$stderrTask = $process.StandardError.ReadToEndAsync()
$pendingRead = $process.StandardOutput.ReadLineAsync()

if (-not [string]::IsNullOrWhiteSpace($ReadyFile)) {
    $readyParent = Split-Path -Parent $ReadyFile
    if ($readyParent) { New-Item -ItemType Directory -Force -Path $readyParent | Out-Null }
    [ordered]@{
        ready = $true
        process_id = $PID
        adb_process_id = $process.Id
        device = $Serial
        package = $PackageName
        output_directory = $OutputDir
    } | ConvertTo-Json | Set-Content -LiteralPath $ReadyFile -Encoding utf8
}

Write-Host "Continuous Logcat monitor started."
Write-Host "Device: $Serial"
Write-Host "Package: $PackageName"
Write-Host "Raw log: $rawPath"
Write-Host "Filtered events: $filteredPath"
Write-Host "Press Ctrl+C to stop, or create: $StopFile"

$stopReason = "logcat-ended"
try {
    while (-not $process.HasExited) {
        $now = Get-Date
        if ($now -ge $deadline) { $stopReason = "duration-reached"; break }
        if (-not [string]::IsNullOrWhiteSpace($StopFile) -and (Test-Path -LiteralPath $StopFile)) {
            $stopReason = "stop-file"
            break
        }
        if ($now -ge $nextPidRefresh) {
            Update-AppPids
            $nextPidRefresh = $now.AddSeconds(3)
        }

        $completed = [System.Threading.Tasks.Task]::WhenAny(
            $pendingRead,
            [System.Threading.Tasks.Task]::Delay(250)
        ).GetAwaiter().GetResult()
        if ($completed -ne $pendingRead) { continue }

        $line = $pendingRead.GetAwaiter().GetResult()
        if ($null -eq $line) { break }
        $pendingRead = $process.StandardOutput.ReadLineAsync()
        $rawWriter.WriteLine($line)

        $linePid = Get-LinePid -Line $line
        if ($line -match "(?i)(?:Start proc\s+|PID:\s*)(?<appPid>\d+)(?::|\s).*?$([regex]::Escape($PackageName))") {
            if ([int]$Matches.appPid -gt 100) { [void]$knownPids.Add($Matches.appPid) }
        }
        $appRelated = (
            (-not [string]::IsNullOrWhiteSpace($linePid) -and $knownPids.Contains($linePid)) -or
            $line.Contains($PackageName, [System.StringComparison]::OrdinalIgnoreCase)
        )
        $category = Get-EventCategory -Line $line -AppRelated $appRelated

        if (-not [string]::IsNullOrWhiteSpace($category)) {
            $filteredWriter.WriteLine("--- context before event ---")
            foreach ($contextLine in $ring) { $filteredWriter.WriteLine($contextLine) }
            Write-DetectedEvent -Category $category -Line $line -LinePid $linePid
            $contextPid = $linePid
            $contextRemaining = 30
        } elseif ($contextRemaining -gt 0 -and (
            [string]::IsNullOrWhiteSpace($contextPid) -or
            $linePid -eq $contextPid -or
            $line.Contains($PackageName, [System.StringComparison]::OrdinalIgnoreCase)
        )) {
            $filteredWriter.WriteLine("[context] $line")
            $contextRemaining--
        }

        $ring.Enqueue($line)
        while ($ring.Count -gt 12) { [void]$ring.Dequeue() }
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    $stopReason = "interrupted"
} finally {
    if (-not $process.HasExited) {
        try { $process.Kill($true) } catch {}
    }
    try { $process.WaitForExit(5000) | Out-Null } catch {}
    $stderr = ""
    try { $stderr = $stderrTask.GetAwaiter().GetResult() } catch {}
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { $rawWriter.WriteLine("[adb stderr] $stderr") }
    $rawWriter.Dispose()
    $filteredWriter.Dispose()
    $eventsWriter.Dispose()
}

if ([int]$counts.ANR -gt 0) {
    $lastAnr = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("shell", "dumpsys", "activity", "lastanr") -TimeoutSeconds 30
    ($lastAnr.StdOut + $lastAnr.StdErr) | Set-Content -LiteralPath $lastAnrPath -Encoding utf8
}

$summary = [ordered]@{
    started_at = $startedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    ended_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    stop_reason = $stopReason
    device = $Serial
    package = $PackageName
    known_app_pids = @($knownPids)
    event_count = $eventCount
    severe_count = $severeCount
    counts = $counts
    raw_log = $rawPath
    filtered_log = $filteredPath
    events_jsonl = $eventsPath
    last_anr = if (Test-Path -LiteralPath $lastAnrPath) { $lastAnrPath } else { "" }
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
$summary | ConvertTo-Json -Depth 10

if ($FailOnSevere -and $severeCount -gt 0) { exit 2 }
