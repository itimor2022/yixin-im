param(
    [string]$Backend = "https://api.example.com",
    [string]$QuickRegisterArtifact = "artifacts\real-device-qa\qa400-counterpart-secret.json",
    [string]$OutputPath = "artifacts\real-device-qa\dual-device-counterpart-login.json",
    [string]$Username = "qa_dual_8ad75a",
    [string]$Password = "DualTest123!"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $QuickRegisterArtifact))
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json
$token = [string]$source.data.token
if ([string]::IsNullOrWhiteSpace($token)) { throw "Counterpart token is missing." }

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(20)
$client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $token)

try {
    $payload = @{ username = $Username; password = $Password } | ConvertTo-Json -Compress
    $content = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, "application/json")
    $response = $client.PutAsync("$($Backend.TrimEnd('/'))/api/v1/auth/initialize-credentials", $content).GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $initialize = if ([string]::IsNullOrWhiteSpace($body)) { $null } else { $body | ConvertFrom-Json }

    if (-not $response.IsSuccessStatusCode -and [int]$response.StatusCode -ne 409) {
        throw "Initialize credentials failed: HTTP $([int]$response.StatusCode) $body"
    }

    $client.DefaultRequestHeaders.Authorization = $null
    $loginPayload = @{
        username = $Username
        password = $Password
        device_id = "qa-dual-api-verify"
        device_type = "android"
        device_name = "QA Dual Verify"
    } | ConvertTo-Json -Compress
    $loginContent = [System.Net.Http.StringContent]::new($loginPayload, [System.Text.Encoding]::UTF8, "application/json")
    $loginResponse = $client.PostAsync("$($Backend.TrimEnd('/'))/api/v1/auth/login", $loginContent).GetAwaiter().GetResult()
    $loginBody = $loginResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $loginResponse.IsSuccessStatusCode) {
        throw "Counterpart login verification failed: HTTP $([int]$loginResponse.StatusCode) $loginBody"
    }
    $login = $loginBody | ConvertFrom-Json
    if ([int]$login.code -ne 0 -or [string]::IsNullOrWhiteSpace([string]$login.data.token)) {
        throw "Counterpart login verification did not return a usable token: $loginBody"
    }

    $output = [ordered]@{
        username = $Username
        password = $Password
        uuid = [string]$login.data.user.uuid
        nickname = [string]$login.data.user.nickname
        token = [string]$login.data.token
        initialized_http = [int]$response.StatusCode
        verified_http = [int]$loginResponse.StatusCode
        verified_at = (Get-Date).ToString("o")
    }
    $fullOutput = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullOutput) | Out-Null
    $output | ConvertTo-Json | Set-Content -LiteralPath $fullOutput -Encoding utf8
    Write-Host "Counterpart credentials are initialized and API login is verified."
    Write-Host "Username: $Username"
    Write-Host "UUID: $($output.uuid)"
    Write-Host "Artifact: $fullOutput"
} finally {
    $client.Dispose()
}
