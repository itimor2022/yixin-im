param(
    [Parameter(Mandatory = $true)]
    [string]$UploadID,
    [Parameter(Mandatory = $true)]
    [string]$DeviceSerial,
    [int]$MinimumParts = 2,
    [int]$TimeoutSeconds = 120,
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Username = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$PackageName = "com.genericim.ma100",
    [string]$AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$OutputPath = "artifacts/p1-s3-acceptance-20260727/resume-interrupted.json"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")

if ($MinimumParts -lt 1) {
    throw "MinimumParts must be at least 1"
}
if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw "ADB was not found at $AdbPath"
}

$loginBody = @{
    username = $Username
    password = $Password
    device_id = "p1-resume-interrupt-$Username"
    device_type = "android"
    device_name = "P1 Resume Interrupt"
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

$headers = @{
    "X-Client-Platform" = "android"
    Authorization = "Bearer $($login.data.token)"
}
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    $status = Invoke-RestMethod `
        -Method Get `
        -Uri "$BaseUrl/api/v1/media/uploads/$UploadID" `
        -Headers $headers `
        -TimeoutSec 30
    if ([int]$status.code -ne 0 -or $null -eq $status.data) {
        throw "Status query failed: $($status | ConvertTo-Json -Depth 10 -Compress)"
    }

    $parts = @($status.data.uploaded_parts | Where-Object { $null -ne $_ })
    if ($parts.Count -ge $MinimumParts) {
        & $AdbPath -s $DeviceSerial shell svc wifi disable
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to disable Wi-Fi on $DeviceSerial"
        }
        & $AdbPath -s $DeviceSerial shell am force-stop $PackageName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to force-stop $PackageName on $DeviceSerial"
        }

        $result = [ordered]@{
            interrupted_at = (Get-Date).ToString("o")
            device_serial = $DeviceSerial
            upload_id = $UploadID
            media_id = [string]$status.data.media_id
            status = [string]$status.data.status
            mode = [string]$status.data.mode
            part_count = [int]$status.data.part_count
            uploaded_part_count = $parts.Count
            uploaded_bytes = [int64](($parts | Measure-Object -Property size -Sum).Sum)
            uploaded_parts = $parts
            wifi_disabled = $true
            app_force_stopped = $true
        }
        $outputFullPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
        $json = $result | ConvertTo-Json -Depth 20
        $json | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
        $json
        exit 0
    }

    if ([string]$status.data.status -ne "uploading") {
        throw "Upload reached status '$($status.data.status)' before $MinimumParts parts were observed"
    }
    Start-Sleep -Milliseconds 300
}

throw "Timed out waiting for $MinimumParts uploaded parts on $UploadID"
