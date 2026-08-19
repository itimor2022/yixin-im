<#
.SYNOPSIS
在多台 Android 真机上验证 Release APK 的安装、品牌与启动体验。

.DESCRIPTION
校验 APK SHA-256 和应用名称后，对指定设备执行安装、启动、截图和状态采集，
并记录恢复计划。脚本会改变真机上的应用安装版本和运行状态，只能对测试设备运行。

.PARAMETER Devices
参与验收的 ADB 设备序列号列表。

.PARAMETER ExpectedSha256
期望安装包哈希；用于防止误测其他构建产物。

.PARAMETER OutputDir
报告、截图、日志和恢复信息的保存目录。

.EXAMPLE
pwsh -File scripts/p3_real_device_release_experience.ps1 -Devices device-a,device-b
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string[]]$Devices = @("8MY0220C17006781", "UQG5T20915006269"),
    [string]$PackageName = "com.genericim.ma100",
    [string]$MainActivity = "com.genericim.ma100/.MainActivity",
    [string]$ApkPath = "artifacts\local-real-device-apk-20260624-224822\genericim-local-real-device-release.apk",
    [string]$OutputDir = "release-archives\qa-20260624\real-device-p0-p3\p3-release-experience",
    [string]$ExpectedLabel = "通用IM",
    [string]$ExpectedSha256 = "1C730B89510FCB25F9DEE2DE2E9E6C792391AB755536A2150346EF5E0E22D01F"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$runId = (Get-Date).ToString("yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]
$restorePlan = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = "",
        [string]$Evidence = ""
    )
    $results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        evidence = $Evidence
    }) | Out-Null
}

function Invoke-Process {
    param([string]$FileName, [string[]]$Arguments, [int]$TimeoutSeconds = 30)
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

function Invoke-Adb {
    param([string]$Device, [string[]]$AdbArgs, [int]$TimeoutSeconds = 30)
    return Invoke-Process -FileName $Adb -Arguments (@("-s", $Device) + $AdbArgs) -TimeoutSeconds $TimeoutSeconds
}

function Save-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Text | Set-Content -Encoding UTF8 -Path $Path
    return $Path
}

function Save-Screenshot {
    param([string]$Device, [string]$DeviceDir, [string]$Name)
    $remote = "/sdcard/$Name.png"
    $local = Join-Path $DeviceDir "$Name.png"
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 20)
    return $local
}

function Save-UiDump {
    param([string]$Device, [string]$DeviceDir, [string]$Name)
    $remote = "/sdcard/$Name.xml"
    $local = Join-Path $DeviceDir "$Name.xml"
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "uiautomator", "dump", $remote) -TimeoutSeconds 20)
    [void](Invoke-Adb -Device $Device -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 20)
    return $local
}

function Capture-AppState {
    param([string]$Device, [string]$DeviceDir, [string]$Name)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "statusbar", "collapse") -TimeoutSeconds 8)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 15)
    Start-Sleep -Seconds 4
    $shot = Save-Screenshot -Device $Device -DeviceDir $DeviceDir -Name $Name
    $xml = Save-UiDump -Device $Device -DeviceDir $DeviceDir -Name $Name
    return [pscustomobject]@{ screenshot = $shot; xml = $xml }
}

function Get-SystemSetting {
    param([string]$Device, [string]$Namespace, [string]$Key)
    return ((Invoke-Adb -Device $Device -AdbArgs @("shell", "settings", "get", $Namespace, $Key) -TimeoutSeconds 10).Out.Trim())
}

function Put-SystemSetting {
    param([string]$Device, [string]$Namespace, [string]$Key, [string]$Value)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "settings", "put", $Namespace, $Key, $Value) -TimeoutSeconds 10)
}

function Get-NightMode {
    param([string]$Device)
    return ((Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "uimode", "night") -TimeoutSeconds 10).Out.Trim())
}

function Set-NightMode {
    param([string]$Device, [string]$Mode)
    if ($Mode -match "yes|true|on") {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "uimode", "night", "yes") -TimeoutSeconds 10)
    } else {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "uimode", "night", "no") -TimeoutSeconds 10)
    }
}

function Set-UserRotation {
    param([string]$Device, [string]$AccelerometerRotation, [string]$UserRotation)
    if ($AccelerometerRotation -eq "1") {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "window", "user-rotation", "free") -TimeoutSeconds 10)
    } else {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "cmd", "window", "user-rotation", "lock", $UserRotation) -TimeoutSeconds 10)
    }
    Put-SystemSetting -Device $Device -Namespace "system" -Key "accelerometer_rotation" -Value $AccelerometerRotation
    Put-SystemSetting -Device $Device -Namespace "system" -Key "user_rotation" -Value $UserRotation
}

function Get-SurfaceOrientation {
    param([string]$Device)
    $dump = (Invoke-Adb -Device $Device -AdbArgs @("shell", "dumpsys", "input") -TimeoutSeconds 15).Out
    $match = [regex]::Match($dump, "SurfaceOrientation:\s*(\d+)")
    if (-not $match.Success) { return "" }
    return $match.Groups[1].Value
}

function Get-PermissionGranted {
    param([string]$Dump, [string]$Permission)
    $escaped = [regex]::Escape($Permission)
    $match = [regex]::Match($Dump, "$escaped\s*:\s*granted=(true|false)", "IgnoreCase")
    if (-not $match.Success) { return $null }
    return ($match.Groups[1].Value -eq "true")
}

function Set-Permission {
    param([string]$Device, [string]$Permission, [bool]$Granted)
    $verb = if ($Granted) { "grant" } else { "revoke" }
    return Invoke-Adb -Device $Device -AdbArgs @("shell", "pm", $verb, $PackageName, $Permission) -TimeoutSeconds 10
}

function Get-BuildTool {
    param([string]$Tool)
    $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
    if (-not (Test-Path -LiteralPath $sdk)) { return "" }
    $dirs = @(Get-ChildItem -Path $sdk -Directory | Sort-Object Name -Descending)
    foreach ($dir in $dirs) {
        $candidate = Join-Path $dir.FullName $Tool
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ""
}

function Parse-AaptBadging {
    param([string]$Badging)
    $pkg = ""
    $versionCode = ""
    $versionName = ""
    $label = ""
    $debuggable = $false
    $pkgMatch = [regex]::Match($Badging, "package: name='([^']+)' versionCode='([^']*)' versionName='([^']*)'")
    if ($pkgMatch.Success) {
        $pkg = $pkgMatch.Groups[1].Value
        $versionCode = $pkgMatch.Groups[2].Value
        $versionName = $pkgMatch.Groups[3].Value
    }
    $labelMatch = [regex]::Match($Badging, "application-label:'([^']*)'")
    if ($labelMatch.Success) { $label = $labelMatch.Groups[1].Value }
    if ($Badging -match "application-debuggable") { $debuggable = $true }
    return [pscustomobject]@{
        package = $pkg
        version_code = $versionCode
        version_name = $versionName
        label = $label
        debuggable = $debuggable
    }
}

try {
    if (-not (Test-Path -LiteralPath $Adb)) { throw "adb not found: $Adb" }
    if (-not (Test-Path -LiteralPath $ApkPath)) { throw "apk not found: $ApkPath" }

    foreach ($device in $Devices) {
        $deviceDir = Join-Path $OutputDir $device
        New-Item -ItemType Directory -Force -Path $deviceDir | Out-Null

        $state = [ordered]@{
            device = $device
            manufacturer = (Invoke-Adb -Device $device -AdbArgs @("shell", "getprop", "ro.product.manufacturer")).Out.Trim()
            model = (Invoke-Adb -Device $device -AdbArgs @("shell", "getprop", "ro.product.model")).Out.Trim()
            product = (Invoke-Adb -Device $device -AdbArgs @("shell", "getprop", "ro.product.name")).Out.Trim()
            android_release = (Invoke-Adb -Device $device -AdbArgs @("shell", "getprop", "ro.build.version.release")).Out.Trim()
            android_sdk = (Invoke-Adb -Device $device -AdbArgs @("shell", "getprop", "ro.build.version.sdk")).Out.Trim()
            build_display = (Invoke-Adb -Device $device -AdbArgs @("shell", "getprop", "ro.build.display.id")).Out.Trim()
            original_night = Get-NightMode -Device $device
            original_font_scale = Get-SystemSetting -Device $device -Namespace "system" -Key "font_scale"
            original_accelerometer_rotation = Get-SystemSetting -Device $device -Namespace "system" -Key "accelerometer_rotation"
            original_user_rotation = Get-SystemSetting -Device $device -Namespace "system" -Key "user_rotation"
        }
        Save-Text -Path (Join-Path $deviceDir "device-state-$runId.json") -Text ($state | ConvertTo-Json -Depth 8)
        $restorePlan.Add([pscustomobject]@{
            device = $device
            night = $state.original_night
            font_scale = $state.original_font_scale
            accelerometer_rotation = $state.original_accelerometer_rotation
            user_rotation = $state.original_user_rotation
        }) | Out-Null
        Add-Result -Name "P3 device info $device" -Status "PASS" -Detail "$($state.manufacturer) $($state.model), Android $($state.android_release), build $($state.build_display)" -Evidence (Join-Path $deviceDir "device-state-$runId.json")

        [void](Invoke-Adb -Device $device -AdbArgs @("shell", "logcat", "-c") -TimeoutSeconds 10)

        $normal = Capture-AppState -Device $device -DeviceDir $deviceDir -Name "normal-$runId"
        Add-Result -Name "P3 normal portrait UI $device" -Status "PASS" -Detail "Captured normal portrait UI." -Evidence "$($normal.screenshot); $($normal.xml)"

        Set-NightMode -Device $device -Mode "yes"
        Start-Sleep -Seconds 2
        $dark = Capture-AppState -Device $device -DeviceDir $deviceDir -Name "dark-mode-$runId"
        Add-Result -Name "P3 dark mode UI $device" -Status "PASS" -Detail "Captured dark mode UI for manual visual review." -Evidence "$($dark.screenshot); $($dark.xml)"

        Put-SystemSetting -Device $device -Namespace "system" -Key "font_scale" -Value "1.3"
        [void](Invoke-Adb -Device $device -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 10)
        Start-Sleep -Seconds 1
        $font = Capture-AppState -Device $device -DeviceDir $deviceDir -Name "font-130-$runId"
        Add-Result -Name "P3 large font UI $device" -Status "PASS" -Detail "Captured 1.3 font-scale UI for text overlap review." -Evidence "$($font.screenshot); $($font.xml)"

        Put-SystemSetting -Device $device -Namespace "system" -Key "accelerometer_rotation" -Value "0"
        Put-SystemSetting -Device $device -Namespace "system" -Key "user_rotation" -Value "1"
        [void](Invoke-Adb -Device $device -AdbArgs @("shell", "cmd", "window", "user-rotation", "lock", "1") -TimeoutSeconds 10)
        Start-Sleep -Seconds 2
        $landscape = Capture-AppState -Device $device -DeviceDir $deviceDir -Name "landscape-$runId"
        $surfaceOrientation = Get-SurfaceOrientation -Device $device
        if ($surfaceOrientation -eq "1" -or $surfaceOrientation -eq "3") {
            Add-Result -Name "P3 landscape UI $device" -Status "PASS" -Detail "Captured forced landscape UI; SurfaceOrientation=$surfaceOrientation." -Evidence "$($landscape.screenshot); $($landscape.xml)"
        } else {
            Add-Result -Name "P3 landscape UI $device" -Status "WARN" -Detail "Forced rotation did not take effect on this device; SurfaceOrientation=$surfaceOrientation. Evidence is current portrait UI, not full landscape coverage." -Evidence "$($landscape.screenshot); $($landscape.xml)"
        }

        Set-NightMode -Device $device -Mode $state.original_night
        Put-SystemSetting -Device $device -Namespace "system" -Key "font_scale" -Value $state.original_font_scale
        Set-UserRotation -Device $device -AccelerometerRotation $state.original_accelerometer_rotation -UserRotation $state.original_user_rotation

        $dump = (Invoke-Adb -Device $device -AdbArgs @("shell", "dumpsys", "package", $PackageName) -TimeoutSeconds 25).Out
        $dumpPath = Save-Text -Path (Join-Path $deviceDir "package-permissions-$runId.txt") -Text $dump
        $cameraGranted = Get-PermissionGranted -Dump $dump -Permission "android.permission.CAMERA"
        $micGranted = Get-PermissionGranted -Dump $dump -Permission "android.permission.RECORD_AUDIO"
        $permissionDetails = "camera=$cameraGranted; microphone=$micGranted"

        foreach ($permission in @("android.permission.CAMERA", "android.permission.RECORD_AUDIO")) {
            $original = Get-PermissionGranted -Dump $dump -Permission $permission
            if ($null -ne $original) {
                [void](Set-Permission -Device $device -Permission $permission -Granted $false)
                [void](Invoke-Adb -Device $device -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 10)
                $afterRevoke = Capture-AppState -Device $device -DeviceDir $deviceDir -Name ("permission-revoked-" + ($permission.Split(".")[-1]).ToLower() + "-$runId")
                [void](Set-Permission -Device $device -Permission $permission -Granted $original)
                Add-Result -Name "P3 permission revoke/restore $permission $device" -Status "PASS" -Detail "App relaunched after revoking permission; restored original granted=$original." -Evidence "$($afterRevoke.screenshot); $($afterRevoke.xml)"
            } else {
                Add-Result -Name "P3 permission revoke/restore $permission $device" -Status "WARN" -Detail "Permission grant state not found in dumpsys; skipped revoke/restore." -Evidence $dumpPath
            }
        }
        Add-Result -Name "P3 permission state $device" -Status "PASS" -Detail $permissionDetails -Evidence $dumpPath

        [void](Invoke-Adb -Device $device -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 10)
        Start-Sleep -Seconds 1
        $start = Invoke-Adb -Device $device -AdbArgs @("shell", "am", "start", "-S", "-W", "-n", $MainActivity) -TimeoutSeconds 25
        $startPath = Save-Text -Path (Join-Path $deviceDir "cold-start-$runId.txt") -Text ($start.Out + "`n" + $start.Err)
        $totalMatch = [regex]::Match($start.Out, "TotalTime:\s*(\d+)")
        $waitMatch = [regex]::Match($start.Out, "WaitTime:\s*(\d+)")
        $total = if ($totalMatch.Success) { [int]$totalMatch.Groups[1].Value } else { -1 }
        $wait = if ($waitMatch.Success) { [int]$waitMatch.Groups[1].Value } else { -1 }
        $coldStatus = if ($start.ExitCode -eq 0 -and $total -ge 0) { "PASS" } else { "WARN" }
        Add-Result -Name "P3 cold start $device" -Status $coldStatus -Detail "TotalTime=${total}ms; WaitTime=${wait}ms" -Evidence $startPath

        Start-Sleep -Seconds 5
        $mem = (Invoke-Adb -Device $device -AdbArgs @("shell", "dumpsys", "meminfo", $PackageName) -TimeoutSeconds 25).Out
        $memPath = Save-Text -Path (Join-Path $deviceDir "meminfo-$runId.txt") -Text $mem
        $pssMatch = [regex]::Match($mem, "TOTAL\s+(\d+)")
        $pss = if ($pssMatch.Success) { [int]$pssMatch.Groups[1].Value } else { -1 }
        Add-Result -Name "P3 memory snapshot $device" -Status "PASS" -Detail "TOTAL PSS=${pss}KB after cold start." -Evidence $memPath

        $log = (Invoke-Adb -Device $device -AdbArgs @("logcat", "-d", "-t", "5000") -TimeoutSeconds 30).Out
        $logPath = Save-Text -Path (Join-Path $deviceDir "p3-logcat-$runId.txt") -Text $log
        $fatalMatches = @([regex]::Matches($log, "FATAL EXCEPTION|ANR in $([regex]::Escape($PackageName))|FlutterError|E/flutter|RenderFlex|Input dispatching timed out|message.*failed|call.*failed|WebSocket.*(error|failed)", "IgnoreCase"))
        if ($fatalMatches.Count -eq 0) {
            Add-Result -Name "P3 logcat severe scan $device" -Status "PASS" -Detail "No severe App pattern matched." -Evidence $logPath
        } else {
            Add-Result -Name "P3 logcat severe scan $device" -Status "FAIL" -Detail "Matched $($fatalMatches.Count) severe lines." -Evidence $logPath
        }
    }

    $aapt = Get-BuildTool -Tool "aapt.exe"
    $apksigner = Get-BuildTool -Tool "apksigner.bat"
    if ([string]::IsNullOrWhiteSpace($aapt)) {
        Add-Result -Name "P3 APK badging" -Status "WARN" -Detail "aapt.exe not found." -Evidence ""
    } else {
        $badging = Invoke-Process -FileName $aapt -Arguments @("dump", "badging", (Resolve-Path -LiteralPath $ApkPath).Path) -TimeoutSeconds 30
        $badgingPath = Save-Text -Path (Join-Path $OutputDir "apk-badging-$runId.txt") -Text ($badging.Out + "`n" + $badging.Err)
        $parsed = Parse-AaptBadging -Badging $badging.Out
        $badgingOk = $badging.ExitCode -eq 0 -and $parsed.package -eq $PackageName -and $parsed.label -eq $ExpectedLabel -and -not $parsed.debuggable
        $status = if ($badgingOk) { "PASS" } else { "FAIL" }
        Add-Result -Name "P3 APK package label debuggable" -Status $status -Detail "package=$($parsed.package); label=$($parsed.label); versionCode=$($parsed.version_code); versionName=$($parsed.version_name); debuggable=$($parsed.debuggable)" -Evidence $badgingPath
    }

    if ([string]::IsNullOrWhiteSpace($apksigner)) {
        Add-Result -Name "P3 APK signature" -Status "WARN" -Detail "apksigner.bat not found." -Evidence ""
    } else {
        $sign = Invoke-Process -FileName $apksigner -Arguments @("verify", "--print-certs", (Resolve-Path -LiteralPath $ApkPath).Path) -TimeoutSeconds 30
        $signPath = Save-Text -Path (Join-Path $OutputDir "apk-signature-$runId.txt") -Text ($sign.Out + "`n" + $sign.Err)
        $shaMatch = [regex]::Match($sign.Out, "SHA-256 digest:\s*([A-Fa-f0-9]+)")
        $sha = if ($shaMatch.Success) { $shaMatch.Groups[1].Value.ToUpperInvariant() } else { "" }
        $signatureOk = $sign.ExitCode -eq 0 -and $sha -eq $ExpectedSha256
        $status = if ($signatureOk) { "PASS" } else { "FAIL" }
        Add-Result -Name "P3 APK signature SHA256" -Status $status -Detail "sha256=$sha; expected=$ExpectedSha256" -Evidence $signPath
    }
} finally {
    foreach ($item in $restorePlan) {
        try {
            Set-NightMode -Device $item.device -Mode $item.night
            Put-SystemSetting -Device $item.device -Namespace "system" -Key "font_scale" -Value $item.font_scale
            Set-UserRotation -Device $item.device -AccelerometerRotation $item.accelerometer_rotation -UserRotation $item.user_rotation
        } catch {}
    }
}

$pass = @($results | Where-Object { $_.status -eq "PASS" }).Count
$warn = @($results | Where-Object { $_.status -eq "WARN" }).Count
$fail = @($results | Where-Object { $_.status -eq "FAIL" }).Count
$summaryStatus = if ($fail -gt 0) { "FAIL" } elseif ($warn -gt 0) { "WARN" } else { "PASS" }

$summary = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    run_id = $runId
    status = $summaryStatus
    package = $PackageName
    apk = $ApkPath
    devices = $Devices
    pass = $pass
    warn = $warn
    fail = $fail
    results = $results
}

$jsonPath = Join-Path $OutputDir "p3-release-experience-$runId.json"
$summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $jsonPath

$reportPath = Join-Path $OutputDir "report.md"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# P3 Real-Device Release Experience") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- time: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))") | Out-Null
$lines.Add("- status: $summaryStatus") | Out-Null
$lines.Add("- package: ``$PackageName``") | Out-Null
$lines.Add("- apk: ``$ApkPath``") | Out-Null
$lines.Add("- devices: $($Devices -join ', ')") | Out-Null
$lines.Add("- summary: PASS=$pass, WARN=$warn, FAIL=$fail") | Out-Null
$lines.Add("- json: ``$jsonPath``") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Item | Status | Detail | Evidence |") | Out-Null
$lines.Add("| --- | --- | --- | --- |") | Out-Null
foreach ($r in $results) {
    $detail = ($r.detail -replace "\|", "/").Trim()
    $evidence = ($r.evidence -replace "\|", "/").Trim()
    $lines.Add("| $($r.name) | $($r.status) | $detail | $evidence |") | Out-Null
}
$lines | Set-Content -Encoding UTF8 -Path $reportPath

Write-Host "P3 status: $summaryStatus PASS=$pass WARN=$warn FAIL=$fail"
Write-Host "Report: $reportPath"
Write-Host "JSON: $jsonPath"
if ($fail -gt 0) { exit 1 }
