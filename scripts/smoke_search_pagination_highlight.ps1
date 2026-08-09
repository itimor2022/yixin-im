<#
.SYNOPSIS
验证消息搜索分页稳定性和命中内容高亮字段。

.DESCRIPTION
使用双测试账号准备可唯一检索的消息，连续请求分页结果并检查无重复、无遗漏
及高亮信息。脚本会向目标后端写入测试消息，不应使用生产账号。

.PARAMETER BaseUrl
后端根地址，不包含 /api/v1。

.PARAMETER OutputPath
保存分页结果、游标和高亮断言的 JSON 文件。

.EXAMPLE
pwsh -File scripts/smoke_search_pagination_highlight.ps1
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$OutputPath = "build/smoke/search-pagination-highlight.json"
)

$ErrorActionPreference = "Stop"

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $headers = @{}
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $params = @{
        Method = $Method
        Uri = "$($script:BaseUrl.TrimEnd('/'))$Path"
        Headers = $headers
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }

    for ($attempt = 1; $attempt -le 8; $attempt++) {
        # 搜索分页必须串行重试同一请求，不能跳过被限流的页。
        try {
            return Invoke-RestMethod @params
        } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $detail = "$detail $($_.ErrorDetails.Message)"
            }
            if ($detail -match '"code"\s*:\s*429' -or $detail -match '\b429\b') {
                $sleepSeconds = [Math]::Min(30, 3 * $attempt)
                Write-Host "[search-smoke] rate limited, retrying in ${sleepSeconds}s (attempt $attempt/8)" -ForegroundColor Yellow
                Start-Sleep -Seconds $sleepSeconds
                continue
            }
            throw
        }
    }
    throw "$Method $Path failed after retries because of rate limiting"
}

function Assert-Ok {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        throw "$Action failed: $($Response | ConvertTo-Json -Depth 12 -Compress)"
    }
}

function Login-OrRegister {
    param([string]$Username, [string]$DeviceId)

    $body = @{
        username = $Username
        password = $script:Password
        device_id = $DeviceId
        device_type = "android"
        device_name = "Codex Search $DeviceId"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) { return $login }

    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $script:Password
        nickname = $Username
        gender = "male"
        device_id = $DeviceId
        device_type = "android"
        device_name = "Codex Search $DeviceId"
    }
    Assert-Ok -Response $register -Action "register $Username"

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-Ok -Response $login -Action "login $Username"
    return $login
}

function New-SmokeUsername {
    param([string]$Prefix, [string]$Suffix)
    $safePrefix = ($Prefix -replace '[^a-zA-Z0-9_]', '')
    if ([string]::IsNullOrWhiteSpace($safePrefix)) {
        $safePrefix = "smoke"
    }
    $shortSuffix = $Suffix
    if ($shortSuffix.Length -gt 8) {
        $shortSuffix = $shortSuffix.Substring($shortSuffix.Length - 8)
    }
    $maxPrefixLength = 20 - $shortSuffix.Length
    if ($safePrefix.Length -gt $maxPrefixLength) {
        $safePrefix = $safePrefix.Substring(0, $maxPrefixLength)
    }
    return "$safePrefix$shortSuffix"
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok: $($health | ConvertTo-Json -Compress)"
}

$suffix = Get-Date -Format "yyyyMMddHHmmss"
$shortSuffix = $suffix.Substring($suffix.Length - 8)
$keyword = "sps$shortSuffix"
$aliceEffectiveUsername = New-SmokeUsername -Prefix $AliceUsername -Suffix $shortSuffix
$bobEffectiveUsername = New-SmokeUsername -Prefix "bob_$keyword" -Suffix ""
$alice = Login-OrRegister -Username $aliceEffectiveUsername -DeviceId "codex-search-alice-$suffix"
$bob = Login-OrRegister -Username $bobEffectiveUsername -DeviceId "codex-search-bob-$suffix"
$token = [string]$alice.data.token
$bobToken = [string]$bob.data.token
$bobUuid = [string]$bob.data.user.uuid

$friendRequest = Invoke-ApiJson -Method "POST" -Path "/api/v1/contact/requests" -Token $token -Body @{
    user_id = $bobUuid
    message = "Codex $keyword Contact"
}
Assert-Ok -Response $friendRequest -Action "request searchable contact"
$requestId = [string]$friendRequest.data.request.id
$requestStatus = [string]$friendRequest.data.request.status
if ($requestStatus -ne "accepted") {
    if ([string]::IsNullOrWhiteSpace($requestId)) {
        throw "friend request response did not include a request id"
    }
    $acceptContact = Invoke-ApiJson -Method "POST" -Path "/api/v1/contact/requests/$requestId/accept" -Token $bobToken
    Assert-Ok -Response $acceptContact -Action "accept searchable contact"
}

$chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $token -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-Ok -Response $chat -Action "create private chat"
$chatId = [string]$chat.data.uuid

for ($i = 1; $i -le 3; $i++) {
    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $token -Body @{
        chat_id = $chatId
        type = 1
        msg_id = [guid]::NewGuid().ToString()
        content = @{ text = "global $keyword message $i for highlight" }
    }
    Assert-Ok -Response $send -Action "send searchable message $i"
    Start-Sleep -Milliseconds 300
}

$contacts = Invoke-ApiJson -Method "GET" -Path "/api/v1/search/global?keyword=$keyword&scope=contacts&limit=1&page=1" -Token $token
Assert-Ok -Response $contacts -Action "search contacts"
$contactItems = @($contacts.data.contacts)
if ($contactItems.Count -lt 1) {
    throw "contact search count=$($contactItems.Count), expected >=1"
}
if ($null -eq $contactItems[0].highlight -or [int]$contactItems[0].highlight.start -lt 0) {
    throw "contact search missing highlight"
}

$chats = Invoke-ApiJson -Method "GET" -Path "/api/v1/search/global?keyword=$keyword&scope=chats&limit=1&page=1" -Token $token
Assert-Ok -Response $chats -Action "search chats"
$chatItems = @($chats.data.chats)
if ($chatItems.Count -lt 1) {
    throw "chat search count=$($chatItems.Count), expected >=1"
}
if ($null -eq $chatItems[0].highlight -or [int]$chatItems[0].highlight.start -lt 0) {
    throw "chat search missing highlight"
}

$page1 = Invoke-ApiJson -Method "GET" -Path "/api/v1/search/global?keyword=$keyword&scope=messages&limit=2&page=1" -Token $token
Assert-Ok -Response $page1 -Action "search page 1"
$messages1 = @($page1.data.messages)
if ($messages1.Count -ne 2) {
    throw "page1 count=$($messages1.Count), expected 2"
}
if ($page1.data.has_more.messages -ne $true) {
    throw "page1 has_more.messages expected true"
}
if ($null -eq $messages1[0].highlight -or [int]$messages1[0].highlight.start -lt 0) {
    throw "page1 first result missing highlight"
}

$page2 = Invoke-ApiJson -Method "GET" -Path "/api/v1/search/global?keyword=$keyword&scope=messages&limit=2&page=2" -Token $token
Assert-Ok -Response $page2 -Action "search page 2"
$messages2 = @($page2.data.messages)
if ($messages2.Count -lt 1) {
    throw "page2 count=$($messages2.Count), expected >=1"
}

$summary = [pscustomobject]@{
    base_url = $BaseUrl
    keyword = $keyword
    chat_id = $chatId
    contact_count = $contactItems.Count
    chat_count = $chatItems.Count
    page1_count = $messages1.Count
    page1_has_more = [bool]$page1.data.has_more.messages
    page2_count = $messages2.Count
    highlight_text = [string]$messages1[0].highlight.text
    highlight_start = [int]$messages1[0].highlight.start
    highlight_end = [int]$messages1[0].highlight.end
}

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$json = $summary | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
Write-Output $json
