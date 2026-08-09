<#
.SYNOPSIS
生成线上 Docker 后端与 H5 的覆盖更新包，可选包含管理后台。

.DESCRIPTION
收集后端、H5、可选的管理后台和部署脚本，统一文本换行为 LF，并创建可在
Linux 解压的 ZIP。输出包面向既有安装目录执行覆盖更新，不负责首次部署。

.PARAMETER OutputRoot
更新包的暂存和输出目录。

.PARAMETER PackageName
生成的更新包基础名称。

.PARAMETER ApiDomain
写入更新说明和部署配置的 API 域名。

.PARAMETER H5Domain
写入更新说明和部署配置的 H5 域名。

.PARAMETER InstallDir
服务器上的既有安装目录；更新脚本以此目录为默认目标。

.PARAMETER IncludeAdmin
同时构建并包含同源 /api/v1 管理后台静态文件。

.EXAMPLE
pwsh -File scripts/build-online-backend-h5-update-package.ps1
#>
param(
    [string]$OutputRoot = "release-archives/customer-release-20260724/docker-backend-h5-update",
    [string]$PackageName = "GenericIM-Docker-Backend-H5-Update",
    [string]$ApiDomain = "api.example.com",
    [string]$H5Domain = "h5.example.com",
    [string]$InstallDir = "/www/wwwroot/api.example.com",
    [switch]$IncludeAdmin
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
    # 部署目标为 Linux，固定使用无 BOM UTF-8 和 LF，避免 Shell 解释器报错。
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText(
        $Path,
        $normalized,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Copy-TextAsLf {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Utf8NoBomLf -Path $Destination -Content (Get-Content -Raw -LiteralPath $Source)
}

function New-LinuxCompatibleZip {
    # 手动写入正斜杠 entry，避免 Windows 压缩包在 Linux 上产生错误路径。
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
        Get-ChildItem -LiteralPath $sourceFull -Recurse -File | ForEach-Object {
            $entryName = [System.IO.Path]::GetRelativePath(
                $sourceFull,
                $_.FullName
            ).Replace('\', '/')
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

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputBase = Join-Path $repo $OutputRoot
$outDir = Join-Path $outputBase "$PackageName-$stamp"
$payloadDir = Join-Path $outDir "payload"
$backendPayload = Join-Path $payloadDir "backend"
$webPayload = Join-Path $payloadDir "web-dist"
$adminPayload = Join-Path $payloadDir "admin-dist"

New-Item -ItemType Directory -Force -Path $backendPayload, $webPayload | Out-Null
if ($IncludeAdmin) {
    New-Item -ItemType Directory -Force -Path $adminPayload | Out-Null

    Write-Host "[INFO] Building admin with same-origin /api/v1"
    Push-Location (Join-Path $repo "admin")
    try {
        $env:VITE_BASE_URL = "/"
        $env:VITE_ACCESS_MODE = "frontend"
        $env:VITE_API_URL = "/api/v1"
        $env:VITE_API_BASE_URL = "/api/v1"
        npm.cmd run build
        if ($LASTEXITCODE -ne 0) {
            throw "Admin build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Remove-Item Env:\VITE_BASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\VITE_ACCESS_MODE -ErrorAction SilentlyContinue
        Remove-Item Env:\VITE_API_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\VITE_API_BASE_URL -ErrorAction SilentlyContinue
        Pop-Location
    }

    Copy-Item -Path (Join-Path $repo "admin/dist/*") -Destination $adminPayload -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $adminPayload "index.html"))) {
        throw "Admin output is missing index.html."
    }

    $adminBundleFiles = @(Get-ChildItem -LiteralPath $adminPayload -Recurse -File | Where-Object {
        $_.Extension -in @(".html", ".js", ".css")
    })
    $staleAdminRefs = @($adminBundleFiles | Select-String -SimpleMatch "legacy.example.invalid")
    if ($staleAdminRefs.Count -gt 0) {
        throw "Admin bundle contains a hard-coded demo domain: $($staleAdminRefs[0].Path)"
    }
    $expectedAdminApi = @($adminBundleFiles | Select-String -SimpleMatch "/api/v1")
    if ($expectedAdminApi.Count -eq 0) {
        throw "Admin bundle does not contain the same-origin API base /api/v1."
    }
}

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

Write-Host "[INFO] Building Flutter H5 with $flutter"
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
    if (-not (Test-Path -LiteralPath (Join-Path $webPayload $required))) {
        throw "Required H5 output is missing: $required"
    }
}

$h5MainPath = Join-Path $webPayload "main.dart.js"
$h5MainVersion = (Get-FileHash -Algorithm SHA256 -LiteralPath $h5MainPath).Hash.Substring(0, 16).ToLowerInvariant()
$h5BootstrapPath = Join-Path $webPayload "flutter_bootstrap.js"
$h5Bootstrap = Get-Content -Raw -LiteralPath $h5BootstrapPath
$versionedMainPath = "main.dart.js?v=$h5MainVersion"
$h5Bootstrap = $h5Bootstrap.Replace(
    '"mainJsPath":"main.dart.js"',
    '"mainJsPath":"' + $versionedMainPath + '"'
)
if ($h5Bootstrap -notmatch [regex]::Escape($versionedMainPath)) {
    throw "Could not add the H5 main.dart.js cache-busting version."
}
Write-Utf8NoBomLf -Path $h5BootstrapPath -Content $h5Bootstrap

if ($h5Bootstrap -notmatch '"useLocalCanvasKit"\s*:\s*true') {
    throw "H5 build is not using local CanvasKit."
}

$h5Main = Get-Content -Raw -LiteralPath $h5MainPath
if ($h5Main -notmatch 'sounds/ringtone\.mp3') {
    throw "H5 build does not contain the outgoing call ringtone."
}
if ($h5Main -notmatch [regex]::Escape($serverUrl)) {
    throw "H5 build does not contain the production API endpoint $serverUrl."
}
if ($h5Main -notmatch [regex]::Escape($wsUrl)) {
    throw "H5 build does not contain the production WebSocket endpoint $wsUrl."
}

Write-Host "[INFO] Testing and building Go backend"
Push-Location (Join-Path $repo "backend")
try {
    go test ./...
    if ($LASTEXITCODE -ne 0) {
        throw "go test ./... failed with exit code $LASTEXITCODE"
    }

    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    go build -trimpath -ldflags "-s -w" -o (Join-Path $backendPayload "server-linux-amd64") ./cmd/server
    if ($LASTEXITCODE -ne 0) {
        throw "Go backend build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
    Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}

$backendMagic = [System.IO.File]::ReadAllBytes(
    (Join-Path $backendPayload "server-linux-amd64")
)[0..3]
if (-not [System.Linq.Enumerable]::SequenceEqual(
    [byte[]]$backendMagic,
    [byte[]](0x7F, 0x45, 0x4C, 0x46)
)) {
    throw "Backend output is not an ELF binary."
}

Copy-TextAsLf `
    -Source (Join-Path $repo "scripts/online_update_backend_h5.sh") `
    -Destination (Join-Path $outDir "update.sh")

@"
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="`$(cd "`$(dirname "`${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR="`${INSTALL_DIR:-$InstallDir}"
exec bash "`$ROOT_DIR/update.sh"
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "update-customer.sh")

$includedScope = if ($IncludeAdmin) {
    @"
- payload/backend/server-linux-amd64
- payload/web-dist
- payload/admin-dist
"@
} else {
    @"
- payload/backend/server-linux-amd64
- payload/web-dist
"@
}
$excludedAdmin = if ($IncludeAdmin) { "" } else { "管理后台、" }
$completionLabel = if ($IncludeAdmin) {
    "后端/API、H5 与管理后台"
} else {
    "后端/API 与 H5"
}

@"
# 通用IM Docker $completionLabel 线上覆盖更新包

本包只更新：

$includedScope

本包不会覆盖${excludedAdmin}客服后台、线上 .env.bt、数据库业务数据、上传文件或 Docker volume。

上传 ZIP 到服务器后执行：

~~~bash
cd /tmp
rm -rf GenericIM-backend-h5-update
mkdir -p GenericIM-backend-h5-update
unzip -o $PackageName-$stamp.zip -d GenericIM-backend-h5-update
cd GenericIM-backend-h5-update
chmod +x update.sh update-customer.sh payload/backend/server-linux-amd64
sudo INSTALL_DIR=$InstallDir bash update-customer.sh
~~~

脚本会先备份旧后端、旧 H5$(if ($IncludeAdmin) { "、旧管理后台" })、MySQL、MongoDB 和 Redis；数据库备份失败时会在覆盖前终止。
成功标志：

~~~text
[OK] $completionLabel 覆盖更新完成。
~~~

不要执行 docker compose down -v，该命令可能删除数据库和上传数据卷。
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "线上覆盖更新说明.md")

$backendHash = (Get-FileHash -Algorithm SHA256 (Join-Path $backendPayload "server-linux-amd64")).Hash.ToLowerInvariant()
$h5MainHash = (Get-FileHash -Algorithm SHA256 $h5MainPath).Hash.ToLowerInvariant()
$updateScriptHash = (Get-FileHash -Algorithm SHA256 (Join-Path $outDir "update.sh")).Hash.ToLowerInvariant()
$manifestLines = @(
    "$backendHash  payload/backend/server-linux-amd64",
    "$h5MainHash  payload/web-dist/main.dart.js",
    "$updateScriptHash  update.sh"
)
if ($IncludeAdmin) {
    $adminIndexHash = (Get-FileHash -Algorithm SHA256 (Join-Path $adminPayload "index.html")).Hash.ToLowerInvariant()
    $manifestLines += "$adminIndexHash  payload/admin-dist/index.html"
}
Write-Utf8NoBomLf `
    -Path (Join-Path $outDir "PAYLOAD_SHA256SUMS.txt") `
    -Content (($manifestLines -join "`n") + "`n")

$zipPath = Join-Path $outputBase "$PackageName-$stamp.zip"
New-LinuxCompatibleZip -SourceDir $outDir -Destination $zipPath

$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
$sidecarPath = Join-Path $outputBase "$PackageName-$stamp.sha256.txt"
Write-Utf8NoBomLf `
    -Path $sidecarPath `
    -Content "$archiveHash  $(Split-Path -Leaf $zipPath)`n"

Write-Host "[OK] $completionLabel update package created"
Write-Host "  Directory: $outDir"
Write-Host "  Zip:       $zipPath"
Write-Host "  SHA256:    $archiveHash"
Write-Host "  Sidecar:   $sidecarPath"
