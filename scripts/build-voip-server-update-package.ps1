<#
.SYNOPSIS
生成只更新 VoIP 服务端组件的最小 Linux 覆盖包。

.DESCRIPTION
收集 VoIP 服务端所需二进制/配置和更新脚本，统一为 UTF-8 LF 后创建 ZIP，
并校验包内没有无关客户端或完整源码。该包用于既有安装目录，不负责首次部署。

.PARAMETER OutputRoot
暂存目录和最终 ZIP 的输出根目录。

.PARAMETER PackageName
更新包基础名称。

.PARAMETER InstallDir
服务器上既有通用IM安装目录，更新脚本以此作为默认目标。

.EXAMPLE
pwsh -File scripts/build-voip-server-update-package.ps1
#>
param(
    [string]$OutputRoot = "artifacts",
    [string]$PackageName = "genericim-voip-server-only-update",
    [string]$InstallDir = "/www/wwwroot/api.example.com"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function Copy-TextAsLf {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Utf8NoBomLf -Path $Destination -Content (Get-Content -Raw -LiteralPath $Source)
}

function New-LinuxCompatibleZip {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open(
        $Destination,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        $sourceFull = (Resolve-Path -LiteralPath $SourceDir).Path
        Get-ChildItem -LiteralPath $sourceFull -Recurse -File | ForEach-Object {
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
}

function Assert-MinimalPackage {
    param([Parameter(Mandatory = $true)][string]$PackageDir)

    $required = @(
        "update.sh",
        "update-customer.sh",
        "README_UPDATE.md",
        "payload/backend/server-linux-amd64"
    )
    $files = Get-ChildItem -LiteralPath $PackageDir -Recurse -File | ForEach-Object {
        [System.IO.Path]::GetRelativePath($PackageDir, $_.FullName).Replace('\', '/')
    }

    foreach ($item in $required) {
        if ($item -notin $files) {
            throw "Required package file is missing: $item"
        }
    }
    if ($files.Count -ne $required.Count) {
        throw "Unexpected file in minimal package: $($files -join ', ')"
    }

    $forbidden = '(?i)(square|appstore|review-account|seed|admin-dist|web-dist|h5-dist|kf-dist|\.sql$|\.js$|\.env|\.pem$|\.key$|\.p12$|\.pfx$)'
    $matches = $files | Where-Object { $_ -match $forbidden }
    if ($matches) {
        throw "Forbidden content found in minimal package: $($matches -join ', ')"
    }
}

$repo = Split-Path -Parent $PSScriptRoot
$outputBase = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot
} else {
    Join-Path $repo $OutputRoot
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $outputBase "$PackageName-$stamp"
$backendPayload = Join-Path $outDir "payload/backend"
$zipPath = Join-Path $outputBase "$PackageName-$stamp.zip"
$tarPath = Join-Path $outputBase "$PackageName-$stamp.tar.gz"
$sumsPath = Join-Path $outputBase "$PackageName-$stamp-SHA256SUMS.txt"

New-Item -ItemType Directory -Path $backendPayload -Force | Out-Null

$goCommand = Get-Command go.exe -ErrorAction SilentlyContinue
if (-not $goCommand) {
    $fallback = "C:\dev\go\bin\go.exe"
    if (Test-Path -LiteralPath $fallback) {
        $goExe = $fallback
    } else {
        throw "go.exe was not found."
    }
} else {
    $goExe = $goCommand.Source
}

Push-Location (Join-Path $repo "backend")
try {
    & $goExe test ./...
    if ($LASTEXITCODE -ne 0) {
        throw "go test ./... failed with exit code $LASTEXITCODE"
    }

    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    & $goExe build -buildvcs=false -trimpath -ldflags "-s -w" `
        -o (Join-Path $backendPayload "server-linux-amd64") ./cmd/server
    if ($LASTEXITCODE -ne 0) {
        throw "Linux amd64 backend build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
    Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}

Copy-TextAsLf `
    -Source (Join-Path $repo "scripts/voip_server_update.sh") `
    -Destination (Join-Path $outDir "update.sh")

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
  echo "[ERR] Existing Docker install was not found. Run: sudo INSTALL_DIR=/actual/path bash update-customer.sh" >&2
  exit 1
fi

export INSTALL_DIR
echo "[INFO] Install directory: `$INSTALL_DIR"
exec bash "`$ROOT_DIR/update.sh"
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "update-customer.sh")

@"
# VoIP 服务端最小更新包

本包只包含 Linux amd64 API 后端二进制，并且只重建 Docker Compose 的 ``api`` 服务。

明确不会执行：

- 广场发布内容导入或任何 SQL/数据库种子；
- App Store 审核账号重置或聊天记录写入；
- 管理后台、客服后台、H5/Web 静态资源更新；
- MySQL、MongoDB、Redis 数据修改。

## 执行

把压缩包上传到服务器并解压，然后执行：

~~~bash
chmod +x update.sh update-customer.sh payload/backend/server-linux-amd64
sudo bash update-customer.sh
~~~

如果自动识别不到安装目录：

~~~bash
sudo INSTALL_DIR=$InstallDir bash update-customer.sh
~~~

脚本会先将现有 ``backend/server`` 和 ``backend/server-linux-amd64`` 备份到：

~~~text
$InstallDir/backups/voip-server-update-YYYYMMDD-HHMMSS
~~~

随后仅重建 ``api`` 容器，并检查 ``http://127.0.0.1:18080/health``（端口以 ``.env.bt`` 为准）。
如果重建或健康检查失败，脚本会自动恢复旧二进制并再次重建 ``api``。
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "README_UPDATE.md")

Assert-MinimalPackage -PackageDir $outDir
New-LinuxCompatibleZip -SourceDir $outDir -Destination $zipPath

if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    throw "tar.exe was not found."
}
& tar.exe -czf $tarPath -C $outDir .
if ($LASTEXITCODE -ne 0) {
    throw "tar.gz creation failed with exit code $LASTEXITCODE"
}

$hashLines = @(
    "$(Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath | Select-Object -ExpandProperty Hash)  $(Split-Path -Leaf $zipPath)",
    "$(Get-FileHash -Algorithm SHA256 -LiteralPath $tarPath | Select-Object -ExpandProperty Hash)  $(Split-Path -Leaf $tarPath)"
)
$hashLines | Set-Content -LiteralPath $sumsPath -Encoding ASCII

Write-Host "[OK] VoIP server-only update package created:"
Write-Host "  Directory: $outDir"
Write-Host "  ZIP:       $zipPath"
Write-Host "  Tar.gz:    $tarPath"
Write-Host "  SHA256:    $sumsPath"
