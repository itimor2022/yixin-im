<#
.SYNOPSIS
编排后端、Flutter 和可选 Android 的 IM 核心回归检查。

.DESCRIPTION
依次执行 Docker 构建/健康检查、Go 测试、Flutter analyze/test、聊天 API
与 WebSocket smoke，并可追加 Android UI 验收。任何 Skip 参数都会降低
覆盖范围，最终报告必须保留实际跳过阶段。

.PARAMETER IncludeAndroid
在静态与 API 检查后执行 Android 设备 UI smoke。

.PARAMETER AndroidDeviceId
IncludeAndroid 启用时使用的 ADB 设备；为空时由子脚本选择。

.PARAMETER OutputDir
保存每阶段耗时、状态和原始输出的目录。

.EXAMPLE
pwsh -File scripts/smoke_im_core_regression.ps1 -SkipDockerBuild
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$WsUrl = "ws://127.0.0.1:8080/api/v1/ws",
    [string]$OutputDir = "build/smoke/im-core-regression",
    [switch]$SkipDockerBuild,
    [switch]$SkipGoTest,
    [switch]$SkipFlutterAnalyze,
    [switch]$SkipFlutterTest,
    [switch]$IncludeAndroid,
    [string]$AndroidDeviceId = "",
    [int]$AndroidUiWaitSeconds = 90
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function New-StepResult {
    param(
        [string]$Name,
        [datetime]$StartedAt,
        [string]$Status,
        [string]$Detail = ""
    )
    return [pscustomobject]@{
        name = $Name
        status = $Status
        started_at = $StartedAt.ToString("o")
        duration_ms = [int]((Get-Date) - $StartedAt).TotalMilliseconds
        detail = $Detail
    }
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Step $Name
    $started = Get-Date
    try {
        $detail = & $Body
        $script:Results += New-StepResult -Name $Name -StartedAt $started -Status "passed" -Detail (($detail | Out-String).Trim())
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = "$detail $($_.ErrorDetails.Message)"
        }
        $script:Results += New-StepResult -Name $Name -StartedAt $started -Status "failed" -Detail $detail
        throw
    }
}

function Wait-BackendHealth {
    param([string]$Url, [int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $health = Invoke-RestMethod -Uri "$($Url.TrimEnd('/'))/health" -TimeoutSec 3
            if ($health.status -eq "ok") {
                return ($health | ConvertTo-Json -Compress)
            }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "Backend health timeout: $Url"
}

function Save-Report {
    param([string]$Status)
    $summary = [pscustomobject]@{
        status = $Status
        base_url = $BaseUrl
        ws_url = $WsUrl
        generated_at = (Get-Date).ToString("o")
        steps = $script:Results
    }
    $reportPath = Join-Path $OutputDir "summary.json"
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
    return $reportPath
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendDir = Join-Path $repoRoot "backend"
$OutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
$script:Results = @()
$PowerShellExe = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if ([string]::IsNullOrWhiteSpace($PowerShellExe)) {
    $PowerShellExe = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source
}
if ([string]::IsNullOrWhiteSpace($PowerShellExe)) {
    throw "Neither pwsh nor powershell was found in PATH."
}

Push-Location $repoRoot
try {
    if (-not $SkipGoTest) {
        Invoke-Step "go test handlers/services" {
            Push-Location $backendDir
            try {
                $out = & go test ./internal/handlers ./internal/services 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
                return ($out | Out-String)
            } finally {
                Pop-Location
            }
        }
    }

    if (-not $SkipFlutterAnalyze) {
        Invoke-Step "flutter analyze IM targets" {
            $out = & flutter analyze `
                lib\core\services\api\chat_service.dart `
                lib\features\chat\pages\search_page.dart `
                lib\features\chat\providers\chat_provider.dart `
                lib\features\chat\providers\message_provider.dart `
                lib\features\chat\widgets\message_bubble.dart `
                test\features\chat\message_reliability_test.dart 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
            return ($out | Out-String)
        }
    }

    if (-not $SkipFlutterTest) {
        Invoke-Step "flutter message reliability tests" {
            $out = & flutter test test\features\chat\message_reliability_test.dart 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
            return ($out | Out-String)
        }
    }

    if (-not $SkipDockerBuild) {
        Invoke-Step "docker rebuild api" {
            $out = & docker compose up -d --build api 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
            return ($out | Select-Object -Last 30 | Out-String)
        }
    }

    Invoke-Step "backend health" {
        Wait-BackendHealth -Url $BaseUrl
    }

    Invoke-Step "chat API smoke" {
        $path = Join-Path $OutputDir "chat-api.json"
        $out = & $PowerShellExe -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\smoke_chat_api.ps1") `
            -BaseUrl $BaseUrl `
            -OutputPath $path 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
        return "output=$path`n$($out | Out-String)"
    }

    Invoke-Step "search pagination highlight smoke" {
        $path = Join-Path $OutputDir "search-pagination-highlight.json"
        $out = & $PowerShellExe -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\smoke_search_pagination_highlight.ps1") `
            -BaseUrl $BaseUrl `
            -OutputPath $path 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
        return "output=$path`n$($out | Out-String)"
    }

    Invoke-Step "unread push consistency stress" {
        $path = Join-Path $OutputDir "unread-push-consistency.json"
        $out = & $PowerShellExe -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\stress_unread_push_consistency.ps1") `
            -BaseUrl $BaseUrl `
            -MessageCount 5 `
            -SendDelayMs 800 `
            -OutputPath $path 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
        return "output=$path`n$($out | Out-String)"
    }

    Invoke-Step "multi-device WS consistency smoke" {
        $path = Join-Path $OutputDir "multidevice-ws-consistency.json"
        $out = & $PowerShellExe -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\smoke_multidevice_ws_consistency.ps1") `
            -BaseUrl $BaseUrl `
            -WsUrl $WsUrl `
            -OutputPath $path 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
        return "output=$path`n$($out | Out-String)"
    }

    if ($IncludeAndroid) {
        Invoke-Step "Android chat smoke" {
            $androidOut = Join-Path $OutputDir "android-chat"
            $args = @(
                "-ExecutionPolicy", "Bypass",
                "-File", (Join-Path $repoRoot "scripts\smoke_android_chat.ps1"),
                "-ApiBaseUrl", $BaseUrl,
                "-ServerUrl", "http://10.0.2.2:8080",
                "-WsUrl", "ws://10.0.2.2:8080/api/v1/ws",
                "-HostHealthUrl", "$($BaseUrl.TrimEnd('/'))/health",
                "-OutputDir", $androidOut,
                "-SkipPubGet",
                "-SkipAnalyze",
                "-SkipBuild",
                "-KeepAppData",
                "-UiWaitSeconds", $AndroidUiWaitSeconds,
                "-LaunchWaitSeconds", $AndroidUiWaitSeconds
            )
            if (-not [string]::IsNullOrWhiteSpace($AndroidDeviceId)) {
                $args += @("-DeviceId", $AndroidDeviceId)
            }
            $out = & $PowerShellExe @args 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
            return "output=$androidOut`n$($out | Out-String)"
        }
    }

    $reportPath = Save-Report -Status "passed"
    Write-Host ""
    Write-Host "IM core regression passed: $reportPath" -ForegroundColor Green
} catch {
    $reportPath = Save-Report -Status "failed"
    Write-Host ""
    Write-Host "IM core regression failed: $reportPath" -ForegroundColor Red
    throw
} finally {
    Pop-Location
}
