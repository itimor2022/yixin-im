#Requires -Version 7.0
<#
.SYNOPSIS
验证短信验证码注册和登录的后端闭环。

.DESCRIPTION
通过本地 API 触发验证码流程，从本地 Redis 测试容器读取验证码，完成注册、
登录和清理测试账号。脚本依赖可控的本地 Docker 环境，不适用于真实短信渠道
或生产 Redis。

.PARAMETER BaseUrl
本地测试后端 API v1 根地址。

.EXAMPLE
pwsh -File scripts/real-device-qa/Verify-SmsRegistrationLogin.ps1
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1'
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')

function Invoke-ApiJson {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null,
        [string]$Token = ''
    )

    $request = @{
        Method = $Method
        Uri = "$BaseUrl$Path"
        TimeoutSec = 30
        Headers = @{}
    }
    if ($Token) {
        $request.Headers.Authorization = "Bearer $Token"
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = $Body | ConvertTo-Json -Depth 12
    }
    Invoke-RestMethod @request
}

function Assert-ApiCode {
    param(
        [object]$Response,
        [int]$Expected,
        [string]$Action
    )
    if ($null -eq $Response -or [int]$Response.code -ne $Expected) {
        throw "$Action returned an unexpected response: $($Response | ConvertTo-Json -Depth 12 -Compress)"
    }
}

function Get-RedisCode {
    # 直接读取 Redis 仅用于本地自动化，不能作为生产短信流程的验证方式。
    param([Parameter(Mandatory = $true)][string]$Key)
    $args = @('exec', 'genericim-redis', 'redis-cli', '--raw', 'GET', $Key)
    $value = ((& docker @args) | Select-Object -First 1).Trim('"').Trim()
    if ($LASTEXITCODE -ne 0 -or $value -notmatch '^\d{6}$') {
        throw "Unable to read verification code for $Key"
    }
    $value
}

function Remove-TestAccount {
    param(
        [string]$Token,
        [string]$UserUuid
    )
    if (-not $Token -or -not $UserUuid) {
        return
    }
    $send = Invoke-ApiJson -Method 'POST' -Path '/user/account/send-delete-code' -Token $Token
    Assert-ApiCode -Response $send -Expected 0 -Action 'send account deletion code'
    $code = Get-RedisCode -Key "verify:delete_account:$UserUuid"
    $delete = Invoke-ApiJson -Method 'DELETE' -Path "/user/account?code=$code" -Token $Token
    Assert-ApiCode -Response $delete -Expected 0 -Action 'delete temporary account'
}

$runId = Get-Date -Format 'yyyyMMddHHmmss'
$username = "smsflow$($runId.Substring(4))"
$password = 'SmsFlow!Pass123'
$phoneSeed = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 1000000000)
$phone = '19' + $phoneSeed.ToString('D9')
$token = ''
$userUuid = ''

try {
    $health = Invoke-RestMethod -Uri ($BaseUrl -replace '/api/v1$', '/health') -TimeoutSec 8
    if ($health.status -ne 'ok') {
        throw 'Backend health check failed'
    }

    $send = Invoke-ApiJson -Method 'POST' -Path '/auth/register/send-code' -Body @{
        phone = $phone
    }
    Assert-ApiCode -Response $send -Expected 0 -Action 'send registration code'
    $code = Get-RedisCode -Key "auth:register:sms:$phone"

    $wrongCode = if ($code -eq '000000') { '000001' } else { '000000' }
    $wrong = Invoke-ApiJson -Method 'POST' -Path '/auth/register/verify-code' -Body @{
        phone = $phone
        sms_code = $wrongCode
    }
    Assert-ApiCode -Response $wrong -Expected 400 -Action 'reject incorrect registration code'

    $valid = Invoke-ApiJson -Method 'POST' -Path '/auth/register/verify-code' -Body @{
        phone = $phone
        sms_code = $code
    }
    Assert-ApiCode -Response $valid -Expected 0 -Action 'accept correct registration code'
    if ($valid.data.verified -ne $true) {
        throw 'Correct registration code did not return verified=true'
    }

    $register = Invoke-ApiJson -Method 'POST' -Path '/auth/register' -Body @{
        username = $username
        password = $password
        nickname = 'SMS Registration Flow QA'
        gender = 'male'
        phone = $phone
        sms_code = $code
        device_id = "sms-register-$runId"
        device_type = 'ios'
        device_name = 'iPhone Registration QA'
    }
    Assert-ApiCode -Response $register -Expected 0 -Action 'register with verified SMS code'
    $token = [string]$register.data.token
    $userUuid = [string]$register.data.user.uuid
    if (-not $token -or -not $userUuid -or [string]$register.data.user.phone -ne $phone) {
        throw 'Registration did not return a complete authenticated user payload'
    }

    $login = Invoke-ApiJson -Method 'POST' -Path '/auth/login' -Body @{
        username = $username
        password = $password
        device_id = "sms-login-$runId"
        device_type = 'ios'
        device_name = 'iPhone Login QA'
    }
    Assert-ApiCode -Response $login -Expected 0 -Action 'login after SMS registration'
    $token = [string]$login.data.token
    if (-not $token -or [string]$login.data.user.uuid -ne $userUuid) {
        throw 'Login did not return the registered authenticated user'
    }

    [ordered]@{
        status = 'PASS'
        wrong_code_rejected = $true
        correct_code_verified = $true
        registration_authenticated = $true
        subsequent_ios_login_authenticated = $true
        user_uuid = $userUuid
    } | ConvertTo-Json -Depth 4
}
finally {
    Remove-TestAccount -Token $token -UserUuid $userUuid
}
