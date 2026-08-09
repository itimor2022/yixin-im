<#
.SYNOPSIS
验证账号和业务对象进入删除、冻结、退出等破坏性状态后的系统行为。

.DESCRIPTION
通过 API 和 MySQL 容器准备 P3 边界状态，执行断言并输出报告。脚本会直接
修改测试数据库和账号状态，可能无法仅靠重新登录恢复；严禁指向生产环境。

.PARAMETER BaseUrl
与 MysqlContainer 对应的本地测试后端。

.PARAMETER OutputDir
保存破坏性操作、响应和恢复结果的证据目录。

.PARAMETER MysqlContainer
允许被本脚本修改的本地 MySQL 测试容器。

.EXAMPLE
pwsh -File scripts/p3_destructive_state_flows.ps1 -BaseUrl http://127.0.0.1:8080
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$OutputDir = "release-archives\qa-20260624\real-device-p0-p3\p3-destructive-state-flows",
    [string]$MysqlContainer = "genericim-mysql",
    [string]$MysqlUser = "root",
    [string]$MysqlPassword = "genericim_root",
    [string]$MysqlDatabase = "genericim"
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
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try { return Invoke-RestMethod @params } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = "$detail $($_.ErrorDetails.Message)" }
            if ($detail -match '\b429\b') {
                Start-Sleep -Seconds ([Math]::Min(20, $attempt * 3))
                continue
            }
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try { return ($_.ErrorDetails.Message | ConvertFrom-Json) } catch {}
            }
            throw
        }
    }
    throw "$Method $Path failed after retries"
}

function Assert-Code {
    param([object]$Resp, [string]$Action, [int]$Expected = 0)
    if ($null -eq $Resp -or [int]$Resp.code -ne $Expected) {
        throw "$Action expected code=$Expected got: $($Resp | ConvertTo-Json -Depth 20 -Compress)"
    }
}

function Register-Or-Login {
    param([string]$Username, [string]$Nickname, [string]$DeviceId)
    $password = "Smoke123"
    $loginBody = @{
        username = $Username
        password = $password
        device_id = $DeviceId
        device_type = "android"
        device_name = "P3 destructive API"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $loginBody
    if ([int]$login.code -eq 0) { return $login }
    $reg = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $password
        nickname = $Nickname
        gender = "male"
        device_id = $DeviceId
        device_type = "android"
        device_name = "P3 destructive API"
    }
    Assert-Code -Resp $reg -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $loginBody
    Assert-Code -Resp $login -Action "login $Username"
    return $login
}

function Invoke-Mysql {
    param([string]$Sql)
    $args = @(
        "exec", $MysqlContainer,
        "mysql", "-u$MysqlUser", "-p$MysqlPassword", "-N", "-B", $MysqlDatabase,
        "-e", $Sql
    )
    $out = & docker @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "mysql failed: $out"
    }
    $clean = @($out | Where-Object { $_ -notmatch '^mysql:\s+\[Warning\]' })
    return ($clean -join "`n").Trim()
}

function Set-TestWallet {
    param([string]$UserUuid, [double]$Balance)
    $sql = @"
SET @uid = (SELECT id FROM users WHERE uuid = '$UserUuid' LIMIT 1);
INSERT INTO wallets (user_id, balance, frozen_balance, pay_password, is_locked, created_at, updated_at)
VALUES (@uid, $Balance, 0, '', 0, NOW(), NOW())
ON DUPLICATE KEY UPDATE balance = VALUES(balance), frozen_balance = 0, is_locked = 0, updated_at = NOW();
"@
    [void](Invoke-Mysql -Sql $sql)
}

function Set-TestVip {
    param([string]$UserUuid, [int]$Level = 2)
    $planCode = if ($Level -ge 2) { "svip_month" } else { "vip_month" }
    $sql = @"
SET @uid = (SELECT id FROM users WHERE uuid = '$UserUuid' LIMIT 1);
SET @plan = (SELECT id FROM vip_plans WHERE code = '$planCode' AND deleted_at IS NULL LIMIT 1);
INSERT INTO user_vip_memberships (user_id, plan_id, level, source, status, started_at, expired_at, canceled_at, remark, created_at, updated_at)
VALUES (@uid, @plan, $Level, 'qa', 'active', NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY), NULL, 'P3 highest-permission isolated test account', NOW(), NOW())
ON DUPLICATE KEY UPDATE plan_id = VALUES(plan_id), level = VALUES(level), source = 'qa', status = 'active', started_at = NOW(), expired_at = VALUES(expired_at), canceled_at = NULL, remark = VALUES(remark), updated_at = NOW();
"@
    [void](Invoke-Mysql -Sql $sql)
}

function Get-TestWallet {
    param([string]$UserUuid)
    $sql = "SELECT COALESCE(w.balance,0), COALESCE(w.frozen_balance,0), IF(w.pay_password IS NULL OR w.pay_password='',0,1) FROM users u LEFT JOIN wallets w ON w.user_id=u.id WHERE u.uuid='$UserUuid' LIMIT 1;"
    $raw = Invoke-Mysql -Sql $sql
    $parts = @($raw -split "`t")
    return [pscustomobject]@{
        balance = [double]$parts[0]
        frozen_balance = [double]$parts[1]
        has_pay_password = ([int]$parts[2] -eq 1)
    }
}

$health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 10
if ($health.status -ne "ok") { throw "Backend health is not ok" }

$suffix = (Get-Date).ToString("MMddHHmmss")
$aliceName = "p3a_$suffix"
$bobName = "p3b_$suffix"
$charlieName = "p3c_$suffix"
$payPassword = "135790"

$alice = Register-Or-Login -Username $aliceName -Nickname "P3 Destructive Alice" -DeviceId "p3-destr-a-$suffix"
$bob = Register-Or-Login -Username $bobName -Nickname "P3 Destructive Bob" -DeviceId "p3-destr-b-$suffix"
$charlie = Register-Or-Login -Username $charlieName -Nickname "P3 Destructive Charlie" -DeviceId "p3-destr-c-$suffix"

$aliceToken = [string]$alice.data.token
$bobToken = [string]$bob.data.token
$charlieToken = [string]$charlie.data.token
$aliceUuid = [string]$alice.data.user.uuid
$bobUuid = [string]$bob.data.user.uuid
$charlieUuid = [string]$charlie.data.user.uuid

Add-Result -Name "Create isolated test accounts" -Status "PASS" -Detail "$aliceName, $bobName, $charlieName" -Data @{ alice = $aliceUuid; bob = $bobUuid; charlie = $charlieUuid }

Set-TestWallet -UserUuid $aliceUuid -Balance 100
Set-TestWallet -UserUuid $bobUuid -Balance 0
Set-TestWallet -UserUuid $charlieUuid -Balance 0
Set-TestVip -UserUuid $aliceUuid -Level 2
$walletBaseAlice = Get-TestWallet -UserUuid $aliceUuid
Add-Result -Name "Prepare isolated wallet balance" -Status "PASS" -Detail "Alice test balance set to 100.00 via local test DB only." -Data $walletBaseAlice
Add-Result -Name "Prepare isolated SVIP permission" -Status "PASS" -Detail "Alice test account promoted to SVIP by local test DB only for group/channel entitlement checks."

$setPay = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/pay-password" -Token $aliceToken -Body @{ password = $payPassword }
Assert-Code -Resp $setPay -Action "set pay password"
$verifyBad = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/verify-password" -Token $aliceToken -Body @{ password = "000000" }
$verifyGood = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/verify-password" -Token $aliceToken -Body @{ password = $payPassword }
Assert-Code -Resp $verifyGood -Action "verify pay password"
Add-Result -Name "Payment password set and verify" -Status ($(if ([int]$verifyBad.code -ne 0) { "PASS" } else { "FAIL" })) -Detail "Wrong password rejected; correct password accepted." -Data @{ bad_code = $verifyBad.code; good_code = $verifyGood.code }

$privateChat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{ type = 1; member_ids = @($bobUuid) }
Assert-Code -Resp $privateChat -Action "create private chat"
$privateChatId = [string]$privateChat.data.uuid
Add-Result -Name "Private chat create for destructive wallet flows" -Status "PASS" -Detail "chat=$privateChatId"

$msgId = [guid]::NewGuid().ToString()
$msgText = "p3-delete-$runId"
$sendMsg = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $aliceToken -Body @{ chat_id = $privateChatId; type = 1; msg_id = $msgId; content = @{ text = $msgText } }
Assert-Code -Resp $sendMsg -Action "send deletable message"
Start-Sleep -Seconds 1
$deleteMsg = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/delete" -Token $aliceToken -Body @{ chat_id = $privateChatId; msg_id = $msgId }
Assert-Code -Resp $deleteMsg -Action "delete own message"
$aliceListAfterDelete = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$privateChatId&limit=50" -Token $aliceToken
Assert-Code -Resp $aliceListAfterDelete -Action "list after delete"
$deletedVisible = (($aliceListAfterDelete.data | ConvertTo-Json -Depth 30 -Compress) -match [regex]::Escape($msgText))
Add-Result -Name "Message delete confirmation" -Status ($(if (-not $deletedVisible) { "PASS" } else { "FAIL" })) -Detail "Message deleted for current user visibility." -Data @{ msg_id = $msgId; visible_after_delete = $deletedVisible }

$block = Invoke-ApiJson -Method "POST" -Path "/api/v1/user/blocked" -Token $aliceToken -Body @{ user_id = $bobUuid }
Assert-Code -Resp $block -Action "block user"
$blockCheck = Invoke-ApiJson -Method "GET" -Path "/api/v1/user/blocked/check?user_id=$bobUuid" -Token $aliceToken
Assert-Code -Resp $blockCheck -Action "check block"
$unblock = Invoke-ApiJson -Method "DELETE" -Path "/api/v1/user/blocked/$bobUuid" -Token $aliceToken
Assert-Code -Resp $unblock -Action "unblock user"
$blockCheckAfter = Invoke-ApiJson -Method "GET" -Path "/api/v1/user/blocked/check?user_id=$bobUuid" -Token $aliceToken
Assert-Code -Resp $blockCheckAfter -Action "check unblock"
Add-Result -Name "Block and unblock user" -Status ($(if ($blockCheck.data.is_blocked -eq $true -and $blockCheckAfter.data.is_blocked -eq $false) { "PASS" } else { "FAIL" })) -Detail "Block became true, then restored to false." -Data @{ blocked = $blockCheck.data.is_blocked; after_unblock = $blockCheckAfter.data.is_blocked }

$group = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $aliceToken -Body @{ type = 2; name = "P3 destructive group $suffix"; member_ids = @($bobUuid); is_public = $false }
Assert-Code -Resp $group -Action "create group"
$groupId = [string]$group.data.uuid
$membersBefore = Invoke-ApiJson -Method "GET" -Path "/api/v1/chat/$groupId/members" -Token $aliceToken
Assert-Code -Resp $membersBefore -Action "members before"
$addMember = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/$groupId/members" -Token $aliceToken -Body @{ user_ids = @($charlieUuid) }
Assert-Code -Resp $addMember -Action "add group member"
$membersAfterAdd = Invoke-ApiJson -Method "GET" -Path "/api/v1/chat/$groupId/members" -Token $aliceToken
Assert-Code -Resp $membersAfterAdd -Action "members after add"
$removeMember = Invoke-ApiJson -Method "DELETE" -Path "/api/v1/chat/$groupId/members/$charlieUuid" -Token $aliceToken
Assert-Code -Resp $removeMember -Action "remove group member"
$membersAfterRemove = Invoke-ApiJson -Method "GET" -Path "/api/v1/chat/$groupId/members" -Token $aliceToken
Assert-Code -Resp $membersAfterRemove -Action "members after remove"
$afterAddHasCharlie = (($membersAfterAdd.data | ConvertTo-Json -Depth 30 -Compress) -match [regex]::Escape($charlieUuid))
$afterRemoveHasCharlie = (($membersAfterRemove.data | ConvertTo-Json -Depth 30 -Compress) -match [regex]::Escape($charlieUuid))
Add-Result -Name "Group member add/remove restore" -Status ($(if ($afterAddHasCharlie -and -not $afterRemoveHasCharlie) { "PASS" } else { "FAIL" })) -Detail "Charlie added then removed from isolated test group." -Data @{ group = $groupId; after_add = $afterAddHasCharlie; after_remove = $afterRemoveHasCharlie }

$rpBeforeAlice = Get-TestWallet -UserUuid $aliceUuid
$red = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/red-packet/send" -Token $aliceToken -Body @{ chat_id = $groupId; type = "normal"; total_amount = 1.00; total_count = 1; message = "p3 destructive red packet"; pay_password = $payPassword }
Assert-Code -Resp $red -Action "send red packet"
$redId = [string]$red.data.id
$redClaim = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/red-packet/$redId/claim" -Token $bobToken
Assert-Code -Resp $redClaim -Action "claim red packet"
$redDetail = Invoke-ApiJson -Method "GET" -Path "/api/v1/wallet/red-packet/$redId" -Token $aliceToken
Assert-Code -Resp $redDetail -Action "red packet detail"
$rpAfterAlice = Get-TestWallet -UserUuid $aliceUuid
$rpAfterBob = Get-TestWallet -UserUuid $bobUuid
Add-Result -Name "Red packet send and claim" -Status ($(if ($redDetail.data.status -eq "finished" -and [Math]::Round($rpBeforeAlice.balance - $rpAfterAlice.balance, 2) -eq 1.00 -and [Math]::Round($rpAfterBob.balance, 2) -ge 1.00) { "PASS" } else { "FAIL" })) -Detail "Sent 1.00 red packet and Bob claimed it." -Data @{ red_packet = $redId; before_alice = $rpBeforeAlice; after_alice = $rpAfterAlice; after_bob = $rpAfterBob; status = $redDetail.data.status }

$transferBeforeAlice = Get-TestWallet -UserUuid $aliceUuid
$transferBeforeBob = Get-TestWallet -UserUuid $bobUuid
$transfer = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/transfer/send" -Token $aliceToken -Body @{ receiver_id = $bobUuid; amount = 2.00; remark = "p3 destructive transfer"; pay_password = $payPassword }
Assert-Code -Resp $transfer -Action "send transfer"
$transferId = [string]$transfer.data.id
$transferAccept = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/transfer/$transferId/accept" -Token $bobToken
Assert-Code -Resp $transferAccept -Action "accept transfer"
$transferDetail = Invoke-ApiJson -Method "GET" -Path "/api/v1/wallet/transfer/$transferId" -Token $aliceToken
Assert-Code -Resp $transferDetail -Action "transfer detail"
$transferAfterAlice = Get-TestWallet -UserUuid $aliceUuid
$transferAfterBob = Get-TestWallet -UserUuid $bobUuid
Add-Result -Name "Transfer send and accept" -Status ($(if ($transferDetail.data.status -eq "accepted" -and [Math]::Round($transferBeforeAlice.balance - $transferAfterAlice.balance, 2) -eq 2.00 -and [Math]::Round($transferAfterBob.balance - $transferBeforeBob.balance, 2) -eq 2.00) { "PASS" } else { "FAIL" })) -Detail "Alice sent 2.00 and Bob accepted." -Data @{ transfer = $transferId; before_alice = $transferBeforeAlice; after_alice = $transferAfterAlice; before_bob = $transferBeforeBob; after_bob = $transferAfterBob; status = $transferDetail.data.status }

$transferRejectBeforeAlice = Get-TestWallet -UserUuid $aliceUuid
$transferReject = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/transfer/send" -Token $aliceToken -Body @{ receiver_id = $bobUuid; amount = 1.50; remark = "p3 destructive reject"; pay_password = $payPassword }
Assert-Code -Resp $transferReject -Action "send reject transfer"
$transferRejectId = [string]$transferReject.data.id
$reject = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/transfer/$transferRejectId/reject" -Token $bobToken
Assert-Code -Resp $reject -Action "reject transfer"
$transferRejectAfterAlice = Get-TestWallet -UserUuid $aliceUuid
$rejectDetail = Invoke-ApiJson -Method "GET" -Path "/api/v1/wallet/transfer/$transferRejectId" -Token $aliceToken
Assert-Code -Resp $rejectDetail -Action "reject transfer detail"
Add-Result -Name "Transfer reject refund" -Status ($(if ($rejectDetail.data.status -eq "rejected" -and [Math]::Round($transferRejectAfterAlice.balance - $transferRejectBeforeAlice.balance, 2) -eq 0.00) { "PASS" } else { "FAIL" })) -Detail "Bob rejected transfer; Alice balance restored to pre-send level." -Data @{ transfer = $transferRejectId; before_alice = $transferRejectBeforeAlice; after_alice = $transferRejectAfterAlice; status = $rejectDetail.data.status }

$rechargeMethods = Invoke-ApiJson -Method "GET" -Path "/api/v1/wallet/recharge-methods" -Token $aliceToken
Assert-Code -Resp $rechargeMethods -Action "recharge methods"
if (($rechargeMethods.data | Measure-Object).Count -gt 0) {
    $methodId = [uint64]$rechargeMethods.data[0].id
    $rechargeOrder = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/recharge-order" -Token $aliceToken -Body @{ method_id = $methodId; amount = 10.00; proof_image = "/uploads/p3-test-proof.png"; remark = "p3 destructive recharge order" }
    Assert-Code -Resp $rechargeOrder -Action "create recharge order"
    $orders = Invoke-ApiJson -Method "GET" -Path "/api/v1/wallet/recharge-orders" -Token $aliceToken
    Assert-Code -Resp $orders -Action "list recharge orders"
    $foundOrder = (($orders.data | ConvertTo-Json -Depth 30 -Compress) -match ([string]$rechargeOrder.data.id))
    Add-Result -Name "Recharge order submit" -Status ($(if ($rechargeOrder.data.status -eq "pending" -and $foundOrder) { "PASS" } else { "FAIL" })) -Detail "Submitted pending recharge order without real external payment." -Data @{ order = $rechargeOrder.data; found = $foundOrder }
} else {
    Add-Result -Name "Recharge order submit" -Status "WARN" -Detail "No enabled recharge method found."
}

$withdrawMethods = Invoke-ApiJson -Method "GET" -Path "/api/v1/wallet/withdraw/methods" -Token $aliceToken
Assert-Code -Resp $withdrawMethods -Action "withdraw methods"
if (($withdrawMethods.data | Measure-Object).Count -gt 0) {
    $methodId = [uint64]$withdrawMethods.data[0].id
    $withdrawBeforeAlice = Get-TestWallet -UserUuid $aliceUuid
    $withdraw = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/withdraw" -Token $aliceToken -Body @{
        method_id = $methodId
        amount = 10.00
        form_data = '{"account":"p3-test-account","real_name":"P3 Test"}'
        pay_password = $payPassword
    }
    Assert-Code -Resp $withdraw -Action "create withdraw request"
    $withdrawAfterAlice = Get-TestWallet -UserUuid $aliceUuid
    Add-Result -Name "Withdraw request submit" -Status ($(if ($withdraw.data.status -eq "pending" -and [Math]::Round($withdrawBeforeAlice.balance - $withdrawAfterAlice.balance, 2) -eq 10.00 -and [Math]::Round($withdrawAfterAlice.frozen_balance, 2) -ge 10.00) { "PASS" } else { "FAIL" })) -Detail "Submitted pending withdraw; balance moved to frozen balance." -Data @{ withdraw = $withdraw.data; before = $withdrawBeforeAlice; after = $withdrawAfterAlice }
} else {
    Add-Result -Name "Withdraw request submit" -Status "WARN" -Detail "No enabled withdraw method found."
}

$directRecharge = Invoke-ApiJson -Method "POST" -Path "/api/v1/wallet/recharge" -Token $aliceToken -Body @{ amount = 1.00 }
Add-Result -Name "Deprecated direct recharge rejects credit" -Status ($(if ([int]$directRecharge.code -ne 0) { "PASS" } else { "FAIL" })) -Detail "Direct top-up endpoint should not credit balance." -Data @{ code = $directRecharge.code; message = $directRecharge.message }

$logout = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/logout" -Token $aliceToken
Assert-Code -Resp $logout -Action "logout"
$meAfterLogout = Invoke-ApiJson -Method "GET" -Path "/api/v1/user/me" -Token $aliceToken
Add-Result -Name "Logout invalidates current session" -Status ($(if ([int]$meAfterLogout.code -ne 0) { "PASS" } else { "FAIL" })) -Detail "After logout, user/me with old token is rejected." -Data @{ logout_code = $logout.code; me_after_logout_code = $meAfterLogout.code; me_message = $meAfterLogout.message }

$bobMe = Invoke-ApiJson -Method "GET" -Path "/api/v1/user/me" -Token $bobToken
Assert-Code -Resp $bobMe -Action "bob me"
$aliceRelogin = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body @{
    username = $aliceName
    password = "Smoke123"
    device_id = "p3-destr-a-relogin-$suffix"
    device_type = "android"
    device_name = "P3 destructive relogin"
}
Assert-Code -Resp $aliceRelogin -Action "alice relogin"
$bobMeUuid = if ($bobMe.data.user.uuid) { $bobMe.data.user.uuid } else { $bobMe.data.uuid }
$aliceReloginUuid = if ($aliceRelogin.data.user.uuid) { $aliceRelogin.data.user.uuid } else { $aliceRelogin.data.uuid }
Add-Result -Name "Switch account token isolation" -Status ($(if ($bobMeUuid -eq $bobUuid -and $aliceReloginUuid -eq $aliceUuid) { "PASS" } else { "FAIL" })) -Detail "Bob token remains Bob; Alice relogin returns Alice." -Data @{ bob_token_user = $bobMeUuid; alice_relogin_user = $aliceReloginUuid }

$finalAliceWallet = Get-TestWallet -UserUuid $aliceUuid
$finalBobWallet = Get-TestWallet -UserUuid $bobUuid
Add-Result -Name "Final wallet state captured" -Status "PASS" -Detail "Captured balances after destructive wallet flows." -Data @{ alice = $finalAliceWallet; bob = $finalBobWallet }

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
    test_accounts = @{
        alice = @{ username = $aliceName; uuid = $aliceUuid }
        bob = @{ username = $bobName; uuid = $bobUuid }
        charlie = @{ username = $charlieName; uuid = $charlieUuid }
    }
    results = $results
}

$jsonPath = Join-Path $OutputDir "p3-destructive-state-flows-$runId.json"
$summary | ConvertTo-Json -Depth 40 | Set-Content -Encoding UTF8 -Path $jsonPath

$reportPath = Join-Path $OutputDir "report.md"
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# P3 Destructive State Flows") | Out-Null
$md.Add("") | Out-Null
$md.Add("- time: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))") | Out-Null
$md.Add("- status: $status") | Out-Null
$md.Add("- summary: PASS=$pass, WARN=$warn, FAIL=$fail") | Out-Null
$md.Add("- json: ``$jsonPath``") | Out-Null
$md.Add("- accounts: $aliceName, $bobName, $charlieName") | Out-Null
$md.Add("") | Out-Null
$md.Add("| Item | Status | Detail |") | Out-Null
$md.Add("| --- | --- | --- |") | Out-Null
foreach ($r in $results) {
    $detail = ($r.detail -replace "\|", "/").Trim()
    $md.Add("| $($r.name) | $($r.status) | $detail |") | Out-Null
}
$md | Set-Content -Encoding UTF8 -Path $reportPath

Write-Host "P3 destructive status: $status PASS=$pass WARN=$warn FAIL=$fail"
Write-Host "Report: $reportPath"
Write-Host "JSON: $jsonPath"
if ($fail -gt 0) { exit 1 }
