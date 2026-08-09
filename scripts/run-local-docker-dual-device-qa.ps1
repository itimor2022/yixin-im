<#
.SYNOPSIS
在两台 Android 真机上运行连接本地 Docker 后端的完整 QA 套件。

.DESCRIPTION
为公共 QA 套件组装本机后端、局域网后端和双设备参数。默认复用已安装应用，
不刷新 ADB、不执行 Monkey；运行过程会操作指定设备上的测试账号和应用状态。

.PARAMETER AliceDevice
第一台测试设备的 ADB 序列号。

.PARAMETER BobDevice
第二台测试设备的 ADB 序列号。

.PARAMETER HostAddress
真机可访问的开发机局域网地址，不能使用 localhost 或 10.0.2.2。

.PARAMETER Adb
ADB 可执行文件的绝对路径。

.EXAMPLE
pwsh -File scripts/run-local-docker-dual-device-qa.ps1 -HostAddress 192.168.1.20
#>
[CmdletBinding()]
param(
    [string]$AliceDevice = "8MY0220C17006781",
    [string]$BobDevice = "UQG5T20915006269",
    [string]$HostAddress = "192.168.1.100",
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$suite = Join-Path $PSScriptRoot "full_android_qa_suite.ps1"
$devices = @($AliceDevice, $BobDevice)
$parameters = @{
    Adb = $Adb
    BaseUrl = "http://127.0.0.1:8080"
    EmulatorBaseUrl = "http://${HostAddress}:8080"
    Devices = $devices
    AliceDevice = $AliceDevice
    BobDevice = $BobDevice
    ObserverDevice = ""
    AliceUsername = "smoke_alice"
    BobUsername = "smoke_bob"
    Password = "Smoke123"
    RefreshAdbConnections = $false
    SkipInstall = $true
    SkipMonkey = $true
}

Push-Location $repoRoot
try {
    & $suite @parameters
    if ($LASTEXITCODE -ne 0) {
        throw "Local Docker dual-device QA failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
