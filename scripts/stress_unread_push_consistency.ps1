<#
.SYNOPSIS
压力验证消息未读数、已读回执与推送日志的一致性。

.DESCRIPTION
使用双测试账号连续发送消息，并在限流时退避重试，最终将未读和推送观测
结果写入 JSON。脚本会在目标后端创建消息与推送日志，不应对生产账号运行。

.PARAMETER MessageCount
本轮连续发送的消息数量。

.PARAMETER SendDelayMs
相邻请求间隔；过小可能触发服务端限流。

.PARAMETER OutputPath
保存一致性断言和原始观测结果的 JSON 文件。

.EXAMPLE
pwsh -File scripts/stress_unread_push_consistency.ps1 -MessageCount 20
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "stress_alice",
    [string]$BobUsername = "stress_bob",
    [string]$Password = "Smoke123",
    [int]$MessageCount = 20,
    [int]$SendDelayMs = 300,
    [string]$OutputPath = "build/smoke/unread-push-consistency.json"
)

$ErrorActionPreference = "Stop"

function Join-ApiUrl {
    param([string]$Path)
    return "$($script:BaseUrl.TrimEnd('/'))$Path"
}

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
        Uri = (Join-ApiUrl -Path $Path)
        Headers = $headers
        TimeoutSec = 30
    }

    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 20)
    }

    for ($attempt = 1; $attempt -le 8; $attempt++) {
        # 429 使用线性退避重试；其他错误立即失败，避免掩盖真实一致性问题。
        try {
            return Invoke-RestMethod @params
        } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $detail = "$detail $($_.ErrorDetails.Message)"
            }
            if ($detail -match '"code"\s*:\s*429' -or $detail -match '\b429\b') {
                $sleepSeconds = [Math]::Min(30, 3 * $attempt)
                Write-Host "[stress] rate limited, retrying in ${sleepSeconds}s (attempt $attempt/8)" -ForegroundColor Yellow
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
        device_name = "Codex Consistency $DeviceId"
    }

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) {
        return $login
    }

    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $script:Password
        nickname = $Username
        gender = "male"
        device_id = $DeviceId
        device_type = "android"
        device_name = "Codex Consistency $DeviceId"
    }
    Assert-Ok -Response $register -Action "register $Username"

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-Ok -Response $login -Action "login $Username"
    return $login
}

function Get-ChatFromList {
    param([string]$Token, [string]$ChatId, [switch]$AllowMissing)
    $resp = Invoke-ApiJson -Method "GET" -Path "/api/v1/chat/list?page=1&page_size=100" -Token $Token
    Assert-Ok -Response $resp -Action "chat list"
    $items = if ($resp.data -and $resp.data.list) { @($resp.data.list) } else { @($resp.data) }
    foreach ($item in $items) {
        if ([string]$item.chat_id -eq $ChatId -or [string]$item.uuid -eq $ChatId -or [string]$item.id -eq $ChatId) {
            return $item
        }
    }
    if ($AllowMissing) {
        return $null
    }
    throw "chat $ChatId not found in list"
}

if ($MessageCount -lt 1) {
    throw "MessageCount must be >= 1"
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$health = Invoke-RestMethod -Uri (Join-ApiUrl -Path "/health") -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok: $($health | ConvertTo-Json -Compress)"
}

$suffix = Get-Date -Format "yyyyMMddHHmmss"
$alice = Login-OrRegister -Username $AliceUsername -DeviceId "codex-stress-alice-$suffix"
$bobA = Login-OrRegister -Username $BobUsername -DeviceId "codex-stress-bob-a-$suffix"
$bobB = Login-OrRegister -Username $BobUsername -DeviceId "codex-stress-bob-b-$suffix"

$aliceToken = [string]$alice.data.token
$bobAToken = [string]$bobA.data.token
$bobBToken = [string]$bobB.data.token
$bobUuid = [string]$bobA.data.user.uuid

foreach ($entry in @(
    @{ token = $bobAToken; device = "codex-stress-bob-a-$suffix"; push = "codex-fcm-token-a-$suffix" },
    @{ token = $bobBToken; device = "codex-stress-bob-b-$suffix"; push = "codex-fcm-token-b-$suffix" }
)) {
    $pushResp = Invoke-ApiJson -Method "POST" -Path "/api/v1/user/push-token" -Token $entry.token -Body @{
        device_id = $entry.device
        device_type = "android"
        push_token = $entry.push
        push_channel = "fcm"
    }
    Assert-Ok -Response $pushResp -Action "bind push token $($entry.device)"
}

$chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{
    type = 1
    member_ids = @($bobUuid)
}
Assert-Ok -Response $chat -Action "create private chat"
$chatId = [string]$chat.data.uuid

$baselineA = Get-ChatFromList -Token $bobAToken -ChatId $chatId -AllowMissing
$baselineUnread = if ($null -eq $baselineA) { 0 } else { [int]$baselineA.unread_count }

$lastSeq = 0
for ($i = 1; $i -le $MessageCount; $i++) {
    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{
        chat_id = $chatId
        type = 1
        msg_id = [guid]::NewGuid().ToString()
        content = @{ text = "unread consistency $suffix #$i" }
    }
    Assert-Ok -Response $send -Action "send message $i"
    $lastSeq = [int]$send.data.seq
    if ($SendDelayMs -gt 0) {
        Start-Sleep -Milliseconds $SendDelayMs
    }
}

Start-Sleep -Milliseconds 500

$afterA = Get-ChatFromList -Token $bobAToken -ChatId $chatId
$afterB = Get-ChatFromList -Token $bobBToken -ChatId $chatId
$expectedUnread = $baselineUnread + $MessageCount
if ([int]$afterA.unread_count -ne $expectedUnread) {
    throw "bob device A unread=$($afterA.unread_count), expected $expectedUnread"
}
if ([int]$afterB.unread_count -ne $expectedUnread) {
    throw "bob device B unread=$($afterB.unread_count), expected $expectedUnread"
}
if ([int]$afterA.last_msg_seq -ne $lastSeq -or [int]$afterB.last_msg_seq -ne $lastSeq) {
    throw "last_msg_seq mismatch: A=$($afterA.last_msg_seq) B=$($afterB.last_msg_seq) expected=$lastSeq"
}

$read = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/read" -Token $bobAToken -Body @{
    chat_id = $chatId
    msg_seq = $lastSeq
}
Assert-Ok -Response $read -Action "mark read"

Start-Sleep -Milliseconds 500

$readA = Get-ChatFromList -Token $bobAToken -ChatId $chatId
$readB = Get-ChatFromList -Token $bobBToken -ChatId $chatId
if ([int]$readA.unread_count -ne 0 -or [int]$readB.unread_count -ne 0) {
    throw "unread not cleared across devices: A=$($readA.unread_count) B=$($readB.unread_count)"
}

$summary = [pscustomobject]@{
    base_url = $BaseUrl
    chat_id = $chatId
    message_count = $MessageCount
    send_delay_ms = $SendDelayMs
    baseline_unread = $baselineUnread
    expected_unread_after_send = $expectedUnread
    device_a_unread_after_send = [int]$afterA.unread_count
    device_b_unread_after_send = [int]$afterB.unread_count
    last_msg_seq = $lastSeq
    device_a_unread_after_read = [int]$readA.unread_count
    device_b_unread_after_read = [int]$readB.unread_count
    push_tokens_bound = 2
}

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
$summaryJson = $summary | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding utf8
Write-Output $summaryJson
