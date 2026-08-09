<#
.SYNOPSIS
为消息可靠性 QA 创建账号、会话和多类型消息种子。

.DESCRIPTION
通过后端 API 准备可重复识别的文本和媒体消息，并把后续 UI/同步测试需要的
ID 与标记写入输出目录。脚本会在目标后端创建持久业务数据，只能使用隔离的
QA 环境和专用账号。

.PARAMETER BaseUrl
用于创建种子的测试后端根地址。

.PARAMETER Password
新建或复用 QA 账号的测试密码，不应使用生产凭据。

.PARAMETER OutputDir
保存账号、会话、消息 ID 和媒体可用性结果的目录。

.EXAMPLE
pwsh -File scripts/qa_message_seed.ps1
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$Password = "QaMsg123",
    [string]$OutputDir = "build/smoke/qa-message-reliability"
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
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Method = $Method
        Uri = "$($BaseUrl.TrimEnd('/'))$Path"
        Headers = $headers
        TimeoutSec = 20
    }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        $detail = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($detail)) {
            throw
        }
        try {
            return $detail | ConvertFrom-Json
        } catch {
            throw
        }
    }
}

function Assert-Ok {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        throw "$Action failed: code=$($Response.code) message=$($Response.message)"
    }
}

function Assert-MediaAvailable {
    # 媒体路径为空表示该种子不包含附件；非空时必须能从测试环境实际访问。
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $url = $Path
    if ($Path.StartsWith("/")) {
        $url = "$($BaseUrl.TrimEnd('/'))$Path"
    }

    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.Timeout = 10000
        $response = $request.GetResponse()
        $statusCode = [int]$response.StatusCode
    } catch {
        throw "media unavailable: $Path"
    } finally {
        if ($null -ne $response) {
            $response.Close()
        }
    }
    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        throw "media unavailable: $Path status=$statusCode"
    }
}

function Login-OrRegister {
    param([string]$Username)

    $body = @{
        username = $Username
        password = $Password
        device_id = "qa-$Username"
        device_type = "android"
        device_name = "QA Device"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -ne 0) {
        $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
            username = $Username
            password = $Password
            nickname = $Username
            gender = "male"
            device_id = "qa-$Username"
            device_type = "android"
            device_name = "QA Device"
        }
        Assert-Ok -Response $register -Action "register $Username"
        $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    }
    Assert-Ok -Response $login -Action "login $Username"
    return $login
}

$health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok."
}

$batch = "qa" + (Get-Date -Format "MMddHHmmss")
$users = @(
    "${batch}a",
    "${batch}b",
    "${batch}c",
    "${batch}d"
)

$logins = @{}
foreach ($user in $users) {
    $logins[$user] = Login-OrRegister -Username $user
}

$alice = $users[0]
$bob = $users[1]
$carl = $users[2]
$dina = $users[3]

$aliceToken = [string]$logins[$alice].data.token
$bobToken = [string]$logins[$bob].data.token
$carlToken = [string]$logins[$carl].data.token
$aliceUuid = [string]$logins[$alice].data.user.uuid
$bobUuid = [string]$logins[$bob].data.user.uuid
$dinaUuid = [string]$logins[$dina].data.user.uuid

$chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-Ok -Response $chat -Action "create alice-bob chat"
$chatId = [string]$chat.data.uuid

$secondChat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $carlToken -Body @{
    type = 1
    member_ids = @($dinaUuid)
}
Assert-Ok -Response $secondChat -Action "create carl-dina chat"
$secondChatId = [string]$secondChat.data.uuid

$seedMessages = @(
    @{
        type = 1
        label = "text"
        content = @{ text = "$batch seed text 01 hello history" }
    },
    @{
        type = 1
        label = "emoji_text"
        content = @{ text = "$batch seed emoji 02 smile" }
    },
    @{
        type = 8
        label = "sticker"
        content = @{
            sticker = @{
                pack_id = "yier_bubu"
                sticker_id = "001"
                url = "/uploads/stickers/yier_bubu/001.gif"
                emoji = "gif"
            }
        }
    },
    @{
        type = 2
        label = "image"
        content = @{
            media = @{
                url = "/uploads/stickers/yier_bubu/002.gif"
                thumbnail = "/uploads/stickers/yier_bubu/002.gif"
                width = 128
                height = 128
                size = 487096
                mime_type = "image/gif"
            }
        }
    },
    @{
        type = 1
        label = "text_after_media"
        content = @{ text = "$batch seed text 05 after media" }
    }
)

$sent = @()
$index = 0
foreach ($message in $seedMessages) {
    Assert-MediaAvailable -Path $message.content.sticker.url
    Assert-MediaAvailable -Path $message.content.media.url
    Assert-MediaAvailable -Path $message.content.media.thumbnail

    $index++
    $msgId = "$batch-seed-$("{0:d2}" -f $index)-$([guid]::NewGuid().ToString())"
    $response = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = $chatId
        type = $message.type
        msg_id = $msgId
        content = $message.content
    }
    Assert-Ok -Response $response -Action "send seed $($message.label)"
    $sent += [pscustomobject]@{
        msg_id = $msgId
        label = $message.label
        type = $message.type
        seq = $response.data.seq
        text = $message.content.text
    }
    Start-Sleep -Milliseconds 120
}

$secondResponse = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $carlToken -Body @{
    chat_id = $secondChatId
    type = 1
    msg_id = "$batch-carl-dina-$([guid]::NewGuid().ToString())"
    content = @{ text = "$batch carl to dina independent chat" }
}
Assert-Ok -Response $secondResponse -Action "send carl-dina text"

$summary = [pscustomobject]@{
    batch = $batch
    password = $Password
    users = $users
    alice = $alice
    bob = $bob
    carl = $carl
    dina = $dina
    alice_uuid = $aliceUuid
    bob_uuid = $bobUuid
    alice_token = $aliceToken
    bob_token = $bobToken
    chat_id = $chatId
    second_chat_id = $secondChatId
    seed_messages = $sent
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = Join-Path $OutputDir "seed-$batch.json"
$summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outputPath -Encoding utf8
$summary | ConvertTo-Json -Depth 30
