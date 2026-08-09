<#
.SYNOPSIS
验证本地 P2 后端包的认证、会话及关键兼容 API。

.DESCRIPTION
以两个测试设备登录专用账号，调用 P2 验收清单中的接口并输出 JSON 结果。
脚本会在目标后端创建设备会话和业务测试数据，默认端口面向本地 Docker 包。

.PARAMETER BaseUrl
后端根地址，不包含尾部斜杠。

.PARAMETER OutputPath
保存各接口响应摘要和断言结果的 JSON 文件。

.EXAMPLE
pwsh -File scripts/validate-p2-backend-api.ps1 -BaseUrl http://127.0.0.1:18080
#>
<#
.SYNOPSIS
验证本地 P2 后端部署后的认证、会话和核心 API 行为。

.DESCRIPTION
使用双测试账号调用认证和业务接口，将响应与断言写入 JSON，供后端二进制热替换后
快速回归。脚本会在目标数据库创建测试会话和数据，不应指向生产环境。

.PARAMETER BaseUrl
本地后端根地址，不包含结尾斜杠。

.PARAMETER OutputPath
保存 API 响应摘要与断言结果的 JSON 文件。

.PARAMETER PeerUsername
与主测试账号建立业务关系的对端账号。

.EXAMPLE
pwsh -File scripts/validate-p2-backend-api.ps1 -BaseUrl http://127.0.0.1:18080
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:18080",
    [string]$Username = "smoke_bob",
    [string]$PeerUsername = "smoke_alice",
    [string]$Password = "Smoke123",
    [string]$OutputPath = "artifacts/p2-local-backend/api-validation.json"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $params = @{
        Method = $Method
        Uri = "$BaseUrl$Path"
        TimeoutSec = 20
        Headers = @{}
    }
    if ($Token) { $params.Headers.Authorization = "Bearer $Token" }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = $Body | ConvertTo-Json -Depth 30 -Compress
    }
    $response = Invoke-RestMethod @params
    if ([int]$response.code -ne 0) {
        throw "$Method $Path failed: code=$($response.code) message=$($response.message)"
    }
    return $response
}

function Login-Device {
    param([string]$User, [string]$DeviceId, [string]$DeviceName)

    return Invoke-Api -Method POST -Path "/api/v1/auth/login" -Body @{
        username = $User
        password = $Password
        device_id = $DeviceId
        device_type = "android"
        device_name = $DeviceName
    }
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-PublicJwk {
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $parameters = $rsa.ExportParameters($false)
        return @{
            kty = "RSA"
            n = ConvertTo-Base64Url -Bytes $parameters.Modulus
            e = ConvertTo-Base64Url -Bytes $parameters.Exponent
        } | ConvertTo-Json -Compress
    } finally {
        $rsa.Dispose()
    }
}

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$sourceDeviceId = "p2-source-$stamp"
$requesterDeviceId = "p2-requester-$stamp"
$peerDeviceId = "p2-peer-$stamp"

$sourceLogin = Login-Device -User $Username -DeviceId $sourceDeviceId -DeviceName "P2 Trusted Device"
$requesterLogin = Login-Device -User $Username -DeviceId $requesterDeviceId -DeviceName "P2 New Device"
$peerLogin = Login-Device -User $PeerUsername -DeviceId $peerDeviceId -DeviceName "P2 Peer Device"
$sourceToken = [string]$sourceLogin.data.token
$requesterToken = [string]$requesterLogin.data.token
$peerUuid = [string]$peerLogin.data.user.uuid

$capabilities = Invoke-Api -Method GET -Path "/api/v1/message/recovery-capabilities" -Token $sourceToken
if ([int]$capabilities.data.retention_months -ne 120) {
    throw "Unexpected retention months: $($capabilities.data.retention_months)"
}
if ([int]$capabilities.data.idempotency_months -lt [int]$capabilities.data.retention_months) {
    throw "Idempotency window is shorter than message retention."
}

$chat = Invoke-Api -Method POST -Path "/api/v1/chat/create" -Token $sourceToken -Body @{
    type = 1
    member_ids = @($peerUuid)
}
$chatId = [string]$chat.data.uuid
$clientMsgId = [guid]::NewGuid().ToString()
$sendBody = @{
    chat_id = $chatId
    type = 1
    msg_id = $clientMsgId
    content = @{ text = "p2 idempotency smoke $stamp" }
}
$firstSend = Invoke-Api -Method POST -Path "/api/v1/message/send" -Token $sourceToken -Body $sendBody
$secondSend = Invoke-Api -Method POST -Path "/api/v1/message/send" -Token $sourceToken -Body $sendBody
if ($secondSend.data.duplicate -ne $true) {
    throw "Repeated client msg id was not acknowledged as duplicate."
}
if ([string]$firstSend.data.msg_id -ne [string]$secondSend.data.msg_id -or
    [string]$firstSend.data.server_seq -ne [string]$secondSend.data.server_seq) {
    throw "Repeated send returned a different server message."
}

$sourcePublicJwk = New-PublicJwk
$requesterPublicJwk = New-PublicJwk
$sourceKey = Invoke-Api -Method PUT -Path "/api/v1/user/e2ee/device-key" -Token $sourceToken -Body @{
    public_key = $sourcePublicJwk
    algo = "rsa-jwk-oaep-2048"
}
$request = Invoke-Api -Method POST -Path "/api/v1/user/e2ee/recovery/requests" -Token $requesterToken -Body @{
    public_key = $requesterPublicJwk
    algo = "rsa-jwk-oaep-2048"
}
$requestId = [string]$request.data.request_id

$sourceList = Invoke-Api -Method GET -Path "/api/v1/user/e2ee/recovery/requests" -Token $sourceToken
$pending = @($sourceList.data.requests) | Where-Object { $_.request_id -eq $requestId -and $_.status -eq "pending" }
if ($pending.Count -ne 1 -or $pending[0].is_requester -eq $true) {
    throw "Trusted device did not receive the pending recovery request."
}

$opaquePayload = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes("opaque-p2-recovery-$stamp"))
$approval = Invoke-Api -Method POST -Path "/api/v1/user/e2ee/recovery/requests/$requestId/approve" -Token $sourceToken -Body @{
    encrypted_payload = $opaquePayload
    payload_algo = "rsa-jwk-oaep-2048"
}
$requesterList = Invoke-Api -Method GET -Path "/api/v1/user/e2ee/recovery/requests" -Token $requesterToken
$approved = @($requesterList.data.requests) | Where-Object { $_.request_id -eq $requestId -and $_.status -eq "approved" }
if ($approved.Count -ne 1 -or [string]$approved[0].encrypted_payload -ne $opaquePayload) {
    throw "Requester did not receive the approved opaque recovery payload."
}
if ([string]$approved[0].source_key_fingerprint -ne [string]$sourceKey.data.fingerprint) {
    throw "Recovery response source key fingerprint mismatch."
}

$null = Invoke-Api -Method POST -Path "/api/v1/user/e2ee/recovery/requests/$requestId/consume" -Token $requesterToken
$null = Invoke-Api -Method DELETE -Path "/api/v1/user/e2ee/device-key" -Token $sourceToken

$summary = [ordered]@{
    retention_months = [int]$capabilities.data.retention_months
    idempotency_months = [int]$capabilities.data.idempotency_months
    e2ee_recovery_mode = [string]$capabilities.data.e2ee_recovery_mode
    chat_id = $chatId
    client_msg_id = $clientMsgId
    server_seq = $firstSend.data.server_seq
    duplicate_ack = [bool]$secondSend.data.duplicate
    recovery_request_id = $requestId
    recovery_status = [string]$approval.data.status
    source_key_version = $sourceKey.data.key_version
    source_key_fingerprint = [string]$sourceKey.data.fingerprint
    source_device_revoked = $true
}

$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path $OutputPath
}
$parent = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 -LiteralPath $resolvedOutput

Write-Host "P2 backend API validation passed." -ForegroundColor Green
Write-Host "Evidence: $resolvedOutput"
$summary | ConvertTo-Json -Depth 10
