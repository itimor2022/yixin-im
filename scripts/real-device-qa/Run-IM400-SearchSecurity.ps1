param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDir = 'artifacts/real-device-qa/local-docker-dual-device-20260717/search-security-api',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

# 默认重建 API 容器，复用既有环境时可用 SkipBuild 缩短验证时间。
if (-not $SkipBuild) {
    docker compose up -d --build api
}

$healthUrl = "$BaseUrl/health"
$healthy = $false
# 容器启动时间不固定，以健康端点作为运行 Python 用例的就绪屏障。
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            break
        }
    }
    catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $healthy) {
    throw "Local API did not become healthy at $healthUrl"
}

$runner = Join-Path $PSScriptRoot 'run_im400_search_security_api.py'
# PowerShell 负责环境编排，具体搜索与安全断言集中在 Python runner 中。
$arguments = @(
    $runner
    '--base-url', $BaseUrl
    '--output-dir', (Join-Path $repoRoot $OutputDir)
)
& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Search/security API QA failed with exit code $LASTEXITCODE"
}
