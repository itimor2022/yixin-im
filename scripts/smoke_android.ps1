<#
.SYNOPSIS
构建、安装并启动 Android 客户端，执行基础存活与后端连通 smoke。

.DESCRIPTION
检查宿主机健康接口和模拟器到后端的访问路径，按参数构建或复用 APK，
安装到指定设备并收集日志/截图。-ClearAppData 会删除目标包的本地登录态
和缓存，仅可用于测试设备。

.PARAMETER DeviceId
目标 ADB 设备；为空时要求环境中存在可唯一选择的在线设备。

.PARAMETER ApkPath
复用已有 APK；为空时由脚本构建测试包。

.PARAMETER ClearAppData
启动前清除应用全部本地数据。

.PARAMETER SkipDeviceBackendProbe
跳过设备侧后端探测，仅用于已确认网络路径可用的环境。

.EXAMPLE
pwsh -File scripts/smoke_android.ps1 -DeviceId emulator-5554 -SkipBuild -ApkPath build/app/outputs/flutter-apk/app-debug.apk
#>
param(
    [string]$DeviceId = "",
    [string]$PackageName = "com.genericim.ma100",
    [string]$ServerUrl = "http://10.0.2.2:8080",
    [string]$WsUrl = "ws://10.0.2.2:8080/api/v1/ws",
    [string]$HostHealthUrl = "http://127.0.0.1:8080/health",
    [string]$OutputDir = "build/smoke",
    [string]$ApkPath = "",
    [int]$LaunchWaitSeconds = 30,
    [switch]$SkipPubGet,
    [switch]$SkipAnalyze,
    [switch]$SkipBuild,
    [switch]$SkipDeviceBackendProbe,
    [switch]$ClearAppData
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RepoRoot {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent $PSCommandPath
    }
    if (-not $scriptDir) {
        throw "Could not determine script directory."
    }
    return (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Get-FlutterCommand {
    param([string]$RepoRoot)

    $repoFlutter = Join-Path $RepoRoot ".tools\flutter\bin\flutter.bat"
    if (Test-Path -LiteralPath $repoFlutter) {
        return (Resolve-Path -LiteralPath $repoFlutter).Path
    }

    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Could not find flutter. Add Flutter to PATH or install it under .tools/flutter."
}

function Get-AdbCommand {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @()
    if ($env:ANDROID_HOME) {
        $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe")
    }
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe")
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Could not find adb. Install Android platform-tools or add adb to PATH."
}

function Resolve-DeviceId {
    param(
        [string]$Adb,
        [string]$PreferredDeviceId
    )

    $devices = & $Adb devices
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices failed."
    }

    $online = @(
        $devices |
            Where-Object { $_ -match "\tdevice$" } |
            ForEach-Object { ($_ -split "\s+")[0] }
    )

    if ($PreferredDeviceId) {
        if ($online -contains $PreferredDeviceId) {
            return $PreferredDeviceId
        }
        throw "Device '$PreferredDeviceId' is not online. Online devices: $($online -join ', ')"
    }

    if ($online.Count -eq 0) {
        throw "No online Android device or emulator found."
    }

    return $online[0]
}

function Invoke-AdbShell {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$Command
    )

    return & $Adb -s $Device shell $Command
}

function Assert-EmulatorCanReachBackend {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$ServerUrl
    )

    $uri = [Uri]$ServerUrl
    $port = $uri.Port
    if ($port -lt 0) {
        if ($uri.Scheme -eq "https") {
            $port = 443
        } else {
            $port = 80
        }
    }

    $probeCommand = "printf 'GET /health HTTP/1.0\r\n\r\n' | nc -w 5 $($uri.Host) $port"
    $probe = Invoke-AdbShell -Adb $Adb -Device $Device -Command $probeCommand
    $probeText = ($probe -join "`n")
    if ($probeText -notmatch "200 OK" -or $probeText -notmatch '"status"\s*:\s*"ok"') {
        throw "Emulator cannot reach backend health endpoint through $ServerUrl. Probe output: $probeText"
    }
}

function Get-BoundsCenter {
    param([string]$Bounds)

    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) {
        return $null
    }

    $x1 = [int]$match.Groups[1].Value
    $y1 = [int]$match.Groups[2].Value
    $x2 = [int]$match.Groups[3].Value
    $y2 = [int]$match.Groups[4].Value

    return [pscustomobject]@{
        X = [int](($x1 + $x2) / 2)
        Y = [int](($y1 + $y2) / 2)
    }
}

function Try-TapRuntimePermissionDialog {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$XmlText
    )

    if ($XmlText -notmatch 'permissioncontroller') {
        return $false
    }

    $nodes = [regex]::Matches($XmlText, '<node\b[^>]*>')
    foreach ($nodeMatch in $nodes) {
        $node = $nodeMatch.Value
        if ($node -notmatch 'permission_allow_button') {
            continue
        }

        $boundsMatch = [regex]::Match($node, 'bounds="([^"]+)"')
        if (-not $boundsMatch.Success) {
            continue
        }

        $center = Get-BoundsCenter -Bounds $boundsMatch.Groups[1].Value
        if ($null -eq $center) {
            continue
        }

        Invoke-AdbShell -Adb $Adb -Device $Device -Command "input tap $($center.X) $($center.Y)" | Out-Null
        Start-Sleep -Seconds 1
        return $true
    }

    return $false
}

function Wait-ForLoginScreen {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$PackageName,
        [int]$TimeoutSeconds
    )

    $loginPrompt = [string]::Concat(
        [char]0x767B, [char]0x5F55, [char]0x60A8,
        [char]0x7684, [char]0x8D26, [char]0x53F7
    )
    $userHint = [string]::Concat([char]0x7528, [char]0x6237, [char]0x540D)
    $passwordHint = [string]::Concat([char]0x5BC6, [char]0x7801)
    $loginButton = [string]::Concat([char]0x767B, [char]0x5F55)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastXml = ""
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3

        $appPid = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "pidof $PackageName") -join ""
        if ([string]::IsNullOrWhiteSpace($appPid)) {
            throw "App process '$PackageName' is not running."
        }

        Invoke-AdbShell -Adb $Adb -Device $Device -Command "uiautomator dump /sdcard/genericim_smoke_window.xml" | Out-Null
        $xml = Invoke-AdbShell -Adb $Adb -Device $Device -Command "cat /sdcard/genericim_smoke_window.xml"
        $lastXml = ($xml -join "`n")

        if (Try-TapRuntimePermissionDialog -Adb $Adb -Device $Device -XmlText $lastXml) {
            continue
        }

        $hasTextSignals =
            $lastXml.Contains("content-desc=`"$loginPrompt`"") -and
            $lastXml.Contains("hint=`"$userHint`"") -and
            $lastXml.Contains("hint=`"$passwordHint`"") -and
            $lastXml.Contains("content-desc=`"$loginButton`"")

        $editTextCount = [regex]::Matches(
            $lastXml,
            'class="android\.widget\.EditText"'
        ).Count
        $hasStructureSignals =
            $lastXml -match "package=`"$([regex]::Escape($PackageName))`"" -and
            $editTextCount -ge 2 -and
            $lastXml -match 'password="true"' -and
            $lastXml.Contains("content-desc=`"$loginButton`"")

        if ($hasTextSignals -or $hasStructureSignals) {
            return $lastXml
        }
    }

    throw "Login screen was not detected within $TimeoutSeconds seconds. Last UI dump: $lastXml"
}

function Assert-NoCrashLogs {
    param(
        [string]$Adb,
        [string]$Device
    )

    $log = & $Adb -s $Device logcat -d -v time
    $legacyPrefix = "gao"
    $legacyPackage = $legacyPrefix + "_ran_im"
    $legacyDomain = "com\." + $legacyPrefix + "ran"
    $failurePattern = "Dart_LookupLibrary|FATAL EXCEPTION|E/flutter\s*\(|FlutterError|package:$legacyPackage|$legacyPackage|$legacyDomain"
    $failures = @(
        $log |
            Select-String -Pattern $failurePattern
    )

    if ($failures.Count -gt 0) {
        $tail = ($failures | Select-Object -Last 40 | ForEach-Object { $_.Line }) -join "`n"
        throw "Crash or legacy-brand log detected:`n$tail"
    }
}

$repoRoot = Get-RepoRoot
$flutter = Get-FlutterCommand -RepoRoot $repoRoot
$adb = Get-AdbCommand
$resolvedOutputDir = Join-Path $repoRoot $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

Push-Location $repoRoot
try {
    Write-Step "Check source mojibake"
    & (Join-Path $repoRoot "scripts\check-mojibake.ps1")

    Write-Step "Check host backend health"
    $health = Invoke-RestMethod -Uri $HostHealthUrl -TimeoutSec 8
    Write-Host "Host health: $($health.status)"

    Write-Step "Resolve Android device"
    $DeviceId = Resolve-DeviceId -Adb $adb -PreferredDeviceId $DeviceId
    Write-Host "Device: $DeviceId"

    Write-Step "Check emulator backend reachability"
    if (-not $SkipDeviceBackendProbe) {
        Assert-EmulatorCanReachBackend -Adb $adb -Device $DeviceId -ServerUrl $ServerUrl
    } else {
        Write-Host "Device backend probe skipped by request."
    }

    if (-not $SkipPubGet) {
        Write-Step "Run flutter pub get"
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
    }

    if (-not $SkipAnalyze) {
        Write-Step "Run flutter analyze"
        & $flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }
    }

    if (-not $SkipBuild) {
        Write-Step "Build debug APK"
        & $flutter build apk --debug "--dart-define=GENERIC_IM_SERVER_URL=$ServerUrl" "--dart-define=GENERIC_IM_WS_URL=$WsUrl"
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk --debug failed." }
    }

    if ([string]::IsNullOrWhiteSpace($ApkPath)) {
        $ApkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-debug.apk"
    } elseif (-not [System.IO.Path]::IsPathRooted($ApkPath)) {
        $ApkPath = Join-Path $repoRoot $ApkPath
    }
    if (-not (Test-Path -LiteralPath $ApkPath)) {
        throw "APK not found: $ApkPath"
    }

    Write-Step "Install and launch app"
    & $adb -s $DeviceId install -r $ApkPath
    if ($LASTEXITCODE -ne 0) { throw "adb install failed." }

    if ($ClearAppData) {
        Invoke-AdbShell -Adb $adb -Device $DeviceId -Command "pm clear $PackageName" | Out-Host
    }

    & $adb -s $DeviceId logcat -c
    Invoke-AdbShell -Adb $adb -Device $DeviceId -Command "am force-stop $PackageName" | Out-Null
    Invoke-AdbShell -Adb $adb -Device $DeviceId -Command "monkey -p $PackageName -c android.intent.category.LAUNCHER 1" | Out-Host

    Write-Step "Wait for login screen"
    $xml = Wait-ForLoginScreen -Adb $adb -Device $DeviceId -PackageName $PackageName -TimeoutSeconds $LaunchWaitSeconds

    Write-Step "Check crash logs"
    Assert-NoCrashLogs -Adb $adb -Device $DeviceId

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $remoteScreenshot = "/sdcard/genericim_smoke_$timestamp.png"
    $screenshotPath = Join-Path $resolvedOutputDir "android-smoke-$timestamp.png"
    $xmlPath = Join-Path $resolvedOutputDir "android-smoke-$timestamp.xml"

    Write-Step "Capture evidence"
    Invoke-AdbShell -Adb $adb -Device $DeviceId -Command "screencap -p $remoteScreenshot" | Out-Null
    & $adb -s $DeviceId pull $remoteScreenshot $screenshotPath | Out-Null
    Set-Content -LiteralPath $xmlPath -Value $xml -Encoding utf8

    Write-Host ""
    Write-Host "Android smoke passed." -ForegroundColor Green
    Write-Host "Screenshot: $screenshotPath"
    Write-Host "UI dump:    $xmlPath"
}
finally {
    Pop-Location
}
