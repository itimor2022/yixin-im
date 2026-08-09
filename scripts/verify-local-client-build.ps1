#Requires -Version 7.0
<#
.SYNOPSIS
构建指定平台的本地客户端，验证当前源码具备完整编译能力。

.DESCRIPTION
Android 构建会临时设置 JAVA_HOME 和 Gradle JDK；Windows 构建生成 Debug，
Web 构建生成 Release。本脚本不安装产物，也不验证登录等运行时行为。

.PARAMETER Target
需要验证的 Android、Windows 或 Web 平台。

.PARAMETER JdkPath
Android 构建使用的 JDK 17 目录。

.PARAMETER FlutterPath
Flutter 可执行文件路径。

.EXAMPLE
pwsh -File scripts/verify-local-client-build.ps1 -Target Android
#>
[CmdletBinding()]
param(
    [ValidateSet("Android", "Windows", "Web")]
    [string]$Target,
    [string]$JdkPath = ".tools\jdk-17.0.19+10",
    [string]$FlutterPath = "D:\flutter\bin\flutter.bat"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if ($Target -eq "Android") {
    $resolvedJdk = Resolve-Path $JdkPath
    $env:JAVA_HOME = $resolvedJdk.Path
    $env:PATH = "$($resolvedJdk.Path)\bin;$env:PATH"
    $gradleJdk = $resolvedJdk.Path.Replace([char]92, [char]47)
    $env:GRADLE_OPTS = "-Dorg.gradle.java.home=$gradleJdk -Dorg.gradle.java.installations.paths=$gradleJdk"
    & $FlutterPath build apk --debug
} elseif ($Target -eq "Windows") {
    & $FlutterPath build windows --debug
} else {
    & $FlutterPath build web --release
}

if ($LASTEXITCODE -ne 0) {
    throw "$Target client build failed with exit code $LASTEXITCODE"
}
