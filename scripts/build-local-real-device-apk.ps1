<#
.SYNOPSIS
构建供 Android 真机连接局域网或公网后端使用的 APK。

.DESCRIPTION
自动探测可访问本地后端的局域网 IPv4，也允许显式传入服务地址。
脚本拒绝 10.0.2.2、localhost 和其他回环地址，避免把只能在模拟器或
开发机内部访问的地址写入真机包。

.PARAMETER ServerUrl
真机可访问的 HTTP/HTTPS 后端地址；为空时尝试探测当前局域网地址。

.PARAMETER WsUrl
WebSocket 完整地址；为空时根据 ServerUrl 推导。

.PARAMETER AndroidLoopbackHost
需要传递给客户端的 Android 回环主机覆盖值。

.PARAMETER JdkPath
JDK 17 目录；相对路径按仓库根目录解析。

.PARAMETER SkipPub
跳过 flutter pub get，适用于依赖已经准备完成的本地环境。

.EXAMPLE
pwsh -File scripts/build-local-real-device-apk.ps1 -ServerUrl http://192.168.1.20:8080
#>
[CmdletBinding()]
param(
    [string]$ServerUrl = "",
    [string]$WsUrl = "",
    [string]$AndroidLoopbackHost = "",
    [string]$JdkPath = ".tools\jdk-17.0.19+10",
    [string]$PubHostedUrl = "https://pub.flutter-io.cn",
    [switch]$SkipPub = $true
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

& (Join-Path $PSScriptRoot "check-mojibake.ps1")

function Get-DefaultLanIPv4 {
    # 优先选择能实际访问后端健康接口的网卡，避免选中虚拟网卡地址。
    $ips = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
        ForEach-Object { $_.IPv4Address.IPAddress } |
        Where-Object {
            $_ -and
            $_ -notmatch "^127\." -and
            $_ -notmatch "^169\.254\." -and
            $_ -ne "10.0.2.2"
        }

    foreach ($ip in $ips) {
        try {
            Invoke-RestMethod -Uri "http://${ip}:8080/health" -TimeoutSec 3 | Out-Null
            return $ip
        } catch {
            # Try the next active interface.
        }
    }

    return ($ips | Select-Object -First 1)
}

function Resolve-WsUrl {
    param([Parameter(Mandatory = $true)][string]$HttpUrl)

    $trimmed = $HttpUrl.TrimEnd("/")
    if ($trimmed.StartsWith("https://")) {
        return "wss://" + $trimmed.Substring("https://".Length) + "/api/v1/ws"
    }
    if ($trimmed.StartsWith("http://")) {
        return "ws://" + $trimmed.Substring("http://".Length) + "/api/v1/ws"
    }
    throw "ServerUrl must start with http:// or https://."
}

function Assert-RealDeviceHost {
    # 真机无法使用模拟器专用地址或开发机回环地址访问后端。
    param([Parameter(Mandatory = $true)][string]$Url)

    $uri = [System.Uri]$Url
    $targetHost = $uri.Host.ToLowerInvariant()
    if ($targetHost -eq "10.0.2.2" -or $targetHost -eq "127.0.0.1" -or $targetHost -eq "localhost" -or $targetHost -eq "::1") {
        throw "Real-device APK must not use emulator/loopback host '$targetHost'. Pass -ServerUrl with a LAN or public backend URL."
    }
}

function Remove-IntegrationTestRegistrant {
    $registrant = Join-Path $repoRoot "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java"
    if (-not (Test-Path $registrant)) {
        return $false
    }

    $content = Get-Content -Raw -Path $registrant
    if ($content -notmatch "dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin") {
        return $false
    }

    $pattern = '(?ms)^\s*try\s*\{\s*\r?\n\s*flutterEngine\.getPlugins\(\)\.add\(new\s+dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\r?\n\s*\}\s*catch\s*\(Exception\s+e\)\s*\{\s*\r?\n\s*Log\.e\(TAG,\s*"Error registering plugin integration_test, dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin",\s*e\);\s*\r?\n\s*\}\s*'
    $updated = [regex]::Replace($content, $pattern, "")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($registrant, $updated, $utf8NoBom)
    Write-Host "Removed generated integration_test registrant from $registrant"
    return $true
}

function Remove-IntegrationTestPluginMetadata {
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

function ConvertTo-DartDefineValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
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
    $encodedDefines = ($defines | ForEach-Object { ConvertTo-DartDefineValue $_ }) -join ","
    $gradleArgs = @(
        "-q"
        "-Ptarget-platform=android-arm,android-arm64,android-x64"
        "-Ptarget=lib\main.dart"
        "-Pbase-application-name=android.app.Application"
        "-Pdart-defines=$encodedDefines"
        "-Pdart-obfuscation=false"
        "-Ptrack-widget-creation=true"
        "-Ptree-shake-icons=true"
    )

    Push-Location "android"
    try {
        # Flutter regenerates the Android registrant during this task. Compile
        # Dart/assets first, then remove the dev-only integration_test entry
        # before Java compilation and exclude the already completed task.
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

if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
    $lanIp = Get-DefaultLanIPv4
    if ([string]::IsNullOrWhiteSpace($lanIp)) {
        throw "Could not auto-detect a LAN IPv4 address. Pass -ServerUrl, for example http://192.168.1.100:8080."
    }
    $ServerUrl = "http://${lanIp}:8080"
}
$ServerUrl = $ServerUrl.TrimEnd("/")

Assert-RealDeviceHost -Url $ServerUrl

if ([string]::IsNullOrWhiteSpace($WsUrl)) {
    $WsUrl = Resolve-WsUrl -HttpUrl $ServerUrl
}
$WsUrl = $WsUrl.TrimEnd("/")

if ([string]::IsNullOrWhiteSpace($AndroidLoopbackHost)) {
    $AndroidLoopbackHost = ([System.Uri]$ServerUrl).Host
}
if ($AndroidLoopbackHost -eq "10.0.2.2" -or $AndroidLoopbackHost -eq "127.0.0.1" -or $AndroidLoopbackHost -eq "localhost") {
    throw "GENERIC_IM_ANDROID_LOOPBACK_HOST must be a real-device reachable host, got '$AndroidLoopbackHost'."
}

try {
    Invoke-RestMethod -Uri "$ServerUrl/health" -TimeoutSec 5 | Out-Null
} catch {
    throw "Backend health check failed from host for $ServerUrl/health. Fix the URL before building a real-device APK. $($_.Exception.Message)"
}

$resolvedJdk = Resolve-Path $JdkPath
$env:JAVA_HOME = $resolvedJdk.Path
$env:PATH = "$($resolvedJdk.Path)\bin;$env:PATH"
$gradleJdk = $resolvedJdk.Path.Replace([char]92, [char]47)
$env:GRADLE_OPTS = "-Dorg.gradle.java.home=$gradleJdk -Dorg.gradle.java.installations.paths=$gradleJdk"
if (-not [string]::IsNullOrWhiteSpace($PubHostedUrl)) {
    $env:PUB_HOSTED_URL = $PubHostedUrl
}

$flutterArgs = @(
    "build",
    "apk",
    "--release",
    "--dart-define=GENERIC_IM_SERVER_URL=$ServerUrl",
    "--dart-define=GENERIC_IM_WS_URL=$WsUrl",
    "--dart-define=GENERIC_IM_ANDROID_LOOPBACK_HOST=$AndroidLoopbackHost"
)

if (-not $SkipPub) {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }
}

$flutterArgs = @("build", "apk", "--release", "--no-pub") + $flutterArgs[3..($flutterArgs.Count - 1)]

Write-Host "Building real-device APK"
Write-Host "ServerUrl: $ServerUrl"
Write-Host "WsUrl: $WsUrl"
Write-Host "AndroidLoopbackHost: $AndroidLoopbackHost"
Clear-IntegrationTestReleaseArtifacts
& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    Clear-IntegrationTestReleaseArtifacts
    Write-Host "Retrying release packaging through Gradle after removing generated test-only registrant"
    Invoke-GradleRelease
}

$apk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    throw "APK was not produced: $apk"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactDir = Join-Path $repoRoot "artifacts\local-real-device-apk-$timestamp"
New-Item -ItemType Directory -Force $artifactDir | Out-Null
$artifactApk = Join-Path $artifactDir "genericim-local-real-device-release.apk"
Copy-Item -LiteralPath $apk -Destination $artifactApk -Force
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifactApk

Write-Host "APK: $artifactApk"
Write-Host "SHA256: $($hash.Hash)"
