param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$FixturePath = "artifacts/real-device-qa/aws-two-device-20260727/fixtures/aws-image-huawei-to-samsung.png",
    [string]$OutputPath = "artifacts/real-device-qa/p0-s3-acceptance-20260727/api-acceptance.json"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")

function Invoke-JsonApi {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int[]]$ExpectedStatus = @(200)
    )

    $headers = @{}
    $headers["X-Client-Platform"] = "android"
    if ($Token) {
        $headers.Authorization = "Bearer $Token"
    }
    $params = @{
        Uri = "$BaseUrl$Path"
        Method = $Method
        Headers = $headers
        SkipHttpErrorCheck = $true
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    $response = Invoke-WebRequest @params
    if ($ExpectedStatus -notcontains [int]$response.StatusCode) {
        throw "$Method $Path returned HTTP $($response.StatusCode): $($response.Content)"
    }
    $json = $null
    if ($response.Content) {
        $json = $response.Content | ConvertFrom-Json
    }
    return [pscustomobject]@{
        Status = [int]$response.StatusCode
        Json = $json
    }
}

function Assert-ApiSuccess {
    param([object]$Response, [string]$Label)
    if ($null -eq $Response.Json -or [int]$Response.Json.code -ne 0) {
        throw "$Label failed: $($Response.Json | ConvertTo-Json -Depth 10 -Compress)"
    }
}

function Login-TestUser {
    param([string]$Username)
    $response = Invoke-JsonApi -Method POST -Path "/api/v1/auth/login" -Body @{
        username = $Username
        password = $Password
        device_id = "p0-s3-api-$Username"
        device_type = "android"
        device_name = "P0 S3 API Acceptance"
    }
    Assert-ApiSuccess -Response $response -Label "login $Username"
    return $response.Json.data
}

function Get-SHA256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Put-PresignedObject {
    param(
        [string]$Url,
        [object]$SignedHeaders,
        [byte[]]$Bytes
    )
    $client = [System.Net.Http.HttpClient]::new()
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Put,
            $Url
        )
        $request.Content = [System.Net.Http.ByteArrayContent]::new($Bytes)
        foreach ($property in $SignedHeaders.PSObject.Properties) {
            $name = [string]$property.Name
            $value = [string]$property.Value
            if (-not $request.Headers.TryAddWithoutValidation($name, $value)) {
                [void]$request.Content.Headers.TryAddWithoutValidation($name, $value)
            }
        }
        $response = $client.Send($request)
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            Body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    } finally {
        $client.Dispose()
    }
}

function Init-ImageUpload {
    param(
        [string]$Token,
        [byte[]]$Bytes,
        [string]$Checksum,
        [string]$RequestId,
        [string]$FileName = "p0-safe.png"
    )
    $response = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/init" -Token $Token -Body @{
        client_request_id = $RequestId
        category = "image"
        file_name = $FileName
        size = $Bytes.Length
        mime_type = "image/png"
        checksum_sha256 = $Checksum
    }
    Assert-ApiSuccess -Response $response -Label "init image upload"
    return $response.Json.data
}

$fixture = (Resolve-Path -LiteralPath $FixturePath).Path
$safeBytes = [System.IO.File]::ReadAllBytes($fixture)
$safeChecksum = Get-SHA256Hex -Bytes $safeBytes
$alice = Login-TestUser -Username $AliceUsername
$bob = Login-TestUser -Username $BobUsername
$aliceToken = [string]$alice.token
$bobToken = [string]$bob.token
$bobUuid = [string]$bob.user.uuid

$chatResponse = Invoke-JsonApi -Method POST -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-ApiSuccess -Response $chatResponse -Label "create private chat"
$chatId = [string]$chatResponse.Json.data.uuid

$results = [ordered]@{}

$missingChecksum = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/init" -Token $aliceToken -ExpectedStatus @(400) -Body @{
    client_request_id = [guid]::NewGuid().ToString()
    category = "image"
    file_name = "missing-checksum.png"
    size = $safeBytes.Length
    mime_type = "image/png"
}
$results.missing_checksum_rejected = ($missingChecksum.Status -eq 400)

$wrongChecksum = "0" * 64
$wrongInit = Init-ImageUpload -Token $aliceToken -Bytes $safeBytes -Checksum $wrongChecksum -RequestId ([guid]::NewGuid().ToString()) -FileName "wrong-checksum.png"
$wrongPut = Put-PresignedObject -Url ([string]$wrongInit.put_url) -SignedHeaders $wrongInit.headers -Bytes $safeBytes
if ($wrongPut.Status -ge 200 -and $wrongPut.Status -lt 300) {
    $wrongComplete = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$($wrongInit.media_id)/complete" -Token $aliceToken -ExpectedStatus @(400) -Body @{}
    $results.wrong_checksum_rejected = ($wrongComplete.Status -eq 400)
} else {
    $results.wrong_checksum_rejected = $true
}

$fakeBytes = [Text.Encoding]::UTF8.GetBytes("MZ-not-a-real-png-p0")
$fakeChecksum = Get-SHA256Hex -Bytes $fakeBytes
$fakeInit = Init-ImageUpload -Token $aliceToken -Bytes $fakeBytes -Checksum $fakeChecksum -RequestId ([guid]::NewGuid().ToString()) -FileName "fake-signature.png"
$fakePut = Put-PresignedObject -Url ([string]$fakeInit.put_url) -SignedHeaders $fakeInit.headers -Bytes $fakeBytes
if ($fakePut.Status -lt 200 -or $fakePut.Status -ge 300) {
    throw "fake signature fixture did not reach complete: HTTP $($fakePut.Status) $($fakePut.Body)"
}
$fakeComplete = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$($fakeInit.media_id)/complete" -Token $aliceToken -ExpectedStatus @(400) -Body @{}
$results.fake_signature_rejected = ($fakeComplete.Status -eq 400)

$requestId = [guid]::NewGuid().ToString()
$upload = Init-ImageUpload -Token $aliceToken -Bytes $safeBytes -Checksum $safeChecksum -RequestId $requestId
$put = Put-PresignedObject -Url ([string]$upload.put_url) -SignedHeaders $upload.headers -Bytes $safeBytes
if ($put.Status -lt 200 -or $put.Status -ge 300) {
    throw "safe S3 PUT failed: HTTP $($put.Status) $($put.Body)"
}
$mediaId = [string]$upload.media_id
$complete1 = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$mediaId/complete" -Token $aliceToken -Body @{}
$complete2 = Invoke-JsonApi -Method POST -Path "/api/v1/media/uploads/$mediaId/complete" -Token $aliceToken -Body @{}
Assert-ApiSuccess -Response $complete1 -Label "complete image"
Assert-ApiSuccess -Response $complete2 -Label "repeat complete image"
$results.complete_idempotent = (
    [string]$complete1.Json.data.media_id -eq $mediaId -and
    [string]$complete2.Json.data.media_id -eq $mediaId
)
$results.checksum_persisted_in_response = ([string]$complete1.Json.data.checksum -eq $safeChecksum)
$results.complete_returns_signed_get = ([string]$complete1.Json.data.url -match "X-Amz-Signature")

$bobAccessBeforeBind = Invoke-JsonApi -Method GET -Path "/api/v1/media/$mediaId/access-url" -Token $bobToken -ExpectedStatus @(200, 403)
$results.non_owner_access_before_bind_rejected = ([int]$bobAccessBeforeBind.Json.code -eq 403)

$hijackMsgId = [guid]::NewGuid().ToString()
$hijack = Invoke-JsonApi -Method POST -Path "/api/v1/message/send" -Token $bobToken -ExpectedStatus @(400) -Body @{
    chat_id = $chatId
    type = 2
    msg_id = $hijackMsgId
    content = @{
        media = @{
            media_id = $mediaId
            url = "https://attacker.invalid/forged.png"
            size = $safeBytes.Length
            mime_type = "image/png"
        }
    }
}
$results.other_user_media_binding_rejected = ($hijack.Status -eq 400)

$msgId = [guid]::NewGuid().ToString()
$send = Invoke-JsonApi -Method POST -Path "/api/v1/message/send" -Token $aliceToken -Body @{
    chat_id = $chatId
    type = 2
    msg_id = $msgId
    content = @{
        media = @{
            media_id = $mediaId
            url = "https://attacker.invalid/forged.png"
            width = 320
            height = 180
            size = $safeBytes.Length
            mime_type = "image/png"
        }
    }
}
Assert-ApiSuccess -Response $send -Label "bind image message"
$storedUrl = [string]$send.Json.data.content.media.url
$results.server_replaced_untrusted_url = (
    $storedUrl -notmatch "attacker.invalid" -and
    $storedUrl -match "^https://[^/]+/uploads/images/"
)

$bobAccessAfterBind = Invoke-JsonApi -Method GET -Path "/api/v1/media/$mediaId/access-url" -Token $bobToken
Assert-ApiSuccess -Response $bobAccessAfterBind -Label "member access after bind"
$results.chat_member_signed_access_allowed = ([string]$bobAccessAfterBind.Json.data.url -match "X-Amz-Signature")

$revoke1 = Invoke-JsonApi -Method POST -Path "/api/v1/message/revoke" -Token $aliceToken -Body @{
    chat_id = $chatId
    msg_id = $msgId
}
$revoke2 = Invoke-JsonApi -Method POST -Path "/api/v1/message/revoke" -Token $aliceToken -Body @{
    chat_id = $chatId
    msg_id = $msgId
}
Assert-ApiSuccess -Response $revoke1 -Label "revoke media message"
Assert-ApiSuccess -Response $revoke2 -Label "repeat revoke media message"
$results.revoke_idempotent = $true

$dbLine = docker exec genericim-mysql mysql -ugenericim -pgenericim -N -B genericim -e "SELECT status,reference_count,expected_sha256,checksum_sha256,object_key FROM media_objects WHERE media_id='$mediaId' LIMIT 1;" 2>$null
$dbParts = [string]$dbLine -split "`t"
$results.revoke_marks_deleting = ($dbParts[0] -eq "deleting" -and [int]$dbParts[1] -eq 0)
$results.database_checksum_matches = ($dbParts[2] -eq $safeChecksum -and $dbParts[3] -eq $safeChecksum)

$failed = @($results.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object Key)
$summary = [ordered]@{
    passed = ($failed.Count -eq 0)
    failed_checks = $failed
    chat_id = $chatId
    message_id = $msgId
    media_id = $mediaId
    object_key = $dbParts[4]
    checksum_sha256 = $safeChecksum
    checks = $results
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 20

if ($failed.Count -gt 0) {
    throw "P0 S3 acceptance failed: $($failed -join ', ')"
}
