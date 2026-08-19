<#
.SYNOPSIS
验证高消息量、通话循环和前后台恢复组合场景的可靠性。

.DESCRIPTION
使用 Alice/Bob 双设备发送突发消息、循环建立/结束通话并切换应用状态，
同时收集 API、ADB、截图和日志证据。脚本会创建大量消息与通话记录，
并可能因限流等待较长时间，只能对测试环境运行。

.PARAMETER BurstCount
可靠性阶段连续发送的消息数量。

.PARAMETER CallCycles
建立并释放通话的循环次数。

.PARAMETER Api429RetryDelaySeconds
触发服务端限流后的等待时间。

.EXAMPLE
pwsh -File scripts/reliability_call_resume_suite.ps1 -BurstCount 20 -CallCycles 2
#>
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$EmulatorBaseUrl = "http://10.0.2.2:8080",
    [string]$PackageName = "com.genericim.ma100",
    [string]$AliceDevice = "127.0.0.1:16416",
    [string]$BobDevice = "127.0.0.1:16448",
    [string]$AliceUsername = "smoke_alice",
    [string]$BobUsername = "smoke_bob",
    [string]$Password = "Smoke123",
    [int]$BurstCount = 80,
    [int]$CallCycles = 4,
    [int]$SendDelayMs = 0,
    [int]$Api429RetryCount = 5,
    [int]$Api429RetryDelaySeconds = 65,
    [int]$AdbTimeoutSeconds = 20
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:StartedAt = Get-Date
$script:RunId = $script:StartedAt.ToString("yyyyMMdd-HHmmss")
$script:OutputRoot = Join-Path "release-archives\qa-20260624" "reliability-call-resume-$script:RunId"
$script:ReportPath = Join-Path $script:OutputRoot "report.md"
$script:JsonPath = Join-Path $script:OutputRoot "results.json"
$script:RunLog = Join-Path $script:OutputRoot "run.log"
$script:Results = New-Object System.Collections.Generic.List[object]
$script:Artifacts = New-Object System.Collections.Generic.List[string]
New-Item -ItemType Directory -Force -Path $script:OutputRoot | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'HH:mm:ss') $Message"
    Write-Host $line
    $line | Add-Content -Encoding UTF8 -Path $script:RunLog
}

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet("PASS", "FAIL", "WARN", "INFO")]
        [string]$Status,
        [string]$Detail,
        [string[]]$Artifacts = @()
    )
    $entry = [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        artifacts = $Artifacts
        time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $script:Results.Add($entry) | Out-Null
    foreach ($artifact in $Artifacts) {
        if (-not [string]::IsNullOrWhiteSpace($artifact)) {
            $script:Artifacts.Add($artifact) | Out-Null
        }
    }
    Write-Log "[$Status] $Name - $Detail"
}

function Invoke-Adb {
    param(
        [string]$Device,
        [string[]]$AdbArgs,
        [int]$TimeoutSeconds = $script:AdbTimeoutSeconds
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Adb
    foreach ($arg in @("-s", $Device) + $AdbArgs) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch {}
        try { $p.WaitForExit(2000) | Out-Null } catch {}
        return [pscustomobject]@{
            ExitCode = 124
            Out = $outTask.GetAwaiter().GetResult()
            Err = "timeout after ${TimeoutSeconds}s`n$($errTask.GetAwaiter().GetResult())"
        }
    }
    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        Out = $outTask.GetAwaiter().GetResult()
        Err = $errTask.GetAwaiter().GetResult()
    }
}

function Save-Screenshot {
    param([string]$Device, [string]$Name)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $remote = "/sdcard/genericim-reliability-screen.png"
    $local = Join-Path $script:OutputRoot "$safe-$Name.png"
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "screencap", "-p", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 15)
    return $local
}

function Save-UiDump {
    param([string]$Device, [string]$Name)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $remote = "/sdcard/genericim-reliability-window.xml"
    $local = Join-Path $script:OutputRoot "$safe-$Name.xml"
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "uiautomator", "dump", $remote) -TimeoutSeconds 15)
    [void](Invoke-Adb -Device $Device -AdbArgs @("pull", $remote, $local) -TimeoutSeconds 15)
    if (Test-Path -LiteralPath $local) {
        return [pscustomobject]@{ Path = $local; Xml = (Get-Content -LiteralPath $local -Raw -Encoding UTF8) }
    }
    return [pscustomobject]@{ Path = $local; Xml = "" }
}

function Tap {
    param([string]$Device, [int]$X, [int]$Y, [int]$SleepMs = 350)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "tap", "$X", "$Y") -TimeoutSeconds 6)
    Start-Sleep -Milliseconds $SleepMs
}

function Input-Text {
    param([string]$Device, [string]$Text)
    $encoded = $Text.Replace("%", "%25").Replace(" ", "%s").Replace("&", "\&")
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "text", $encoded) -TimeoutSeconds 8)
    Start-Sleep -Milliseconds 300
}

function Clear-FocusedText {
    param([string]$Device)
    [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_MOVE_END") -TimeoutSeconds 8)
    for ($i = 0; $i -lt 32; $i++) {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_DEL") -TimeoutSeconds 8)
    }
    Start-Sleep -Milliseconds 150
}

function Get-WindowSize {
    param([string]$Device)
    $r = Invoke-Adb -Device $Device -AdbArgs @("shell", "wm", "size") -TimeoutSeconds 8
    if ($r.Out -match "(\d+)x(\d+)") {
        return [pscustomobject]@{ Width = [int]$Matches[1]; Height = [int]$Matches[2] }
    }
    return [pscustomobject]@{ Width = 1080; Height = 1920 }
}

function Get-Nodes {
    param([string]$Xml)
    return @([regex]::Matches($Xml, "<node\b[^>]*>") | ForEach-Object { $_.Value })
}

function Get-Attr {
    param([string]$Node, [string]$Name)
    $m = [regex]::Match($Node, "$Name=`"([^`"]*)`"")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Get-BoundsCenter {
    param([string]$Bounds)
    $m = [regex]::Match($Bounds, "\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{
        X = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
        Y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
    }
}

function Get-BoundsRect {
    param([string]$Bounds)
    $m = [regex]::Match($Bounds, "\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{
        Left = [int]$m.Groups[1].Value
        Top = [int]$m.Groups[2].Value
        Right = [int]$m.Groups[3].Value
        Bottom = [int]$m.Groups[4].Value
        Width = [int]$m.Groups[3].Value - [int]$m.Groups[1].Value
        Height = [int]$m.Groups[4].Value - [int]$m.Groups[2].Value
    }
}

function Find-Node {
    param([string]$Xml, [string]$Pattern)
    foreach ($node in (Get-Nodes -Xml $Xml)) {
        $text = Get-Attr -Node $node -Name "text"
        $desc = Get-Attr -Node $node -Name "content-desc"
        $class = Get-Attr -Node $node -Name "class"
        if ("$text $desc $class" -match $Pattern) {
            return $node
        }
    }
    return $null
}

function Tap-Node {
    param([string]$Device, [string]$Node)
    $center = Get-BoundsCenter -Bounds (Get-Attr -Node $Node -Name "bounds")
    if ($null -eq $center) { return $false }
    Tap -Device $Device -X $center.X -Y $center.Y
    return $true
}

function Find-Nodes {
    param([string]$Xml, [string]$Pattern)
    $foundNodes = New-Object System.Collections.Generic.List[string]
    foreach ($node in (Get-Nodes -Xml $Xml)) {
        $text = Get-Attr -Node $node -Name "text"
        $desc = Get-Attr -Node $node -Name "content-desc"
        $class = Get-Attr -Node $node -Name "class"
        if ("$text $desc $class" -match $Pattern) {
            $foundNodes.Add($node) | Out-Null
        }
    }
    return @($foundNodes)
}

function Tap-ChatPeerNode {
    param([string]$Device, [string]$Node)
    $rect = Get-BoundsRect -Bounds (Get-Attr -Node $Node -Name "bounds")
    if ($null -eq $rect) { return $false }
    if ($rect.Width -gt 600) {
        $x = [int]($rect.Left + [Math]::Min(180, [Math]::Max(80, $rect.Width * 0.18)))
        $y = [int](($rect.Top + $rect.Bottom) / 2)
        Tap -Device $Device -X $x -Y $y
        return $true
    }
    return (Tap-Node -Device $Device -Node $Node)
}

function Find-BottomNode {
    param([string]$Xml, [string]$Pattern, [int]$MinY)
    foreach ($node in (Get-Nodes -Xml $Xml)) {
        $text = Get-Attr -Node $node -Name "text"
        $desc = Get-Attr -Node $node -Name "content-desc"
        $center = Get-BoundsCenter -Bounds (Get-Attr -Node $node -Name "bounds")
        if ($null -ne $center -and $center.Y -ge $MinY -and "$text $desc" -match $Pattern) {
            return $node
        }
    }
    return $null
}

function Tap-MessagesTab {
    param([string]$Device, [string]$Xml, [object]$Size)
    $node = Find-BottomNode -Xml $Xml -Pattern "(^|[\s;#0-9]+)消息($|[\s;#0-9]+)" -MinY ([int]($Size.Height * 0.78))
    if ($null -ne $node) {
        [void](Tap-Node -Device $Device -Node $node)
    } else {
        Tap -Device $Device -X ([int]($Size.Width * 0.22)) -Y ([int]($Size.Height * 0.92))
    }
    Start-Sleep -Seconds 2
}

function Exit-CallSurfaceIfNeeded {
    param([string]$Device, [string]$Xml)
    if ($Xml -notmatch "呼叫中|正在呼叫|通话中|等待接听|取消|挂断|结束通话") {
        return $false
    }
    if ($Xml -match "输入消息" -and $Xml -match "语音通话|视频通话") {
        return $false
    }
    $action = Find-Node -Xml $Xml -Pattern "取消|挂断|结束通话|拒绝"
    if ($null -ne $action) {
        [void](Tap-Node -Device $Device -Node $action)
    } else {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_BACK") -TimeoutSeconds 8)
    }
    Start-Sleep -Seconds 2
    return $true
}

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = "",
        [int]$TimeoutSec = 20
    )
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }
    $params = @{
        Method = $Method
        Uri = "$($BaseUrl.TrimEnd('/'))$Path"
        Headers = $headers
        TimeoutSec = $TimeoutSec
    }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json; charset=utf-8"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 30)
    }
    $attempt = 0
    while ($true) {
        try {
            return Invoke-RestMethod @params
        } catch {
            $status = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $status = [int]$_.Exception.Response.StatusCode
            }
            if ($status -eq 429 -and $attempt -lt $Api429RetryCount) {
                $attempt++
                Write-Log "[WARN] API 429 $Method $Path, retry $attempt/$Api429RetryCount after ${Api429RetryDelaySeconds}s"
                Start-Sleep -Seconds $Api429RetryDelaySeconds
                continue
            }
            throw
        }
    }
}

function Assert-ApiOk {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response) { throw "$Action empty response" }
    if ([int]$Response.code -ne 0) {
        throw "$Action code=$($Response.code) message=$($Response.message)"
    }
}

function Login-Or-RegisterApi {
    param([string]$Username)
    $body = @{
        username = $Username
        password = $Password
        device_id = "reliability-api-$Username"
        device_type = "android"
        device_name = "Reliability API"
    }
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    if ([int]$login.code -eq 0) { return $login }
    $register = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/register" -Body @{
        username = $Username
        password = $Password
        nickname = $Username
        gender = "male"
        device_id = "reliability-api-$Username"
        device_type = "android"
        device_name = "Reliability API"
    }
    Assert-ApiOk -Response $register -Action "register $Username"
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body $body
    Assert-ApiOk -Response $login -Action "login $Username"
    return $login
}

function Send-ChatText {
    param([string]$Token, [string]$ChatId, [string]$Text)
    $msgId = [guid]::NewGuid().ToString()
    $send = Invoke-ApiJson -Method "POST" -Path "/api/v1/message/send" -Token $Token -Body @{
        chat_id = $ChatId
        type = 1
        msg_id = $msgId
        content = @{ text = $Text }
    }
    Assert-ApiOk -Response $send -Action "send message $Text"
    return $msgId
}

function Get-MessageJson {
    param([string]$Token, [string]$ChatId, [int]$Limit = 300)
    $list = Invoke-ApiJson -Method "GET" -Path "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($ChatId))&limit=$Limit" -Token $Token
    Assert-ApiOk -Response $list -Action "list messages"
    return ($list.data | ConvertTo-Json -Depth 30 -Compress)
}

function Get-MessageJsonWindow {
    param([string]$Token, [string]$ChatId, [int]$ExpectedCount)
    $all = New-Object System.Collections.Generic.List[object]
    $beforeSeq = 0
    $pageLimit = 100
    for ($page = 0; $page -lt 12 -and $all.Count -lt $ExpectedCount; $page++) {
        $path = "/api/v1/message/list?chat_id=$([uri]::EscapeDataString($ChatId))&limit=$pageLimit"
        if ($beforeSeq -gt 0) {
            $path = "$path&before_seq=$beforeSeq"
        }
        $list = Invoke-ApiJson -Method "GET" -Path $path -Token $Token
        Assert-ApiOk -Response $list -Action "list messages page $page"
        $items = @($list.data)
        if ($items.Count -eq 0) {
            break
        }
        foreach ($item in $items) {
            $all.Add($item) | Out-Null
        }
        $seqs = @($items | ForEach-Object { [int]$_.seq } | Where-Object { $_ -gt 0 })
        if ($seqs.Count -eq 0) {
            break
        }
        $nextBeforeSeq = ($seqs | Measure-Object -Minimum).Minimum
        if ($nextBeforeSeq -le 0 -or $nextBeforeSeq -eq $beforeSeq) {
            break
        }
        $beforeSeq = $nextBeforeSeq
    }
    return ($all | ConvertTo-Json -Depth 30 -Compress)
}

function Check-Device {
    param([string]$Device)
    $model = (Invoke-Adb -Device $Device -AdbArgs @("shell", "getprop", "ro.product.model") -TimeoutSeconds 8).Out.Trim()
    $hostName = ([uri]$EmulatorBaseUrl).Host
    $curlPath = (Invoke-Adb -Device $Device -AdbArgs @("shell", "command", "-v", "curl") -TimeoutSeconds 8).Out.Trim()
    $health = ""
    if (-not [string]::IsNullOrWhiteSpace($curlPath)) {
        $health = (Invoke-Adb -Device $Device -AdbArgs @("shell", "curl", "-s", "-m", "3", "$EmulatorBaseUrl/health") -TimeoutSeconds 8).Out.Trim()
    }
    $ping = (Invoke-Adb -Device $Device -AdbArgs @("shell", "ping", "-c", "1", "-W", "2", $hostName) -TimeoutSeconds 8).Out
    [void](Invoke-Adb -Device $Device -AdbArgs @("reverse", "tcp:8080", "tcp:8080") -TimeoutSeconds 8)
    [void](Invoke-Adb -Device $Device -AdbArgs @("logcat", "-c") -TimeoutSeconds 8)
    if ($health -match '"status"\s*:\s*"ok"') {
        Add-Result -Name "Device reachable $Device" -Status "PASS" -Detail "model=$model reaches $EmulatorBaseUrl"
    } elseif ([string]::IsNullOrWhiteSpace($curlPath) -and $ping -match "1 received|0% packet loss") {
        Add-Result -Name "Device reachable $Device" -Status "PASS" -Detail "model=$model reaches host $hostName by ping; curl unavailable on device"
    } else {
        Add-Result -Name "Device reachable $Device" -Status "FAIL" -Detail "model=$model health=$health ping=$($ping.Trim())"
    }
}

function Open-App {
    param([string]$Device)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "am", "start", "-W", "-n", "$PackageName/.MainActivity") -TimeoutSeconds 18)
        Start-Sleep -Seconds 4
        $focus = (Invoke-Adb -Device $Device -AdbArgs @("shell", "dumpsys", "window") -TimeoutSeconds 8).Out
        if ($focus -match [regex]::Escape($PackageName)) {
            return
        }
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "monkey", "-p", $PackageName, "-c", "android.intent.category.LAUNCHER", "1") -TimeoutSeconds 12)
        Start-Sleep -Seconds 4
        $focus = (Invoke-Adb -Device $Device -AdbArgs @("shell", "dumpsys", "window") -TimeoutSeconds 8).Out
        if ($focus -match [regex]::Escape($PackageName)) {
            return
        }
    }
}

function Ensure-App-LoggedIn {
    param([string]$Device, [string]$Username, [string]$DisplayName)
    Open-App -Device $Device
    Start-Sleep -Seconds 2
    $size = Get-WindowSize -Device $Device
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $dump = Save-UiDump -Device $Device -Name "$DisplayName-login-$attempt"
        if ($dump.Xml -match "消息|联系人|发现|设置" -and $dump.Xml -notmatch "登录您的账号") {
            Add-Result -Name "Device login $DisplayName" -Status "PASS" -Detail "$Username already logged in or reached main UI" -Artifacts @($dump.Path)
            return $true
        }
        if ($dump.Xml -notmatch "登录您的账号|用户名|密码|立即注册") {
            [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_BACK") -TimeoutSeconds 8)
            Start-Sleep -Seconds 1
            Open-App -Device $Device
            continue
        }

        $edits = @(Find-Nodes -Xml $dump.Xml -Pattern "android.widget.EditText")
        if ($edits.Count -lt 2) {
            Start-Sleep -Seconds 2
            continue
        }

        [void](Tap-Node -Device $Device -Node $edits[0])
        Clear-FocusedText -Device $Device
        Input-Text -Device $Device -Text $Username
        [void](Tap-Node -Device $Device -Node $edits[1])
        Clear-FocusedText -Device $Device
        Input-Text -Device $Device -Text $Password
        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_BACK") -TimeoutSeconds 8)
        Start-Sleep -Seconds 1
        $postInputDump = Save-UiDump -Device $Device -Name "$DisplayName-login-$attempt-ready"
        $loginXml = if ([string]::IsNullOrWhiteSpace($postInputDump.Xml)) { $dump.Xml } else { $postInputDump.Xml }

        $agreement = Find-BottomNode -Xml $loginXml -Pattern "我已阅读并同意|用户协议|隐私政策|android.widget.CheckBox" -MinY ([int]($size.Height * 0.82))
        if ($null -ne $agreement) {
            [void](Tap-Node -Device $Device -Node $agreement)
        } else {
            Tap -Device $Device -X ([int]($size.Width * 0.16)) -Y ([int]($size.Height * 0.95)) -SleepMs 500
        }

        Start-Sleep -Milliseconds 500
        $afterAgreementDump = Save-UiDump -Device $Device -Name "$DisplayName-login-$attempt-submit"
        $submitXml = if ([string]::IsNullOrWhiteSpace($afterAgreementDump.Xml)) { $loginXml } else { $afterAgreementDump.Xml }
        $loginNode = Find-Node -Xml $submitXml -Pattern "^登录$| 登录 |content-desc=`"登录`""
        if ($null -ne $loginNode) {
            [void](Tap-Node -Device $Device -Node $loginNode)
        } else {
            Tap -Device $Device -X ([int]($size.Width * 0.5)) -Y ([int]($size.Height * 0.8)) -SleepMs 500
        }
        Start-Sleep -Seconds 6
    }

    $finalDump = Save-UiDump -Device $Device -Name "$DisplayName-login-final"
    $shot = Save-Screenshot -Device $Device -Name "$DisplayName-login-final"
    if ($finalDump.Xml -match "消息|联系人|发现|设置" -and $finalDump.Xml -notmatch "登录您的账号") {
        Add-Result -Name "Device login $DisplayName" -Status "PASS" -Detail "$Username logged in" -Artifacts @($finalDump.Path, $shot)
        return $true
    }
    Add-Result -Name "Device login $DisplayName" -Status "FAIL" -Detail "$Username did not reach main UI" -Artifacts @($finalDump.Path, $shot)
    return $false
}

function Bring-To-Chat {
    param([string]$Device, [string]$PeerPattern, [string]$ExpectedText, [string]$Name)
    Open-App -Device $Device
    $size = Get-WindowSize -Device $Device
    for ($i = 0; $i -lt 7; $i++) {
        $dump = Save-UiDump -Device $Device -Name "$Name-step-$i"
        if ($dump.Xml -match [regex]::Escape($ExpectedText)) {
            return [pscustomobject]@{
                Found = $true
                Dump = $dump.Path
                Shot = (Save-Screenshot -Device $Device -Name "$Name-found")
                Xml = $dump.Xml
            }
        }

        if (Exit-CallSurfaceIfNeeded -Device $Device -Xml $dump.Xml) {
            continue
        }

        if ($dump.Xml -match "输入消息" -and $dump.Xml -notmatch [regex]::Escape($ExpectedText)) {
            if ($dump.Xml -notmatch $PeerPattern) {
                [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_BACK") -TimeoutSeconds 8)
                Start-Sleep -Seconds 2
                continue
            }
            [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "swipe", "540", "1450", "540", "650", "300") -TimeoutSeconds 8)
            Start-Sleep -Seconds 1
            continue
        }

        if ($dump.Xml -match $PeerPattern -and
            $dump.Xml -match "个人简介|用户名|照片和视频" -and
            $dump.Xml -match "消息") {
            $messageButton = Find-Node -Xml $dump.Xml -Pattern "^消息$|[\s`"']消息[\s`"']"
            if ($null -eq $messageButton) {
                $messageButton = Find-Node -Xml $dump.Xml -Pattern "消息"
            }
            if ($null -ne $messageButton) {
                [void](Tap-Node -Device $Device -Node $messageButton)
                Start-Sleep -Seconds 3
                continue
            }
        }

        $peer = Find-Node -Xml $dump.Xml -Pattern $PeerPattern
        if ($null -ne $peer) {
            [void](Tap-ChatPeerNode -Device $Device -Node $peer)
            Start-Sleep -Seconds 3
            continue
        }

        $messagesTab = Find-BottomNode -Xml $dump.Xml -Pattern "(^|[\s;#0-9]+)消息($|[\s;#0-9]+)" -MinY ([int]($size.Height * 0.78))
        if ($null -ne $messagesTab -and $dump.Xml -match "设置|联系人|发现|钱包|VIP|个人资料|通知和声音|数据和存储|聊天设置") {
            Tap-MessagesTab -Device $Device -Xml $dump.Xml -Size $size
            continue
        }

        if ($dump.Xml -match "搜索|聊天|消息") {
            Tap -Device $Device -X ([int]($size.Width * 0.5)) -Y ([int]($size.Height * 0.36)) -SleepMs 900
            continue
        }

        if ($null -ne $messagesTab) {
            Tap-MessagesTab -Device $Device -Xml $dump.Xml -Size $size
            continue
        }

        [void](Invoke-Adb -Device $Device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_BACK") -TimeoutSeconds 8)
        Start-Sleep -Seconds 1
    }
    $finalDump = Save-UiDump -Device $Device -Name "$Name-final"
    return [pscustomobject]@{
        Found = ($finalDump.Xml -match [regex]::Escape($ExpectedText))
        Dump = $finalDump.Path
        Shot = (Save-Screenshot -Device $Device -Name "$Name-final")
        Xml = $finalDump.Xml
    }
}

function Test-MessageReliability {
    param([object]$State)
    $prefix = "rel-$script:RunId"
    $expected = New-Object System.Collections.Generic.List[string]
    $sendErrors = New-Object System.Collections.Generic.List[string]

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 1; $i -le $BurstCount; $i++) {
        foreach ($side in @("A", "B")) {
            $text = "{0}-{1}-{2:D3}" -f $prefix, $side, $i
            $expected.Add($text) | Out-Null
            try {
                $token = if ($side -eq "A") { $State.alice_token } else { $State.bob_token }
                [void](Send-ChatText -Token $token -ChatId $State.chat_id -Text $text)
                if ($SendDelayMs -gt 0) {
                    Start-Sleep -Milliseconds $SendDelayMs
                }
            } catch {
                $sendErrors.Add("$text => $($_.Exception.Message)") | Out-Null
            }
        }
    }
    $sw.Stop()

    $aliceJson = Get-MessageJsonWindow -Token $State.alice_token -ChatId $State.chat_id -ExpectedCount ([Math]::Max(300, $expected.Count + 50))
    $bobJson = Get-MessageJsonWindow -Token $State.bob_token -ChatId $State.chat_id -ExpectedCount ([Math]::Max(300, $expected.Count + 50))
    $missingAlice = @($expected | Where-Object { $aliceJson -notmatch [regex]::Escape($_) })
    $missingBob = @($expected | Where-Object { $bobJson -notmatch [regex]::Escape($_) })

    $summary = [pscustomobject]@{
        prefix = $prefix
        burst_count_each_side = $BurstCount
        expected_total = $expected.Count
        send_errors = $sendErrors
        missing_for_alice = $missingAlice
        missing_for_bob = $missingBob
        elapsed_ms = $sw.ElapsedMilliseconds
    }
    $path = Join-Path $script:OutputRoot "message-reliability.json"
    $summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $path

    if ($sendErrors.Count -eq 0 -and $missingAlice.Count -eq 0 -and $missingBob.Count -eq 0) {
        Add-Result -Name "Message reliability burst" -Status "PASS" -Detail "$($expected.Count) messages sent/listed with no missing messages in $($sw.ElapsedMilliseconds)ms" -Artifacts @($path)
    } else {
        Add-Result -Name "Message reliability burst" -Status "FAIL" -Detail "sendErrors=$($sendErrors.Count), missingAlice=$($missingAlice.Count), missingBob=$($missingBob.Count)" -Artifacts @($path)
    }
    return $expected[$expected.Count - 1]
}

function Test-CallRedial {
    param([object]$State)
    $records = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[string]

    for ($i = 1; $i -le $CallCycles; $i++) {
        try {
            $voice = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $State.alice_token -Body @{
                target_user_id = $State.bob_uuid
                call_type = "voice"
            }
            Assert-ApiOk -Response $voice -Action "cycle $i voice create"
            $voiceId = [uint32]$voice.data.call_id
            $reject = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/reject" -Token $State.bob_token -Body @{
                call_id = $voiceId
                reason = "qa_reject_cycle_$i"
            }
            Assert-ApiOk -Response $reject -Action "cycle $i voice reject"
            $records.Add([pscustomobject]@{ cycle = $i; flow = "voice_reject"; call_id = $voiceId }) | Out-Null

            $cancelCall = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $State.alice_token -Body @{
                target_user_id = $State.bob_uuid
                call_type = "voice"
            }
            Assert-ApiOk -Response $cancelCall -Action "cycle $i voice recreate after reject"
            $cancelId = [uint32]$cancelCall.data.call_id
            $cancel = Invoke-ApiJson -Method "DELETE" -Path "/api/v1/call/$cancelId" -Token $State.alice_token
            Assert-ApiOk -Response $cancel -Action "cycle $i voice cancel"
            $records.Add([pscustomobject]@{ cycle = $i; flow = "voice_cancel_after_reject"; call_id = $cancelId }) | Out-Null

            $video = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $State.bob_token -Body @{
                target_user_id = $State.alice_uuid
                call_type = "video"
            }
            Assert-ApiOk -Response $video -Action "cycle $i video create"
            $videoId = [uint32]$video.data.call_id
            $accept = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/accept" -Token $State.alice_token -Body @{ call_id = $videoId }
            Assert-ApiOk -Response $accept -Action "cycle $i video accept"
            Start-Sleep -Milliseconds 600
            $end = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/end" -Token $State.bob_token -Body @{
                call_id = $videoId
                reason = "qa_end_cycle_$i"
            }
            Assert-ApiOk -Response $end -Action "cycle $i video end"
            $records.Add([pscustomobject]@{ cycle = $i; flow = "video_accept_end"; call_id = $videoId }) | Out-Null
        } catch {
            $failures.Add("cycle $i => $($_.Exception.Message)") | Out-Null
        }
    }

    $history = Invoke-ApiJson -Method "GET" -Path "/api/v1/call/history" -Token $State.alice_token
    Assert-ApiOk -Response $history -Action "call history after redial"
    $summary = [pscustomobject]@{
        cycles = $CallCycles
        records = $records
        failures = $failures
        history = $history.data
    }
    $path = Join-Path $script:OutputRoot "call-redial.json"
    $summary | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path $path
    if ($failures.Count -eq 0) {
        Add-Result -Name "Call redial after reject/cancel/end" -Status "PASS" -Detail "$CallCycles cycles passed; repeated create/reject/cancel/video accept/end all succeeded" -Artifacts @($path)
    } else {
        Add-Result -Name "Call redial after reject/cancel/end" -Status "FAIL" -Detail "$($failures.Count) call cycle failures" -Artifacts @($path)
    }
}

function Test-BackgroundResume {
    param([object]$State)
    $aliceText = "resume-to-alice-$script:RunId"
    $bobText = "resume-to-bob-$script:RunId"

    foreach ($device in @($AliceDevice, $BobDevice)) {
        Open-App -Device $device
        [void](Invoke-Adb -Device $device -AdbArgs @("shell", "input", "keyevent", "KEYCODE_HOME") -TimeoutSeconds 8)
    }
    Start-Sleep -Seconds 2
    [void](Send-ChatText -Token $State.bob_token -ChatId $State.chat_id -Text $aliceText)
    [void](Send-ChatText -Token $State.alice_token -ChatId $State.chat_id -Text $bobText)

    $aliceUi = Bring-To-Chat -Device $AliceDevice -PeerPattern "Smoke Bob|smoke_bob" -ExpectedText $aliceText -Name "alice-resume"
    $bobUi = Bring-To-Chat -Device $BobDevice -PeerPattern "Smoke Alice|smoke_alice" -ExpectedText $bobText -Name "bob-resume"

    foreach ($device in @($AliceDevice, $BobDevice)) {
        [void](Invoke-Adb -Device $device -AdbArgs @("shell", "am", "force-stop", $PackageName) -TimeoutSeconds 8)
    }
    Start-Sleep -Seconds 2
    $aliceKilledText = "killed-resume-alice-$script:RunId"
    $bobKilledText = "killed-resume-bob-$script:RunId"
    [void](Send-ChatText -Token $State.bob_token -ChatId $State.chat_id -Text $aliceKilledText)
    [void](Send-ChatText -Token $State.alice_token -ChatId $State.chat_id -Text $bobKilledText)

    $aliceKilledUi = Bring-To-Chat -Device $AliceDevice -PeerPattern "Smoke Bob|smoke_bob" -ExpectedText $aliceKilledText -Name "alice-killed-resume"
    $bobKilledUi = Bring-To-Chat -Device $BobDevice -PeerPattern "Smoke Alice|smoke_alice" -ExpectedText $bobKilledText -Name "bob-killed-resume"

    $summary = [pscustomobject]@{
        background_text_to_alice = $aliceText
        background_text_to_bob = $bobText
        killed_text_to_alice = $aliceKilledText
        killed_text_to_bob = $bobKilledText
        alice_background_found = $aliceUi.Found
        bob_background_found = $bobUi.Found
        alice_killed_found = $aliceKilledUi.Found
        bob_killed_found = $bobKilledUi.Found
    }
    $path = Join-Path $script:OutputRoot "background-resume.json"
    $summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $path
    $artifacts = @($path, $aliceUi.Dump, $aliceUi.Shot, $bobUi.Dump, $bobUi.Shot, $aliceKilledUi.Dump, $aliceKilledUi.Shot, $bobKilledUi.Dump, $bobKilledUi.Shot)
    if ($aliceUi.Found -and $bobUi.Found -and $aliceKilledUi.Found -and $bobKilledUi.Found) {
        Add-Result -Name "Background and killed-app resume" -Status "PASS" -Detail "latest messages visible after HOME background and force-stop relaunch on both devices" -Artifacts $artifacts
    } else {
        Add-Result -Name "Background and killed-app resume" -Status "FAIL" -Detail "found flags: aliceBg=$($aliceUi.Found), bobBg=$($bobUi.Found), aliceKilled=$($aliceKilledUi.Found), bobKilled=$($bobKilledUi.Found)" -Artifacts $artifacts
    }
}

function Collect-DeviceLogs {
    param([string]$Device)
    $safe = $Device.Replace(":", "-").Replace(".", "-")
    $rawPath = Join-Path $script:OutputRoot "$safe-logcat.txt"
    $errPath = Join-Path $script:OutputRoot "$safe-logcat-errors.txt"
    $r = Invoke-Adb -Device $Device -AdbArgs @("logcat", "-d", "-t", "3000") -TimeoutSeconds 25
    $r.Out | Set-Content -Encoding UTF8 -Path $rawPath
    $matches = ($r.Out -split "`r?`n") | Where-Object {
        $_ -match "FATAL EXCEPTION|ANR in com\.genericim\.app|FlutterError|E/flutter|Input dispatching timed out.*com\.genericim\.app"
    }
    $matches | Set-Content -Encoding UTF8 -Path $errPath
    if ($matches.Count -gt 0) {
        Add-Result -Name "Device logcat $Device" -Status "WARN" -Detail "matched $($matches.Count) error-like lines" -Artifacts @($errPath, $rawPath)
    } else {
        Add-Result -Name "Device logcat $Device" -Status "PASS" -Detail "no app Fatal/ANR/FlutterError lines matched" -Artifacts @($errPath, $rawPath)
    }
}

function Write-Report {
    $pass = @($script:Results | Where-Object status -eq "PASS").Count
    $fail = @($script:Results | Where-Object status -eq "FAIL").Count
    $warn = @($script:Results | Where-Object status -eq "WARN").Count
    $info = @($script:Results | Where-Object status -eq "INFO").Count
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 通用IM 消息可靠性 + 通话二次拉起 + 后台恢复专项报告") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- 时间: $($script:StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $lines.Add("- 包名: ``$PackageName``") | Out-Null
    $lines.Add("- Alice: ``$AliceUsername`` / ``$AliceDevice``") | Out-Null
    $lines.Add("- Bob: ``$BobUsername`` / ``$BobDevice``") | Out-Null
    $lines.Add("- 消息突发: 每边 $BurstCount 条，总计 $($BurstCount * 2) 条") | Out-Null
    $lines.Add("- 发送间隔: ${SendDelayMs}ms") | Out-Null
    $lines.Add("- 429重试: $Api429RetryCount 次，间隔 ${Api429RetryDelaySeconds}s") | Out-Null
    $lines.Add("- 通话二次拉起: $CallCycles 轮") | Out-Null
    $lines.Add("- 统计: PASS=$pass, FAIL=$fail, WARN=$warn, INFO=$info") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("## Bug / 风险汇总") | Out-Null
    $issues = @($script:Results | Where-Object { $_.status -in @("FAIL", "WARN") })
    if ($issues.Count -eq 0) {
        $lines.Add("- 未发现 FAIL/WARN。") | Out-Null
    } else {
        foreach ($issue in $issues) {
            $lines.Add("- **$($issue.status)** $($issue.name): $($issue.detail)") | Out-Null
            foreach ($artifact in $issue.artifacts) {
                $lines.Add("  - evidence: ``$artifact``") | Out-Null
            }
        }
    }
    $lines.Add("") | Out-Null
    $lines.Add("## 全部结果") | Out-Null
    foreach ($r in $script:Results) {
        $lines.Add("- **$($r.status)** $($r.name): $($r.detail)") | Out-Null
    }
    $lines | Set-Content -Encoding UTF8 -Path $script:ReportPath
    [pscustomobject]@{
        started_at = $script:StartedAt
        finished_at = Get-Date
        package = $PackageName
        summary = @{ pass = $pass; fail = $fail; warn = $warn; info = $info }
        results = $script:Results
        artifacts = $script:Artifacts
    } | ConvertTo-Json -Depth 40 | Set-Content -Encoding UTF8 -Path $script:JsonPath
}

Write-Log "Output: $script:OutputRoot"

try {
    $health = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/health" -TimeoutSec 8
    if ($health.status -eq "ok") {
        Add-Result -Name "Backend health" -Status "PASS" -Detail "health ok"
    } else {
        Add-Result -Name "Backend health" -Status "FAIL" -Detail "health=$($health | ConvertTo-Json -Compress)"
    }
} catch {
    Add-Result -Name "Backend health" -Status "FAIL" -Detail $_.Exception.Message
}

Check-Device -Device $AliceDevice
Check-Device -Device $BobDevice

$state = $null
try {
    $alice = Login-Or-RegisterApi -Username $AliceUsername
    $bob = Login-Or-RegisterApi -Username $BobUsername
    $chat = Invoke-ApiJson -Method "POST" -Path "/api/v1/chat/create" -Token $alice.data.token -Body @{
        type = 1
        member_ids = @([string]$bob.data.user.uuid)
    }
    Assert-ApiOk -Response $chat -Action "create private chat"
    $state = [pscustomobject]@{
        alice_token = [string]$alice.data.token
        bob_token = [string]$bob.data.token
        alice_uuid = [string]$alice.data.user.uuid
        bob_uuid = [string]$bob.data.user.uuid
        chat_id = [string]$chat.data.uuid
    }
    $state | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path (Join-Path $script:OutputRoot "state.json")
    Add-Result -Name "API users/chat setup" -Status "PASS" -Detail "chat=$($state.chat_id)"
} catch {
    Add-Result -Name "API users/chat setup" -Status "FAIL" -Detail $_.Exception.Message
}

if ($null -ne $state) {
    $aliceLoggedIn = $false
    $bobLoggedIn = $false
    try { $aliceLoggedIn = Ensure-App-LoggedIn -Device $AliceDevice -Username $AliceUsername -DisplayName "alice" } catch { Add-Result -Name "Device login alice" -Status "FAIL" -Detail $_.Exception.Message }
    try { $bobLoggedIn = Ensure-App-LoggedIn -Device $BobDevice -Username $BobUsername -DisplayName "bob" } catch { Add-Result -Name "Device login bob" -Status "FAIL" -Detail $_.Exception.Message }

    try { [void](Test-MessageReliability -State $state) } catch { Add-Result -Name "Message reliability burst" -Status "FAIL" -Detail $_.Exception.Message }
    try { Test-CallRedial -State $state } catch { Add-Result -Name "Call redial after reject/cancel/end" -Status "FAIL" -Detail $_.Exception.Message }
    if ($aliceLoggedIn -and $bobLoggedIn) {
        try { Test-BackgroundResume -State $state } catch { Add-Result -Name "Background and killed-app resume" -Status "FAIL" -Detail $_.Exception.Message }
    } else {
        Add-Result -Name "Background and killed-app resume" -Status "FAIL" -Detail "skipped because device login precondition failed: alice=$aliceLoggedIn, bob=$bobLoggedIn"
    }
}

Collect-DeviceLogs -Device $AliceDevice
Collect-DeviceLogs -Device $BobDevice
Write-Report

Write-Host ""
Write-Host "Report: $script:ReportPath"
Write-Host "JSON:   $script:JsonPath"
if (@($script:Results | Where-Object status -eq "FAIL").Count -gt 0) {
    exit 1
}
