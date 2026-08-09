param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Offline", "NetworkSwitch", "Background", "KillProcess", "WeakNetwork")]
    [string]$Scenario,
    [Parameter(Mandatory = $true)]
    [string]$UploadID,
    [string]$DeviceSerial = "R5CT928J30B",
    [int]$MinimumParts = 2,
    [int]$DisruptionSeconds = 15,
    [int]$CompletionTimeoutSeconds = 2100,
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Username = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$PackageName = "com.genericim.app",
    [string]$ActivityName = "com.genericim.app/.MainActivity",
    [int]$ResumeChatTapX = 400,
    [int]$ResumeChatTapY = 600,
    [string]$AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$MySqlContainer = "genericim-mysql",
    [string]$OutputDirectory = "artifacts/p1-s3-acceptance-20260727/resilience"
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

$outputFullDirectory = [IO.Path]::GetFullPath(
    (Join-Path (Get-Location) $OutputDirectory)
)
New-Item -ItemType Directory -Force -Path $outputFullDirectory | Out-Null
$scenarioSlug = $Scenario.ToLowerInvariant()
$startedAt = Get-Date
$transientStatusFailures = [Collections.Generic.List[object]]::new()

function Invoke-Adb {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    $output = & $AdbPath -s $DeviceSerial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ADB failed: adb -s $DeviceSerial $($Arguments -join ' ')`n$output"
    }
    return @($output)
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int]$TimeoutSeconds = 60
    )
    $headers = @{ "X-Client-Platform" = "android" }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $params = @{
        Method = $Method
        Uri = "$BaseUrl$Path"
        Headers = $headers
        TimeoutSec = $TimeoutSeconds
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = $Body | ConvertTo-Json -Depth 10 -Compress
    }
    $response = Invoke-RestMethod @params
    if ([int]$response.code -ne 0) {
        throw "$Method $Path failed: $($response | ConvertTo-Json -Depth 10 -Compress)"
    }
    return $response.data
}

function Get-UploadStatus {
    param(
        [string]$Token,
        [int]$MaxAttempts = 5,
        [int]$RequestTimeoutSeconds = 60,
        [switch]$AllowUnavailable
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $data = Invoke-Api -Method Get `
                -Path "/api/v1/media/uploads/$UploadID" -Token $Token `
                -TimeoutSeconds $RequestTimeoutSeconds
            $parts = @($data.uploaded_parts | Where-Object { $null -ne $_ })
            return [pscustomobject]@{
                available = $true
                observed_at = (Get-Date).ToString("o")
                upload_id = $UploadID
                media_id = [string]$data.media_id
                client_request_id = [string]$data.client_request_id
                status = [string]$data.status
                mode = [string]$data.mode
                part_size = [int64]$data.part_size
                part_count = [int]$data.part_count
                uploaded_part_count = $parts.Count
                uploaded_bytes = [int64](
                    ($parts | Measure-Object -Property size -Sum).Sum
                )
                uploaded_parts = $parts
            }
        } catch {
            $failure = [pscustomobject]@{
                observed_at = (Get-Date).ToString("o")
                attempt = $attempt
                max_attempts = $MaxAttempts
                error = $_.Exception.Message
            }
            $transientStatusFailures.Add($failure)
            if ($attempt -lt $MaxAttempts) {
                $delaySeconds = [Math]::Min(
                    [Math]::Pow(2, $attempt - 1),
                    8
                )
                Write-Warning (
                    "Upload status temporarily unavailable " +
                    "(attempt $attempt/$MaxAttempts); retrying in " +
                    "$delaySeconds second(s): $($_.Exception.Message)"
                )
                Start-Sleep -Seconds $delaySeconds
                continue
            }
            if ($AllowUnavailable) {
                return [pscustomobject]@{
                    available = $false
                    observed_at = (Get-Date).ToString("o")
                    upload_id = $UploadID
                    error = $_.Exception.Message
                    attempts = $MaxAttempts
                }
            }
            throw
        }
    }
}

function Wait-ForParts {
    param([string]$Token)
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        $status = Get-UploadStatus -Token $Token
        if ($status.uploaded_part_count -ge $MinimumParts) {
            return $status
        }
        if ($status.status -ne "uploading") {
            throw "Upload reached '$($status.status)' before $MinimumParts parts were observed"
        }
        Start-Sleep -Milliseconds 300
    }
    throw "Timed out waiting for $MinimumParts uploaded parts on $UploadID"
}

function Test-PartsPreserved {
    param([object]$Before, [object]$After)
    $afterByNumber = @{}
    foreach ($part in @($After.uploaded_parts)) {
        $afterByNumber[[int]$part.part_number] = $part
    }
    foreach ($part in @($Before.uploaded_parts)) {
        $number = [int]$part.part_number
        if (-not $afterByNumber.ContainsKey($number)) { return $false }
        $afterPart = $afterByNumber[$number]
        if ([string]$afterPart.etag -ne [string]$part.etag) { return $false }
        if ([int64]$afterPart.size -ne [int64]$part.size) { return $false }
    }
    return $true
}

function Get-MediaDatabaseState {
    $query = @"
SELECT status FROM media_objects WHERE media_id='$UploadID' LIMIT 1;
SELECT CONCAT(media_id, CHAR(9), status, CHAR(9), size_bytes)
FROM media_objects
WHERE client_request_id='derived-thumbnail:$UploadID'
ORDER BY id DESC LIMIT 1;
"@
    $rows = @(
        docker exec $MySqlContainer mysql -ugenericim -pgenericim `
            --batch --raw --silent --skip-column-names genericim -e $query 2>$null
    )
    $sourceStatus = if ($rows.Count -ge 1) { [string]$rows[0] } else { "" }
    $derivative = if ($rows.Count -ge 2) { [string]$rows[1] } else { "" }
    $fields = @($derivative -split "`t")
    return [pscustomobject]@{
        source_status = $sourceStatus.Trim()
        thumbnail_media_id = if ($fields.Count -ge 1) { $fields[0].Trim() } else { "" }
        thumbnail_status = if ($fields.Count -ge 2) { $fields[1].Trim() } else { "" }
        thumbnail_size = if ($fields.Count -ge 3) { [int64]$fields[2] } else { 0 }
    }
}

function Restore-Network {
    param([string]$OriginalWifi, [string]$OriginalMobileData)
    if ($Scenario -eq "WeakNetwork") {
        try { Invoke-Adb emu network speed full | Out-Null } catch {}
        try { Invoke-Adb emu network delay none | Out-Null } catch {}
        return
    }
    if ($OriginalMobileData -eq "1") {
        Invoke-Adb shell svc data enable | Out-Null
    } else {
        Invoke-Adb shell svc data disable | Out-Null
    }
    if ($OriginalWifi -eq "1") {
        Invoke-Adb shell svc wifi enable | Out-Null
    } else {
        Invoke-Adb shell svc wifi disable | Out-Null
    }
}

$login = Invoke-Api -Method Post -Path "/api/v1/auth/login" -Body @{
    username = $Username
    password = $Password
    device_id = "p1-resilience-background-$Username"
    device_type = "android"
    device_name = "P1 $Scenario Acceptance"
}
$token = [string]$login.token
if (-not $token) { throw "Login did not return a token" }

$deviceState = @(Invoke-Adb get-state)
if (($deviceState -join "").Trim() -ne "device") {
    throw "Device $DeviceSerial is not ready"
}

$originalWifi = ((Invoke-Adb shell settings get global wifi_on) -join "").Trim()
$originalMobileData = (
    (Invoke-Adb shell settings get global mobile_data) -join ""
).Trim()
$before = $null
$during = $null
$final = $null
$database = $null
$disruptionConnectivity = ""

try {
    Invoke-Adb logcat -c | Out-Null
    $before = Wait-ForParts -Token $token

    switch ($Scenario) {
        "Offline" {
            Invoke-Adb shell svc data disable | Out-Null
            Invoke-Adb shell svc wifi disable | Out-Null
        }
        "NetworkSwitch" {
            Invoke-Adb shell svc data enable | Out-Null
            Invoke-Adb shell svc wifi disable | Out-Null
        }
        "Background" {
            Invoke-Adb shell input keyevent KEYCODE_HOME | Out-Null
        }
        "KillProcess" {
            Invoke-Adb shell am force-stop $PackageName | Out-Null
        }
        "WeakNetwork" {
            Invoke-Adb emu network speed edge | Out-Null
            Invoke-Adb emu network delay gprs | Out-Null
        }
    }

    $disruptionConnectivity = (
        Invoke-Adb shell dumpsys connectivity
    ) -join "`n"
    Start-Sleep -Seconds $DisruptionSeconds
    $during = Get-UploadStatus -Token $token -MaxAttempts 3 `
        -RequestTimeoutSeconds 15 -AllowUnavailable
    $partsPreservedDuringDisruption = if ($during.available) {
        Test-PartsPreserved -Before $before -After $during
    } else {
        $null
    }

    Restore-Network -OriginalWifi $originalWifi -OriginalMobileData $originalMobileData
    Invoke-Adb shell am start -n $ActivityName | Out-Null
    if ($Scenario -eq "KillProcess") {
        Start-Sleep -Seconds 4
        Invoke-Adb shell input tap $ResumeChatTapX $ResumeChatTapY | Out-Null
    }

    $deadline = (Get-Date).AddSeconds($CompletionTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $final = Get-UploadStatus -Token $token
        $database = Get-MediaDatabaseState
        if ($final.status -eq "bound" -and
            $database.source_status -eq "bound" -and
            $database.thumbnail_status -eq "bound" -and
            $database.thumbnail_media_id) {
            break
        }
        Start-Sleep -Seconds 2
    }
    $partsPreserved = if ($null -ne $partsPreservedDuringDisruption) {
        $partsPreservedDuringDisruption
    } else {
        $final.upload_id -eq $UploadID -and $final.status -eq "bound"
    }
    $partsPreservationEvidence = if ($null -ne $partsPreservedDuringDisruption) {
        "during_disruption_part_list"
    } else {
        "same_upload_completed_after_status_unavailable"
    }

    $remoteScreenshot = "/sdcard/p1-$scenarioSlug-final.png"
    $screenshotArgs = @("shell", "screencap", "-p", $remoteScreenshot)
    Invoke-Adb @screenshotArgs | Out-Null
    Invoke-Adb pull $remoteScreenshot (
        Join-Path $outputFullDirectory "$scenarioSlug-final.png"
    ) | Out-Null
    $logcatArgs = @("logcat", "-d", "-v", "threadtime")
    $logcat = (Invoke-Adb @logcatArgs) -join "`n"
    $logcatPath = Join-Path $outputFullDirectory "$scenarioSlug-logcat.txt"
    $logcat | Set-Content -LiteralPath $logcatPath -Encoding UTF8

    $resumeLogged = (
        $logcat -match [regex]::Escape("Resume video") -and
        $logcat -match [regex]::Escape($UploadID)
    )
    $skipLogged = (
        $logcat -match [regex]::Escape("skip completed part upload=$UploadID")
    )
    $requiresExplicitResumeLog = $Scenario -in @(
        "Offline", "KillProcess", "WeakNetwork"
    )
    $passed = (
        $partsPreserved -and
        $final.upload_id -eq $UploadID -and
        $final.status -eq "bound" -and
        $database.source_status -eq "bound" -and
        $database.thumbnail_status -eq "bound" -and
        [int64]$database.thumbnail_size -gt 0 -and
        (-not $requiresExplicitResumeLog -or ($resumeLogged -and $skipLogged))
    )

    $result = [ordered]@{
        passed = $passed
        scenario = $Scenario
        started_at = $startedAt.ToString("o")
        completed_at = (Get-Date).ToString("o")
        device_serial = $DeviceSerial
        upload_id = $UploadID
        disruption_seconds = $DisruptionSeconds
        original_network = @{
            wifi_on = $originalWifi
            mobile_data = $originalMobileData
        }
        checks = @{
            same_upload_id = ($final.upload_id -eq $UploadID)
            completed_parts_preserved = $partsPreserved
            parts_preservation_evidence = $partsPreservationEvidence
            disruption_status_available = [bool]$during.available
            source_bound = ($database.source_status -eq "bound")
            thumbnail_bound = ($database.thumbnail_status -eq "bound")
            thumbnail_nonempty = ([int64]$database.thumbnail_size -gt 0)
            resume_logged = $resumeLogged
            completed_parts_skipped = $skipLogged
        }
        before = $before
        during = $during
        final = $final
        database = $database
        transient_status_failures = @($transientStatusFailures)
        disruption_active_default_network = [regex]::Match(
            $disruptionConnectivity,
            "Active default network:[^\r\n]*"
        ).Value
    }
    $json = $result | ConvertTo-Json -Depth 30
    $jsonPath = Join-Path $outputFullDirectory "$scenarioSlug.json"
    $json | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $json
    if (-not $passed) {
        throw "$Scenario resilience acceptance failed; see $jsonPath"
    }
} finally {
    Restore-Network -OriginalWifi $originalWifi -OriginalMobileData $originalMobileData
}
