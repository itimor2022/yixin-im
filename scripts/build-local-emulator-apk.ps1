#Requires -Version 7.0
<#
.SYNOPSIS
构建供 Android 模拟器连接本地通用IM后端使用的 APK。

.DESCRIPTION
从仓库内解析 JDK，检查乱码，并通过 Dart Define 写入 REST、WebSocket、
Bootstrap 和公共 H5 地址。脚本会临时清理 integration_test 的 Android
注册信息，避免测试插件进入交付包；构建结束后由脚本恢复相关文件。

.PARAMETER ServerUrl
模拟器访问的 REST 服务地址。默认使用 Android 模拟器宿主机地址 10.0.2.2。

.PARAMETER WsUrl
WebSocket 完整地址，必须包含 /api/v1/ws。

.PARAMETER JdkPath
JDK 17 目录；相对路径按仓库根目录解析。

.PARAMETER ProductionArm64
生成面向 arm64 真机的生产构建，而不是默认的本地模拟器构建。

.PARAMETER SkipPub
跳过 flutter pub get，适用于依赖已经准备完成的本地环境。

.EXAMPLE
pwsh -File scripts/build-local-emulator-apk.ps1 -SkipPub
#>
[CmdletBinding()]
param(
    [string]$ServerUrl = "http://10.0.2.2:8080",
    [string]$WsUrl = "ws://10.0.2.2:8080/api/v1/ws",
    [string]$BootstrapUrl = "",
    [string]$PublicH5Url = "",
    [string]$AndroidLoopbackHost = "10.0.2.2",
    [string]$JdkPath = ".tools\jdk-17.0.19+10",
    [switch]$DisableReleaseShrink = $true,
    [switch]$DisableSplashImage,
    [switch]$ProductionArm64,
    [switch]$SkipPub = $true
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

& (Join-Path $PSScriptRoot "check-mojibake.ps1")

$resolvedJdk = Resolve-Path $JdkPath
$env:JAVA_HOME = $resolvedJdk.Path
$env:PATH = "$($resolvedJdk.Path)\bin;$env:PATH"
$gradleJdk = $resolvedJdk.Path.Replace([char]92, [char]47)
$env:GRADLE_OPTS = "-Dorg.gradle.java.home=$gradleJdk -Dorg.gradle.java.installations.paths=$gradleJdk"

function ConvertTo-DartDefineValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
}

function Remove-IntegrationTestRegistrant {
    # 交付构建不能注册 integration_test；该生成文件会在构建收尾阶段恢复。
    $registrant = Join-Path $repoRoot "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java"
    if (-not (Test-Path $registrant)) {
        return $false
    }

    $content = Get-Content -Raw -Path $registrant
    if ($content -notmatch "dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin") {
        return $false
    }

    $pattern = '(?ms)^\s*try\s*\{(?:(?!^\s*try\s*\{).)*?dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)(?:(?!^\s*try\s*\{).)*?\}\s*catch\s*\(Exception\s+e\)\s*\{(?:(?!^\s*try\s*\{).)*?integration_test(?:(?!^\s*try\s*\{).)*?\}\s*'
    $updated = [regex]::Replace($content, $pattern, "")
    Set-Content -Path $registrant -Value $updated -Encoding utf8NoBOM
    Write-Host "Removed generated integration_test registrant from $registrant"
    return $true
}

function Remove-IntegrationTestPluginMetadata {
    # 同步清理插件元数据，防止 Gradle 根据缓存再次生成测试插件注册代码。
    $metadataPath = Join-Path $repoRoot ".flutter-plugins-dependencies"
    if (-not (Test-Path $metadataPath)) {
        return $false
    }

    $json = Get-Content -Raw -Path $metadataPath | ConvertFrom-Json
    $changed = $false
    foreach ($platform in @("android", "ios", "linux", "macos", "windows", "web")) {
        $plugins = $json.plugins.$platform
        if ($null -eq $plugins) {
            continue
        }
        $filtered = @($plugins | Where-Object { $_.name -ne "integration_test" })
        if ($filtered.Count -ne @($plugins).Count) {
            $json.plugins.$platform = $filtered
            $changed = $true
        }
    }
    if ($json.dependencyGraph) {
        $filteredGraph = @($json.dependencyGraph | Where-Object { $_.name -ne "integration_test" })
        if ($filteredGraph.Count -ne @($json.dependencyGraph).Count) {
            $json.dependencyGraph = $filteredGraph
            $changed = $true
        }
    }

    if (-not $changed) {
        return $false
    }

    $json | ConvertTo-Json -Depth 100 -Compress | Set-Content -Path $metadataPath -Encoding utf8NoBOM
    Write-Host "Removed integration_test plugin metadata from $metadataPath"
    return $true
}

function Clear-IntegrationTestReleaseArtifacts {
    Remove-IntegrationTestPluginMetadata | Out-Null
    Remove-IntegrationTestRegistrant | Out-Null
}

function Invoke-GradleRelease {
    $version = & flutter --version --machine | ConvertFrom-Json
    $dartVersion = (($version.dartSdkVersion -as [string]) -split "\s+")[0]
    $defines = @(
        "GENERIC_IM_SERVER_URL=$ServerUrl"
        "GENERIC_IM_WS_URL=$WsUrl"
        "GENERIC_IM_ANDROID_LOOPBACK_HOST=$AndroidLoopbackHost"
        "FLUTTER_VERSION=$($version.frameworkVersion)"
        "FLUTTER_CHANNEL=$($version.channel)"
        "FLUTTER_GIT_URL=$($version.repositoryUrl)"
        "FLUTTER_FRAMEWORK_REVISION=$($version.frameworkRevision)"
        "FLUTTER_ENGINE_REVISION=$($version.engineRevision)"
        "FLUTTER_DART_VERSION=$dartVersion"
    )
    if (-not [string]::IsNullOrWhiteSpace($BootstrapUrl)) {
        $defines += "GENERIC_IM_BOOTSTRAP_URL=$($BootstrapUrl.Trim())"
    }
    if (-not [string]::IsNullOrWhiteSpace($PublicH5Url)) {
        $defines += "GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))"
    }
    if ($DisableSplashImage) {
        $defines += "GENERIC_IM_DISABLE_SPLASH_IMAGE=true"
    }
    $encodedDefines = ($defines | ForEach-Object { ConvertTo-DartDefineValue $_ }) -join ","
    $targetPlatforms = if ($ProductionArm64) {
        "android-arm64"
    } else {
        "android-arm,android-arm64,android-x64"
    }
    $gradleArgs = @(
        "-q"
        "-Ptarget-platform=$targetPlatforms"
        "-Ptarget=lib\main.dart"
        "-Pbase-application-name=android.app.Application"
        "-Pdart-defines=$encodedDefines"
        "-Pdart-obfuscation=false"
        "-Ptrack-widget-creation=true"
        "-Ptree-shake-icons=true"
    )
    if (-not $ProductionArm64) {
        $gradleArgs += "-PGENERIC_IM_ENABLE_EMULATOR_ABIS=true"
    }
    if ($DisableReleaseShrink) {
        $gradleArgs += "-PGENERIC_IM_DISABLE_RELEASE_SHRINK=true"
    }
    Clear-IntegrationTestReleaseArtifacts

    Push-Location "android"
    try {
        # Flutter regenerates the Android registrant while compiling Dart and
        # assets. Finish that step first, remove the dev-only integration_test
        # entry again, then assemble without repeating the Flutter task.
        & ".\gradlew.bat" @gradleArgs "compileFlutterBuildRelease"
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle compileFlutterBuildRelease failed with exit code $LASTEXITCODE"
        }

        Clear-IntegrationTestReleaseArtifacts

        & ".\gradlew.bat" @gradleArgs "-x" "compileFlutterBuildRelease" "assembleRelease"
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle assembleRelease failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

$flutterArgs = @(
    "build"
    "apk"
    "--release"
    "--dart-define=GENERIC_IM_SERVER_URL=$ServerUrl"
    "--dart-define=GENERIC_IM_WS_URL=$WsUrl"
    "--dart-define=GENERIC_IM_ANDROID_LOOPBACK_HOST=$AndroidLoopbackHost"
)
if (-not $ProductionArm64) {
    $flutterArgs += "--android-project-arg=GENERIC_IM_ENABLE_EMULATOR_ABIS=true"
}
if (-not [string]::IsNullOrWhiteSpace($BootstrapUrl)) {
    $flutterArgs += "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$($BootstrapUrl.Trim())"
}
if (-not [string]::IsNullOrWhiteSpace($PublicH5Url)) {
    $flutterArgs += "--dart-define=GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))"
}
if ($DisableReleaseShrink) {
    $flutterArgs += "--android-project-arg=GENERIC_IM_DISABLE_RELEASE_SHRINK=true"
}
if ($DisableSplashImage) {
    $flutterArgs += "--dart-define=GENERIC_IM_DISABLE_SPLASH_IMAGE=true"
}

if (-not $SkipPub) {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }
}

Clear-IntegrationTestReleaseArtifacts
$flutterArgs = @("build", "apk", "--release", "--no-pub") + $flutterArgs[3..($flutterArgs.Count - 1)]

$buildKind = if ($ProductionArm64) { "production arm64" } else { "local emulator" }
Write-Host "Building $buildKind APK with server $ServerUrl"
& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    $flutterExitCode = $LASTEXITCODE
    Clear-IntegrationTestReleaseArtifacts
    Write-Host "Retrying release packaging through Gradle after removing generated test-only registrant"
    Invoke-GradleRelease
}

$apk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    throw "APK was not produced: $apk"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactDir = Join-Path $repoRoot "artifacts\local-emulator-apk-$timestamp"
New-Item -ItemType Directory -Force $artifactDir | Out-Null
$artifactApk = Join-Path $artifactDir "genericim-local-emulator-release.apk"
Copy-Item -LiteralPath $apk -Destination $artifactApk -Force
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifactApk

Write-Host "APK: $artifactApk"
Write-Host "SHA256: $($hash.Hash)"
