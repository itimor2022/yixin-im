[CmdletBinding()]
param(
    [switch]$SkipFlutter,
    [switch]$UseChinaMirror = $true
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
Set-Location -LiteralPath $ProjectRoot

if ($UseChinaMirror) {
    $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
    $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
}

& (Join-Path $ScriptRoot "apply-fixed-delivery-branding.ps1")
