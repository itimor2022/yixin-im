param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$FixtureUrl = "https://samplelib.com/lib/preview/mp4/sample-5s.mp4",
    [string]$OutputPath = "artifacts/p1-s3-acceptance-20260727/playable-video-acceptance.json"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")
$fixturePath = Join-Path ([IO.Path]::GetTempPath()) "genericim-p1-playable-$([guid]::NewGuid()).mp4"

function Invoke-JsonApi {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int[]]$ExpectedStatus = @(200)
    )
    $headers = @{ "X-Client-Platform" = "android" }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $parameters = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = $headers
        SkipHttpErrorCheck = $true
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $parameters.ContentType = "application/json; charset=utf-8"
        $parameters.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    $response = Invoke-WebRequest @parameters
    if ($ExpectedStatus -notcontains [int]$response.StatusCode) {
        throw "$Method $Path returned HTTP $($response.StatusCode): $($response.Content)"
    }
    [pscustomobject]@{
        Status = [int]$response.StatusCode
        Json = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
    }
}

function Assert-Success {
    param([object]$Response, [string]$Label)
    if ($null -eq $Response.Json -or [int]$Response.Json.code -ne 0) {
        throw "$Label failed: $($Response.Json | ConvertTo-Json -Depth 20 -Compress)"
    }
}

function Login-TestUser {
    param([string]$Username)
    $response = Invoke-JsonApi -Method POST -Path "/api/v1/auth/login" -Body @{
        username = $Username
        password = $Password
        device_id = "p1-playable-video-$Username"
        device_type = "android"
        device_name = "P1 Playable Video Acceptance"
    }
    Assert-Success -Response $response -Label "login $Username"
    return $response.Json.data
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
            return [int]$response.StatusCode
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
            Bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        }
    } finally {
        $client.Dispose()
    }
}

try {
    Invoke-WebRequest -Uri $FixtureUrl -OutFile $fixturePath -UseBasicParsing -TimeoutSec 120
    $bytes = [IO.File]::ReadAllBytes($fixturePath)
    $sha256 = ([Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    )).ToLowerInvariant()

    $alice = Login-TestUser -Username $AliceUsername
    $bob = Login-TestUser -Username $BobUsername
    $aliceToken = [string]$alice.token
    $bobToken = [string]$bob.token
    $bobUUID = [string]$bob.user.uuid

    $init = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/init" -Token $aliceToken -Body @{
        client_request_id = [guid]::NewGuid().ToString()
        category = "video"
        file_name = "p1-playable-sample.mp4"
        size = $bytes.Length
        mime_type = "video/mp4"
        checksum_sha256 = $sha256
    }
    Assert-Success -Response $init -Label "init playable video"
    $session = $init.Json.data
    if ([string]$session.mode -ne "single") {
        throw "playable fixture unexpectedly selected $($session.mode)"
    }

    $putStatus = Put-File -Url ([string]$session.put_url) -SignedHeaders $session.headers -Path $fixturePath
    if ($putStatus -lt 200 -or $putStatus -ge 300) {
        throw "playable video PUT failed: HTTP $putStatus"
    }
    $complete = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$($session.media_id)/complete" -Token $aliceToken -Body @{}
    Assert-Success -Response $complete -Label "complete playable video"
    $completedMedia = $complete.Json.data
    $completedMediaId = [string]$completedMedia.media_id
    if (-not $completedMediaId) {
        throw "complete playable video did not return media_id"
    }
    $thumbnailMediaId = [string]$completedMedia.thumbnail_media_id
    $thumbnailUrl = [string]$completedMedia.thumbnail

    $chat = Invoke-JsonApi -Method POST -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
        type = 1
        member_ids = @($bobUUID)
    }
    Assert-Success -Response $chat -Label "create playable video chat"
    $messageId = [guid]::NewGuid().ToString()
    $messageMedia = @{
        media_id = $completedMediaId
        url = "https://attacker.invalid/not-playable.mp4"
        size = $bytes.Length
        mime_type = "video/mp4"
    }
    if ($thumbnailMediaId) {
        $messageMedia.thumbnail_media_id = $thumbnailMediaId
        $messageMedia.thumbnail = "https://attacker.invalid/not-a-thumbnail.jpg"
    }
    if ($completedMedia.width) { $messageMedia.width = [int]$completedMedia.width }
    if ($completedMedia.height) { $messageMedia.height = [int]$completedMedia.height }
    if ($completedMedia.duration) { $messageMedia.duration = [int]$completedMedia.duration }
    $send = Invoke-JsonApi -Method POST -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = [string]$chat.Json.data.uuid
        type = 3
        msg_id = $messageId
        content = @{
            media = $messageMedia
        }
    }
    Assert-Success -Response $send -Label "bind playable video"

    $access = Invoke-JsonApi -Method GET -Path "/api/v1/media/$completedMediaId/access-url" -Token $bobToken
    Assert-Success -Response $access -Label "member access playable video"
    $range = Get-Range -Url ([string]$access.Json.data.url)
    $rangeBytes = [byte[]]$range.Bytes
    $thumbnailRange = $null
    if ($thumbnailMediaId) {
        $thumbnailAccess = Invoke-JsonApi -Method GET -Path "/api/v1/media/$thumbnailMediaId/access-url" -Token $bobToken
        Assert-Success -Response $thumbnailAccess -Label "member access video thumbnail"
        $thumbnailRange = Get-Range -Url ([string]$thumbnailAccess.Json.data.url)
    }
    $outputFullPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
    $result = [ordered]@{
        passed = (
            $range.Status -eq 206 -and
            $range.ContentRange -match "/$($bytes.Length)$" -and
            $rangeBytes.Length -ge 12 -and
            [Text.Encoding]::ASCII.GetString($rangeBytes, 4, 4) -eq "ftyp" -and
            $thumbnailMediaId -and
            $thumbnailRange.Status -eq 206 -and
            $thumbnailRange.Bytes.Length -ge 3 -and
            $thumbnailRange.Bytes[0] -eq 0xFF -and
            $thumbnailRange.Bytes[1] -eq 0xD8 -and
            $thumbnailRange.Bytes[2] -eq 0xFF
        )
        fixture_url = $FixtureUrl
        fixture_size_bytes = $bytes.Length
        fixture_sha256 = $sha256
        upload_id = [string]$session.media_id
        media_id = $completedMediaId
        thumbnail_media_id = $thumbnailMediaId
        thumbnail_url_returned = [bool]$thumbnailUrl
        width = $completedMedia.width
        height = $completedMedia.height
        duration_ms = $completedMedia.duration
        transcoded = [bool]$completedMedia.transcoded
        chat_id = [string]$chat.Json.data.uuid
        message_id = $messageId
        put_status = $putStatus
        range_status = $range.Status
        range_content_range = $range.ContentRange
        thumbnail_range_status = if ($thumbnailRange) { $thumbnailRange.Status } else { 0 }
        signed_url = $true
    }
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 20
    if (-not $result.passed) {
        throw "playable video acceptance failed"
    }
} finally {
    Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
}
