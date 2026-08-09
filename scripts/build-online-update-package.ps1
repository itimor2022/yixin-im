<#
.SYNOPSIS
生成供既有线上 Docker 环境覆盖升级的完整更新包。

.DESCRIPTION
收集后端、Admin、客服端、Flutter Web、H5、Docker 配置和更新脚本，统一 Linux
换行后创建 ZIP。包内配置包含目标域名和安装目录，生成后仍需在隔离环境解包核对。

.PARAMETER InstallDir
线上既有安装目录；更新脚本默认在此目录备份并覆盖文件。

.PARAMETER PackageName
输出更新包的基础名称。

.PARAMETER OutputRoot
暂存目录和 ZIP 输出目录。

.EXAMPLE
pwsh -File scripts/build-online-update-package.ps1 -OutputRoot artifacts
#>
param(
    [string]$OutputRoot = "artifacts",
    [string]$PackageName = "genericim-online-update",
    [string]$AdminDomain = "admin.example.com",
    [string]$ApiDomain = "api.example.com",
    [string]$H5Domain = "h5.example.com",
    [string]$KfDomain = "support.example.com",
    [string]$InstallDir = "/www/wwwroot/api.example.com"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8)
}

function Copy-TextAsLf {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $text = Get-Content -Raw $Source
    Write-Utf8NoBomLf -Path $Destination -Content $text
}

function New-LinuxCompatibleZip {
    # ZIP entry 固定使用正斜杠，确保由 Windows 生成后仍可在 Linux 正确解压。
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tempZip = "$Destination.tmp"
    if (Test-Path -LiteralPath $tempZip) {
        Remove-Item -LiteralPath $tempZip -Force
    }
    $archive = [System.IO.Compression.ZipFile]::Open(
        $tempZip,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        $sourceFull = (Resolve-Path -LiteralPath $SourceDir).Path
        Get-ChildItem -LiteralPath $sourceFull -Recurse -File | Where-Object {
            $_.Name -ne "SHA256SUMS.txt"
        } | ForEach-Object {
            $entryName = [System.IO.Path]::GetRelativePath($sourceFull, $_.FullName).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $_.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }
    Move-Item -LiteralPath $tempZip -Destination $Destination -Force
}

function Assert-NoManagedSslDirectives {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $patterns = @(
        @{ Name = "ssl_certificate"; Regex = "ssl_certificate" },
        @{ Name = "listen 443"; Regex = "listen\s+443" },
        @{ Name = "http2"; Regex = "\bhttp2\b" },
        @{ Name = "https redirect"; Regex = "return\s+301\s+https" }
    )
    $textExtensions = @(
        ".conf", ".env", ".json", ".md", ".nginx", ".ps1", ".service",
        ".sh", ".txt", ".yaml", ".yml"
    )
    $rootFull = (Resolve-Path -LiteralPath $Path).Path
    $rootFull = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $violations = New-Object System.Collections.Generic.List[string]

    Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $ext = $_.Extension.ToLowerInvariant()
        $textExtensions -contains $ext -or $_.Name -match '^(Dockerfile|README|deploy|update|docker-compose)'
    } | ForEach-Object {
        $file = $_
        $content = Get-Content -Raw -LiteralPath $file.FullName
        $relative = $file.FullName
        if ($relative.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $relative.Substring($rootFull.Length).TrimStart('\', '/')
        }
        $lines = $content -split "`n"
        foreach ($pattern in $patterns) {
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ([regex]::IsMatch($lines[$i], $pattern.Regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                    $violations.Add("${relative}:$($i + 1) forbidden $($pattern.Name)")
                }
            }
        }
    }

    if ($violations.Count -gt 0) {
        throw "Baota owns SSL/HTTPS certificates. Remove managed SSL directives from package files:`n$($violations -join "`n")"
    }
}

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $repo (Join-Path $OutputRoot "$PackageName-$stamp")
$payloadDir = Join-Path $outDir "payload"
$adminPayload = Join-Path $payloadDir "admin-dist"
$kfPayload = Join-Path $payloadDir "kf-dist"
$webPayload = Join-Path $payloadDir "web-dist"
$backendPayload = Join-Path $payloadDir "backend"
$dockerPayload = Join-Path $payloadDir "docker\genericim"
$squarePayload = Join-Path $payloadDir "square-content"
$squareImagePayload = Join-Path $squarePayload "images"
$reviewPayload = Join-Path $payloadDir "appstore-review"

New-Item -ItemType Directory -Force -Path $adminPayload, $kfPayload, $webPayload, $backendPayload, $dockerPayload, $squareImagePayload, $reviewPayload | Out-Null

Push-Location (Join-Path $repo "admin")
try {
    $env:VITE_BASE_URL = "/"
    $env:VITE_ACCESS_MODE = "frontend"
    $env:VITE_API_URL = "/api/v1"
    $env:VITE_API_BASE_URL = "/api/v1"
    npm.cmd run build
}
finally {
    Remove-Item Env:\VITE_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_ACCESS_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_API_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_API_BASE_URL -ErrorAction SilentlyContinue
    Pop-Location
}

Copy-Item -Path (Join-Path $repo "admin/dist/*") -Destination $adminPayload -Recurse -Force

$adminBundleFiles = @(Get-ChildItem -LiteralPath $adminPayload -Recurse -File | Where-Object {
    $_.Extension -in @(".html", ".js", ".css")
})
$staleAdminRefs = @($adminBundleFiles | Select-String -SimpleMatch "legacy.example.invalid")
if ($staleAdminRefs.Count -gt 0) {
    throw "Customer admin bundle still contains demo-domain references: $($staleAdminRefs[0].Path)"
}
$expectedAdminApi = @($adminBundleFiles | Select-String -SimpleMatch "/api/v1")
if ($expectedAdminApi.Count -eq 0) {
    throw "Customer admin bundle does not contain the same-origin API base /api/v1"
}
Write-Host "[OK] Customer admin same-origin API verified: /api/v1"

Push-Location (Join-Path $repo "admin-kf")
try {
    $env:VITE_API_BASE_URL = "/api/v1"
    $env:VITE_USE_MOCK = "false"
    npm.cmd run build
}
finally {
    Remove-Item Env:\VITE_API_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_USE_MOCK -ErrorAction SilentlyContinue
    Pop-Location
}

Copy-Item -Path (Join-Path $repo "admin-kf/dist/*") -Destination $kfPayload -Recurse -Force
Copy-TextAsLf -Source (Join-Path $repo "docker/genericim/kf-nginx.conf") -Destination (Join-Path $dockerPayload "kf-nginx.conf")

$serverUrl = "https://$ApiDomain"
$wsUrl = "wss://$ApiDomain/api/v1/ws"

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
Write-Host "[INFO] Flutter: $flutter"

Push-Location $repo
try {
    & $flutter build web --release `
        "--no-web-resources-cdn" `
        "--dart-define=GENERIC_IM_SERVER_URL=$serverUrl" `
        "--dart-define=GENERIC_IM_WS_URL=$wsUrl" `
        "--dart-define=GENERIC_IM_PUBLIC_H5_URL=https://$H5Domain" `
        "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$serverUrl/api/v1/client/bootstrap"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter web build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Copy-Item -Path (Join-Path $repo "build/web/*") -Destination $webPayload -Recurse -Force

foreach ($required in @(
    "index.html",
    "flutter_bootstrap.js",
    "main.dart.js",
    "assets/assets/sounds/ringtone.mp3",
    "canvaskit/chromium/canvaskit.wasm"
)) {
    $requiredPath = Join-Path $webPayload $required
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required H5 output is missing: $required"
    }
}
$h5MainPath = Join-Path $webPayload "main.dart.js"
$h5MainVersion = (Get-FileHash -Algorithm SHA256 -LiteralPath $h5MainPath).Hash.Substring(0, 16).ToLowerInvariant()
$h5BootstrapPath = Join-Path $webPayload "flutter_bootstrap.js"
$h5Bootstrap = Get-Content -Raw -LiteralPath $h5BootstrapPath
$versionedMainPath = "main.dart.js?v=$h5MainVersion"
$h5Bootstrap = $h5Bootstrap.Replace('"mainJsPath":"main.dart.js"', '"mainJsPath":"' + $versionedMainPath + '"')
if ($h5Bootstrap -notmatch [regex]::Escape($versionedMainPath)) {
    throw "Could not add the H5 main.dart.js cache-busting version"
}
[System.IO.File]::WriteAllText($h5BootstrapPath, $h5Bootstrap, [System.Text.UTF8Encoding]::new($false))
if ($h5Bootstrap -notmatch '"useLocalCanvasKit"\s*:\s*true') {
    throw "H5 build is not using local CanvasKit"
}
$h5Main = Get-Content -Raw -LiteralPath $h5MainPath
if ($h5Main -notmatch 'sounds/ringtone\.mp3') {
    throw "H5 build does not contain the outgoing call ringtone"
}
Write-Host "[OK] H5 local CanvasKit, versioned main JS and outgoing ringtone verified"

Push-Location (Join-Path $repo "backend")
try {
    go test ./...
    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    go build -trimpath -ldflags "-s -w" -o (Join-Path $backendPayload "server-linux-amd64") ./cmd/server
}
finally {
    Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
    Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}

Copy-TextAsLf -Source (Join-Path $repo "scripts/online_update.sh") -Destination (Join-Path $outDir "update.sh")
$squareSeedSource = Join-Path $repo "backend/scripts/seed_square_release_notes_20260723.sql"
$squareAssetsSource = Join-Path $repo "backend/scripts/seed_assets/square_collaboration"
Copy-TextAsLf -Source $squareSeedSource -Destination (Join-Path $squarePayload "seed.sql")
Copy-Item -Path (Join-Path $squareAssetsSource "*.jpg") -Destination $squareImagePayload -Force
Copy-TextAsLf -Source (Join-Path $squareAssetsSource "IMAGE_SOURCES.md") -Destination (Join-Path $squarePayload "IMAGE_SOURCES.md")
Copy-TextAsLf -Source (Join-Path $repo "backend/scripts/seed_appstore_review_account.sql") -Destination (Join-Path $reviewPayload "account.sql")
Copy-TextAsLf -Source (Join-Path $repo "backend/scripts/seed_appstore_review_messages.js") -Destination (Join-Path $reviewPayload "messages.js")
$updatePath = Join-Path $outDir "update.sh"
$updateText = Get-Content -Raw -LiteralPath $updatePath
$updateText = $updateText.Replace("admin.example.com", $AdminDomain)
$updateText = $updateText.Replace("api.example.com", $ApiDomain)
$updateText = $updateText.Replace("h5.example.com", $H5Domain)
$updateText = $updateText.Replace("support.example.com", $KfDomain)
Write-Utf8NoBomLf -Path $updatePath -Content $updateText

@"
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="`$(cd "`$(dirname "`${BASH_SOURCE[0]}")" && pwd)"

if [ -z "`${INSTALL_DIR:-}" ]; then
  candidates=(
    "$InstallDir"
    "/www/wwwroot/genericim"
    "/www/wwwroot/api.example.com"
  )
  for candidate in "`${candidates[@]}"; do
    if [ -f "`$candidate/.env.bt" ] && [ -f "`$candidate/compose.bt.yaml" ]; then
      INSTALL_DIR="`$candidate"
      break
    fi
  done
fi

if [ -z "`${INSTALL_DIR:-}" ]; then
  echo "[ERR] 未找到现有一键部署目录，请执行：sudo INSTALL_DIR=/实际安装目录 bash update-customer.sh" >&2
  exit 1
fi

export INSTALL_DIR
echo "[INFO] 检测到安装目录：`$INSTALL_DIR"

exec bash "`$ROOT_DIR/update.sh"
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "update-customer.sh")

@"
# 通用IM Docker 一键部署整套覆盖更新包

本包仅用于覆盖客户现有 Docker 一键部署环境，包含：

- API 后端 Linux amd64 二进制
- 管理后台 admin-dist（同源 /api/v1）
- 客服后台 kf-dist
- Web/H5/PC web-dist（本地 CanvasKit、最新通话响铃修复）
- 自动备份、Docker 重启和健康检查脚本

脚本会自动检测以下现有安装目录：

- $InstallDir
- /www/wwwroot/genericim
- /www/wwwroot/api.example.com

如果实际目录不同，可执行 `sudo INSTALL_DIR=/实际安装目录 bash update-customer.sh`。

执行前会检查现有 `.env.bt`、`compose.bt.yaml` 和 Docker Compose 环境；不符合条件会停止，不会盲目覆盖。

## 执行方法

将 ZIP 上传到服务器 `/tmp` 后执行：

~~~bash
cd /tmp
rm -rf GenericIM-full-online-update
mkdir -p GenericIM-full-online-update
unzip -o $PackageName-$stamp.zip -d GenericIM-full-online-update
cd GenericIM-full-online-update
chmod +x update.sh update-customer.sh payload/backend/server-linux-amd64
sudo bash update-customer.sh
~~~

脚本会先把当前静态目录、后端二进制、MySQL、MongoDB 和 Redis 备份到：

~~~text
$InstallDir/backups/update-YYYYMMDD-HHMMSS
~~~

宝塔继续负责域名 SSL 证书和公网反向代理，本包不会覆盖证书。
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "客户覆盖更新说明.md")

@"
# GenericIM IM online update package

Upload this archive to the server install parent directory, then run:

~~~bash
cd $InstallDir
rm -rf genericim-online-update
unzip -o $PackageName-$stamp.zip -d genericim-online-update
cd genericim-online-update
chmod +x update.sh payload/backend/server-linux-amd64
sudo INSTALL_DIR=$InstallDir bash update.sh
~~~

The update script will:

- Back up admin-dist, web-dist, kf-dist, backend binaries, MySQL, MongoDB and Redis.
- Update admin, H5/Web, kf/service-admin static files and backend binary.
- Hide previous public square content and publish six curated release-note posts with locally hosted office images.
- Reset the dedicated App Store review account to exactly two normal conversations.
- Generate h5/kf Docker compose overrides for older installs when needed.
- Update CORS origins for admin/api/h5/kf.
- Fix static file read permissions for nginx containers.
- Restart Docker services and run health checks.

To switch existing installs to Aliyun OSS before running update.sh, edit $InstallDir/.env.bt or pass env vars:

~~~bash
sudo STORAGE_PROVIDER=aliyun \
  STORAGE_ALIYUN_ENDPOINT=oss-cn-hangzhou.aliyuncs.com \
  STORAGE_ALIYUN_BUCKET=your-bucket \
  STORAGE_ALIYUN_ACCESS_KEY_ID=your-access-key-id \
  STORAGE_ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret \
  STORAGE_ALIYUN_PUBLIC_BASE_URL=https://media.example.com \
  INSTALL_DIR=$InstallDir \
  bash update.sh
~~~

Baota owns SSL/HTTPS/certificate renewal for all public domains. This package does not write SSL certificates or HTTPS vhosts.

Baota reverse proxy targets:

~~~text
$AdminDomain -> http://127.0.0.1:18084
$ApiDomain   -> http://127.0.0.1:18080
$H5Domain    -> http://127.0.0.1:18083
$KfDomain    -> http://127.0.0.1:18085
~~~

Backup directory: backups/update-YYYYMMDD-HHMMSS
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "README_UPDATE.md")

Assert-NoManagedSslDirectives -Path $outDir

$zipPath = Join-Path (Split-Path $outDir -Parent) "$PackageName-$stamp.zip"
New-LinuxCompatibleZip -SourceDir $outDir -Destination $zipPath

$tarPath = Join-Path (Split-Path $outDir -Parent) "$PackageName-$stamp.tar.gz"
if (Get-Command tar -ErrorAction SilentlyContinue) {
    Push-Location $outDir
    try {
        tar -czf $tarPath .
    }
    finally {
        Pop-Location
    }
}

$hashes = @()
$hashes += Get-FileHash -Algorithm SHA256 $zipPath
if (Test-Path $tarPath) {
    $hashes += Get-FileHash -Algorithm SHA256 $tarPath
}
$hashes | ForEach-Object { "$($_.Hash)  $($_.Path)" } | Set-Content -Path (Join-Path $outDir "SHA256SUMS.txt") -Encoding ASCII

Write-Host "[OK] Update package created:"
Write-Host "  Directory: $outDir"
Write-Host "  Zip:       $zipPath"
if (Test-Path $tarPath) {
    Write-Host "  Tar.gz:    $tarPath"
}
Write-Host "  SHA256:    $(Join-Path $outDir 'SHA256SUMS.txt')"
