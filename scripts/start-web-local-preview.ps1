<#
.SYNOPSIS
构建并启动 Flutter Web 本地预览服务。

.DESCRIPTION
将本地 REST、WebSocket、Bootstrap 和公共 H5 地址写入 Flutter Web
Release 构建，然后使用仓库内 SPA 静态服务器在回环地址提供预览。
后台进程的标准输出和错误日志写入 build 目录。

.PARAMETER Port
本地预览端口。端口已有监听时复用现有服务，不重复启动进程。

.PARAMETER NoBuild
跳过 Flutter 构建并直接复用 build/web；调用方需确保产物与当前配置一致。

.PARAMETER UseCdnWebResources
允许 Flutter Web 从 CDN 加载运行资源；默认构建自包含资源以便离线验证。

.EXAMPLE
pwsh -File scripts/start-web-local-preview.ps1 -Port 5185 -NoBuild
#>
param(
    [int]$Port = 5185,
    [string]$ApiUrl = "http://127.0.0.1:8080",
    [string]$WsUrl = "ws://127.0.0.1:8080/api/v1/ws",
    [string]$BootstrapUrl = "http://127.0.0.1:8080/api/v1/client/bootstrap",
    [string]$PublicH5Url = "",
    [switch]$UseCdnWebResources,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$webDir = Join-Path $repo "build\web"
$outLog = Join-Path $repo "build\web-preview-local.out.log"
$errLog = Join-Path $repo "build\web-preview-local.err.log"
$flutterCandidates = @(@(
    $(if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT "bin\flutter.bat" }),
    (Join-Path $repo ".tools\flutter\bin\flutter.bat"),
    "D:\flutter\bin\flutter.bat",
    "C:\src\flutter\bin\flutter.bat"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
$flutter = if ($flutterCandidates.Count -gt 0) {
    $flutterCandidates[0]
} else {
    "flutter"
}

Push-Location $repo
try {
    if (-not $NoBuild) {
        # Dart Define 在编译期固化，切换后端地址后必须重新构建才能生效。
        $flutterArgs = @(
            "build",
            "web",
            "--release",
            "--dart-define=GENERIC_IM_SERVER_URL=$ApiUrl",
            "--dart-define=GENERIC_IM_WS_URL=$WsUrl",
            "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$BootstrapUrl"
        )
        if (-not $UseCdnWebResources) {
            $flutterArgs += "--no-web-resources-cdn"
        }
        if (-not [string]::IsNullOrWhiteSpace($PublicH5Url)) {
            $flutterArgs += "--dart-define=GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))"
        }

        & $flutter @flutterArgs

        if ($LASTEXITCODE -ne 0) {
            throw "Flutter web build failed with exit code $LASTEXITCODE"
        }
    }

    $indexPath = Join-Path $webDir "index.html"
    if (-not (Test-Path $indexPath)) {
        throw "Missing Flutter Web index.html: $indexPath"
    }

    $used = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $used) {
        # 预览服务常用于自动化验收，因此隐藏运行并将日志固定写入 build。
        $env:GENERIC_IM_WEB_STATIC_DIR = $webDir
        $env:GENERIC_IM_WEB_PORT = [string]$Port
        $env:GENERIC_IM_WEB_HOST = "127.0.0.1"

        Start-Process `
            -FilePath "node" `
            -ArgumentList @("scripts/serve_flutter_web_spa.mjs") `
            -WorkingDirectory $repo `
            -WindowStyle Hidden `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError $errLog | Out-Null

        Start-Sleep -Seconds 2
    }

    $url = "http://127.0.0.1:$Port/"
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 10
    Write-Host "Web/H5/PC preview: $url"
    Write-Host "API: $ApiUrl"
    Write-Host "WS: $WsUrl"
    Write-Host "HTTP status: $($response.StatusCode)"
}
finally {
    Pop-Location
}
