<#
.SYNOPSIS
启动连接本地后端的运营管理后台开发服务。

.DESCRIPTION
按需启动 Docker 依赖，准备 Vite 环境变量，并以前台或后台方式运行 Admin。
后台模式会记录 PID 和日志；再次运行时只停止该 PID 文件所指向的旧服务。

.PARAMETER Port
管理后台 Vite 监听端口。

.PARAMETER ApiUrl
管理后台访问的后端地址。

.PARAMETER SkipDocker
不启动 Docker 依赖；调用方需保证后端已经可访问。

.PARAMETER Background
隐藏启动 Vite，并将 PID、标准输出和错误日志写入 artifacts/local-dev。

.EXAMPLE
pwsh -File scripts/start-local-admin-dev.ps1 -Background -SkipDocker
#>
param(
    [int]$Port = 8082,
    [string]$ApiUrl = "http://127.0.0.1:8080",
    [switch]$SkipDocker,
    [switch]$Background
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$adminRoot = Join-Path $repoRoot "admin"
$composeFile = Join-Path $repoRoot "compose.yaml"
$logDir = Join-Path $repoRoot "artifacts\local-dev"
$pidFile = Join-Path $logDir "admin-vite.pid"
$outLog = Join-Path $logDir "admin-vite.out.log"
$errLog = Join-Path $logDir "admin-vite.err.log"
$version = "local-dev-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timeout waiting for $Url"
}

function Get-Pnpm {
    $cmd = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command pnpm -ErrorAction SilentlyContinue
    }
    if (-not $cmd) {
        throw "pnpm is not installed or not in PATH."
    }
    return $cmd.Source
}

function Stop-ExistingVite {
    # 只处理本脚本记录的进程，避免误停机器上的其他 Vite 项目。
    if (-not (Test-Path $pidFile)) {
        return
    }

    $oldPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $oldPid) {
        return
    }
    if ([int]$oldPid -eq $PID) {
        return
    }

    $process = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[local-admin] Stopping previous Vite process $oldPid..."
        Stop-Process -Id ([int]$oldPid) -Force
        Start-Sleep -Seconds 1
    }
}

if (-not $SkipDocker) {
    Write-Host "[local-admin] Starting local backend dependencies..."
    & docker compose -f $composeFile up -d mysql mongodb redis api
    Wait-HttpOk -Url "$ApiUrl/health" -TimeoutSeconds 120
}

$adminContainer = & docker ps -q --filter "name=^/genericim-admin$"
if ($adminContainer) {
    Write-Host "[local-admin] Stopping static admin container genericim-admin to free port $Port..."
    & docker stop genericim-admin | Out-Null
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Stop-ExistingVite

if ($Background) {
    $pwsh = "pwsh"
    if (-not (Test-Path $pwsh)) {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    }

    $args = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $PSCommandPath,
        "-Port",
        $Port.ToString(),
        "-ApiUrl",
        $ApiUrl,
        "-SkipDocker"
    )

    $process = Start-Process -FilePath $pwsh -ArgumentList $args -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    Set-Content -Path $pidFile -Value $process.Id -Encoding ASCII
    Wait-HttpOk -Url "http://127.0.0.1:$Port/" -TimeoutSeconds 60
    Write-Host "[local-admin] Vite dev server started: http://127.0.0.1:$Port/"
    Write-Host "[local-admin] Logs: $outLog"
    return
}

$pnpm = Get-Pnpm
if (-not (Test-Path (Join-Path $adminRoot "node_modules"))) {
    Write-Host "[local-admin] Installing admin dependencies..."
    Push-Location $adminRoot
    try {
        & $pnpm install
    } finally {
        Pop-Location
    }
}

$env:VITE_IS_DEV = "true"
$env:VITE_ACCESS_MODE = "frontend"
$env:VITE_BASE_URL = "/"
$env:VITE_PORT = $Port.ToString()
$env:VITE_API_URL = "/api/v1"
$env:VITE_API_PROXY_URL = $ApiUrl
$env:VITE_VERSION = $version
$env:BROWSER = "none"

Write-Host "[local-admin] Hot reload URL: http://127.0.0.1:$Port/"
Write-Host "[local-admin] API proxy: $ApiUrl"
Push-Location $adminRoot
try {
    & $pnpm exec vite --host 0.0.0.0 --port $Port --strictPort
} finally {
    Pop-Location
}
