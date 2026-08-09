<#
.SYNOPSIS
验证真实登录流程中的两步验证启用、挑战和关闭闭环。

.DESCRIPTION
使用指定账号开启二次密码，断言主密码登录只能获得临时 ticket，再用二次密码
完成登录，最后尽力恢复运行前状态。脚本会修改目标账号安全设置，不应对生产账号
或无法人工恢复的账号运行。

.PARAMETER Username
专用测试账号用户名。

.PARAMETER PrimaryPassword
账号主密码，仅用于本次请求，不会写入输出文件。

.PARAMETER SecondaryPassword
本轮设置并验证的二次密码。

.EXAMPLE
pwsh -File scripts/validate-two-step-auth.ps1 -Username qa_user -PrimaryPassword '***' -SecondaryPassword '***'
#>
<#
.SYNOPSIS
验证真实账号的两步验证启用、挑战登录、错误密码和关闭闭环。

.DESCRIPTION
脚本会临时为指定账号启用二级密码并执行多轮登录断言，最后尝试恢复原状态。
必须使用专用测试账号；中途终止后应检查二级密码是否仍处于启用状态。

.PARAMETER Username
用于验证的测试账号。

.PARAMETER PrimaryPassword
账号主密码。

.PARAMETER SecondaryPassword
测试期间设置的二级密码，不应与生产密码相同。

.EXAMPLE
pwsh -File scripts/validate-two-step-auth.ps1 -Username test_user -PrimaryPassword '***' -SecondaryPassword '***'
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080/api/v1",
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$PrimaryPassword,
    [Parameter(Mandatory = $true)]
    [string]$SecondaryPassword
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")
$script:EnabledByRun = $false
$script:CleanupToken = $null
$script:LastTicket = $null

function Invoke-AppApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST")]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [hashtable]$Body = @{},
        [string]$Token = ""
    )

    $headers = @{}
    if ($Token) {
        $headers.Authorization = "Bearer $Token"
    }

    $request = @{
        Uri               = "$BaseUrl$Path"
        Method            = $Method
        Headers           = $headers
        ContentType       = "application/json"
        SkipHttpErrorCheck = $true
    }
    if ($Method -eq "POST") {
        $request.Body = $Body | ConvertTo-Json -Depth 8 -Compress
    }

    $response = Invoke-WebRequest @request
    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        throw "Empty API response: $Method $Path (HTTP $($response.StatusCode))"
    }

    return $response.Content | ConvertFrom-Json
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-PrimaryLogin {
    param([string]$DeviceId)
    return Invoke-AppApi -Method POST -Path "/auth/login" -Body @{
        username    = $Username
        password    = $PrimaryPassword
        device_id   = $DeviceId
        device_name = "Two-step integration test"
        device_type = "android"
    }
}

function Invoke-TwoStepVerify {
    param(
        [string]$Ticket,
        [string]$Password
    )
    return Invoke-AppApi -Method POST -Path "/auth/two-step/verify" -Body @{
        ticket   = $Ticket
        password = $Password
    }
}

function Disable-TestTwoStep {
    param([string]$Token)
    if (-not $Token) {
        return $false
    }
    $result = Invoke-AppApi -Method POST -Path "/user/two-step/disable" -Token $Token -Body @{
        password = $SecondaryPassword
    }
    return $result.code -eq 0
}

$runId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$checks = [ordered]@{}

try {
    $initialLogin = Invoke-PrimaryLogin -DeviceId "two-step-setup-$runId"
    if ($initialLogin.code -eq 1007) {
        $existingVerify = Invoke-TwoStepVerify -Ticket ([string]$initialLogin.data.verify_ticket) -Password $SecondaryPassword
        Assert-Condition ($existingVerify.code -eq 0) "The test account already has a different two-step password"
        $existingToken = [string]$existingVerify.data.token
        Assert-Condition (Disable-TestTwoStep -Token $existingToken) "Could not normalize the existing test two-step state"
        $initialLogin = Invoke-PrimaryLogin -DeviceId "two-step-setup-reset-$runId"
    }
    Assert-Condition ($initialLogin.code -eq 0) "Initial login failed: code=$($initialLogin.code), message=$($initialLogin.message)"
    $setupToken = [string]$initialLogin.data.token
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($setupToken)) "Initial login did not return a token"
    $checks.initial_login = "PASS"

    $enable = Invoke-AppApi -Method POST -Path "/user/two-step/enable" -Token $setupToken -Body @{
        current_password = $PrimaryPassword
        password         = $SecondaryPassword
        hint             = "integration-test"
    }
    Assert-Condition ($enable.code -eq 0) "Enable failed: code=$($enable.code), message=$($enable.message)"
    $script:EnabledByRun = $true
    $checks.enable = "PASS"

    $challengedLogin = Invoke-PrimaryLogin -DeviceId "two-step-challenge-$runId"
    Assert-Condition ($challengedLogin.code -eq 1007) "Primary login was not blocked: code=$($challengedLogin.code)"
    Assert-Condition ([string]::IsNullOrWhiteSpace([string]$challengedLogin.data.token)) "Blocked login unexpectedly returned a token"
    $ticket = [string]$challengedLogin.data.verify_ticket
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($ticket)) "Challenge did not return a verification ticket"
    $script:LastTicket = $ticket
    $checks.primary_login_blocked = "PASS"

    $wrong = Invoke-TwoStepVerify -Ticket $ticket -Password "definitely-wrong-secondary-password"
    Assert-Condition ($wrong.code -ne 0) "Wrong secondary password unexpectedly succeeded"
    Assert-Condition ([string]::IsNullOrWhiteSpace([string]$wrong.data.token)) "Wrong secondary password unexpectedly returned a token"
    $checks.wrong_password_rejected = "PASS"

    $verified = Invoke-TwoStepVerify -Ticket $ticket -Password $SecondaryPassword
    Assert-Condition ($verified.code -eq 0) "Correct secondary password failed: code=$($verified.code), message=$($verified.message)"
    $verifiedToken = [string]$verified.data.token
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($verifiedToken)) "Correct secondary password did not return a token"
    $script:CleanupToken = $verifiedToken
    $checks.correct_password_accepted = "PASS"

    $replay = Invoke-TwoStepVerify -Ticket $ticket -Password $SecondaryPassword
    Assert-Condition ($replay.code -ne 0) "Consumed verification ticket was replayed successfully"
    Assert-Condition ([string]::IsNullOrWhiteSpace([string]$replay.data.token)) "Replayed ticket unexpectedly returned a token"
    $checks.ticket_replay_rejected = "PASS"

    $disabled = Disable-TestTwoStep -Token $verifiedToken
    Assert-Condition $disabled "Disable failed"
    $script:EnabledByRun = $false
    $checks.disable = "PASS"

    $finalLogin = Invoke-PrimaryLogin -DeviceId "two-step-final-$runId"
    Assert-Condition ($finalLogin.code -eq 0) "Login after disable failed: code=$($finalLogin.code), message=$($finalLogin.message)"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$finalLogin.data.token)) "Login after disable did not return a token"
    $checks.login_after_disable = "PASS"

    [ordered]@{
        result = "PASS"
        checks = $checks
    } | ConvertTo-Json -Depth 5
}
finally {
    if ($script:EnabledByRun) {
        try {
            if (-not $script:CleanupToken) {
                $cleanupLogin = Invoke-PrimaryLogin -DeviceId "two-step-cleanup-$runId"
                if ($cleanupLogin.code -eq 1007) {
                    $cleanupVerify = Invoke-TwoStepVerify -Ticket ([string]$cleanupLogin.data.verify_ticket) -Password $SecondaryPassword
                    if ($cleanupVerify.code -eq 0) {
                        $script:CleanupToken = [string]$cleanupVerify.data.token
                    }
                }
            }
            if (Disable-TestTwoStep -Token $script:CleanupToken) {
                $script:EnabledByRun = $false
            }
        }
        catch {
            Write-Warning "Automatic cleanup failed: $($_.Exception.Message)"
        }
    }
}
