param(
    [Parameter(Mandatory = $true)]
    [string]$UploadID,
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Username = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")

$loginBody = @{
    username = $Username
    password = $Password
    device_id = "p1-resume-status-$Username"
    device_type = "android"
    device_name = "P1 Resume Status"
} | ConvertTo-Json -Compress

$login = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/api/v1/auth/login" `
    -ContentType "application/json; charset=utf-8" `
    -Headers @{ "X-Client-Platform" = "android" } `
    -Body $loginBody `
    -TimeoutSec 30

if ([int]$login.code -ne 0 -or -not $login.data.token) {
    throw "Login failed: $($login | ConvertTo-Json -Depth 10 -Compress)"
}

$status = Invoke-RestMethod `
    -Method Get `
    -Uri "$BaseUrl/api/v1/media/uploads/$UploadID" `
    -Headers @{
        "X-Client-Platform" = "android"
        Authorization = "Bearer $($login.data.token)"
    } `
    -TimeoutSec 60

if ([int]$status.code -ne 0 -or $null -eq $status.data) {
    throw "Status query failed: $($status | ConvertTo-Json -Depth 10 -Compress)"
}

$parts = @($status.data.uploaded_parts | Where-Object { $null -ne $_ })
$result = [ordered]@{
    queried_at = (Get-Date).ToString("o")
    upload_id = $UploadID
    media_id = [string]$status.data.media_id
    client_request_id = [string]$status.data.client_request_id
    status = [string]$status.data.status
    mode = [string]$status.data.mode
    part_size = [int64]$status.data.part_size
    part_count = [int]$status.data.part_count
    uploaded_part_count = $parts.Count
    uploaded_bytes = [int64](($parts | Measure-Object -Property size -Sum).Sum)
    uploaded_parts = $parts
}

$json = $result | ConvertTo-Json -Depth 20
if ($OutputPath) {
    $outputFullPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
    $json | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
}
$json
