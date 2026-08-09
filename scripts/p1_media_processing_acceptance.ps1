param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$ImagePath = "artifacts/p1-s3-acceptance-20260727/real-device/samsung-resume-complete.png",
    [string]$HeicUrl = "https://raw.githubusercontent.com/strukturag/libheif/master/examples/example.heic",
    [string]$OutputPath = "artifacts/p1-s3-acceptance-20260727/media-processing-acceptance.json"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "genericim-p1-media-$([guid]::NewGuid())"
$heicPath = Join-Path $tempRoot "example.heic"
$webmPath = Join-Path $tempRoot "transcode-source.webm"
$containerWebmPath = "/tmp/genericim-p1-transcode.webm"
$originalDirectUploadEnabled = $null
$originalDirectUploadRollout = $null

function Invoke-LocalMySql {
    param([string]$Sql)
    $arguments = @(
        "exec", "genericim-mysql",
        "mysql", "-ugenericim", "-pgenericim", "genericim",
        "--batch", "--skip-column-names",
        "--execute=$Sql"
    )
    $output = & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "local MySQL command failed"
    }
    if ($null -eq $output) { return "" }
    return ([string]$output).Trim()
}

function Set-LocalDirectUploadGate {
    param([string]$Enabled, [int]$RolloutPercent)
    if ($Enabled -notin @("true", "false")) {
        throw "invalid direct-upload enabled value"
    }
    if ($RolloutPercent -lt 0 -or $RolloutPercent -gt 100) {
        throw "invalid direct-upload rollout value"
    }
    [void](Invoke-LocalMySql -Sql (
        "UPDATE system_settings SET value='$Enabled' " +
        "WHERE system_settings.key='chat_image_direct_upload_enabled';"
    ))
    [void](Invoke-LocalMySql -Sql (
        "UPDATE system_settings SET value='$RolloutPercent' " +
        "WHERE system_settings.key='chat_image_direct_upload_rollout_percent';"
    ))
}

function Invoke-JsonApi {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )
    $headers = @{ "X-Client-Platform" = "android" }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $parameters = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = $headers
        SkipHttpErrorCheck = $true
        TimeoutSec = 1800
    }
    if ($null -ne $Body) {
        $parameters.ContentType = "application/json; charset=utf-8"
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    $response = Invoke-WebRequest @parameters
    if ([int]$response.StatusCode -ne 200) {
        throw "$Method $Path returned HTTP $($response.StatusCode): $($response.Content)"
    }
    $json = $response.Content | ConvertFrom-Json
    if ([int]$json.code -ne 0) {
        throw "$Method $Path failed: $($response.Content)"
    }
    return $json.data
}

function Login-TestUser {
    param([string]$Username)
    Invoke-JsonApi -Method POST -Path "/api/v1/auth/login" -Body @{
        username = $Username
        password = $Password
        device_id = "p1-media-processing-$Username"
        device_type = "android"
        device_name = "P1 Media Processing Acceptance"
    }
}

function Put-File {
    param([string]$Url, [object]$SignedHeaders, [string]$Path)
    $client = [Net.Http.HttpClient]::new()
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Put, $Url)
        $stream = [IO.File]::OpenRead($Path)
        try {
            $request.Content = [Net.Http.StreamContent]::new($stream)
            foreach ($property in $SignedHeaders.PSObject.Properties) {
                $name = [string]$property.Name
                $value = [string]$property.Value
                if (-not $request.Headers.TryAddWithoutValidation($name, $value)) {
                    [void]$request.Content.Headers.TryAddWithoutValidation($name, $value)
                }
            }
            $response = $client.Send($request)
            if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
                throw "S3 PUT returned HTTP $([int]$response.StatusCode)"
            }
        } finally {
            $stream.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function Get-Range {
    param([string]$Url)
    $client = [Net.Http.HttpClient]::new()
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Url)
        $request.Headers.Range = [Net.Http.Headers.RangeHeaderValue]::new(0, 23)
        $response = $client.Send($request)
        [pscustomobject]@{
            Status = [int]$response.StatusCode
            ContentRange = [string]$response.Content.Headers.ContentRange
            Bytes = [byte[]]$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        }
    } finally {
        $client.Dispose()
    }
}

function Upload-And-Process {
    param(
        [string]$Token,
        [string]$Category,
        [string]$FilePath,
        [string]$FileName,
        [string]$MimeType
    )
    $file = Get-Item -LiteralPath $FilePath
    $hash = Get-FileHash -LiteralPath $FilePath -Algorithm SHA256
    $session = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/init" -Token $Token -Body @{
        client_request_id = [guid]::NewGuid().ToString()
        category = $Category
        file_name = $FileName
        size = [int64]$file.Length
        mime_type = $MimeType
        checksum_sha256 = $hash.Hash.ToLowerInvariant()
    }
    if ([string]$session.mode -ne "single") {
        throw "$FileName unexpectedly selected upload mode $($session.mode)"
    }
    Put-File -Url ([string]$session.put_url) -SignedHeaders $session.headers -Path $FilePath
    $completed = Invoke-JsonApi -Method POST `
        -Path "/api/v1/media/uploads/$($session.media_id)/complete" `
        -Token $Token `
        -Body @{}
    [pscustomobject]@{
        UploadId = [string]$session.media_id
        InputSize = [int64]$file.Length
        InputSha256 = $hash.Hash.ToLowerInvariant()
        Completed = $completed
    }
}

function Bind-Media {
    param(
        [string]$Token,
        [string]$ChatId,
        [int]$Type,
        [object]$Upload
    )
    $media = @{
        media_id = [string]$Upload.Completed.media_id
        url = "https://attacker.invalid/untrusted-media"
        size = [int64]$Upload.Completed.size
        mime_type = [string]$Upload.Completed.mime_type
    }
    if ($Upload.Completed.thumbnail_media_id) {
        $media.thumbnail_media_id = [string]$Upload.Completed.thumbnail_media_id
        $media.thumbnail = "https://attacker.invalid/untrusted-thumbnail"
    }
    foreach ($field in @("width", "height", "duration")) {
        if ($Upload.Completed.$field) {
            $media[$field] = [int]$Upload.Completed.$field
        }
    }
    $messageId = [guid]::NewGuid().ToString()
    [void](Invoke-JsonApi -Method POST -Path "/api/v1/message/send" -Token $Token -Body @{
        chat_id = $ChatId
        type = $Type
        msg_id = $messageId
        content = @{ media = $media }
    })
    return $messageId
}

function Get-MemberMediaRange {
    param([string]$Token, [string]$MediaId)
    $access = Invoke-JsonApi -Method GET -Path "/api/v1/media/$MediaId/access-url" -Token $Token
    Get-Range -Url ([string]$access.url)
}

function Test-JpegHeader {
    param([byte[]]$Bytes)
    return $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xFF -and
        $Bytes[1] -eq 0xD8 -and
        $Bytes[2] -eq 0xFF
}

function Test-PngHeader {
    param([byte[]]$Bytes)
    return $Bytes.Length -ge 8 -and
        $Bytes[0] -eq 0x89 -and
        $Bytes[1] -eq 0x50 -and
        $Bytes[2] -eq 0x4E -and
        $Bytes[3] -eq 0x47
}

function Test-Mp4Header {
    param([byte[]]$Bytes)
    return $Bytes.Length -ge 8 -and
        [Text.Encoding]::ASCII.GetString($Bytes, 4, 4) -eq "ftyp"
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $originalDirectUploadEnabled = Invoke-LocalMySql -Sql (
        "SELECT value FROM system_settings " +
        "WHERE system_settings.key='chat_image_direct_upload_enabled' LIMIT 1;"
    )
    $originalDirectUploadRollout = Invoke-LocalMySql -Sql (
        "SELECT value FROM system_settings " +
        "WHERE system_settings.key='chat_image_direct_upload_rollout_percent' LIMIT 1;"
    )
    Set-LocalDirectUploadGate -Enabled "true" -RolloutPercent 100

    $resolvedImagePath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $ImagePath))
    if (-not (Test-Path -LiteralPath $resolvedImagePath)) {
        throw "Standard image fixture not found: $resolvedImagePath"
    }
    if (Test-Path -LiteralPath $HeicUrl -PathType Leaf) {
        Copy-Item -LiteralPath $HeicUrl -Destination $heicPath -Force
    } else {
        Invoke-WebRequest -Uri $HeicUrl -OutFile $heicPath -TimeoutSec 120
    }

    $ffmpegArguments = @(
        "exec", "genericim-api", "ffmpeg",
        "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24",
        "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000",
        "-t", "4",
        "-c:v", "libvpx-vp9", "-b:v", "800k",
        "-c:a", "libopus",
        "-y", $containerWebmPath
    )
    & docker @ffmpegArguments
    if ($LASTEXITCODE -ne 0) { throw "failed to generate WebM fixture" }
    & docker cp "genericim-api`:$containerWebmPath" $webmPath
    if ($LASTEXITCODE -ne 0) { throw "failed to copy WebM fixture" }

    $alice = Login-TestUser -Username $AliceUsername
    $bob = Login-TestUser -Username $BobUsername
    $aliceToken = [string]$alice.token
    $bobToken = [string]$bob.token
    $chat = Invoke-JsonApi -Method POST -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
        type = 1
        member_ids = @([string]$bob.user.uuid)
    }
    $chatId = [string]$chat.uuid

    $png = Upload-And-Process -Token $aliceToken -Category "image" `
        -FilePath $resolvedImagePath -FileName "p1-thumbnail.png" -MimeType "image/png"
    $pngMessageId = Bind-Media -Token $aliceToken -ChatId $chatId -Type 2 -Upload $png
    $pngRange = Get-MemberMediaRange -Token $bobToken -MediaId ([string]$png.Completed.media_id)
    $pngThumbRange = Get-MemberMediaRange -Token $bobToken `
        -MediaId ([string]$png.Completed.thumbnail_media_id)

    $heic = Upload-And-Process -Token $aliceToken -Category "image" `
        -FilePath $heicPath -FileName "p1-convert.heic" -MimeType "image/heic"
    $heicMessageId = Bind-Media -Token $aliceToken -ChatId $chatId -Type 2 -Upload $heic
    $heicRange = Get-MemberMediaRange -Token $bobToken -MediaId ([string]$heic.Completed.media_id)
    $heicThumbRange = Get-MemberMediaRange -Token $bobToken `
        -MediaId ([string]$heic.Completed.thumbnail_media_id)

    $webm = Upload-And-Process -Token $aliceToken -Category "video" `
        -FilePath $webmPath -FileName "p1-transcode.webm" -MimeType "video/webm"
    $webmMessageId = Bind-Media -Token $aliceToken -ChatId $chatId -Type 3 -Upload $webm
    $webmRange = Get-MemberMediaRange -Token $bobToken -MediaId ([string]$webm.Completed.media_id)
    $webmThumbRange = Get-MemberMediaRange -Token $bobToken `
        -MediaId ([string]$webm.Completed.thumbnail_media_id)

    $pngPassed = $pngRange.Status -eq 206 -and
        (Test-PngHeader $pngRange.Bytes) -and
        $png.Completed.thumbnail_media_id -and
        $pngThumbRange.Status -eq 206 -and
        (Test-JpegHeader $pngThumbRange.Bytes)
    $heicPassed = $heic.Completed.processed -eq $true -and
        [string]$heic.Completed.source_media_id -eq $heic.UploadId -and
        [string]$heic.Completed.media_id -ne $heic.UploadId -and
        [string]$heic.Completed.mime_type -eq "image/jpeg" -and
        $heicRange.Status -eq 206 -and
        (Test-JpegHeader $heicRange.Bytes) -and
        $heicThumbRange.Status -eq 206 -and
        (Test-JpegHeader $heicThumbRange.Bytes)
    $webmPassed = $webm.Completed.processed -eq $true -and
        $webm.Completed.transcoded -eq $true -and
        [string]$webm.Completed.source_media_id -eq $webm.UploadId -and
        [string]$webm.Completed.media_id -ne $webm.UploadId -and
        [string]$webm.Completed.mime_type -eq "video/mp4" -and
        $webmRange.Status -eq 206 -and
        (Test-Mp4Header $webmRange.Bytes) -and
        $webmThumbRange.Status -eq 206 -and
        (Test-JpegHeader $webmThumbRange.Bytes)

    $result = [ordered]@{
        passed = [bool]($pngPassed -and $heicPassed -and $webmPassed)
        chat_id = $chatId
        standard_image = [ordered]@{
            passed = [bool]$pngPassed
            upload_id = $png.UploadId
            media_id = [string]$png.Completed.media_id
            thumbnail_media_id = [string]$png.Completed.thumbnail_media_id
            width = [int]$png.Completed.width
            height = [int]$png.Completed.height
            primary_range_status = $pngRange.Status
            thumbnail_range_status = $pngThumbRange.Status
            message_id = $pngMessageId
        }
        heic = [ordered]@{
            passed = [bool]$heicPassed
            fixture_url = $HeicUrl
            upload_id = $heic.UploadId
            media_id = [string]$heic.Completed.media_id
            source_media_id = [string]$heic.Completed.source_media_id
            thumbnail_media_id = [string]$heic.Completed.thumbnail_media_id
            mime_type = [string]$heic.Completed.mime_type
            width = [int]$heic.Completed.width
            height = [int]$heic.Completed.height
            primary_range_status = $heicRange.Status
            thumbnail_range_status = $heicThumbRange.Status
            message_id = $heicMessageId
        }
        webm_transcode = [ordered]@{
            passed = [bool]$webmPassed
            upload_id = $webm.UploadId
            media_id = [string]$webm.Completed.media_id
            source_media_id = [string]$webm.Completed.source_media_id
            thumbnail_media_id = [string]$webm.Completed.thumbnail_media_id
            mime_type = [string]$webm.Completed.mime_type
            transcoded = [bool]$webm.Completed.transcoded
            width = [int]$webm.Completed.width
            height = [int]$webm.Completed.height
            duration_ms = [int]$webm.Completed.duration
            primary_range_status = $webmRange.Status
            thumbnail_range_status = $webmThumbRange.Status
            message_id = $webmMessageId
        }
    }
    $outputFullPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 20
    if (-not $result.passed) {
        throw "P1 media processing acceptance failed"
    }
} finally {
    if ($originalDirectUploadEnabled -in @("true", "false") -and
        $originalDirectUploadRollout -match "^\d{1,3}$") {
        Set-LocalDirectUploadGate `
            -Enabled $originalDirectUploadEnabled `
            -RolloutPercent ([int]$originalDirectUploadRollout)
    }
    & docker exec genericim-api rm -f $containerWebmPath 2>$null
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
