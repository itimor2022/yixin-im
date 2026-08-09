<#
.SYNOPSIS
生成无需服务器现场编译的通用IM Docker 预构建部署包。

.DESCRIPTION
汇总已构建前端、后端二进制、Docker 配置和部署脚本，写入客户域名、端口和安装目录。
DefaultAdminPassword 会进入交付配置，生产交付前必须替换默认值并复核包内敏感信息。

.PARAMETER CustomerName
客户交付标识，用于产物命名和说明，不应包含隐私数据。

.PARAMETER Scheme
对外服务使用的 http 或 https 协议。

.PARAMETER DefaultAdminPassword
首次部署管理员密码；禁止在生产包中保留默认 123456。

.EXAMPLE
pwsh -File scripts/build-online-prebuilt-package.ps1 -CustomerName demo -DefaultAdminPassword '<strong-password>'
#>
param(
    [string]$OutputRoot = "artifacts",
    [string]$PackageName = "genericim-online-prebuilt",
    [string]$CustomerName = "",
    [string]$AdminDomain = "admin.example.com",
    [string]$ApiDomain = "api.example.com",
    [string]$H5Domain = "h5.example.com",
    [string]$KfDomain = "support.example.com",
    [string]$H5Port = "18083",
    [string]$AdminPort = "18084",
    [string]$KfPort = "18085",
    [ValidateSet("http", "https")]
    [string]$Scheme = "https",
    [string]$InstallDir = "",
    [string]$DefaultAdminPassword = "123456"
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outRoot = Join-Path $repo $OutputRoot
$outDir = Join-Path $outRoot "$PackageName-$stamp"
$adminPayload = Join-Path $outDir "admin-dist"
$kfPayload = Join-Path $outDir "kf-dist"
$webPayload = Join-Path $outDir "web-dist"
$backendPayload = Join-Path $outDir "backend"
$scriptPayload = Join-Path $outDir "scripts"
$dockerPayload = Join-Path $outDir "docker\genericim"

New-Item -ItemType Directory -Force -Path $adminPayload, $kfPayload, $webPayload, $backendPayload, $scriptPayload, $dockerPayload | Out-Null

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

function Assert-NoBundledCertificates {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $certificates = @(Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $_.Name -match '\.(pem|key|p12|pfx)$'
    })
    if ($certificates.Count -gt 0) {
        throw "The deployment package must not contain customer certificates or private keys:`n$($certificates.FullName -join "`n")"
    }
}

$deployDirName = if ($CustomerName.Trim()) {
    ($CustomerName.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-') -replace '^-+|-+$', ''
} else {
    ($ApiDomain.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-') -replace '^-+|-+$', ''
}
if (-not $deployDirName) {
    $deployDirName = "genericim-online-server"
}
if (-not $InstallDir.Trim()) {
    $InstallDir = "/www/wwwroot/$deployDirName/genericim-online-server"
}

$serverUrl = "${Scheme}://$ApiDomain"
$adminApiUrl = "/api/v1"
$wsScheme = if ($Scheme -eq "https") { "wss" } else { "ws" }
$wsUrl = "${wsScheme}://${ApiDomain}/api/v1/ws"

Push-Location (Join-Path $repo "admin")
try {
    $env:VITE_BASE_URL = "/"
    $env:VITE_ACCESS_MODE = "frontend"
    $env:VITE_API_URL = $adminApiUrl
    $env:VITE_API_BASE_URL = $adminApiUrl
    npm.cmd run build
}
finally {
    Remove-Item Env:\VITE_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_ACCESS_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_API_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\VITE_API_BASE_URL -ErrorAction SilentlyContinue
    Pop-Location
}

Copy-Item -Path (Join-Path $repo "admin\dist\*") -Destination $adminPayload -Recurse -Force

$adminBundleFiles = @(Get-ChildItem -LiteralPath $adminPayload -Recurse -File | Where-Object {
    $_.Extension -in @(".html", ".js", ".css")
})
$staleAdminRefs = @($adminBundleFiles | Select-String -SimpleMatch "legacy.example.invalid")
if ($staleAdminRefs.Count -gt 0) {
    throw "Customer admin bundle still contains demo-domain references: $($staleAdminRefs[0].Path)"
}
$expectedAdminApi = @($adminBundleFiles | Select-String -SimpleMatch $adminApiUrl)
if ($expectedAdminApi.Count -eq 0) {
    throw "Customer admin bundle does not contain expected API URL: $adminApiUrl"
}
Write-Host "[OK] Customer admin API verified: $adminApiUrl"

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

Copy-Item -Path (Join-Path $repo "admin-kf\dist\*") -Destination $kfPayload -Recurse -Force

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
        "--dart-define=GENERIC_IM_PUBLIC_H5_URL=${Scheme}://$H5Domain" `
        "--dart-define=GENERIC_IM_BOOTSTRAP_URL=$serverUrl/api/v1/client/bootstrap"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter web build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Copy-Item -Path (Join-Path $repo "build\web\*") -Destination $webPayload -Recurse -Force

Push-Location (Join-Path $repo "backend")
try {
    go test ./...

    $targets = @(
        @{ GOOS = "linux"; GOARCH = "amd64"; Output = "server-linux-amd64" },
        @{ GOOS = "linux"; GOARCH = "arm64"; Output = "server-linux-arm64" }
    )

    foreach ($target in $targets) {
        $env:GOOS = $target.GOOS
        $env:GOARCH = $target.GOARCH
        $env:CGO_ENABLED = "0"
        go build -trimpath -ldflags "-s -w" -o (Join-Path $backendPayload $target.Output) ./cmd/server
    }
}
finally {
    Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
    Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}

$backendAssets = Join-Path $repo "backend\assets"
if (Test-Path $backendAssets) {
    Copy-Item -Path $backendAssets -Destination (Join-Path $backendPayload "assets") -Recurse -Force
}

$backendUploads = Join-Path $repo "backend\uploads"
if (Test-Path $backendUploads) {
    Copy-Item -Path $backendUploads -Destination (Join-Path $backendPayload "uploads") -Recurse -Force
}

$deployEntryPath = Join-Path $outDir "deploy-online-prebuilt.sh"
Copy-TextAsLf -Source (Join-Path $repo "deploy-online-prebuilt.sh") -Destination $deployEntryPath
$deployEntryText = Get-Content -Raw $deployEntryPath
$deployEntryText = $deployEntryText.Replace("admin.example.com", $AdminDomain)
$deployEntryText = $deployEntryText.Replace("api.example.com", $ApiDomain)
$deployEntryText = $deployEntryText.Replace("h5.example.com", $H5Domain)
$deployEntryText = $deployEntryText.Replace("support.example.com", $KfDomain)
Write-Utf8NoBomLf -Path $deployEntryPath -Content $deployEntryText
Copy-TextAsLf -Source (Join-Path $repo "scripts\baota_docker_deploy_prebuilt.sh") -Destination (Join-Path $scriptPayload "baota_docker_deploy_prebuilt.sh")
Copy-Item -Path (Join-Path $repo "docker\genericim\backend-config.yaml") -Destination (Join-Path $dockerPayload "backend-config.yaml") -Force
Copy-Item -Path (Join-Path $repo "docker\genericim\admin-nginx.conf") -Destination (Join-Path $dockerPayload "admin-nginx.conf") -Force
Copy-Item -Path (Join-Path $repo "docker\genericim\kf-nginx.conf") -Destination (Join-Path $dockerPayload "kf-nginx.conf") -Force
$readmeText = Get-Content -Raw (Join-Path $repo "docs\deployment\ONLINE_PREBUILT_DEPLOY_README.md")
$readmeText = $readmeText.Replace("admin.example.com", $AdminDomain)
$readmeText = $readmeText.Replace("api.example.com", $ApiDomain)
$readmeText = $readmeText.Replace("h5.example.com", $H5Domain)
$readmeText = $readmeText.Replace("support.example.com", $KfDomain)
$readmeText = $readmeText.Replace("/www/wwwroot/genericim", $InstallDir)
$readmeText | Set-Content -Path (Join-Path $outDir "README.md") -Encoding UTF8

@"
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="`$(cd "`$(dirname "`${BASH_SOURCE[0]}")" && pwd)"

export INSTALL_DIR="`${INSTALL_DIR:-$InstallDir}"
export SCHEME="`${SCHEME:-$Scheme}"
export ADMIN_DOMAIN="`${ADMIN_DOMAIN:-$AdminDomain}"
export API_DOMAIN="`${API_DOMAIN:-$ApiDomain}"
export H5_DOMAIN="`${H5_DOMAIN:-$H5Domain}"
export KF_DOMAIN="`${KF_DOMAIN:-$KfDomain}"
export H5_PORT="`${H5_PORT:-$H5Port}"
export ADMIN_PORT="`${ADMIN_PORT:-$AdminPort}"
export KF_PORT="`${KF_PORT:-$KfPort}"
export ADMIN_PASSWORD="`${ADMIN_PASSWORD:-$DefaultAdminPassword}"
export WRITE_NGINX="`${WRITE_NGINX:-1}"

exec bash "`$ROOT_DIR/deploy-online-prebuilt.sh"
"@ | Write-Utf8NoBomLf -Path (Join-Path $outDir "deploy-customer.sh")

@"
# 客户一键部署包

客户名称：$CustomerName

默认域名：

- 后台：admin -> $AdminDomain
- 客服后台：kf -> $KfDomain
- API/媒体：api -> $ApiDomain
- Web/H5/PC：web -> $H5Domain
- 协议：$Scheme
- 安装目录：$InstallDir
- 后台本地容器端口：127.0.0.1:$AdminPort
- 客服后台本地容器端口：127.0.0.1:$KfPort
- H5 本地容器端口：127.0.0.1:$H5Port

## 服务器执行

mkdir -p genericim-online-prebuilt
tar -xzf $PackageName-$stamp.tar.gz -C genericim-online-prebuilt
cd genericim-online-prebuilt
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh

如需首次部署就启用阿里云 OSS：

sudo STORAGE_PROVIDER=aliyun \
  STORAGE_ALIYUN_ENDPOINT=oss-cn-hangzhou.aliyuncs.com \
  STORAGE_ALIYUN_BUCKET=your-bucket \
  STORAGE_ALIYUN_ACCESS_KEY_ID=your-access-key-id \
  STORAGE_ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret \
  STORAGE_ALIYUN_PUBLIC_BASE_URL=https://media.example.com \
  bash deploy-customer.sh

如需临时改域名：

sudo API_DOMAIN=api.example.com ADMIN_DOMAIN=admin.example.com H5_DOMAIN=h5.example.com KF_DOMAIN=kf.example.com bash deploy-customer.sh

部署后检查：

curl ${Scheme}://$ApiDomain/health
curl -I ${Scheme}://$AdminDomain/
curl -I ${Scheme}://$KfDomain/
curl -I ${Scheme}://$H5Domain/
curl http://127.0.0.1:$KfPort/
curl http://127.0.0.1:$H5Port/
"@ | Set-Content -Path (Join-Path $outDir "CUSTOMER_DEPLOY_README.md") -Encoding UTF8

Assert-NoBundledCertificates -Path $outDir

$zipPath = Join-Path $outRoot "$PackageName-$stamp.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath -Force

$tarPath = Join-Path $outRoot "$PackageName-$stamp.tar.gz"
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
$hashes | ForEach-Object { "$($_.Hash)  $([System.IO.Path]::GetFileName($_.Path))" } | Set-Content -Path (Join-Path $outDir "SHA256SUMS.txt") -Encoding ASCII

Write-Host "[OK] Online prebuilt package created:"
Write-Host "  Directory: $outDir"
Write-Host "  Zip:       $zipPath"
if (Test-Path $tarPath) {
    Write-Host "  Tar.gz:    $tarPath"
}
Write-Host "  SHA256:    $(Join-Path $outDir 'SHA256SUMS.txt')"
Write-Host "  Customer:  $(Join-Path $outDir 'deploy-customer.sh')"
