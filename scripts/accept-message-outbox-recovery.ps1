# 文件用途：在本地 Docker 上验证消息 Outbox 的真实生产、崩溃恢复、幂等重试和阶段重放。
# 核心逻辑：发送唯一群消息后立即终止 API，再检查 pending 恢复；随后伪造已完成数据库阶段的过期租约并验证未读数不重复。

[CmdletBinding()]
param(
    [string]$BaseUrl = "http://127.0.0.1:8080/api/v1",
    [string]$ChatId = "9308452c-4c1a-4f2b-8681-d7537413b10e",
    [string]$ActorUsername = "gload0729124731003",
    [string]$PrivateActorPath = "artifacts/group-message-load/group-load-0729124731-private.json",
    [string]$MediaId = "",
    [string]$OutputPath = "artifacts/real-device-qa/message-outbox-p3-20260729/recovery-result.json"
)

$ErrorActionPreference = "Stop"

function Get-ContainerEnvironment {
    param([Parameter(Mandatory)][string]$Container)
    $result = @{}
    $lines = & docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $Container
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect environment for $Container"
    }
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $result[$matches[1]] = $matches[2]
        }
    }
    return $result
}

$mysqlEnvironment = Get-ContainerEnvironment -Container "genericim-mysql"
$mysqlUser = [string]$mysqlEnvironment["MYSQL_USER"]
$mysqlPassword = [string]$mysqlEnvironment["MYSQL_PASSWORD"]
$mysqlDatabase = [string]$mysqlEnvironment["MYSQL_DATABASE"]
if ([string]::IsNullOrWhiteSpace($mysqlUser) -or
    [string]::IsNullOrWhiteSpace($mysqlPassword) -or
    [string]::IsNullOrWhiteSpace($mysqlDatabase)) {
    throw "MySQL container credentials are incomplete"
}

function Invoke-MySql {
    param([Parameter(Mandatory)][string]$Sql)
    $arguments = @(
        "exec", "genericim-mysql", "mysql",
        "-u$mysqlUser", "-p$mysqlPassword", $mysqlDatabase,
        "-N", "-B", "-e", $Sql
    )
    $output = & docker @arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "MySQL command failed"
    }
    return @($output)
}

function Get-OutboxEvents {
    param([Parameter(Mandatory)][string]$MessageId)
    $sql = @"
SELECT COALESCE(
  JSON_ARRAYAGG(JSON_OBJECT(
    'id', id,
    'event_type', event_type,
    'status', status,
    'attempts', attempts,
    'db_applied', db_applied_at IS NOT NULL,
    'worker_id', worker_id,
    'last_error', last_error
  )),
  JSON_ARRAY()
)
FROM message_outbox_events
WHERE message_id = '$MessageId';
"@
    $line = (Invoke-MySql -Sql $sql | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($line)) {
        return @()
    }
    return @($line | ConvertFrom-Json)
}

function Get-TargetUnread {
    param(
        [Parameter(Mandatory)][string]$TargetUserId,
        [Parameter(Mandatory)][string]$TargetChatId
    )
    $sql = @"
SELECT unread_count
FROM user_chats
WHERE user_id = $TargetUserId
  AND chat_id = (SELECT id FROM chats WHERE uuid = '$TargetChatId' LIMIT 1)
LIMIT 1;
"@
    return [int64](Invoke-MySql -Sql $sql | Select-Object -First 1)
}

function Get-MediaStatus {
    param([Parameter(Mandatory)][string]$TargetMediaId)
    return [string](Invoke-MySql -Sql "SELECT status FROM media_objects WHERE media_id = '$TargetMediaId' LIMIT 1;" | Select-Object -First 1)
}

function Wait-ApiHealthy {
    param([int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $health = & docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' genericim-api 2>$null
        if ($LASTEXITCODE -eq 0 -and $health -eq "healthy") {
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "API did not become healthy in $TimeoutSeconds seconds"
}

function Start-Api {
    & docker compose up -d --no-deps api | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start API"
    }
    Wait-ApiHealthy
}

function Stop-ApiImmediately {
    & docker kill genericim-api | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to terminate API"
    }
}

function Wait-OutboxCompleted {
    param(
        [Parameter(Mandatory)][string]$MessageId,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $events = @(Get-OutboxEvents -MessageId $MessageId)
        if ($events.Count -gt 0 -and @($events | Where-Object status -ne "completed").Count -eq 0) {
            return $events
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw "Outbox events did not complete for message $MessageId"
}

function Get-RedisScanCalls {
    $info = & docker exec genericim-redis redis-cli INFO commandstats
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query Redis commandstats"
    }
    $match = [regex]::Match(($info -join "`n"), 'cmdstat_scan:calls=(\d+)')
    if (-not $match.Success) {
        return 0L
    }
    return [int64]$match.Groups[1].Value
}

$privateData = Get-Content -LiteralPath $PrivateActorPath -Raw -Encoding UTF8 | ConvertFrom-Json
$actor = @($privateData.actors | Where-Object username -eq $ActorUsername | Select-Object -First 1)
if ($actor.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$actor[0].token)) {
    throw "Actor $ActorUsername with a token was not found"
}
$token = [string]$actor[0].token
$senderUuid = [string]$actor[0].user_id

$senderNumericId = [uint64](Invoke-MySql -Sql "SELECT id FROM users WHERE uuid = '$senderUuid' LIMIT 1;" | Select-Object -First 1)
$targetRowJson = Invoke-MySql -Sql @"
SELECT JSON_OBJECT('user_id', user_id, 'unread_count', unread_count)
FROM user_chats
WHERE chat_id = (SELECT id FROM chats WHERE uuid = '$ChatId' LIMIT 1)
  AND user_id <> $senderNumericId
ORDER BY user_id ASC
LIMIT 1;
"@ | Select-Object -First 1
$targetRow = $targetRowJson | ConvertFrom-Json
$targetUserId = [string]$targetRow.user_id
$unreadBefore = [int64]$targetRow.unread_count
$scanBefore = Get-RedisScanCalls

$messageId = [guid]::NewGuid().ToString()
$request = @{
    chat_id = $ChatId
    type = 1
    msg_id = $messageId
    content = @{
        text = "P3 outbox restart acceptance $messageId"
    }
}
if (-not [string]::IsNullOrWhiteSpace($MediaId)) {
    $request.type = 2
    $request.content = @{
        media = @{
            media_id = $MediaId
            url = "https://untrusted.invalid/outbox-fixture.png"
            size = 1009
            mime_type = "image/png"
            width = 24
            height = 24
        }
    }
}
$requestBody = $request | ConvertTo-Json -Depth 6 -Compress

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$sendResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/message/send" `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json; charset=utf-8" `
    -Body $requestBody
$stopwatch.Stop()
if ([int]$sendResponse.code -ne 0) {
    throw "Message send failed with code $($sendResponse.code)"
}

Stop-ApiImmediately
$eventsAfterCrash = @(Get-OutboxEvents -MessageId $messageId)
$unreadAfterCrash = Get-TargetUnread -TargetUserId $targetUserId -TargetChatId $ChatId
if ($eventsAfterCrash.Count -eq 0) {
    throw "Producer did not persist outbox events before ACK"
}

Start-Api
$eventsAfterRecovery = @(Wait-OutboxCompleted -MessageId $messageId)
$unreadAfterRecovery = Get-TargetUnread -TargetUserId $targetUserId -TargetChatId $ChatId
if ($unreadAfterRecovery -ne ($unreadBefore + 1)) {
    throw "Unread projection mismatch after recovery: before=$unreadBefore after=$unreadAfterRecovery"
}
$mediaStatusAfterRecovery = ""
if (-not [string]::IsNullOrWhiteSpace($MediaId)) {
    $mediaStatusAfterRecovery = Get-MediaStatus -TargetMediaId $MediaId
    if ($mediaStatusAfterRecovery -ne "bound") {
        throw "Media was not bound after recovery: media_id=$MediaId status=$mediaStatusAfterRecovery"
    }
}

$duplicateResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/message/send" `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json; charset=utf-8" `
    -Body $requestBody
if ([int]$duplicateResponse.code -ne 0) {
    throw "Duplicate retry failed with code $($duplicateResponse.code)"
}
Start-Sleep -Milliseconds 800
$eventsAfterDuplicate = @(Get-OutboxEvents -MessageId $messageId)
$unreadAfterDuplicate = Get-TargetUnread -TargetUserId $targetUserId -TargetChatId $ChatId
if ($eventsAfterDuplicate.Count -ne $eventsAfterRecovery.Count) {
    throw "Duplicate retry created extra outbox events"
}
if ($unreadAfterDuplicate -ne $unreadAfterRecovery) {
    throw "Duplicate retry changed unread count"
}

Stop-ApiImmediately
Invoke-MySql -Sql @"
UPDATE message_outbox_events
SET status = 'processing',
    worker_id = 'crashed-worker-acceptance',
    lease_until = UTC_TIMESTAMP(3) - INTERVAL 1 SECOND,
    completed_at = NULL
WHERE message_id = '$messageId'
  AND event_type = 'projection'
  AND db_applied_at IS NOT NULL;
"@ | Out-Null
$unreadBeforeStageReplay = Get-TargetUnread -TargetUserId $targetUserId -TargetChatId $ChatId
Start-Api
$eventsAfterStageReplay = @(Wait-OutboxCompleted -MessageId $messageId)
$unreadAfterStageReplay = Get-TargetUnread -TargetUserId $targetUserId -TargetChatId $ChatId
if ($unreadAfterStageReplay -ne $unreadBeforeStageReplay) {
    throw "Expired lease replay duplicated the unread projection"
}

$scanAfter = Get-RedisScanCalls
$result = [ordered]@{
    run_at = (Get-Date).ToString("o")
    chat_id = $ChatId
    message_id = $messageId
    message_type = if ([string]::IsNullOrWhiteSpace($MediaId)) { "text" } else { "image" }
    media_id = $MediaId
    media_status_after_recovery = $mediaStatusAfterRecovery
    ack_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
    target_user_id = $targetUserId
    unread = [ordered]@{
        before = $unreadBefore
        immediately_after_crash = $unreadAfterCrash
        after_recovery = $unreadAfterRecovery
        after_duplicate_retry = $unreadAfterDuplicate
        before_stage_replay = $unreadBeforeStageReplay
        after_stage_replay = $unreadAfterStageReplay
    }
    events = [ordered]@{
        immediately_after_crash = $eventsAfterCrash
        after_recovery = $eventsAfterRecovery
        after_duplicate_retry = $eventsAfterDuplicate
        after_stage_replay = $eventsAfterStageReplay
    }
    redis_scan = [ordered]@{
        before = $scanBefore
        after = $scanAfter
        delta = $scanAfter - $scanBefore
    }
    assertions = [ordered]@{
        ack_persisted_events = $true
        restart_recovered_all_events = $true
        unread_applied_once = $true
        duplicate_retry_did_not_add_events = $true
        expired_lease_stage_replay_did_not_repeat_projection = $true
        media_bound_after_restart = ([string]::IsNullOrWhiteSpace($MediaId) -or $mediaStatusAfterRecovery -eq "bound")
        redis_scan_delta_zero = (($scanAfter - $scanBefore) -eq 0)
    }
}

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
