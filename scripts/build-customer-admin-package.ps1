param(
    [string]$ApiUrl = "/api/v1",
    [string]$PublicAdminUrl = "https://admin.example.com",
    [string]$InstallDir = "/www/wwwroot/genericim/genericim-online-server",
    [string]$OutputRoot = "artifacts",
    [string]$PackageName = "GenericIM-admin-api-genericim"
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$adminDir = Join-Path $repo "admin"
$distDir = Join-Path $adminDir "dist"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outRoot = Join-Path $repo $OutputRoot
$outDir = Join-Path $outRoot "$PackageName-$stamp"
$adminPayload = Join-Path $outDir "admin-dist"
$zipPath = Join-Path $outRoot "$PackageName-$stamp.zip"

$normalizedApiUrl = $ApiUrl.TrimEnd("/")
$normalizedAdminUrl = $PublicAdminUrl.TrimEnd("/")
# 同源部署允许相对 API 路径；独立 API 地址必须使用 HTTPS。
if ($normalizedApiUrl -ne "/api/v1" -and $normalizedApiUrl -notmatch '^https://') {
    throw "Customer API URL must be /api/v1 or use HTTPS: $normalizedApiUrl"
}

Push-Location $adminDir
try {
    # 构建参数仅在当前进程临时注入，finally 中清理以免污染后续前端构建。
    $env:VITE_BASE_URL = "/"
    $env:VITE_ACCESS_MODE = "frontend"
    $env:VITE_API_URL = $normalizedApiUrl
    $env:VITE_API_BASE_URL = $normalizedApiUrl
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

if (-not (Test-Path -LiteralPath (Join-Path $distDir "index.html"))) {
    throw "Admin dist was not generated: $distDir"
}

$bundleFiles = @(Get-ChildItem -LiteralPath $distDir -Recurse -File | Where-Object {
    $_.Extension -in @(".html", ".js", ".css")
})
# 发布前扫描编译产物，阻止演示域名或错误的跨域 API 地址进入客户包。
$staleRefs = @($bundleFiles | Select-String -SimpleMatch "legacy.example.invalid")
if ($staleRefs.Count -gt 0) {
    throw "Admin dist still contains demo-domain references: $($staleRefs[0].Path)"
}
$crossOriginRefs = @($bundleFiles | Select-String -SimpleMatch "https://api.example.com")
if ($normalizedApiUrl -eq "/api/v1" -and $crossOriginRefs.Count -gt 0) {
    throw "Same-origin admin bundle still contains the cross-origin API host: $($crossOriginRefs[0].Path)"
}
$expectedRefs = @($bundleFiles | Select-String -SimpleMatch $normalizedApiUrl)
if ($expectedRefs.Count -eq 0) {
    throw "Admin dist does not contain expected API URL: $normalizedApiUrl"
}

New-Item -ItemType Directory -Path $adminPayload -Force | Out-Null
# 交付包同时携带静态文件、部署脚本和可直接执行的服务器操作说明。
Copy-Item -Path (Join-Path $distDir "*") -Destination $adminPayload -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "deploy-admin-static.sh") -Destination $outDir -Force

@"
Customer admin static update

Admin URL: $normalizedAdminUrl
API URL:   $normalizedApiUrl
Install:   $InstallDir

Server commands:

  cd /tmp
  unzip -o $(Split-Path -Leaf $zipPath) -d /tmp/genericim-admin-api-fix
  sudo env PUBLIC_ADMIN_URL=$normalizedAdminUrl EXPECTED_API_URL=$normalizedApiUrl \
    bash /tmp/genericim-admin-api-fix/deploy-admin-static.sh \
    /tmp/genericim-admin-api-fix/admin-dist \
    $InstallDir
"@ | Set-Content -LiteralPath (Join-Path $outDir "DEPLOY.txt") -Encoding UTF8

New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
Push-Location $outDir
try {
    # 从产物目录内部归档，避免 ZIP 中额外嵌套时间戳目录。
    tar -a -c -f $zipPath .
    if ($LASTEXITCODE -ne 0) {
        throw "ZIP creation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
Write-Host "[OK] Customer admin package created"
Write-Host "  API:    $normalizedApiUrl"
Write-Host "  ZIP:    $zipPath"
Write-Host "  SHA256: $($hash.Hash)"
