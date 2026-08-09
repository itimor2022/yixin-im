<#
.SYNOPSIS
在双 Android 真机上验证群组权限、违禁词和成员边界。

.DESCRIPTION
可选安装并登录测试 APK，随后向本地 MySQL 临时写入唯一违禁词，运行 Python
严格 UI 用例并在收尾阶段删除临时数据。脚本会操作两台设备和 Docker 数据库，
中断后应确认临时违禁词已经清理。

.PARAMETER PrepareDevices
运行用例前安装 APK 并准备双设备测试账号。

.PARAMETER Apk
PrepareDevices 启用时必须提供的测试 APK。

.PARAMETER Only
只执行指定 IM 用例；为空时执行完整群边界集合。

.EXAMPLE
pwsh -File scripts/run-local-group-boundary-qa.ps1 -Only IM-249,IM-262
#>
<#
.SYNOPSIS
在双 Android 真机上验证群权限、违禁词和成员边界。

.DESCRIPTION
可先安装并准备两台设备，然后向本地 MySQL 临时插入唯一违禁词，运行 Python UI
用例并在收尾阶段删除测试数据。中途失败时也必须确认临时数据库记录已被清理。

.PARAMETER PrepareDevices
运行用例前重新安装 APK 并登录双测试账号。

.PARAMETER Only
只执行指定群边界用例；为空时执行完整集合。

.PARAMETER Apk
PrepareDevices 启用时必须提供的安装包。

.EXAMPLE
pwsh -File scripts/run-local-group-boundary-qa.ps1 -Only IM-249,IM-262
#>
[CmdletBinding()]
param(
    [string]$AliceDevice = "8MY0220C17006781",
    [string]$BobDevice = "UQG5T20915006269",
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$OutputDir = "artifacts\real-device-qa\local-docker-dual-device-20260717\group-boundary-strict-ui",
    [string]$Apk = "",
    [switch]$PrepareDevices,
    [ValidateSet("IM-249", "IM-262", "IM-267", "IM-268", "IM-269", "IM-292", "IM-293")]
    [string[]]$Only = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runner = Join-Path $PSScriptRoot "real-device-qa\run_local_group_boundary_strict_ui.py"
$preparer = Join-Path $PSScriptRoot "real-device-qa\prepare_dual_device_apk.py"
$blockedWord = "IM400BLOCK$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
$escapedWord = $blockedWord.Replace("'", "''")
$insertSql = "INSERT INTO banned_words (word, category, level, status, hit_count, created_at, updated_at) VALUES ('$escapedWord', 'qa', 3, 1, 0, NOW(3), NOW(3));"
# 删除语句必须与本轮唯一词和 qa 分类同时匹配，避免清理其他测试或运营数据。
$deleteSql = "DELETE FROM banned_words WHERE word = '$escapedWord' AND category = 'qa';"

Push-Location $repoRoot
try {
    $env:PYTHONUTF8 = "1"
    if ($PrepareDevices) {
        if ([string]::IsNullOrWhiteSpace($Apk)) {
            throw "Pass -Apk when -PrepareDevices is enabled."
        }
        $resolvedApk = (Resolve-Path $Apk).Path
        $prepareArgs = @(
            $preparer,
            "--adb", $Adb,
            "--apk", $resolvedApk,
            "--device", "${AliceDevice}=smoke_alice",
            "--device", "${BobDevice}=smoke_bob",
            "--password", "Smoke123",
            "--output-dir", (Join-Path $repoRoot "artifacts\real-device-qa\local-docker-dual-device-20260717\prepare-group-boundary")
        )
        & python @prepareArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Dual-device APK preparation failed with exit code $LASTEXITCODE."
        }
    }

    # 使用本轮唯一词避免与现有运营配置冲突；finally 中必须执行对应删除语句。
    & docker exec genericim-mysql mysql -uroot -pgenericim_root -D genericim -e $insertSql
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to provision the temporary blocked word."
    }

    $pythonArgs = @(
        $runner,
        "--repo", $repoRoot,
        "--adb", $Adb,
        "--alice", $AliceDevice,
        "--bob", $BobDevice,
        "--base", "http://127.0.0.1:8080/api/v1",
        "--blocked-word", $blockedWord,
        "--output-dir", (Join-Path $repoRoot $OutputDir)
    )
    foreach ($caseId in $Only) {
        $pythonArgs += @("--only", $caseId)
    }
    & python @pythonArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Strict group boundary QA failed with exit code $LASTEXITCODE."
    }
} finally {
    & docker exec genericim-mysql mysql -uroot -pgenericim_root -D genericim -e $deleteSql
    Pop-Location
}
