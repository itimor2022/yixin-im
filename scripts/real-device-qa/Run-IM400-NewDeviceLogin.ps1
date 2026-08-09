<#
.SYNOPSIS
验证同一账号在新设备登录后的会话、WebSocket 和旧设备状态。

.DESCRIPTION
通过 API 创建多个设备登录并建立 WebSocket，执行 IM-400 新设备场景断言，
将事件和响应写入 JSON。脚本会创建测试设备会话并可能触发设备安全策略，
只能使用专用测试账号。

.PARAMETER BaseUrl
测试后端 API v1 根地址。

.PARAMETER WsUrl
与 BaseUrl 指向同一实例的 WebSocket 地址。

.PARAMETER OutputPath
保存设备会话、事件和断言结果的 JSON 文件。

.EXAMPLE
pwsh -File scripts/real-device-qa/Run-IM400-NewDeviceLogin.ps1
#>
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$WsUrl = 'ws://127.0.0.1:8080/api/v1/ws',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ''
    )

    $headers = @{}
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $request = @{
        Method = $Method
        Uri = "$BaseUrl$Path"
        Headers = $headers
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = $Body | ConvertTo-Json -Depth 12
    }
    return Invoke-RestMethod @request
}

function Assert-ApiOk {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        throw "$Action failed: $($Response | ConvertTo-Json -Depth 12 -Compress)"
    }
}

function New-LoginBody {
    param([string]$Username, [string]$Password, [string]$DeviceId, [string]$DeviceName)
    return @{
        username = $Username
        password = $Password
        device_id = $DeviceId
        device_type = 'android'
        device_name = $DeviceName
    }
}

function New-ClientWebSocket {
    param([string]$Token)
    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    $encodedToken = [Uri]::EscapeDataString($Token)
    $uri = [Uri]"$WsUrl`?device_type=android&token=$encodedToken"
    $null = $client.ConnectAsync($uri, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
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
    }
    catch [OperationCanceledException] {
        return $null
    }
    finally {
        $cts.Dispose()
    }
}

function Wait-NewDeviceLoginEvent {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Client,
        [int]$TimeoutSeconds = 10
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $remainingMs = [Math]::Max(1, [int](($deadline - (Get-Date)).TotalMilliseconds))
        $message = Receive-JsonMessage -Client $Client -TimeoutMs $remainingMs
        if ($null -eq $message) { return $null }
        if ($null -ne $message -and $message.type -eq 'new_device_login') {
            return $message
        }
    }
    return $null
}

function Remove-TestAccount {
    param([string]$Token, [string]$UserUuid)
    if (-not $Token -or -not $UserUuid) { return }
    $send = Invoke-ApiJson -Method 'POST' -Path '/user/account/send-delete-code' -Token $Token
    Assert-ApiOk -Response $send -Action 'send delete account code'
    $redisArgs = @(
        'exec'
        'genericim-redis'
        'redis-cli'
        '--raw'
        'GET'
        "verify:delete_account:$UserUuid"
    )
    $code = ((& docker @redisArgs) | Select-Object -First 1).Trim('"').Trim()
    if ($LASTEXITCODE -ne 0 -or $code -notmatch '^\d{6}$') {
        throw 'Unable to read delete account verification code'
    }
    $delete = Invoke-ApiJson -Method 'DELETE' -Path "/user/account?code=$code" -Token $Token
    Assert-ApiOk -Response $delete -Action 'delete temporary account'
}

$health = Invoke-RestMethod -Uri ($BaseUrl -replace '/api/v1$', '/health') -TimeoutSec 8
if ($health.status -ne 'ok') { throw 'Backend health check failed' }

$runId = Get-Date -Format 'yyyyMMddHHmmss'
$username = "devlogin$($runId.Substring(4))"
$password = 'Round11!Pass123'
$phoneSeed = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 1000000000)
$phone = '19' + $phoneSeed.ToString('D9')
$deviceA = "round11-a-$runId"
$deviceB = "round11-b-$runId"
$deviceAName = 'Round 11 Huawei A'
$deviceBName = 'Round 11 Huawei B'
$token = ''
$userUuid = ''
$wsA = $null

try {
    $sendRegisterCode = Invoke-ApiJson -Method 'POST' -Path '/auth/register/send-code' -Body @{ phone = $phone }
    Assert-ApiOk -Response $sendRegisterCode -Action 'send registration code'
    $registrationRedisArgs = @('exec', 'genericim-redis', 'redis-cli', '--raw', 'GET', "auth:register:sms:$phone")
    $registrationCode = ((& docker @registrationRedisArgs) | Select-Object -First 1).Trim('"').Trim()
    if ($LASTEXITCODE -ne 0 -or $registrationCode -notmatch '^\d{6}$') {
        throw 'Unable to read registration verification code'
    }
    $register = Invoke-ApiJson -Method 'POST' -Path '/auth/register' -Body @{
        username = $username
        password = $password
        nickname = 'Round 11 Device Login QA'
        gender = 'male'
        phone = $phone
        sms_code = $registrationCode
        device_id = $deviceA
        device_type = 'android'
        device_name = $deviceAName
    }
    Assert-ApiOk -Response $register -Action 'register device A'
    $tokenA = [string]$register.data.token
    $token = $tokenA
    $userUuid = [string]$register.data.user.uuid
    $wsA = New-ClientWebSocket -Token $tokenA
    Start-Sleep -Milliseconds 500

    $loginB = Invoke-ApiJson -Method 'POST' -Path '/auth/login' -Body (New-LoginBody -Username $username -Password $password -DeviceId $deviceB -DeviceName $deviceBName)
    Assert-ApiOk -Response $loginB -Action 'first login on device B'
    $token = [string]$loginB.data.token
    $event = Wait-NewDeviceLoginEvent -Client $wsA -TimeoutSeconds 10
    if ($null -eq $event) { throw 'Device A did not receive new_device_login event' }
    if ([string]$event.device_id -ne $deviceB) { throw "Unexpected event device_id: $($event.device_id)" }
    if ([string]$event.device_name -ne $deviceBName) { throw "Unexpected event device_name: $($event.device_name)" }
    if ([string]$event.device_type -ne 'android') { throw "Unexpected event device_type: $($event.device_type)" }
    if (-not [string]$event.event_id -or -not [string]$event.occurred_at -or -not [string]$event.ip) {
        throw "Event audit context is incomplete: $($event | ConvertTo-Json -Compress)"
    }
    if ([string]$loginB.data.multi_device_policy -ne 'coexist' -or [int]$loginB.data.other_active_device_count -ne 1) {
        throw 'Device B login did not report the expected coexistence context'
    }

    $repeatLoginB = Invoke-ApiJson -Method 'POST' -Path '/auth/login' -Body (New-LoginBody -Username $username -Password $password -DeviceId $deviceB -DeviceName $deviceBName)
    Assert-ApiOk -Response $repeatLoginB -Action 'repeat login on device B'
    $token = [string]$repeatLoginB.data.token
    $duplicateEvent = Wait-NewDeviceLoginEvent -Client $wsA -TimeoutSeconds 3
    if ($null -ne $duplicateEvent) {
        throw "Repeat login generated a duplicate new-device event: $($duplicateEvent | ConvertTo-Json -Compress)"
    }

    if (-not $OutputPath) {
        $OutputPath = "artifacts/real-device-qa/local-docker-dual-device-20260717/new-device-login/new-device-login-$runId.json"
    }
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $result = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        base_url = $BaseUrl
        ws_url = $WsUrl
        summary = @{ passed = 1; failed = 0 }
        cases = @(
            [ordered]@{
                case_id = 'IM-031'
                name = '新设备登录提醒'
                status = 'PASS'
                detail = '旧设备收到准确的新设备登录 WebSocket 安全提醒；同一物理设备重复登录不重复提醒。'
                evidence = @{
                    event_id = [string]$event.event_id
                    device_id = [string]$event.device_id
                    device_name = [string]$event.device_name
                    device_type = [string]$event.device_type
                    ip = [string]$event.ip
                    occurred_at = [string]$event.occurred_at
                    repeat_login_duplicate_event = $false
                }
            }
        )
    }
    $json = $result | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
    Write-Output $json
}
finally {
    if ($wsA) {
        if ($wsA.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $closeTask = $wsA.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                'done',
                [Threading.CancellationToken]::None
            )
            $null = $closeTask.GetAwaiter().GetResult()
        }
        $wsA.Dispose()
    }
    Remove-TestAccount -Token $token -UserUuid $userUuid
}
