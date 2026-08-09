<#
.SYNOPSIS
将当前 Go 后端热替换到正在运行的本地 Docker API 容器。

.DESCRIPTION
交叉编译 Linux amd64 二进制，备份容器内现有 server，再复制新二进制并重启容器，
最后等待健康检查。该操作会造成短暂服务中断；失败时使用保存的 previous 二进制恢复。

.PARAMETER ContainerName
需要替换后端二进制的 Docker 容器名称。

.PARAMETER HealthUrl
重启后用于确认新后端可用的健康检查地址。

.PARAMETER OutputDir
新旧二进制和部署证据目录。

.EXAMPLE
pwsh -File scripts/deploy-local-p2-backend.ps1 -ContainerName genericim-api
#>
param(
    [string]$ContainerName = "genericim-api",
    [string]$HealthUrl = "http://127.0.0.1:18080/health",
    [int]$HealthTimeoutSeconds = 60,
    [string]$OutputDir = "artifacts/p2-local-backend"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendDir = Join-Path $repoRoot "backend"
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $repoRoot $OutputDir
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$newBinary = Join-Path $resolvedOutputDir "server-p2-$stamp"
$previousBinary = Join-Path $resolvedOutputDir "server-previous-$stamp"

Write-Host "Building Linux backend binary..." -ForegroundColor Cyan
$previousGoOs = $env:GOOS
$previousGoArch = $env:GOARCH
$previousCgo = $env:CGO_ENABLED
try {
    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    Push-Location $backendDir
    try {
        & go build -trimpath -o $newBinary ./cmd/server
        if ($LASTEXITCODE -ne 0) { throw "Backend build failed." }
    } finally {
        Pop-Location
    }
} finally {
    $env:GOOS = $previousGoOs
    $env:GOARCH = $previousGoArch
    $env:CGO_ENABLED = $previousCgo
}

$running = (& docker inspect $ContainerName --format '{{.State.Running}}').Trim()
if ($running -ne "true") {
    throw "Container '$ContainerName' is not running."
}

# 先保存可直接回滚的运行中二进制，再进行任何容器内覆盖。
& docker cp "${ContainerName}:/app/server" $previousBinary
if ($LASTEXITCODE -ne 0) { throw "Could not back up the current backend binary." }

function Install-ContainerBinary {
    param([string]$SourcePath)

    & docker cp $SourcePath "${ContainerName}:/tmp/genericim-server-next"
    if ($LASTEXITCODE -ne 0) { throw "Could not copy backend binary into container." }
    & docker exec $ContainerName sh -c 'chmod 0755 /tmp/genericim-server-next && mv /tmp/genericim-server-next /app/server'
    if ($LASTEXITCODE -ne 0) { throw "Could not activate backend binary." }
    & docker restart $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not restart backend container." }
}

function Wait-BackendHealth {
    $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 3
            if ($health.status -eq "ok") { return $true }
        } catch {
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

try {
    Install-ContainerBinary -SourcePath $newBinary
    if (-not (Wait-BackendHealth)) {
        throw "Updated backend did not become healthy."
    }
} catch {
    Write-Warning "P2 backend activation failed; restoring previous binary."
    Install-ContainerBinary -SourcePath $previousBinary
    $null = Wait-BackendHealth
    throw
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $newBinary).Hash
Write-Host "Local P2 backend is healthy." -ForegroundColor Green
Write-Host "Binary: $newBinary"
Write-Host "Previous: $previousBinary"
Write-Host "SHA256: $hash"
