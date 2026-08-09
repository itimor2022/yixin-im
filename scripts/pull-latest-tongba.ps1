$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

Write-Host "[INFO] Repo: $repo"
Write-Host "[INFO] Current branch:"
git branch --show-current

# fetch 会更新 FETCH_HEAD，先验证 Git 元数据目录没有被权限或占用问题锁死。
Write-Host "[INFO] Checking .git write access..."
try {
    $fetchHead = Join-Path $repo '.git\FETCH_HEAD'
    $stream = [System.IO.File]::Open($fetchHead, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    $stream.Close()
}
catch {
    Write-Host "[ERROR] Cannot write .git/FETCH_HEAD: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Close editors/terminals using this repo, then run this script from a normal PowerShell window." -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Starting ssh-agent if available..."
# ssh-agent 不可自动启动时继续探测已有身份，由后续检查给出明确失败原因。
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent) {
    if ($agent.Status -ne 'Running') {
        try {
            Start-Service ssh-agent
        }
        catch {
            Write-Host "[WARN] Could not start ssh-agent automatically: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "[INFO] Checking SSH identities..."
$hasIdentity = $false
try {
    ssh-add -l | Out-Host
    if ($LASTEXITCODE -eq 0) {
        $hasIdentity = $true
    }
}
catch {
    $hasIdentity = $false
}

if (-not $hasIdentity) {
    # 仅尝试常见私钥文件名，不扫描或输出其他 SSH 配置与密钥内容。
    $candidates = @(
        "$env:USERPROFILE\.ssh\id_ed25519",
        "$env:USERPROFILE\.ssh\id_rsa",
        "$env:USERPROFILE\.ssh\gitee",
        "$env:USERPROFILE\.ssh\gitee_ed25519"
    )
    foreach ($key in $candidates) {
        if (Test-Path $key) {
            Write-Host "[INFO] Adding SSH key: $key"
            ssh-add $key
            if ($LASTEXITCODE -eq 0) {
                $hasIdentity = $true
                break
            }
        }
    }
}

if (-not $hasIdentity) {
    Write-Host "[ERROR] No SSH key is loaded. Add your Gitee private key first, for example:" -ForegroundColor Red
    Write-Host "ssh-add `$env:USERPROFILE\.ssh\id_ed25519"
    exit 1
}

Write-Host "[INFO] Fetching tongba/main..."
git fetch tongba main

Write-Host "[INFO] Pulling latest with autostash..."
git pull --rebase --autostash tongba main

Write-Host "[OK] Done. Current status:"
git status -sb
