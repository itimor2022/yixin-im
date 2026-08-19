<#
.SYNOPSIS
初始化 Android 真机 QA 所需的设备、Python 和 UIAutomator 环境。

.DESCRIPTION
探测 PowerShell、ADB 和目标设备，按需创建 Python 虚拟环境并安装依赖，
验证 UIAutomator 可用性，最后输出环境报告。脚本不会安装业务 APK，但可能
在 VenvPath 写入或升级 Python 包。

.PARAMETER Serial
目标 ADB 设备；为空时要求存在可唯一选择的在线设备。

.PARAMETER VenvPath
QA Python 虚拟环境目录。

.PARAMETER SkipPythonInstall
只检查现有 Python 环境，不安装依赖。

.EXAMPLE
pwsh -File scripts/real-device-qa/Initialize-RealDeviceQa.ps1 -Serial emulator-5554
#>
param(
    [string]$Serial = "",
    [string]$PackageName = "com.genericim.ma100",
    [string]$Adb = "",
    [string]$ArtifactRoot = "",
    [string]$VenvPath = "",
    [switch]$SkipPythonInstall,
    [switch]$SkipUiAutomatorProbe
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required. Use pwsh."
}

$repoRoot = Get-QaRepositoryRoot
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $ArtifactRoot = Join-Path $repoRoot "artifacts\real-device-qa"
}
if ([string]::IsNullOrWhiteSpace($VenvPath)) {
    $VenvPath = Join-Path $repoRoot ".tools\real-device-qa"
}
$ArtifactRoot = [System.IO.Path]::GetFullPath($ArtifactRoot)
$VenvPath = [System.IO.Path]::GetFullPath($VenvPath)
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $ArtifactRoot "environment-$runId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$warnings = [System.Collections.Generic.List[string]]::new()
$checks = [ordered]@{}
$adbPath = Resolve-QaAdbPath -Adb $Adb
$checks.powershell = $PSVersionTable.PSVersion.ToString()
$checks.adb_path = $adbPath

$adbVersion = Invoke-QaAdb -Adb $adbPath -Arguments @("version")
if ($adbVersion.ExitCode -ne 0) { throw "adb version failed: $($adbVersion.StdErr)" }
$checks.adb_version = $adbVersion.StdOut.Trim()

$devices = @(Get-QaDevices -Adb $adbPath)
$device = Select-QaDevice -Devices $devices -Serial $Serial
$Serial = $device.Serial
$checks.selected_device = $Serial
$checks.all_devices = @($devices | ForEach-Object {
    [ordered]@{ serial = $_.Serial; state = $_.State; detail = $_.Detail }
})
foreach ($item in @($devices | Where-Object State -ne "device")) {
    $warnings.Add("ADB device $($item.Serial) is $($item.State); it will not be used.")
}

function Get-DeviceValue {
    param([string[]]$Arguments)
    $result = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments $Arguments
    if ($result.ExitCode -ne 0) { throw "adb $($Arguments -join ' ') failed: $($result.StdErr)" }
    return $result.StdOut.Trim()
}

$packagePath = Get-DeviceValue -Arguments @("shell", "pm", "path", $PackageName)
if ($packagePath -notmatch "^package:") { throw "package '$PackageName' is not installed on $Serial" }
$packageDump = Get-DeviceValue -Arguments @("shell", "dumpsys", "package", $PackageName)
$versionName = if ($packageDump -match "versionName=(?<value>\S+)") { $Matches.value } else { "unknown" }
$versionCode = if ($packageDump -match "versionCode=(?<value>\d+)") { $Matches.value } else { "unknown" }
$debuggableFlag = $packageDump -match "\bDEBUGGABLE\b"
$runAs = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("shell", "run-as", $PackageName, "id")
$runAsAvailable = $runAs.ExitCode -eq 0
if (-not $runAsAvailable) {
    $warnings.Add("Installed APK does not expose run-as/debuggable access; UI automation and Logcat remain available.")
}

$checks.device = [ordered]@{
    manufacturer = Get-DeviceValue -Arguments @("shell", "getprop", "ro.product.manufacturer")
    model = Get-DeviceValue -Arguments @("shell", "getprop", "ro.product.model")
    android_version = Get-DeviceValue -Arguments @("shell", "getprop", "ro.build.version.release")
    sdk = Get-DeviceValue -Arguments @("shell", "getprop", "ro.build.version.sdk")
    screen_size = Get-DeviceValue -Arguments @("shell", "wm", "size")
    screen_density = Get-DeviceValue -Arguments @("shell", "wm", "density")
}
$checks.app = [ordered]@{
    package = $PackageName
    package_path = $packagePath
    version_name = $versionName
    version_code = $versionCode
    debuggable_flag = $debuggableFlag
    run_as_available = $runAsAvailable
}

$logcatProbe = Invoke-QaAdb -Adb $adbPath -Serial $Serial -Arguments @("logcat", "-d", "-t", "1", "-v", "threadtime") -TimeoutSeconds 15
if ($logcatProbe.ExitCode -ne 0) { throw "logcat is unavailable: $($logcatProbe.StdErr)" }
$checks.logcat = [ordered]@{ available = $true; sample = $logcatProbe.StdOut.Trim() }

$pythonPath = Join-Path $VenvPath "Scripts\python.exe"
if (-not $SkipPythonInstall) {
    if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $VenvPath -Parent) | Out-Null
        $venv = Invoke-QaProcess -FilePath "py" -Arguments @("-3", "-m", "venv", $VenvPath) -TimeoutSeconds 120
        if ($venv.ExitCode -ne 0) { throw "creating Python venv failed: $($venv.StdErr)" }
    }
    $pip = Invoke-QaProcess -FilePath $pythonPath -Arguments @(
        "-m", "pip", "install", "--disable-pip-version-check", "-r", (Join-Path $PSScriptRoot "requirements.txt")
    ) -TimeoutSeconds 300
    if ($pip.ExitCode -ne 0) { throw "installing uiautomator2 failed: $($pip.StdErr)" }
}
$pythonPath = Resolve-QaPythonPath -VenvPath $VenvPath
$pythonVersion = Invoke-QaProcess -FilePath $pythonPath -Arguments @("--version")
$u2Version = Invoke-QaProcess -FilePath $pythonPath -Arguments @(
    "-c", "from importlib.metadata import version; print(version('uiautomator2'))"
)
if ($u2Version.ExitCode -ne 0) { throw "uiautomator2 import failed: $($u2Version.StdErr)" }
$checks.python = [ordered]@{
    executable = $pythonPath
    version = ($pythonVersion.StdOut + $pythonVersion.StdErr).Trim()
    uiautomator2_version = $u2Version.StdOut.Trim()
}

if (-not $SkipUiAutomatorProbe) {
    $driver = Join-Path $PSScriptRoot "device_driver.py"
    $probe = Invoke-QaProcess -FilePath $pythonPath -Arguments @(
        $driver, "--serial", $Serial, "--package", $PackageName, "probe"
    ) -TimeoutSeconds 90
    if ($probe.ExitCode -ne 0) { throw "uiautomator2 device probe failed: $($probe.StdOut) $($probe.StdErr)" }
    $checks.uiautomator2_probe = $probe.StdOut | ConvertFrom-Json

    $snapshot = Invoke-QaProcess -FilePath $pythonPath -Arguments @(
        $driver, "--serial", $Serial, "--package", $PackageName,
        "snapshot", $runDir, "--name", "environment"
    ) -TimeoutSeconds 90
    if ($snapshot.ExitCode -ne 0) { throw "initial device snapshot failed: $($snapshot.StdOut) $($snapshot.StdErr)" }
    $checks.snapshot = $snapshot.StdOut | ConvertFrom-Json
}

$result = [ordered]@{
    ready = $true
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    repository = $repoRoot
    artifact_directory = $runDir
    checks = $checks
    warnings = @($warnings)
}
$environmentPath = Join-Path $runDir "environment.json"
$activePath = Join-Path $ArtifactRoot "active-device.json"
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $environmentPath -Encoding utf8
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $activePath -Encoding utf8

Write-Host "Real-device QA environment ready."
Write-Host "Device: $Serial"
Write-Host "App: $PackageName $versionName ($versionCode)"
Write-Host "Evidence: $environmentPath"
if ($warnings.Count -gt 0) {
    foreach ($warning in $warnings) { Write-Warning $warning }
}
$result | ConvertTo-Json -Depth 20
