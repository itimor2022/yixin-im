<#
.SYNOPSIS
创建 Android Shorebird Release 并生成 APK 或 AAB。

.DESCRIPTION
从 pubspec.yaml 解析版本，注入线上服务地址后调用 Shorebird Release。
Release 是后续补丁的不可变基线；正式执行前应使用 -PrintOnly 或 -DryRun
确认版本号、构建类型和所有 Dart Define。

.PARAMETER Artifact
发布产物类型：apk 用于直接安装，aab 用于应用商店。

.PARAMETER BuildName
覆盖 pubspec.yaml 中的语义版本名。

.PARAMETER BuildNumber
覆盖 pubspec.yaml 中的构建号；同一发布渠道必须保持递增。

.PARAMETER PrintOnly
只打印最终 Shorebird 命令，不创建线上 Release。

.EXAMPLE
pwsh -File scripts/shorebird-release-android.ps1 -Artifact aab -PrintOnly
#>
param(
    [string]$ServerUrl = "http://10.0.2.2:8080",
    [string]$WsUrl = "",
    [string]$BootstrapUrl = "",
    [string]$BootstrapUrls = "",
    [string]$Target = "lib/main.dart",
    [ValidateSet("apk", "aab")]
    [string]$Artifact = "apk",
    [string]$BuildName = "",
    [string]$BuildNumber = "",
    [string[]]$ExtraDartDefine = @(),
    [string]$PubHostedUrl = "https://pub.flutter-io.cn",
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
$argsList.Add("release")
$argsList.Add("--platforms")
$argsList.Add("android")
$argsList.Add("--artifact")
$argsList.Add($Artifact)
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
if ($DryRun) {
    $argsList.Add("--dry-run")
}

Write-Host "Project root: $projectRoot"
Write-Host "Pubspec version: $($version.Full)"
Write-Host "Shorebird Android baseline release: build-name=$BuildName build-number=$BuildNumber artifact=$Artifact"
Write-Host "ServerUrl: $ServerUrl"
Write-Host "WsUrl: $WsUrl"
Write-Host "Shorebird CLI: $shorebird"
Write-Host "Command:"
Write-Host ("  shorebird " + ($argsList -join " "))
Write-Host ""
Write-Host "After this succeeds, install/distribute this baseline APK once. Later Dart/UI fixes can use scripts/shorebird-patch-android.ps1."

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
