<#
.SYNOPSIS
验证通话运行时数据在 API、MySQL 和 MongoDB 中不存在乱码。

.DESCRIPTION
使用双测试账号创建并结束通话，读取接口与数据库中的相关文本字段，再输出
JSON 证据。脚本会创建通话和设备记录，并要求本地数据库容器可访问。

.PARAMETER MysqlContainer
保存账号与通话元数据的 MySQL 测试容器。

.PARAMETER MongoContainer
保存消息正文的 MongoDB 测试容器。

.PARAMETER OutputPath
保存 API 和数据库编码断言的 JSON 文件。

.EXAMPLE
pwsh -File scripts/smoke_call_mojibake_runtime.ps1
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$AliceUsername = "cmalice",
    [string]$BobUsername = "cmbob",
    [string]$Password = "Smoke123",
    [string]$MysqlContainer = "genericim-mysql",
    [string]$MongoContainer = "genericim-mongodb",
    [string]$OutputPath = "build/smoke/call-mojibake-runtime.json"
)

$ErrorActionPreference = "Stop"

function Join-ApiUrl {
    param([string]$BaseUrl, [string]$Path)
    return "$($BaseUrl.TrimEnd('/'))$Path"
}

function ConvertTo-CompactJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 30 -Compress)
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
        Uri = (Join-ApiUrl -BaseUrl $script:BaseUrl -Path $Path)
        Headers = $headers
        TimeoutSec = 30
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
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        throw "$Action failed: $(ConvertTo-CompactJson -Value $Response)"
    }
}

function New-LoginBody {
    param([string]$Username)
    return @{
        username = $Username
        password = $script:Password
        device_id = "codex-call-mojibake-$Username"
        device_type = "android"
        device_name = "Codex Call Mojibake Smoke"
    }
}

function Login-OrRegister {
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
        device_id = "codex-call-mojibake-$Username"
        device_type = "android"
        device_name = "Codex Call Mojibake Smoke"
    }
    Assert-ApiSuccess -Response $register -Action "register $Username"

    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body (New-LoginBody -Username $Username)
    Assert-ApiSuccess -Response $login -Action "login $Username"
    return $login
}

function New-SmokeUsername {
    param([string]$Prefix, [string]$Suffix)
    $cleanPrefix = ($Prefix -replace '[^A-Za-z0-9_]', '')
    if ([string]::IsNullOrWhiteSpace($cleanPrefix)) {
        $cleanPrefix = "cmuser"
    }
    $maxPrefixLength = [Math]::Max(1, 20 - $Suffix.Length)
    if ($cleanPrefix.Length -gt $maxPrefixLength) {
        $cleanPrefix = $cleanPrefix.Substring(0, $maxPrefixLength)
    }
    return "$cleanPrefix$Suffix"
}

function Invoke-MysqlScalar {
    param([string]$Sql)
    $result = $Sql | docker exec -i $script:MysqlContainer mysql -ugenericim -pgenericim --default-character-set=utf8mb4 -N -B genericim
    $last = $result | Select-Object -Last 1
    if ($null -eq $last) {
        return ""
    }
    return ([string]$last).Trim()
}

function Invoke-MysqlScript {
    param([string]$Sql)
    return $Sql | docker exec -i $script:MysqlContainer mysql -ugenericim -pgenericim --default-character-set=utf8mb4 genericim
}

function Set-TestRtcConfig {
    $keys = @(
        "rtc_provider",
        "agora_enabled",
        "agora_app_id",
        "agora_app_certificate",
        "agora_token_expire"
    )
    $quotedKeys = "'" + ($keys -join "','") + "'"
    $backupSql = "SELECT CONCAT_WS(CHAR(9), ``key``, COALESCE(value, ''), COALESCE(type, 'string'), COALESCE(remark, '')) FROM system_settings WHERE ``key`` IN ($quotedKeys) ORDER BY ``key``;"
    $script:OriginalRtcSettings = @($backupSql | docker exec -i $script:MysqlContainer mysql -ugenericim -pgenericim --default-character-set=utf8mb4 -N -B genericim)

    $deleteSql = "DELETE FROM system_settings WHERE ``key`` IN ($quotedKeys);"
    Invoke-MysqlScript -Sql $deleteSql | Out-Null

    $now = "NOW()"
    $insertSql = @"
INSERT INTO system_settings (``key``, value, type, remark, created_at, updated_at)
VALUES
('rtc_provider', 'agora', 'string', 'codex smoke rtc provider', $now, $now),
('agora_enabled', 'true', 'bool', 'codex smoke agora enabled', $now, $now),
('agora_app_id', '0123456789abcdef0123456789abcdef', 'string', 'codex smoke app id', $now, $now),
('agora_app_certificate', '0123456789abcdef0123456789abcdef', 'string', 'codex smoke app certificate', $now, $now),
('agora_token_expire', '3600', 'int', 'codex smoke token expire', $now, $now);
"@
    Invoke-MysqlScript -Sql $insertSql | Out-Null
}

function Restore-RtcConfig {
    if ($null -eq $script:OriginalRtcSettings) {
        return
    }
    $keys = @(
        "rtc_provider",
        "agora_enabled",
        "agora_app_id",
        "agora_app_certificate",
        "agora_token_expire"
    )
    $quotedKeys = "'" + ($keys -join "','") + "'"
    Invoke-MysqlScript -Sql "DELETE FROM system_settings WHERE ``key`` IN ($quotedKeys);" | Out-Null
    foreach ($line in $script:OriginalRtcSettings) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = $line -split "`t", 4
        $key = ($parts[0] -replace "'", "''")
        $value = ($parts[1] -replace "'", "''")
        $type = ($parts[2] -replace "'", "''")
        $remark = ($parts[3] -replace "'", "''")
        $sql = "INSERT INTO system_settings (``key``, value, type, remark, created_at, updated_at) VALUES ('$key', '$value', '$type', '$remark', NOW(), NOW());"
        Invoke-MysqlScript -Sql $sql | Out-Null
    }
}

function Get-MysqlRemainingCounts {
    $sql = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\backend\scripts\check_mojibake_remaining.sql")
    $output = Invoke-MysqlScript -Sql $sql
    $userChats = 0
    $pushLogs = 0
    for ($i = 0; $i -lt $output.Count; $i++) {
        if ($output[$i] -match '^user_chats_remaining$' -and ($i + 1) -lt $output.Count) {
            $userChats = [int]$output[$i + 1]
        }
        if ($output[$i] -match '^push_delivery_logs_remaining$' -and ($i + 1) -lt $output.Count) {
            $pushLogs = [int]$output[$i + 1]
        }
    }
    return [pscustomobject]@{
        user_chats_remaining = $userChats
        push_delivery_logs_remaining = $pushLogs
        raw = @($output)
    }
}

function Get-MongoRemainingCount {
    $scriptPath = Join-Path $PSScriptRoot "..\backend\scripts\check_mojibake_remaining_mongo.js"
    docker cp $scriptPath "$($script:MongoContainer):/tmp/check_mojibake_remaining_mongo.js" | Out-Null
    try {
        $output = docker exec $script:MongoContainer mongosh --quiet "mongodb://genericim:genericim@127.0.0.1:27017/genericim_messages?authSource=admin" /tmp/check_mojibake_remaining_mongo.js
    } finally {
        docker exec $script:MongoContainer rm -f /tmp/check_mojibake_remaining_mongo.js | Out-Null
    }
    $remaining = 0
    foreach ($line in $output) {
        if ($line -match '^mongo_remaining=(\d+)$') {
            $remaining = [int]$Matches[1]
        }
    }
    return [pscustomobject]@{
        mongo_remaining = $remaining
        raw = @($output)
    }
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$health = Invoke-RestMethod -Uri (Join-ApiUrl -BaseUrl $BaseUrl -Path "/health") -TimeoutSec 8
if ($health.status -ne "ok") {
    throw "Backend health is not ok: $(ConvertTo-CompactJson -Value $health)"
}

$script:OriginalRtcSettings = $null
$restored = $false

try {
    Set-TestRtcConfig

    $suffix = Get-Date -Format "MMddHHmmss"
    $aliceLogin = Login-OrRegister -Username (New-SmokeUsername -Prefix $AliceUsername -Suffix $suffix)
    $bobLogin = Login-OrRegister -Username (New-SmokeUsername -Prefix $BobUsername -Suffix $suffix)
    $aliceToken = [string]$aliceLogin.data.token
    $bobUuid = [string]$bobLogin.data.user.uuid
    if ([string]::IsNullOrWhiteSpace($aliceToken) -or [string]::IsNullOrWhiteSpace($bobUuid)) {
        throw "Login response did not include token or bob UUID."
    }

    $create = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $aliceToken -Body @{
        target_user_id = $bobUuid
        call_type = "voice"
    }
    Assert-ApiSuccess -Response $create -Action "create voice call"
    $callId = [string]$create.data.call_id
    if ([string]::IsNullOrWhiteSpace($callId)) {
        throw "Create call response did not include call_id: $(ConvertTo-CompactJson -Value $create)"
    }

    $cancel = Invoke-ApiJson -Method "DELETE" -Path "/api/v1/call/$callId" -Token $aliceToken
    Assert-ApiSuccess -Response $cancel -Action "cancel voice call"
    if ([string]$cancel.data.message -ne "取消成功") {
        throw "cancel call response message is not repaired: $($cancel.data.message)"
    }

    Start-Sleep -Seconds 2

    $mysqlCounts = Get-MysqlRemainingCounts
    $mongoCounts = Get-MongoRemainingCount

    if ($mysqlCounts.user_chats_remaining -ne 0 -or $mysqlCounts.push_delivery_logs_remaining -ne 0 -or $mongoCounts.mongo_remaining -ne 0) {
        throw "Mojibake remained after call smoke: mysql=$(ConvertTo-CompactJson -Value $mysqlCounts) mongo=$(ConvertTo-CompactJson -Value $mongoCounts)"
    }

    $callMessageText = Invoke-MysqlScalar -Sql "SELECT last_msg_text FROM user_chats ORDER BY last_msg_time DESC LIMIT 1;"
    $summary = [pscustomobject]@{
        alice = [string]$aliceLogin.data.user.username
        alice_uuid = [string]$aliceLogin.data.user.uuid
        bob = [string]$bobLogin.data.user.username
        bob_uuid = $bobUuid
        call_id = $callId
        cancel_message = [string]$cancel.data.message
        latest_call_preview = $callMessageText
        mysql = $mysqlCounts
        mongo = $mongoCounts
    }

    $summaryJson = $summary | ConvertTo-Json -Depth 20
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding utf8
    }

    Write-Output $summaryJson
} finally {
    Restore-RtcConfig
    $restored = $true
    if ($restored) {
        Write-Host "[call-mojibake-smoke] restored RTC settings"
    }
}
