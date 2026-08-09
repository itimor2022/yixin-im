<#
.SYNOPSIS
为既有 Android Shorebird Release 创建并按比例发布 Dart 补丁。

.DESCRIPTION
根据发布版本和 track 生成补丁命令，并在执行前校验 REST、WebSocket、
Bootstrap 地址及原生/资源差异策略。该操作会影响已安装对应 Release 的用户；
首次执行应使用 -PrintOnly 或 -DryRun 核对完整命令。

.PARAMETER ReleaseVersion
目标 Shorebird Release 版本；为空时由 pubspec.yaml 和现有发布信息推导。

.PARAMETER RolloutPercentage
补丁初始灰度比例，范围由 Shorebird CLI 校验。

.PARAMETER AllowNativeDiffs
允许补丁包含原生差异；只有确认客户端无需重新安装时才能启用。

.PARAMETER AllowAssetDiffs
允许补丁包含资源差异；启用前需验证 Shorebird 对目标资源的支持。

.PARAMETER PrintOnly
只输出命令和解析结果，不创建补丁。

.EXAMPLE
pwsh -File scripts/shorebird-patch-android.ps1 -ReleaseVersion 1.2.3+45 -RolloutPercentage 10 -PrintOnly
#>
param(
    [string]$ReleaseVersion = "",
    [string]$Track = "stable",
    [string]$ServerUrl = "http://10.0.2.2:8080",
    [string]$WsUrl = "",
    [string]$BootstrapUrl = "",
    [string]$BootstrapUrls = "",
    [string]$Target = "lib/main.dart",
    [string]$BuildName = "",
    [string]$BuildNumber = "",
    [string]$PatchVersion = "",
    [int]$RolloutPercentage = 10,
    [string[]]$ExtraDartDefine = @(),
    [string]$PubHostedUrl = "https://pub.flutter-io.cn",
    [switch]$AllowNativeDiffs,
    [switch]$AllowAssetDiffs,
    [switch]$DryRun,
    [switch]$PrintOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-PubspecVersion {
    param([string]$ProjectRoot)

    $pubspec = Join-Path $ProjectRoot "pubspec.yaml"
    $match = Select-String -Path $pubspec -Pattern "^\s*version:\s*(\S+)\s*$" | Select-Object -First 1
    if (-not $match) {
        throw "pubspec.yaml version not found."
    }

    $fullVersion = $match.Matches[0].Groups[1].Value
    $parts = $fullVersion -split "\+", 2
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "pubspec.yaml version must be in build-name+build-number format, got '$fullVersion'."
    }

    return [pscustomobject]@{
        Full = $fullVersion
        Name = $parts[0]
        Number = $parts[1]
    }
}

function Resolve-Shorebird {
    $cmd = Get-Command shorebird -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $fallback = Join-Path $HOME ".shorebird\bin\shorebird.bat"
    if (Test-Path $fallback) {
        $bin = Split-Path $fallback -Parent
        if (($env:Path -split ";") -notcontains $bin) {
            $env:Path = "$bin;$env:Path"
        }
        return $fallback
    }

    throw "Shorebird CLI not found. Install it first, or make sure $fallback exists."
}

function Resolve-WsUrl {
    param([string]$ServerUrl)

    $trimmed = $ServerUrl.TrimEnd("/")
    if ($trimmed.StartsWith("https://")) {
        return "wss://" + $trimmed.Substring("https://".Length) + "/api/v1/ws"
    }
    if ($trimmed.StartsWith("http://")) {
        return "ws://" + $trimmed.Substring("http://".Length) + "/api/v1/ws"
    }
    throw "ServerUrl must start with http:// or https://."
}

function Add-DartDefine {
    param(
        [System.Collections.Generic.List[string]]$ArgumentList,
        [string]$Define
    )

    if ([string]::IsNullOrWhiteSpace($Define)) {
        return
    }
    $ArgumentList.Add("--dart-define")
    $ArgumentList.Add($Define)
}

$projectRoot = Get-ProjectRoot
& (Join-Path $PSScriptRoot "check-mojibake.ps1")

$version = Get-PubspecVersion -ProjectRoot $projectRoot
if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) {
    $ReleaseVersion = $version.Full
}
if ([string]::IsNullOrWhiteSpace($BuildName)) {
    $BuildName = $version.Name
}
if ([string]::IsNullOrWhiteSpace($BuildNumber)) {
    $BuildNumber = $version.Number
}
if ([string]::IsNullOrWhiteSpace($WsUrl)) {
    $WsUrl = Resolve-WsUrl -ServerUrl $ServerUrl
}

$shorebird = Resolve-Shorebird
if (-not [string]::IsNullOrWhiteSpace($PubHostedUrl)) {
    $env:PUB_HOSTED_URL = $PubHostedUrl
}

$argsList = [System.Collections.Generic.List[string]]::new()
$argsList.Add("patch")
$argsList.Add("--platforms")
$argsList.Add("android")
$argsList.Add("--release-version")
$argsList.Add($ReleaseVersion)
$argsList.Add("--track")
$argsList.Add($Track)
$argsList.Add("--build-name")
$argsList.Add($BuildName)
$argsList.Add("--build-number")
$argsList.Add($BuildNumber)
$argsList.Add("--target")
$argsList.Add($Target)
Add-DartDefine -ArgumentList $argsList -Define "GENERIC_IM_SERVER_URL=$ServerUrl"
Add-DartDefine -ArgumentList $argsList -Define "GENERIC_IM_WS_URL=$WsUrl"
Add-DartDefine -ArgumentList $argsList -Define "GENERIC_IM_ANDROID_LOOPBACK_HOST=10.0.2.2"
if (-not [string]::IsNullOrWhiteSpace($BootstrapUrl)) {
    Add-DartDefine -ArgumentList $argsList -Define "GENERIC_IM_BOOTSTRAP_URL=$BootstrapUrl"
}
if (-not [string]::IsNullOrWhiteSpace($BootstrapUrls)) {
    Add-DartDefine -ArgumentList $argsList -Define "GENERIC_IM_BOOTSTRAP_URLS=$BootstrapUrls"
}
foreach ($define in $ExtraDartDefine) {
    Add-DartDefine -ArgumentList $argsList -Define $define
}
if ($AllowNativeDiffs) {
    $argsList.Add("--allow-native-diffs")
}
if ($AllowAssetDiffs) {
    $argsList.Add("--allow-asset-diffs")
}
if ($DryRun) {
    $argsList.Add("--dry-run")
}

$adminPatchVersion = $PatchVersion
if ([string]::IsNullOrWhiteSpace($adminPatchVersion)) {
    $adminPatchVersion = "$ReleaseVersion-p<patch-number>"
}

Write-Host "Project root: $projectRoot"
Write-Host "Pubspec version: $($version.Full)"
Write-Host "Shorebird Android patch target: release-version=$ReleaseVersion track=$Track"
Write-Host "ServerUrl: $ServerUrl"
Write-Host "WsUrl: $WsUrl"
Write-Host "Shorebird CLI: $shorebird"
Write-Host "Command:"
Write-Host ("  shorebird " + ($argsList -join " "))
Write-Host ""
Write-Host "Create/publish this admin hot-update record after the patch upload succeeds:"
Write-Host "  delivery_mode=shorebird"
Write-Host "  platform=android"
Write-Host "  channel=$Track"
Write-Host "  min_app_version=$ReleaseVersion"
Write-Host "  max_app_version=$ReleaseVersion"
Write-Host "  min_build_number=$BuildNumber"
Write-Host "  max_build_number=$BuildNumber"
Write-Host "  target_app_version=$ReleaseVersion"
Write-Host "  patch_version=$adminPatchVersion"
Write-Host "  patch_url=(empty)"
Write-Host "  patch_hash=(empty)"
Write-Host "  rollout_percentage=$RolloutPercentage"

if ($PrintOnly) {
    exit 0
}

Push-Location $projectRoot
try {
    & $shorebird @argsList
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
