param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Apk = 'build\app\outputs\flutter-apk\app-debug.apk',
    [string[]]$Devices = @('8MY0220C17006781', 'UQG5T20915006269', 'emulator-5554'),
    [int]$StartupWaitSeconds = 12,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$apkPath = (Resolve-Path (Join-Path $repoRoot $Apk)).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputRoot = Join-Path $repoRoot "artifacts\real-device-qa\search-filter-device-smoke-$timestamp"
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

# 先构建在线设备集合，随后要求调用方指定的每台设备都可用，避免静默漏测。
$connected = @{}
& $Adb devices | Select-Object -Skip 1 | ForEach-Object {
    if ($_ -match '^(\S+)\s+device$') {
        $connected[$Matches[1]] = $true
    }
}

$results = @()
foreach ($device in $Devices) {
    if (-not $connected.ContainsKey($device)) {
        throw "Android device $device is not online"
    }

    $deviceDir = Join-Path $outputRoot $device
    New-Item -ItemType Directory -Force -Path $deviceDir | Out-Null

    if (-not $SkipInstall) {
        # 每台设备独立保存安装输出，便于定位 ABI、签名或存储空间问题。
        $installOutput = & $Adb -s $device install -r -t $apkPath 2>&1
        $installOutput | Set-Content -Encoding utf8 (Join-Path $deviceDir 'install.txt')
        if ($LASTEXITCODE -ne 0 -or ($installOutput -join "`n") -notmatch 'Success') {
            throw "APK install failed on $device"
        }
    }

    & $Adb -s $device reverse tcp:8080 tcp:8080 | Out-Null
    & $Adb -s $device logcat -c | Out-Null
    & $Adb -s $device shell am force-stop com.genericim.ma100 | Out-Null
    & $Adb -s $device shell am start -W -n com.genericim.ma100/.MainActivity | Out-Null
    Start-Sleep -Seconds $StartupWaitSeconds

    $appPid = (& $Adb -s $device shell pidof com.genericim.ma100 2>$null).Trim()

    $remoteXml = "/sdcard/im400-search-smoke-$timestamp.xml"
    $remotePng = "/sdcard/im400-search-smoke-$timestamp.png"
    $localXml = Join-Path $deviceDir 'screen.xml'
    $xmlReady = $false
    # UIAutomator 在页面切换期间可能失败，有限重试后再判定证据缺失。
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & $Adb -s $device shell uiautomator dump $remoteXml | Out-Null
        if ($LASTEXITCODE -eq 0) {
            & $Adb -s $device pull $remoteXml $localXml | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $localXml)) {
                $xmlReady = (Get-Item $localXml).Length -gt 100
                if ($xmlReady) { break }
            }
        }
        Start-Sleep -Seconds 2
    }
    & $Adb -s $device shell screencap -p $remotePng | Out-Null
    $localPng = Join-Path $deviceDir 'screen.png'
    & $Adb -s $device pull $remotePng $localPng | Out-Null
    $pngReady = $LASTEXITCODE -eq 0 -and (Test-Path $localPng) -and (Get-Item $localPng).Length -gt 10000
    & $Adb -s $device shell rm $remoteXml $remotePng | Out-Null

    $activity = (& $Adb -s $device shell dumpsys activity activities | Select-String 'topResumedActivity|mResumedActivity' | Select-Object -First 1).Line

    $logcat = & $Adb -s $device logcat -d -t 500
    $logcat | Set-Content -Encoding utf8 (Join-Path $deviceDir 'logcat.txt')
    $fatal = ($logcat | Select-String 'FATAL EXCEPTION|Process: com\.genericim\.app.*has died') -join "`n"
    # 冒烟通过条件同时覆盖进程、前台 Activity、崩溃日志以及两类 UI 证据。
    $passed = $appPid -ne '' -and
        $activity -match 'com\.genericim\.app' -and
        $fatal -eq '' -and
        $xmlReady -and
        $pngReady
    $results += [ordered]@{
        device = $device
        status = if ($passed) { 'PASS' } else { 'FAIL' }
        pid = $appPid
        resumed_activity = $activity
        fatal_log = $fatal
        ui_xml_ready = $xmlReady
        screenshot_ready = $pngReady
        evidence = @(
            (Join-Path $deviceDir 'screen.png')
            (Join-Path $deviceDir 'screen.xml')
            (Join-Path $deviceDir 'logcat.txt')
        )
    }
}

$report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    apk = $apkPath
    results = $results
    summary = [ordered]@{
        passed = @($results | Where-Object status -eq 'PASS').Count
        failed = @($results | Where-Object status -eq 'FAIL').Count
    }
}
$reportPath = Join-Path $outputRoot 'results.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $reportPath
$report | ConvertTo-Json -Depth 8

if ($report.summary.failed -gt 0) {
    throw "One or more Android device smoke checks failed"
}
