<#
.SYNOPSIS
通过 REST API 验证双账号私聊的创建、发送和读取闭环。

.DESCRIPTION
登录 Alice/Bob 测试账号，建立联系人/会话并发送唯一消息，然后验证对端
可以读取该消息。脚本会在目标后端创建测试数据，不应对生产账号运行。

.PARAMETER BaseUrl
后端根地址，不包含 /api/v1。

.PARAMETER MessageText
指定测试文本；为空时生成带时间戳的唯一内容。

.PARAMETER OutputPath
可选 JSON 结果路径，用于保存账号、会话和消息断言证据。

.EXAMPLE
pwsh -File scripts/smoke_chat_api.ps1 -BaseUrl http://127.0.0.1:8080
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [string]$MessageText = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Join-ApiUrl {
    param(
        [string]$BaseUrl,
        [string]$Path
    )

    return "$($BaseUrl.TrimEnd('/'))$Path"
}

function Invoke-ApiJson {
    # 所有接口错误在此转换为带 Method/Path 的异常，便于定位失败阶段。
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Method  = $Method
        Uri     = (Join-ApiUrl -BaseUrl $script:BaseUrl -Path $Path)
        Headers = $headers
        TimeoutSec = 20
    }

    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 20)
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = "$detail $($_.ErrorDetails.Message)"
        }
        throw "$Method $Path failed: $detail"
    }
}

function Assert-ApiSuccess {
    param(
        [object]$Response,
        [string]$Action
    )

    if ($null -eq $Response) {
        throw "$Action failed: empty response"
    }

    if ([int]$Response.code -ne 0) {
        throw "$Action failed: code=$($Response.code) message=$($Response.message)"
    }
}

function New-LoginBody {
    param([string]$Username)

    return @{
        username = $Username
        password = $script:Password
        device_id = "codex-smoke-api-$Username"
        device_type = "android"
        device_name = "Codex API Smoke"
    }
}

function Login-SmokeUser {
    param([string]$Username)

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body (New-LoginBody -Username $Username)
    if ([int]$login.code -eq 0) {
        return $login
    }

    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $script:Password
        nickname = $Username
        gender = "male"
        device_id = "codex-smoke-api-$Username"
        device_type = "android"
        device_name = "Codex API Smoke"
    }
    Assert-ApiSuccess -Response $register -Action "register $Username"

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body (New-LoginBody -Username $Username)
    Assert-ApiSuccess -Response $login -Action "login $Username after register"
    return $login
}

function ConvertTo-CompactJson {
    param([object]$Value)

    return ($Value | ConvertTo-Json -Depth 30 -Compress)
}

if ([string]::IsNullOrWhiteSpace($MessageText)) {
    $MessageText = "codex smoke chat message $(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

$BaseUrl = $BaseUrl.TrimEnd("/")

$health = Invoke-RestMethod -Uri (Join-ApiUrl -BaseUrl $BaseUrl -Path "/health") -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok: $($health | ConvertTo-CompactJson)"
}

$aliceLogin = Login-SmokeUser -Username $AliceUsername
$bobLogin = Login-SmokeUser -Username $BobUsername

$aliceToken = [string]$aliceLogin.data.token
$aliceUuid = [string]$aliceLogin.data.user.uuid
$aliceNickname = [string]$aliceLogin.data.user.nickname
$bobUuid = [string]$bobLogin.data.user.uuid
$bobNickname = [string]$bobLogin.data.user.nickname
if ([string]::IsNullOrWhiteSpace($aliceToken) -or [string]::IsNullOrWhiteSpace($bobUuid)) {
    throw "Login response did not include token/user UUID."
}

$chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-ApiSuccess -Response $chat -Action "create private chat"

$chatId = [string]$chat.data.uuid
if ([string]::IsNullOrWhiteSpace($chatId)) {
    throw "Create chat response did not include data.uuid: $(ConvertTo-CompactJson -Value $chat)"
}

$msgId = [guid]::NewGuid().ToString()
$send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{
    chat_id = $chatId
    type = 1
    msg_id = $msgId
    content = @{
        text = $MessageText
    }
}
Assert-ApiSuccess -Response $send -Action "send message"

$chatList = Invoke-ApiJson -Method "GET" -Path "/api/v1/chat/list?page=1&page_size=20" -Token $aliceToken
Assert-ApiSuccess -Response $chatList -Action "list chats"
$chatItems = @($chatList.data)
$chatJson = ConvertTo-CompactJson -Value $chatItems
if ($chatJson -notmatch [regex]::Escape($chatId)) {
    throw "Chat list does not contain chat_id=$chatId"
}

$messageListPath = "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($chatId))&limit=30"
$messageList = Invoke-ApiJson -Method "GET" -Path $messageListPath -Token $aliceToken
Assert-ApiSuccess -Response $messageList -Action "list messages"
$messageItems = @($messageList.data)
$messageJson = ConvertTo-CompactJson -Value $messageItems
if ($messageJson -notmatch [regex]::Escape($MessageText)) {
    throw "Message list does not contain sent text: $MessageText"
}

$summary = [pscustomobject]@{
    alice = $AliceUsername
    alice_uuid = $aliceUuid
    alice_nickname = $aliceNickname
    bob = $BobUsername
    bob_uuid = $bobUuid
    bob_nickname = $bobNickname
    chat_id = $chatId
    message_id = $msgId
    message_text = $MessageText
    chat_count = $chatItems.Count
    message_count = $messageItems.Count
}

$summaryJson = $summary | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding utf8
}

Write-Output $summaryJson
