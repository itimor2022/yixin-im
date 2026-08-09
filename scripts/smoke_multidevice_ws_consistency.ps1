<#
.SYNOPSIS
验证同一账号多设备 WebSocket 事件与 REST 状态的一致性。

.DESCRIPTION
创建多设备登录会话，通过 WebSocket 和 REST 触发消息/已读状态变化，
比较各连接收到的事件并输出 JSON 证据。脚本会创建测试消息和设备会话，
只能对专用测试账号运行。

.PARAMETER WsUrl
WebSocket 完整地址，必须与 BaseUrl 指向同一后端实例。

.PARAMETER OutputPath
保存连接事件、服务端状态和断言结果的 JSON 文件。

.EXAMPLE
pwsh -File scripts/smoke_multidevice_ws_consistency.ps1
#>
<#
.SYNOPSIS
验证同一账号多连接及对端账号之间的 WebSocket 事件一致性。

.DESCRIPTION
登录测试账号并建立多条 WebSocket 连接，通过 REST 创建消息/已读等状态，比较各连接
收到的事件和最终 API 状态。脚本会创建测试会话与消息，不能使用生产账号。

.PARAMETER WsUrl
待验证的 WebSocket 完整地址。

.PARAMETER OutputPath
保存连接事件、API 快照和一致性断言的 JSON 路径。

.EXAMPLE
pwsh -File scripts/smoke_multidevice_ws_consistency.ps1 -BaseUrl http://127.0.0.1:8080
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$WsUrl = "ws://127.0.0.1:8080/api/v1/ws",
    [string]$AliceUsername = "ws_alice",
    [string]$BobUsername = "ws_bob",
    [string]$Password = "Smoke123",
    [string]$OutputPath = "build/smoke/multidevice-ws-consistency.json"
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
    # 仅对明确限流重试；协议或断言失败必须立即暴露。
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        # 限流只延迟当前验证步骤，不改变请求顺序，避免制造错误的多端时序。
        try {
            return Invoke-RestMethod @params
        } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $detail = "$detail $($_.ErrorDetails.Message)"
            }
            if ($detail -match '"code"\s*:\s*429' -or $detail -match '\b429\b') {
                $sleepSeconds = [Math]::Min(30, 3 * $attempt)
                Write-Host "[ws-smoke] rate limited, retrying in ${sleepSeconds}s (attempt $attempt/8)" -ForegroundColor Yellow
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
        device_name = "Codex WS $DeviceId"
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
        device_name = "Codex WS $DeviceId"
    }
    Assert-Ok -Response $register -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-Ok -Response $login -Action "login $Username"
    return $login
}

function New-ClientWebSocket {
    param([string]$Token)
    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    $encodedToken = [Uri]::EscapeDataString($Token)
    $uri = [Uri]"$($script:WsUrl)?device_type=android&token=$encodedToken"
    $connectTask = $client.ConnectAsync($uri, [Threading.CancellationToken]::None)
    $null = $connectTask.GetAwaiter().GetResult()
    return $client
}

function Receive-JsonMessage {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Client,
        [int]$TimeoutMs = 1000
    )

    $buffer = New-Object byte[] 65536
    $segment = [ArraySegment[byte]]::new($buffer)
    $cts = [Threading.CancellationTokenSource]::new($TimeoutMs)
    try {
        $result = $Client.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            return $null
        }
        $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
        return $text | ConvertFrom-Json
    } catch [OperationCanceledException] {
        return $null
    } finally {
        $cts.Dispose()
    }
}

function Wait-ForChatState {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Client,
        [string]$ChatId,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $msg = Receive-JsonMessage -Client $Client -TimeoutMs 1000
        if ($null -eq $msg) { continue }
        if ($msg.type -eq "chat_state_changed" -and [string]$msg.chat_id -eq $ChatId) {
            return $msg
        }
    }
    throw "chat_state_changed for chat $ChatId not received within ${TimeoutSeconds}s"
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok"
}

$suffix = Get-Date -Format "yyyyMMddHHmmss"
$alice = Login-OrRegister -Username $AliceUsername -DeviceId "codex-ws-alice-$suffix"
$bobA = Login-OrRegister -Username $BobUsername -DeviceId "codex-ws-bob-a-$suffix"
$bobB = Login-OrRegister -Username $BobUsername -DeviceId "codex-ws-bob-b-$suffix"

$aliceToken = [string]$alice.data.token
$bobAToken = [string]$bobA.data.token
$bobBToken = [string]$bobB.data.token
$bobUuid = [string]$bobA.data.user.uuid

$chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-Ok -Response $chat -Action "create private chat"
$chatId = [string]$chat.data.uuid

$wsA = New-ClientWebSocket -Token $bobAToken
$wsB = New-ClientWebSocket -Token $bobBToken

try {
    Start-Sleep -Milliseconds 300
    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = $chatId
        type = 1
        msg_id = [guid]::NewGuid().ToString()
        content = @{ text = "multidevice ws consistency $suffix" }
    }
    Assert-Ok -Response $send -Action "send ws message"

    $stateA = Wait-ForChatState -Client $wsA -ChatId $chatId
    $stateB = Wait-ForChatState -Client $wsB -ChatId $chatId

    if ([int]$stateA.unread_count -lt 1 -or [int]$stateB.unread_count -lt 1) {
        throw "unexpected unread_count: A=$($stateA.unread_count) B=$($stateB.unread_count)"
    }
    if ([int]$stateA.last_msg_seq -ne [int]$send.data.seq -or [int]$stateB.last_msg_seq -ne [int]$send.data.seq) {
        throw "last_msg_seq mismatch: sent=$($send.data.seq) A=$($stateA.last_msg_seq) B=$($stateB.last_msg_seq)"
    }

    $summary = [pscustomobject]@{
        base_url = $BaseUrl
        ws_url = $WsUrl
        chat_id = $chatId
        sent_seq = [int]$send.data.seq
        device_a_unread = [int]$stateA.unread_count
        device_b_unread = [int]$stateB.unread_count
        device_a_last_msg_seq = [int]$stateA.last_msg_seq
        device_b_last_msg_seq = [int]$stateB.last_msg_seq
    }

    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $json = $summary | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
    Write-Output $json
} finally {
    foreach ($client in @($wsA, $wsB)) {
        if ($client -and $client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $closeTask = $client.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "done",
                [Threading.CancellationToken]::None
            )
            $null = $closeTask.GetAwaiter().GetResult()
        }
        if ($client) { $client.Dispose() }
    }
}
