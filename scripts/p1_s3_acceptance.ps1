param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [int]$SizeMB = 100,
    [string]$OutputPath = "artifacts/p1-s3-acceptance-20260727/p1-acceptance.json"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")

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
    $json = if ($response.Content) {
        $response.Content | ConvertFrom-Json
    } else {
        $null
    }
    [pscustomobject]@{
        Status = [int]$response.StatusCode
        Json = $json
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
        device_id = "p1-s3-$Username"
        device_type = "android"
        device_name = "P1 S3 Acceptance"
    }
    Assert-Success -Response $response -Label "login $Username"
    return $response.Json.data
}

function Put-FileRange {
    param(
        [string]$Url,
        [object]$SignedHeaders,
        [string]$Path,
        [int64]$Offset,
        [int]$Length
    )
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $bytes = New-Object byte[] $Length
    try {
        [void]$stream.Seek($Offset, [IO.SeekOrigin]::Begin)
        $read = 0
        while ($read -lt $Length) {
            $count = $stream.Read($bytes, $read, $Length - $read)
            if ($count -le 0) { throw "unexpected end of fixture at offset $Offset" }
            $read += $count
        }
    } finally {
        $stream.Dispose()
    }

    $client = [Net.Http.HttpClient]::new()
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Put, $Url)
        $request.Content = [Net.Http.ByteArrayContent]::new($bytes)
        if ($null -ne $SignedHeaders) {
            foreach ($property in $SignedHeaders.PSObject.Properties) {
                $name = [string]$property.Name
                $value = [string]$property.Value
                if (-not $request.Headers.TryAddWithoutValidation($name, $value)) {
                    [void]$request.Content.Headers.TryAddWithoutValidation($name, $value)
                }
            }
        }
        $response = $client.Send($request)
        [pscustomobject]@{
            Status = [int]$response.StatusCode
            Body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    } finally {
        $client.Dispose()
    }
}

function Get-SignedRange {
    param(
        [string]$Url,
        [int64]$Start = 0,
        [int64]$End = 23
    )
    $client = [Net.Http.HttpClient]::new()
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Url)
        $request.Headers.Range = [Net.Http.Headers.RangeHeaderValue]::new($Start, $End)
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

function New-MP4Fixture {
    param([string]$Path, [int64]$Length)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $sha = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] (1024 * 1024)
    $header = [Text.Encoding]::ASCII.GetBytes("`0`0`0`0ftypisom`0`0`0`1isomiso2")
    [Array]::Copy($header, $buffer, $header.Length)
    $remaining = $Length
    try {
        while ($remaining -gt 0) {
            $count = [Math]::Min($buffer.Length, $remaining)
            $stream.Write($buffer, 0, $count)
            [void]$sha.TransformBlock($buffer, 0, $count, $buffer, 0)
            $remaining -= $count
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
    } finally {
        $stream.Dispose()
    }
    [pscustomobject]@{
        Path = $Path
        Sha256 = ([Convert]::ToHexString($sha.Hash)).ToLowerInvariant()
        Length = $Length
    }
}

$sizeBytes = [int64]$SizeMB * 1024 * 1024
if ($SizeMB -lt 100) {
    throw "P1 acceptance requires SizeMB >= 100"
}

$outputFullPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$fixturePath = Join-Path ([IO.Path]::GetTempPath()) "genericim-p1-$([guid]::NewGuid()).mp4"

$alice = Login-TestUser -Username $AliceUsername
$bob = Login-TestUser -Username $BobUsername
$aliceToken = [string]$alice.token
$bobToken = [string]$bob.token
$bobUUID = [string]$bob.user.uuid
$fixture = New-MP4Fixture -Path $fixturePath -Length $sizeBytes
$results = [ordered]@{}

try {
    $requestId = [guid]::NewGuid().ToString()
    $init = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/init" -Token $aliceToken -Body @{
        client_request_id = $requestId
        category = "video"
        file_name = "p1-large.mp4"
        size = $fixture.Length
        mime_type = "video/mp4"
    }
    Assert-Success -Response $init -Label "init multipart video"
    $session = $init.Json.data
    $mediaId = [string]$session.media_id
    $partSize = [int64]$session.part_size
    $partCount = [int]$session.part_count
    $results.multipart_mode = ([string]$session.mode -eq "multipart")
    $results.part_size_16mb = ($partSize -eq 16 * 1024 * 1024)
    $results.part_count_expected = ($partCount -eq [Math]::Ceiling($fixture.Length / $partSize))

    $initialStatus = Invoke-JsonApi -Method GET -Path "/api/v1/media/uploads/$mediaId" -Token $aliceToken
    Assert-Success -Response $initialStatus -Label "initial multipart status"
    $results.initial_parts_empty = (@($initialStatus.Json.data.uploaded_parts).Count -eq 0)

    for ($number = 1; $number -le $partCount; $number++) {
        $presign = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$mediaId/parts/presign" -Token $aliceToken -Body @{
            part_numbers = @($number)
        }
        Assert-Success -Response $presign -Label "presign part $number"
        $part = $presign.Json.data.parts[0]
        $offset = ([int64]($number - 1) * $partSize)
        $length = [int][Math]::Min($partSize, $fixture.Length - $offset)
        $put = Put-FileRange -Url ([string]$part.put_url) -SignedHeaders $part.headers `
            -Path $fixture.Path -Offset $offset -Length $length
        if ($put.Status -lt 200 -or $put.Status -ge 300) {
            throw "part $number PUT failed: HTTP $($put.Status) $($put.Body)"
        }
        if ($number -eq 2) {
            $midStatus = Invoke-JsonApi -Method GET -Path "/api/v1/media/uploads/$mediaId" -Token $aliceToken
            Assert-Success -Response $midStatus -Label "mid-upload status"
            $results.resume_status_after_two_parts = (@($midStatus.Json.data.uploaded_parts).Count -eq 2)
        }
    }

    $complete1 = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$mediaId/complete" -Token $aliceToken -Body @{}
    $complete2 = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$mediaId/complete" -Token $aliceToken -Body @{}
    Assert-Success -Response $complete1 -Label "complete multipart video"
    Assert-Success -Response $complete2 -Label "repeat complete multipart video"
    $results.complete_idempotent = (
        [string]$complete1.Json.data.media_id -eq $mediaId -and
        [string]$complete2.Json.data.media_id -eq $mediaId -and
        [string]$complete1.Json.data.status -in @("uploaded", "bound")
    )
    $results.completed_size = ([int64]$complete1.Json.data.size -eq $fixture.Length)

    $chat = Invoke-JsonApi -Method POST -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
        type = 1
        member_ids = @($bobUUID)
    }
    Assert-Success -Response $chat -Label "create private chat"
    $chatId = [string]$chat.Json.data.uuid
    $beforeBind = Invoke-JsonApi -Method GET -Path "/api/v1/media/$mediaId/access-url" `
        -Token $bobToken -ExpectedStatus @(200, 403)
    $results.non_owner_before_bind_rejected = ([int]$beforeBind.Json.code -eq 403)

    $messageId = [guid]::NewGuid().ToString()
    $send = Invoke-JsonApi -Method POST -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = $chatId
        type = 3
        msg_id = $messageId
        content = @{
            media = @{
                media_id = $mediaId
                url = "https://attacker.invalid/forged.mp4"
                size = $fixture.Length
                mime_type = "video/mp4"
            }
        }
    }
    Assert-Success -Response $send -Label "bind multipart video"
    $afterBind = Invoke-JsonApi -Method GET -Path "/api/v1/media/$mediaId/access-url" -Token $bobToken
    Assert-Success -Response $afterBind -Label "member signed access"
    $expiresAt = [DateTime]::Parse([string]$afterBind.Json.data.expires_at).ToUniversalTime()
    $ttlMinutes = ($expiresAt - [DateTime]::UtcNow).TotalMinutes
    $results.member_signed_access = ([string]$afterBind.Json.data.url -match "X-Amz-Signature")
    $results.access_url_ttl_about_10_minutes = ($ttlMinutes -gt 8 -and $ttlMinutes -le 11)
    $range = Get-SignedRange -Url ([string]$afterBind.Json.data.url)
    $rangeBytes = [byte[]]$range.Bytes
    $results.signed_range_206 = (
        $range.Status -eq 206 -and
        $range.ContentRange -match "/$($fixture.Length)$" -and
        $rangeBytes.Length -ge 12 -and
        [Text.Encoding]::ASCII.GetString($rangeBytes, 4, 4) -eq "ftyp"
    )

    $abortRequestId = [guid]::NewGuid().ToString()
    $abortInit = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/init" -Token $aliceToken -Body @{
        client_request_id = $abortRequestId
        category = "video"
        file_name = "p1-abort.mp4"
        size = $fixture.Length
        mime_type = "video/mp4"
    }
    Assert-Success -Response $abortInit -Label "init abort session"
    $abortID = [string]$abortInit.Json.data.media_id
    $abort = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$abortID/abort" -Token $aliceToken -Body @{}
    Assert-Success -Response $abort -Label "abort multipart session"
    $results.abort_marks_deleted = ([string]$abort.Json.data.status -eq "deleted")

    $failed = @($results.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object Key)
    $summary = [ordered]@{
        passed = ($failed.Count -eq 0)
        failed_checks = $failed
        fixture = @{
            size_bytes = $fixture.Length
            sha256 = $fixture.Sha256
        }
        media_id = $mediaId
        abort_media_id = $abortID
        chat_id = $chatId
        message_id = $messageId
        checks = $results
    }
    $summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
    $summary | ConvertTo-Json -Depth 30
    if ($failed.Count -gt 0) {
        throw "P1 S3 acceptance failed: $($failed -join ', ')"
    }
} finally {
    Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
}
