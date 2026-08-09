param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$OutputDir = 'artifacts/real-device-qa/local-docker-dual-device-20260717/report-api',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

# API 验证默认基于新构建镜像，SkipBuild 仅用于已确认环境可复用的场景。
if (-not $SkipBuild) {
    docker compose up -d --build api
}

$healthy = $false
# 等待服务真正可请求后再执行断言，避免把启动延迟误报成功能失败。
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/health" -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            break
        }
    }
    catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $healthy) { throw 'Local API did not become healthy' }

# 报告接口的业务步骤由 Python runner 承担，本脚本只管理依赖与退出码。
$arguments = @(
    (Join-Path $PSScriptRoot 'run_im400_report_api.py')
    '--base-url', $BaseUrl
    '--output-dir', (Join-Path $repoRoot $OutputDir)
)
& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Report API QA failed with exit code $LASTEXITCODE"
}
