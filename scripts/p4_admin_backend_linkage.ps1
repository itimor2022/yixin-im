<#
.SYNOPSIS
验证运营后台管理操作与后端用户状态的联动。

.DESCRIPTION
使用管理员账号调用后台 API，对测试用户执行查询和状态操作，再从客户端侧
接口验证生效结果并保存报告。该脚本可能封禁、冻结或修改测试用户数据，
严禁使用生产管理员和真实用户。

.PARAMETER AdminUsername
具备验收所需权限的本地测试管理员。

.PARAMETER TestUserKeyword
限制目标用户搜索范围的唯一测试关键字。

.PARAMETER OutputDir
保存管理请求、客户端验证和恢复结果的目录。

.EXAMPLE
pwsh -File scripts/p4_admin_backend_linkage.ps1 -TestUserKeyword p4_qa
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$OutputDir = "release-archives\qa-20260624\real-device-p0-p3\p4-admin-backend-linkage",
    [string]$AdminUsername = "admin",
    [string]$AdminPassword = "123456",
    [string]$TestUserKeyword = "p3"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$runId = (Get-Date).ToString("yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = "", [object]$Data = $null)
    $results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        data = $Data
    }) | Out-Null
}

function Invoke-ApiJson {
    param([string]$Method, [string]$Path, [object]$Body = $null, [string]$Token = "")
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers.Authorization = "Bearer $Token" }
    $params = @{
        Method = $Method
        Uri = "$($BaseUrl.TrimEnd('/'))$Path"
        Headers = $headers
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = ($Body | ConvertTo-Json -Depth 30)
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try { return ($_.ErrorDetails.Message | ConvertFrom-Json) } catch {}
        }
        throw
    }
}

function Assert-Code {
    param([object]$Resp, [string]$Action, [int]$Expected = 0)
    if ($null -eq $Resp -or [int]$Resp.code -ne $Expected) {
        throw "$Action expected code=$Expected got: $($Resp | ConvertTo-Json -Depth 20 -Compress)"
    }
}

$health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 10
if ($health.status -ne "ok") { throw "Backend health is not ok" }
Add-Result -Name "Backend health" -Status "PASS" -Detail "health ok"

$login = Invoke-ApiJson -Method "POST" -Path "/api/v1/admin/login" -Body @{
    username = $AdminUsername
    password = $AdminPassword
}
Assert-Code -Resp $login -Action "admin login"
$adminToken = [string]$login.data.token
Add-Result -Name "Admin login" -Status "PASS" -Detail "admin=$AdminUsername role=$($login.data.admin.role)"

$me = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/me" -Token $adminToken
Assert-Code -Resp $me -Action "admin me"
Add-Result -Name "Admin profile" -Status "PASS" -Detail "id=$($me.data.id), role=$($me.data.role)"

$userList = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/users/list?page=1&page_size=10&keyword=$([uri]::EscapeDataString($TestUserKeyword))" -Token $adminToken
Assert-Code -Resp $userList -Action "admin user list"
Add-Result -Name "Admin user list" -Status "PASS" -Detail "total=$($userList.data.total), keyword=$TestUserKeyword" -Data $userList.data

$chatList = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/chats/list?page=1&page_size=10" -Token $adminToken
Assert-Code -Resp $chatList -Action "admin chat list"
Add-Result -Name "Admin chat list" -Status "PASS" -Detail "total=$($chatList.data.total)" -Data $chatList.data

$walletStats = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/stats" -Token $adminToken
Assert-Code -Resp $walletStats -Action "admin wallet stats"
Add-Result -Name "Admin wallet stats" -Status "PASS" -Detail "wallet stats loaded" -Data $walletStats.data

$walletUsers = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/users?page=1&page_size=10&keyword=$([uri]::EscapeDataString($TestUserKeyword))" -Token $adminToken
Assert-Code -Resp $walletUsers -Action "admin wallet users"
Add-Result -Name "Admin wallet users" -Status "PASS" -Detail "wallet user list loaded for $TestUserKeyword" -Data $walletUsers.data

$withdrawStats = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/withdraw/stats" -Token $adminToken
Assert-Code -Resp $withdrawStats -Action "admin withdraw stats"
Add-Result -Name "Admin withdraw stats" -Status "PASS" -Detail "withdraw stats loaded" -Data $withdrawStats.data

$withdrawList = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/withdraw/list?page=1&page_size=10" -Token $adminToken
Assert-Code -Resp $withdrawList -Action "admin withdraw list"
Add-Result -Name "Admin withdraw list" -Status "PASS" -Detail "total=$($withdrawList.data.total)" -Data $withdrawList.data

$rechargeOrders = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/recharge-orders?page=1&page_size=10" -Token $adminToken
Assert-Code -Resp $rechargeOrders -Action "admin recharge orders"
Add-Result -Name "Admin recharge orders" -Status "PASS" -Detail "recharge orders loaded" -Data $rechargeOrders.data

$redPackets = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/red-packets?page=1&page_size=10" -Token $adminToken
Assert-Code -Resp $redPackets -Action "admin red packets"
Add-Result -Name "Admin red packets" -Status "PASS" -Detail "red packet list loaded" -Data $redPackets.data

$transfers = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/wallet/transfers?page=1&page_size=10" -Token $adminToken
Assert-Code -Resp $transfers -Action "admin transfers"
Add-Result -Name "Admin transfers" -Status "PASS" -Detail "transfer list loaded" -Data $transfers.data

$vipPlans = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/vip/plans" -Token $adminToken
Assert-Code -Resp $vipPlans -Action "admin vip plans"
Add-Result -Name "Admin VIP plans" -Status "PASS" -Detail "vip plans loaded" -Data $vipPlans.data

$broadcasts = Invoke-ApiJson -Method "GET" -Path "/api/v1/admin/broadcast/list?page=1&page_size=10" -Token $adminToken
Assert-Code -Resp $broadcasts -Action "admin broadcast list"
Add-Result -Name "Admin broadcast list" -Status "PASS" -Detail "broadcast list loaded" -Data $broadcasts.data

$pass = @($results | Where-Object { $_.status -eq "PASS" }).Count
$warn = @($results | Where-Object { $_.status -eq "WARN" }).Count
$fail = @($results | Where-Object { $_.status -eq "FAIL" }).Count
$status = if ($fail -gt 0) { "FAIL" } elseif ($warn -gt 0) { "WARN" } else { "PASS" }

$summary = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    run_id = $runId
    status = $status
    pass = $pass
    warn = $warn
    fail = $fail
    admin = $AdminUsername
    test_user_keyword = $TestUserKeyword
    results = $results
}

$jsonPath = Join-Path $OutputDir "p4-admin-backend-linkage-$runId.json"
$summary | ConvertTo-Json -Depth 40 | Set-Content -Encoding UTF8 -Path $jsonPath

$reportPath = Join-Path $OutputDir "report.md"
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# P4 Admin Backend Linkage") | Out-Null
$md.Add("") | Out-Null
$md.Add("- time: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))") | Out-Null
$md.Add("- status: $status") | Out-Null
$md.Add("- summary: PASS=$pass, WARN=$warn, FAIL=$fail") | Out-Null
$md.Add("- json: ``$jsonPath``") | Out-Null
$md.Add("") | Out-Null
$md.Add("| Item | Status | Detail |") | Out-Null
$md.Add("| --- | --- | --- |") | Out-Null
foreach ($r in $results) {
    $detail = ($r.detail -replace "\|", "/").Trim()
    $md.Add("| $($r.name) | $($r.status) | $detail |") | Out-Null
}
$md | Set-Content -Encoding UTF8 -Path $reportPath

Write-Host "P4 admin status: $status PASS=$pass WARN=$warn FAIL=$fail"
Write-Host "Report: $reportPath"
Write-Host "JSON: $jsonPath"
if ($fail -gt 0) { exit 1 }
