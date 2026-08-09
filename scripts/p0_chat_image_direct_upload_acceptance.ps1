param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AdminUsername = "admin",
    [string]$AdminPassword = "123456",
    [string]$AliceUsername = "smoke_alice",
    [string]$Password = "Smoke123",
    [string]$FixturePath = "artifacts/real-device-qa/aws-two-device-20260727/fixtures/aws-image-huawei-to-samsung.png",
    [string]$OutputDir = "artifacts/p0-chat-image-direct-upload-20260727"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")
$OutputDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDir))
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [string]$Platform = "android"
    )
    $headers = @{ "X-Client-Platform" = $Platform }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $parameters = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = $headers
        SkipHttpErrorCheck = $true
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $parameters.ContentType = "application/json; charset=utf-8"
        $parameters.Body = $Body | ConvertTo-Json -Depth 30 -Compress
    }
    $response = Invoke-WebRequest @parameters
    $json = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ Status = [int]$response.StatusCode; Json = $json }
}

function Assert-Code {
    param([object]$Response, [int]$Expected, [string]$Label)
    if ($null -eq $Response.Json -or [int]$Response.Json.code -ne $Expected) {
        throw "$Label expected code=${Expected}: $($Response.Json | ConvertTo-Json -Depth 20 -Compress)"
    }
}

function Update-DirectSettings {
    param(
        [string]$Token,
        [bool]$Enabled,
        [string[]]$Platforms,
        [int]$RolloutPercent,
        [int]$MaxConcurrency = 3
    )
    $response = Invoke-Api -Method PUT -Path "/api/v1/admin/settings" -Token $Token -Body @{
        chat_image_direct_upload_enabled = $Enabled
        chat_image_direct_upload_platforms = $Platforms
        chat_image_direct_upload_rollout_percent = $RolloutPercent
        chat_image_direct_upload_max_concurrency = $MaxConcurrency
    }
    Assert-Code -Response $response -Expected 0 -Label "update direct-upload settings"
}

$adminLogin = Invoke-Api -Method POST -Path "/api/v1/admin/login" -Body @{
    username = $AdminUsername
    password = $AdminPassword
}
Assert-Code -Response $adminLogin -Expected 0 -Label "admin login"
$adminToken = [string]$adminLogin.Json.data.token

$userLogin = Invoke-Api -Method POST -Path "/api/v1/auth/login" -Body @{
    username = $AliceUsername
    password = $Password
    device_id = "p0-direct-config-acceptance"
    device_type = "android"
    device_name = "P0 Direct Config Acceptance"
}
Assert-Code -Response $userLogin -Expected 0 -Label "user login"
$userToken = [string]$userLogin.Json.data.token

$settingsResponse = Invoke-Api -Method GET -Path "/api/v1/admin/settings" -Token $adminToken
Assert-Code -Response $settingsResponse -Expected 0 -Label "read original settings"
$original = $settingsResponse.Json.data
$originalSettings = @{
    enabled = $original.chat_image_direct_upload_enabled -eq $true
    platforms = @($original.chat_image_direct_upload_platforms)
    rollout_percent = [int]$original.chat_image_direct_upload_rollout_percent
    max_concurrency = [int]$original.chat_image_direct_upload_max_concurrency
}

$fixture = (Resolve-Path -LiteralPath $FixturePath).Path
$bytes = [System.IO.File]::ReadAllBytes($fixture)
$checksum = [Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData($bytes)
).ToLowerInvariant()

function New-InitBody {
    return @{
        client_request_id = [guid]::NewGuid().ToString()
        category = "image"
        file_name = "p0-config-gate.png"
        size = $bytes.Length
        mime_type = "image/png"
        checksum_sha256 = $checksum
    }
}

$checks = [ordered]@{}
$lifecycleOutput = Join-Path $OutputDir "s3-lifecycle.json"
try {
    Update-DirectSettings -Token $adminToken -Enabled $false -Platforms @("android", "ios") -RolloutPercent 0
    $disabled = Invoke-Api -Method POST -Path "/api/v1/media/uploads/init" -Token $userToken -Body (New-InitBody)
    Assert-Code -Response $disabled -Expected 4601 -Label "disabled gate"
    $checks.disabled_code_4601 = $true

    Update-DirectSettings -Token $adminToken -Enabled $true -Platforms @("ios") -RolloutPercent 100
    $platform = Invoke-Api -Method POST -Path "/api/v1/media/uploads/init" -Token $userToken -Body (New-InitBody)
    Assert-Code -Response $platform -Expected 4602 -Label "platform gate"
    $checks.platform_code_4602 = $true

    Update-DirectSettings -Token $adminToken -Enabled $true -Platforms @("android") -RolloutPercent 0
    $rollout = Invoke-Api -Method POST -Path "/api/v1/media/uploads/init" -Token $userToken -Body (New-InitBody)
    Assert-Code -Response $rollout -Expected 4603 -Label "rollout gate"
    $checks.rollout_code_4603 = $true

    Update-DirectSettings -Token $adminToken -Enabled $true -Platforms @("android", "ios") -RolloutPercent 100
    & (Join-Path $PSScriptRoot "p0_s3_acceptance.ps1") `
        -BaseUrl $BaseUrl `
        -AliceUsername $AliceUsername `
        -Password $Password `
        -FixturePath $fixture `
        -OutputPath $lifecycleOutput | Out-Null
    $lifecycle = Get-Content -LiteralPath $lifecycleOutput -Raw | ConvertFrom-Json
    if ($lifecycle.passed -ne $true) {
        throw "S3 lifecycle acceptance failed"
    }
    $checks.s3_lifecycle_passed = $true

    $publicSettings = Invoke-Api -Method GET -Path "/api/v1/app/settings"
    Assert-Code -Response $publicSettings -Expected 0 -Label "public app settings"
    $publicDirect = $publicSettings.Json.data.chat_image_direct_upload
    $checks.app_settings_exposed = (
        $publicDirect.enabled -eq $true -and
        [int]$publicDirect.rollout_percent -eq 100 -and
        [int]$publicDirect.max_concurrency -eq 3
    )

    $storageStatus = Invoke-Api -Method GET -Path "/api/v1/admin/storage/status" -Token $adminToken
    Assert-Code -Response $storageStatus -Expected 0 -Label "storage metrics"
    $stageNames = @($storageStatus.Json.data.upload_stages.stages | ForEach-Object { $_.stage })
    $requiredStages = @("direct_init_db", "direct_complete_db", "s3_presign_put", "s3_head_object", "s3_range_get")
    $checks.stage_metrics_exposed = (@($requiredStages | Where-Object { $_ -notin $stageNames }).Count -eq 0)

    Update-DirectSettings -Token $adminToken -Enabled $false -Platforms @("android", "ios") -RolloutPercent 0
    $rateLimited = $false
    for ($index = 0; $index -lt 40; $index++) {
        $probe = Invoke-Api -Method POST -Path "/api/v1/media/uploads/init" -Token $userToken -Body (New-InitBody)
        if ([int]$probe.Json.code -eq 4605 -and $probe.Status -eq 429) {
            $rateLimited = $true
            break
        }
    }
    $checks.rate_limit_code_4605 = $rateLimited
} finally {
    Update-DirectSettings `
        -Token $adminToken `
        -Enabled ([bool]$originalSettings.enabled) `
        -Platforms ([string[]]$originalSettings.platforms) `
        -RolloutPercent ([int]$originalSettings.rollout_percent) `
        -MaxConcurrency ([int]$originalSettings.max_concurrency)
}

$restored = Invoke-Api -Method GET -Path "/api/v1/admin/settings" -Token $adminToken
Assert-Code -Response $restored -Expected 0 -Label "verify restored settings"
$restoredData = $restored.Json.data
$checks.settings_restored = (
    ($restoredData.chat_image_direct_upload_enabled -eq $originalSettings.enabled) -and
    ([int]$restoredData.chat_image_direct_upload_rollout_percent -eq $originalSettings.rollout_percent) -and
    ([int]$restoredData.chat_image_direct_upload_max_concurrency -eq $originalSettings.max_concurrency)
)

$proxyResponse = Invoke-WebRequest `
    -Uri "$BaseUrl/api/v1/upload/image" `
    -Method POST `
    -Headers @{
        Authorization = "Bearer $userToken"
        "X-Client-Platform" = "android"
        "X-Upload-Request-ID" = [guid]::NewGuid().ToString()
    } `
    -Form @{ file = Get-Item -LiteralPath $fixture } `
    -SkipHttpErrorCheck `
    -TimeoutSec 60
$proxyJson = $proxyResponse.Content | ConvertFrom-Json
$checks.proxy_upload_after_rollback = (
    [int]$proxyResponse.StatusCode -eq 200 -and
    [int]$proxyJson.code -eq 0 -and
    -not [string]::IsNullOrWhiteSpace([string]$proxyJson.data.url)
)

$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object Key)
$summary = [ordered]@{
    passed = $failed.Count -eq 0
    failed_checks = $failed
    original_settings = $originalSettings
    restored_settings = @{
        enabled = $restoredData.chat_image_direct_upload_enabled
        platforms = @($restoredData.chat_image_direct_upload_platforms)
        rollout_percent = $restoredData.chat_image_direct_upload_rollout_percent
        max_concurrency = $restoredData.chat_image_direct_upload_max_concurrency
    }
    checks = $checks
    lifecycle_artifact = $lifecycleOutput
}
$summaryPath = Join-Path $OutputDir "acceptance-summary.json"
$summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 30
if ($failed.Count -gt 0) {
    throw "P0 chat image direct upload acceptance failed: $($failed -join ', ')"
}
