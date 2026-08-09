<#
.SYNOPSIS
在多台 Android 真机上执行应用范围内的 Monkey 稳定性测试。

.DESCRIPTION
向指定包注入随机触摸、导航和系统事件，收集日志和最终截图。Monkey 会改变
页面、输入和部分业务状态，可能触发发送或退出等操作；只能使用隔离账号和
可重置测试设备。

.PARAMETER Devices
并行或顺序执行 Monkey 的 ADB 设备列表。

.PARAMETER MonkeyEvents
每台设备注入的随机事件数量。

.PARAMETER ThrottleMs
相邻事件之间的等待毫秒数。

.EXAMPLE
pwsh -File scripts/p2_real_device_monkey.ps1 -MonkeyEvents 200 -ThrottleMs 80
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$PackageName = "com.genericim.app",
    [string[]]$Devices = @("8MY0220C17006781", "UQG5T20915006269"),
    [string]$OutputDir = "release-archives\qa-20260624\real-device-p0-p3\p2-monkey",
    [int]$MonkeyEvents = 1000,
    [int]$ThrottleMs = 45
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$runId = (Get-Date).ToString("yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$logDir = Join-Path $OutputDir "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Invoke-Adb {
    param([string]$Device, [string[]]$AdbArgs, [int]$TimeoutSeconds = 180)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Adb
    foreach ($arg in @("-s", $Device) + $AdbArgs) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch {}
        return [pscustomobject]@{
            ExitCode = 124
            Out = $outTask.GetAwaiter().GetResult()
            Err = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())"
        }
    }
    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        Out = $outTask.GetAwaiter().GetResult()
        Err = $errTask.GetAwaiter().GetResult()
    }
}

function Save-Screenshot {
    param([string]$Device, [string]$Name)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $remote = "/sdcard/p2-monkey-screen.png"
    $local = Join-Path $OutputDir "$safe-$Name.png"
    [void](Invoke-Adb -Device $Device -Args @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -Args @("pull", $remote, $local) -TimeoutSeconds 20)
    return $local
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($device in $Devices) {
    $safe = $device.Replace(":", "-").Replace(".", "-")
    [void](Invoke-Adb -Device $device -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 10)
    [void](Invoke-Adb -Device $device -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 15)
    Start-Sleep -Seconds 3
    [void](Invoke-Adb -Device $device -AdbArgs @("shell", "logcat", "-c") -TimeoutSeconds 10)

    $monkeyPath = Join-Path $OutputDir "$safe-monkey-$runId.txt"
    $timeout = [Math]::Max(120, [int]($MonkeyEvents * (($ThrottleMs + 80) / 1000.0) + 60))
    $monkey = Invoke-Adb -Device $device -AdbArgs @("shell", "monkey", "-p", $PackageName, "--pct-syskeys", "0", "--throttle", "$ThrottleMs", "-v", "$MonkeyEvents") -TimeoutSeconds $timeout
    "EXIT=$($monkey.ExitCode)`nSTDOUT:`n$($monkey.Out)`nSTDERR:`n$($monkey.Err)" | Set-Content -Encoding UTF8 -Path $monkeyPath
    $monkeyText = "$($monkey.Out)`n$($monkey.Err)"

    [void](Invoke-Adb -Device $device -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 15)
    Start-Sleep -Seconds 3
    $focus = (Invoke-Adb -Device $device -AdbArgs @("shell", "dumpsys", "window") -TimeoutSeconds 10).Out
    $screen = Save-Screenshot -Device $device -Name "after-monkey-$runId"

    $logPath = Join-Path $logDir "$safe-logcat-$runId.log"
    $log = Invoke-Adb -Device $device -AdbArgs @("logcat", "-d", "-t", "3000") -TimeoutSeconds 25
    $log.Out | Set-Content -Encoding UTF8 -Path $logPath
    $fatalMatches = @(($log.Out -split "`r?`n") | Where-Object {
        $_ -match "FATAL EXCEPTION|ANR in $([regex]::Escape($PackageName))|Input dispatching timed out|FlutterError|E/flutter|CRASH:"
    })
    $fatalPath = Join-Path $logDir "$safe-logcat-fatal-$runId.log"
    $fatalMatches | Set-Content -Encoding UTF8 -Path $fatalPath

    $status = if (
        $monkey.ExitCode -eq 0 -and
        $monkeyText -notmatch "CRASH:|// CRASH|ANR|NOT RESPONDING|FATAL EXCEPTION|System appears to have crashed" -and
        $fatalMatches.Count -eq 0 -and
        $focus -match [regex]::Escape($PackageName)
    ) { "PASS" } else { "FAIL" }

    $results.Add([pscustomobject]@{
        device = $device
        status = $status
        monkey_events = $MonkeyEvents
        monkey_exit = $monkey.ExitCode
        fatal_pattern_count = $fatalMatches.Count
        focus_contains_package = ($focus -match [regex]::Escape($PackageName))
        monkey_log = $monkeyPath
        logcat = $logPath
        fatal_log = $fatalPath
        screenshot = $screen
    }) | Out-Null
}

$pass = @($results | Where-Object status -eq "PASS").Count
$fail = @($results | Where-Object status -eq "FAIL").Count
$jsonPath = Join-Path $OutputDir "p2-real-device-monkey-$runId.json"
[pscustomobject]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    package = $PackageName
    monkey_events = $MonkeyEvents
    throttle_ms = $ThrottleMs
    total = $results.Count
    pass = $pass
    fail = $fail
    results = $results
} | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path $jsonPath

$reportPath = Join-Path $OutputDir "report.md"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# P2 Real-Device Monkey") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
$lines.Add("- package: ``$PackageName``") | Out-Null
$lines.Add("- devices: $($Devices -join ', ')") | Out-Null
$lines.Add("- monkey_events: $MonkeyEvents") | Out-Null
$lines.Add("- summary: PASS=$pass, FAIL=$fail") | Out-Null
$lines.Add("- json: ``$jsonPath``") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Device | Status | Fatal | Focus OK | Evidence |") | Out-Null
$lines.Add("| --- | --- | ---: | --- | --- |") | Out-Null
foreach ($result in $results) {
    $lines.Add("| $($result.device) | $($result.status) | $($result.fatal_pattern_count) | $($result.focus_contains_package) | $($result.monkey_log) |") | Out-Null
}
$lines | Set-Content -Encoding UTF8 -Path $reportPath

Write-Host (@{
    report_path = $reportPath
    json_path = $jsonPath
    total = $results.Count
    pass = $pass
    fail = $fail
} | ConvertTo-Json -Compress)
