[CmdletBinding()]
param(
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$PublicH5Url = "https://h5.example.com",
    [string]$OutputRoot = "artifacts",
    [switch]$SkipAndroid
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
# 按“显式环境变量 -> 本机固定安装 -> 仓库工具链”顺序选择 Flutter。
$flutterCandidates = @(@(
    $(if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT "bin\flutter.bat" }),
    "D:\flutter\bin\flutter.bat",
    (Join-Path $repo ".tools\flutter\bin\flutter.bat")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
if (-not $flutterCandidates) {
    throw "Flutter SDK was not found."
}
$flutter = $flutterCandidates[0]
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactDir = Join-Path $repo (Join-Path $OutputRoot "GenericIM-quick-link-$stamp")
$webStage = Join-Path $artifactDir "web-dist"
$h5Zip = Join-Path $artifactDir "GenericIM-h5-quick-link-$stamp.zip"
$apkPath = Join-Path $artifactDir "GenericIM-android-quick-link-$stamp.apk"

New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

Push-Location $repo
try {
    # Web 与 Android 共用同一组端点定义，确保快捷交付包连接到相同客户环境。
    $webArgs = @(
        "build", "web", "--release", "--no-web-resources-cdn",
        "--dart-define=GENERIC_IM_SERVER_URL=$($ServerUrl.TrimEnd('/'))",
        "--dart-define=GENERIC_IM_WS_URL=$($WsUrl.TrimEnd('/'))",
        "--dart-define=GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))",
        "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$($ServerUrl.TrimEnd('/'))/api/v1/client/bootstrap"
    )
    & $flutter @webArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter H5 build failed with exit code $LASTEXITCODE"
    }

    foreach ($required in @(
        "index.html",
        "open.html",
        "flutter_bootstrap.js",
        "main.dart.js",
        "canvaskit\chromium\canvaskit.wasm"
    )) {
        # 对运行时必需文件逐项验收，避免仅凭 flutter build 的退出码判定成功。
        $requiredPath = Join-Path $repo (Join-Path "build\web" $required)
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required H5 output is missing: $required"
        }
    }

    $bootstrap = Get-Content -Raw -LiteralPath (Join-Path $repo "build\web\flutter_bootstrap.js")
    # 快捷包要求 CanvasKit 随包分发，不能在客户环境运行时依赖外部 CDN。
    if ($bootstrap -notmatch '"useLocalCanvasKit"\s*:\s*true') {
        throw "H5 build is not using local CanvasKit."
    }

    New-Item -ItemType Directory -Force -Path $webStage | Out-Null
    Copy-Item -Path (Join-Path $repo "build\web\*") -Destination $webStage -Recurse -Force
    Compress-Archive -Path (Join-Path $webStage "*") -DestinationPath $h5Zip -Force

    if (-not $SkipAndroid) {
        $jdk = (Resolve-Path (Join-Path $repo ".tools\jdk-17.0.19+10")).Path
        $configuredJdk = "E:\AS\jbr"
        # Android 构建临时切换到仓库 JDK，并在 finally 中恢复开发机原配置。
        & $flutter config --jdk-dir $jdk | Out-Null
        try {
            $androidArgs = @(
                "build", "apk", "--release", "--no-pub",
                "--android-project-arg=GENERIC_IM_DISABLE_RELEASE_SHRINK=true",
                "--dart-define=GENERIC_IM_SERVER_URL=$($ServerUrl.TrimEnd('/'))",
                "--dart-define=GENERIC_IM_WS_URL=$($WsUrl.TrimEnd('/'))",
                "--dart-define=GENERIC_IM_PUBLIC_H5_URL=$($PublicH5Url.TrimEnd('/'))",
                "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$($ServerUrl.TrimEnd('/'))/api/v1/client/bootstrap"
            )
            & $flutter @androidArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter Android build failed with exit code $LASTEXITCODE"
            }
        }
        finally {
            if (Test-Path -LiteralPath $configuredJdk) {
                & $flutter config --jdk-dir $configuredJdk | Out-Null
            }
        }

        $builtApk = Join-Path $repo "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path -LiteralPath $builtApk)) {
            throw "Android APK was not produced."
        }
        Copy-Item -LiteralPath $builtApk -Destination $apkPath -Force
    }

    Copy-Item -LiteralPath (Join-Path $repo "scripts\deploy-h5-local-canvaskit.sh") `
        -Destination (Join-Path $artifactDir "deploy-h5-local-canvaskit.sh") -Force

    $hashFiles = @($h5Zip)
    if (Test-Path -LiteralPath $apkPath) { $hashFiles += $apkPath }
    # 哈希清单覆盖本次实际生成的全部可交付文件，SkipAndroid 时只包含 H5。
    $hashLines = foreach ($file in $hashFiles) {
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file
        "$($hash.Hash)  $([IO.Path]::GetFileName($file))"
    }
    $hashLines | Set-Content -LiteralPath (Join-Path $artifactDir "SHA256SUMS.txt") -Encoding ASCII

    Write-Host "Quick-link customer release created:"
    Write-Host "  Directory: $artifactDir"
    Write-Host "  H5 ZIP:   $h5Zip"
    if (Test-Path -LiteralPath $apkPath) { Write-Host "  APK:      $apkPath" }
}
finally {
    Pop-Location
}
