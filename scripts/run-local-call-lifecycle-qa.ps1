<#
.SYNOPSIS
在两台 Android 真机上执行严格通话生命周期 UI 用例。

.DESCRIPTION
将设备、ADB、后端和输出目录参数传递给 Python UI 驱动，覆盖呼叫、接听、
挂断、超时和快速重拨等指定用例。脚本会实际操作两台设备并产生通话记录。

.PARAMETER AliceDevice
主叫侧 ADB 序列号。

.PARAMETER BobDevice
被叫侧 ADB 序列号。

.PARAMETER Only
只执行指定 IM 用例；为空时由 Python 驱动执行完整集合。

.PARAMETER OutputDir
截图、日志和断言结果目录。

.EXAMPLE
pwsh -File scripts/run-local-call-lifecycle-qa.ps1 -Only IM-305,IM-308
#>
[CmdletBinding()]
param(
    [string]$AliceDevice = "8MY0220C17006781",
    [string]$BobDevice = "UQG5T20915006269",
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$OutputDir = "artifacts\real-device-qa\local-docker-dual-device-20260717\call-lifecycle-strict-ui",
    [ValidateSet("IM-305", "IM-308", "IM-313", "IM-314", "IM-315", "IM-318", "IM-323", "IM-324", "IM-337")]
    [string[]]$Only = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runner = Join-Path $PSScriptRoot "real-device-qa\run_local_call_lifecycle_strict_ui.py"
$pythonArgs = @(
    $runner,
    "--repo", $repoRoot,
    "--adb", $Adb,
    "--alice", $AliceDevice,
    "--bob", $BobDevice,
    "--base", "http://127.0.0.1:8080/api/v1",
    "--output-dir", (Join-Path $repoRoot $OutputDir)
)
foreach ($caseId in $Only) {
    $pythonArgs += @("--only", $caseId)
}

Push-Location $repoRoot
try {
    $env:PYTHONUTF8 = "1"
    & python @pythonArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Strict call lifecycle QA failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
