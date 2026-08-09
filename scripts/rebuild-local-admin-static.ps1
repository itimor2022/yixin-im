param(
    [int]$Port = 8082
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$composeFile = Join-Path $repoRoot "compose.yaml"
$pidFile = Join-Path $repoRoot "artifacts\local-dev\admin-vite.pid"
$buildVersion = "local-static-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")

# 静态容器与 Vite 开发服务共用端口，重建前先按 pid 文件停止后者。
if (Test-Path $pidFile) {
    $vitePid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($vitePid) {
        $viteProcess = Get-Process -Id ([int]$vitePid) -ErrorAction SilentlyContinue
        if ($viteProcess) {
            Write-Host "[admin-static] Stopping Vite dev server $vitePid to free port $Port..."
            Stop-Process -Id ([int]$vitePid) -Force
            Start-Sleep -Seconds 1
        }
    }
}

Write-Host "[admin-static] Building admin Docker image: $buildVersion"
# 将唯一版本写入镜像，便于浏览器和部署检查确认不是旧缓存。
& docker compose -f $composeFile build `
    --build-arg "VITE_VERSION=$buildVersion" `
    --build-arg "BUILD_INFO=$buildVersion" `
    admin

Write-Host "[admin-static] Restarting admin container..."
& docker compose -f $composeFile up -d admin

$deadline = (Get-Date).AddSeconds(60)
# 轮询首页作为容器就绪屏障，避免重启后立即读取尚未挂载的构建信息。
do {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/" -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            break
        }
    } catch {
        Start-Sleep -Seconds 2
    }
} while ((Get-Date) -lt $deadline)

# build-info.json 是本次镜像版本的最终可观察证据。
$info = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/build-info.json" -TimeoutSec 10
Write-Host "[admin-static] URL: http://127.0.0.1:$Port/"
Write-Host "[admin-static] Build info: $($info.Content)"
