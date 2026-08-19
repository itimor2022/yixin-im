#Requires -Version 7.0
<#
.SYNOPSIS
编排 P0 至 P5 的最高权限全量 Android 验收流程。

.DESCRIPTION
按阶段调用构建、双设备、可靠性、后台联动和破坏性状态脚本，统一收集日志
与报告。部分阶段会安装 APK、修改测试账号/数据库状态并执行 Monkey；
首次运行应使用 OnlyPhase 和各 Skip 参数逐阶段确认环境。

.PARAMETER OnlyPhase
只执行指定 P0-P5 阶段；为空时运行完整套件。

.PARAMETER StopOnFail
任一阶段失败后停止，避免在错误环境继续执行后续写入或破坏性流程。

.PARAMETER AdminPassword
测试后台账号密码；生产凭据不得通过命令历史或报告传入。

.EXAMPLE
pwsh -File scripts/full_power_p0_p5_qa.ps1 -OnlyPhase P0 -SkipMonkey
#>
[CmdletBinding()]
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$PackageName = "com.genericim.ma100",
    [string]$DeviceA = "8MY0220C17006781",
    [string]$DeviceB = "UQG5T20915006269",
    [string]$ApkPath = "artifacts\local-real-device-apk-20260625-005055\genericim-local-real-device-release.apk",
    [string]$AdminUsername = "admin",
    [string]$AdminPassword = "123456",
    [int]$ReliabilityBurstCount = 60,
    [int]$CallCycles = 3,
    [int]$StressIterations = 8,
    [int]$MonkeyEvents = 300,
    [ValidateSet("", "P0", "P1", "P2", "P3", "P4", "P5")]
    [string]$OnlyPhase = "",
    [switch]$StopOnFail,
    [switch]$SkipUi,
    [switch]$SkipMonkey,
    [switch]$SkipAnalyze
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$pwsh = "pwsh"
if (-not (Test-Path -LiteralPath $pwsh)) {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) { throw "PowerShell 7 not found." }
    $pwsh = $pwshCmd.Source
}
if (-not (Test-Path -LiteralPath $Adb)) { throw "adb not found: $Adb" }

$runId = (Get-Date).ToString("yyyyMMdd-HHmmss")
$outputRoot = Join-Path "release-archives\qa-20260625\full-power-p0-p5" $runId
$logDir = Join-Path $outputRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$script:Results = New-Object System.Collections.Generic.List[object]
$script:Artifacts = New-Object System.Collections.Generic.List[string]

function Write-RunLog {
    param([string]$Message)
    $line = "$(Get-Date -Format 'HH:mm:ss') $Message"
    Write-Host $line
    $line | Add-Content -Encoding UTF8 -Path (Join-Path $outputRoot "run.log")
}

function Add-StepResult {
    param(
        [string]$Phase,
        [string]$Name,
        [ValidateSet("PASS", "FAIL", "WARN", "SKIP", "INFO")]
        [string]$Status,
        [string]$Detail = "",
        [string[]]$Artifacts = @()
    )
    $entry = [pscustomobject]@{
        phase = $Phase
        name = $Name
        status = $Status
        detail = $Detail
        artifacts = $Artifacts
        time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $script:Results.Add($entry) | Out-Null
    foreach ($artifact in $Artifacts) {
        if (-not [string]::IsNullOrWhiteSpace($artifact)) {
            $script:Artifacts.Add($artifact) | Out-Null
        }
    }
    Write-RunLog "[$Phase][$Status] $Name - $Detail"
    if ($StopOnFail -and $Status -eq "FAIL") {
        throw "StopOnFail: $Phase $Name failed."
    }
}

function Invoke-ProcessCapture {
    param(
        [string]$FileName,
        [string[]]$Arguments,
        [string]$LogName,
        [int]$TimeoutSeconds = 600
    )
    $outPath = Join-Path $logDir "$LogName.out.log"
    $errPath = Join-Path $logDir "$LogName.err.log"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch {}
        try { $p.WaitForExit(2000) | Out-Null } catch {}
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())"
        $stdout | Set-Content -Encoding UTF8 -Path $outPath
        $stderr | Set-Content -Encoding UTF8 -Path $errPath
        return [pscustomobject]@{ ExitCode = 124; Out = $stdout; Err = $stderr; OutPath = $outPath; ErrPath = $errPath }
    }

    $stdout = $outTask.GetAwaiter().GetResult()
    $stderr = $errTask.GetAwaiter().GetResult()
    $stdout | Set-Content -Encoding UTF8 -Path $outPath
    $stderr | Set-Content -Encoding UTF8 -Path $errPath
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $stdout; Err = $stderr; OutPath = $outPath; ErrPath = $errPath }
}

function Find-ChildArtifacts {
    param([string]$Text)
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match "^(Report|JSON|APK):\s*(.+)$") {
            $candidate = $Matches[2].Trim()
            if ($candidate) { $found.Add($candidate) | Out-Null }
        }
    }
    return @($found)
}

function Invoke-QaScript {
    param(
        [string]$Phase,
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 900,
        [switch]$Optional
    )
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        $status = if ($Optional) { "SKIP" } else { "FAIL" }
        Add-StepResult -Phase $Phase -Name $Name -Status $status -Detail "script not found: $ScriptPath"
        return
    }

    Write-RunLog "Running $Phase $Name"
    $safeLogName = (($Phase + "-" + $Name) -replace "[^a-zA-Z0-9_-]", "_")
    $result = Invoke-ProcessCapture -FileName $pwsh -Arguments (@("-NoProfile", "-File", $ScriptPath) + $Arguments) -LogName $safeLogName -TimeoutSeconds $TimeoutSeconds
    $artifacts = @($result.OutPath, $result.ErrPath) + (Find-ChildArtifacts -Text ($result.Out + "`n" + $result.Err))
    if ($result.ExitCode -eq 0) {
        Add-StepResult -Phase $Phase -Name $Name -Status "PASS" -Detail "exit=0" -Artifacts $artifacts
    } else {
        $tail = (($result.Err + "`n" + $result.Out) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join " / "
        Add-StepResult -Phase $Phase -Name $Name -Status "FAIL" -Detail "exit=$($result.ExitCode); $tail" -Artifacts $artifacts
    }
}

function Invoke-CommandStep {
    param(
        [string]$Phase,
        [string]$Name,
        [string]$FileName,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 900
    )
    $command = Get-Command $FileName -ErrorAction SilentlyContinue
    if (-not $command) {
        Add-StepResult -Phase $Phase -Name $Name -Status "FAIL" -Detail "command not found: $FileName"
        return
    }
    Write-RunLog "Running $Phase $Name"
    $safeLogName = (($Phase + "-" + $Name) -replace "[^a-zA-Z0-9_-]", "_")
    $result = Invoke-ProcessCapture -FileName $command.Source -Arguments $Arguments -LogName $safeLogName -TimeoutSeconds $TimeoutSeconds
    $artifacts = @($result.OutPath, $result.ErrPath)
    if ($result.ExitCode -eq 0) {
        Add-StepResult -Phase $Phase -Name $Name -Status "PASS" -Detail "exit=0" -Artifacts $artifacts
    } else {
        $tail = (($result.Err + "`n" + $result.Out) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join " / "
        Add-StepResult -Phase $Phase -Name $Name -Status "FAIL" -Detail "exit=$($result.ExitCode); $tail" -Artifacts $artifacts
    }
}

function Invoke-Adb {
    param([string]$Device, [string[]]$Arguments, [int]$TimeoutSeconds = 30)
    return Invoke-ProcessCapture -FileName $Adb -Arguments (@("-s", $Device) + $Arguments) -LogName "adb-$($Device -replace '[^a-zA-Z0-9_-]','_')-$([guid]::NewGuid().ToString('N').Substring(0,8))" -TimeoutSeconds $TimeoutSeconds
}

function Save-Screenshot {
    param([string]$Device, [string]$Name)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $remote = "/sdcard/genericim-p0p5-$Name.png"
    $local = Join-Path $outputRoot "$safe-$Name.png"
    [void](Invoke-Adb -Device $Device -Arguments @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -Arguments @("pull", $remote, $local) -TimeoutSeconds 20)
    return $local
}

function Assert-Health {
    try {
        $health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 10
        if ($health.status -eq "ok") {
            Add-StepResult -Phase "P0" -Name "Backend health" -Status "PASS" -Detail "$BaseUrl/health ok"
        } else {
            Add-StepResult -Phase "P0" -Name "Backend health" -Status "FAIL" -Detail "unexpected health: $($health | ConvertTo-Json -Compress)"
        }
    } catch {
        Add-StepResult -Phase "P0" -Name "Backend health" -Status "FAIL" -Detail $_.Exception.Message
    }
}

function Assert-DeviceInstalled {
    param([string]$Device)
    $pkg = Invoke-Adb -Device $Device -Arguments @("shell", "dumpsys", "package", $PackageName) -TimeoutSeconds 20
    $focus = Invoke-Adb -Device $Device -Arguments @("shell", "dumpsys", "window") -TimeoutSeconds 20
    $screen = Save-Screenshot -Device $Device -Name "installed"
    if ($pkg.ExitCode -eq 0 -and $pkg.Out -match "Package \[$([regex]::Escape($PackageName))\]" -and $pkg.Out -match "versionName=4\.0\.3") {
        Add-StepResult -Phase "P0" -Name "Device installed $Device" -Status "PASS" -Detail "package installed; versionName=4.0.3" -Artifacts @($pkg.OutPath, $focus.OutPath, $screen)
    } else {
        Add-StepResult -Phase "P0" -Name "Device installed $Device" -Status "FAIL" -Detail "package/version check failed" -Artifacts @($pkg.OutPath, $pkg.ErrPath, $focus.OutPath, $screen)
    }
}

function Write-Reports {
    $pass = @($script:Results | Where-Object status -eq "PASS").Count
    $warn = @($script:Results | Where-Object status -eq "WARN").Count
    $fail = @($script:Results | Where-Object status -eq "FAIL").Count
    $skip = @($script:Results | Where-Object status -eq "SKIP").Count
    $status = if ($fail -gt 0) { "FAIL" } elseif ($warn -gt 0) { "WARN" } else { "PASS" }
    $summary = [ordered]@{
        generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
        run_id = $runId
        status = $status
        pass = $pass
        warn = $warn
        fail = $fail
        skip = $skip
        package_name = $PackageName
        device_a = $DeviceA
        device_b = $DeviceB
        apk = $ApkPath
        base_url = $BaseUrl
        results = $script:Results
        artifacts = @($script:Artifacts | Select-Object -Unique)
    }
    $jsonPath = Join-Path $outputRoot "results.json"
    $summary | ConvertTo-Json -Depth 50 | Set-Content -Encoding UTF8 -Path $jsonPath

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# 通用IM P0-P5 最高权限全量测试报告") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("- run_id: $runId") | Out-Null
    $md.Add("- time: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))") | Out-Null
    $md.Add("- status: $status") | Out-Null
    $md.Add("- summary: PASS=$pass, WARN=$warn, FAIL=$fail, SKIP=$skip") | Out-Null
    $md.Add("- apk: ``$ApkPath``") | Out-Null
    $md.Add("- devices: ``$DeviceA``, ``$DeviceB``") | Out-Null
    $md.Add("- json: ``$jsonPath``") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("| Phase | Item | Status | Detail |") | Out-Null
    $md.Add("| --- | --- | --- | --- |") | Out-Null
    foreach ($r in $script:Results) {
        $detail = (($r.detail -replace "\|", "/") -replace "`r?`n", " ").Trim()
        $md.Add("| $($r.phase) | $($r.name) | $($r.status) | $detail |") | Out-Null
    }
    $md.Add("") | Out-Null
    $md.Add("## Evidence") | Out-Null
    foreach ($artifact in @($script:Artifacts | Select-Object -Unique)) {
        $md.Add("- ``$artifact``") | Out-Null
    }
    $reportPath = Join-Path $outputRoot "report.md"
    $md | Set-Content -Encoding UTF8 -Path $reportPath
    Write-Host "Full-power status: $status PASS=$pass WARN=$warn FAIL=$fail SKIP=$skip"
    Write-Host "Report: $reportPath"
    Write-Host "JSON: $jsonPath"
    if ($fail -gt 0) { exit 1 }
}

function Test-ShouldRunPhase {
    param([string]$Phase)
    return [string]::IsNullOrWhiteSpace($OnlyPhase) -or $OnlyPhase -eq $Phase
}

try {
    Write-RunLog "Full-power P0-P5 QA started. run_id=$runId"
    if (Test-ShouldRunPhase -Phase "P0") {
        Assert-Health
        foreach ($device in @($DeviceA, $DeviceB)) { Assert-DeviceInstalled -Device $device }

        Invoke-QaScript -Phase "P0" -Name "Message reliability and call resume" -ScriptPath "scripts\reliability_call_resume_suite.ps1" -Arguments @(
            "-Adb", $Adb,
            "-BaseUrl", $BaseUrl,
            "-PackageName", $PackageName,
            "-AliceDevice", $DeviceA,
            "-BobDevice", $DeviceB,
            "-BurstCount", "$ReliabilityBurstCount",
            "-CallCycles", "$CallCycles"
        ) -TimeoutSeconds 1800
    }

    if (Test-ShouldRunPhase -Phase "P1") {
        if ($SkipUi) {
            Add-StepResult -Phase "P1" -Name "Real-device UI traversal" -Status "SKIP" -Detail "SkipUi was set."
            Add-StepResult -Phase "P1" -Name "Message persistence UI" -Status "SKIP" -Detail "SkipUi was set."
            Add-StepResult -Phase "P1" -Name "Write flows UI" -Status "SKIP" -Detail "SkipUi was set."
        } else {
            Invoke-QaScript -Phase "P1" -Name "Real-device UI traversal" -ScriptPath "scripts\fast_real_device_full_suite.ps1" -Arguments @(
                "-BaseDir", $outputRoot,
                "-DeviceA", $DeviceA,
                "-DeviceB", $DeviceB,
                "-PackageName", $PackageName,
                "-IncludeCallProbe"
            ) -TimeoutSeconds 900
            Invoke-QaScript -Phase "P1" -Name "Message persistence UI" -ScriptPath "scripts\fast_real_device_message_persistence.ps1" -Arguments @(
                "-BaseDir", $outputRoot,
                "-DeviceB", $DeviceB,
                "-PackageName", $PackageName
            ) -TimeoutSeconds 600
            Invoke-QaScript -Phase "P1" -Name "Write flows UI" -ScriptPath "scripts\fast_real_device_write_flows.ps1" -Arguments @(
                "-BaseDir", $outputRoot,
                "-DeviceB", $DeviceB,
                "-PackageName", $PackageName
            ) -TimeoutSeconds 600
        }
    }

    if (Test-ShouldRunPhase -Phase "P2") {
        Invoke-QaScript -Phase "P2" -Name "Stress unread push consistency" -ScriptPath "scripts\fast_real_device_stress.ps1" -Arguments @(
            "-BaseDir", $outputRoot,
            "-DeviceA", $DeviceA,
            "-DeviceB", $DeviceB,
            "-PackageName", $PackageName,
            "-Iterations", "$StressIterations"
        ) -TimeoutSeconds 900
        Invoke-QaScript -Phase "P2" -Name "Network resume" -ScriptPath "scripts\p2_real_device_network_resume.ps1" -Arguments @(
            "-Adb", $Adb,
            "-BaseUrl", $BaseUrl,
            "-PackageName", $PackageName,
            "-Device", $DeviceB,
            "-OutputDir", (Join-Path $outputRoot "p2-network-resume")
        ) -TimeoutSeconds 900
        Invoke-QaScript -Phase "P2" -Name "Push notification" -ScriptPath "scripts\p2_real_device_push_notification.ps1" -Arguments @(
            "-Adb", $Adb,
            "-BaseUrl", $BaseUrl,
            "-PackageName", $PackageName,
            "-Device", $DeviceB,
            "-OutputDir", (Join-Path $outputRoot "p2-push-notification")
        ) -TimeoutSeconds 900
        if ($SkipMonkey) {
            Add-StepResult -Phase "P2" -Name "Monkey fast random operation" -Status "SKIP" -Detail "SkipMonkey was set."
        } else {
            foreach ($monkeyDevice in @($DeviceA, $DeviceB)) {
                $monkeyOutputDir = Join-Path $outputRoot "p2-monkey-$monkeyDevice"
                Invoke-QaScript -Phase "P2" -Name "Monkey fast random operation $monkeyDevice" -ScriptPath "scripts\p2_real_device_monkey.ps1" -Arguments @(
                    "-Adb", $Adb,
                    "-PackageName", $PackageName,
                    "-Devices", $monkeyDevice,
                    "-OutputDir", $monkeyOutputDir,
                    "-MonkeyEvents", "$MonkeyEvents"
                ) -TimeoutSeconds 900
            }
        }
    }

    if (Test-ShouldRunPhase -Phase "P3") {
        Invoke-QaScript -Phase "P3" -Name "Release package and device experience" -ScriptPath "scripts\p3_real_device_release_experience.ps1" -Arguments @(
            "-Adb", $Adb,
            "-Devices", $DeviceA, $DeviceB,
            "-PackageName", $PackageName,
            "-ApkPath", $ApkPath,
            "-OutputDir", (Join-Path $outputRoot "p3-release-experience")
        ) -TimeoutSeconds 900
    }

    if (Test-ShouldRunPhase -Phase "P4") {
        Invoke-QaScript -Phase "P4" -Name "Destructive isolated state flows" -ScriptPath "scripts\p3_destructive_state_flows.ps1" -Arguments @(
            "-BaseUrl", $BaseUrl,
            "-OutputDir", (Join-Path $outputRoot "p4-destructive-state-flows")
        ) -TimeoutSeconds 600
        Invoke-QaScript -Phase "P4" -Name "Admin backend linkage" -ScriptPath "scripts\p4_admin_backend_linkage.ps1" -Arguments @(
            "-BaseUrl", $BaseUrl,
            "-OutputDir", (Join-Path $outputRoot "p4-admin-backend-linkage"),
            "-AdminUsername", $AdminUsername,
            "-AdminPassword", $AdminPassword
        ) -TimeoutSeconds 600
    }

    if (Test-ShouldRunPhase -Phase "P5") {
        Invoke-QaScript -Phase "P5" -Name "Mojibake guard" -ScriptPath "scripts\check-mojibake.ps1" -TimeoutSeconds 120

        if (Test-Path -LiteralPath $ApkPath) {
            $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ApkPath
            Add-StepResult -Phase "P5" -Name "APK artifact hash" -Status "PASS" -Detail "SHA256=$($hash.Hash); size=$((Get-Item -LiteralPath $ApkPath).Length)"
        } else {
            Add-StepResult -Phase "P5" -Name "APK artifact hash" -Status "FAIL" -Detail "APK not found: $ApkPath"
        }

        if ($SkipAnalyze) {
            Add-StepResult -Phase "P5" -Name "Flutter analyze" -Status "SKIP" -Detail "SkipAnalyze was set."
        } else {
            Invoke-CommandStep -Phase "P5" -Name "Flutter analyze" -FileName "flutter" -Arguments @("analyze") -TimeoutSeconds 900
        }
    }
} finally {
    Write-Reports
}
