<#
.SYNOPSIS
压力验证通话结束后的资源释放与立即重拨能力。

.DESCRIPTION
使用主叫和被叫测试账号反复调用后端通话接口，检查创建、结束和下一轮呼叫
不会被残留状态阻塞。脚本会真实创建大量通话记录，只能使用专用测试账号。

.PARAMETER Iterations
创建和释放通话的循环次数。

.PARAMETER DelayMs
每轮操作之间的等待毫秒数。

.PARAMETER Video
使用视频通话类型；默认验证语音通话。

.PARAMETER SkipLogin
复用 CallerToken 和 CalleeUuid，跳过账号登录。

.EXAMPLE
pwsh -File scripts/stress_call_redial_release.ps1 -Iterations 20
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$CallerUsername = "alice",
    [string]$CallerPassword = "123456",
    [string]$CalleeUsername = "bob",
    [string]$CalleePassword = "123456",
    [int]$Iterations = 100,
    [int]$DelayMs = 100,
    [switch]$Video,
    [switch]$SkipLogin,
    [string]$CallerToken = "",
    [string]$CalleeUuid = ""
)

$ErrorActionPreference = "Stop"

function Invoke-ApiJson {
    param(
        [ValidateSet("GET", "POST", "DELETE")]
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $headers = @{ "Accept" = "application/json" }
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }
    $uri = "$($BaseUrl.TrimEnd('/'))$Path"
    $json = $null
    if ($null -ne $Body) {
        $headers["Content-Type"] = "application/json"
        $json = $Body | ConvertTo-Json -Depth 8 -Compress
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json
}

function Assert-Ok {
    param([object]$Response, [string]$Action)
    if ($null -eq $Response -or [int]$Response.code -ne 0) {
        $message = if ($Response) { $Response.message } else { "empty response" }
        throw "$Action failed: $message"
    }
}

function New-LoginBody {
    param([string]$Username, [string]$Password, [string]$DeviceName)
    return @{
        username = $Username
        password = $Password
        device_id = "stress-call-$DeviceName-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        device_type = "backend_stress"
        device_name = "Call redial stress $DeviceName"
    }
}

function Login-User {
    param([string]$Username, [string]$Password, [string]$DeviceName)
    $login = Invoke-ApiJson -Method "POST" -Path "/api/v1/auth/login" -Body (New-LoginBody -Username $Username -Password $Password -DeviceName $DeviceName)
    Assert-Ok -Response $login -Action "login $Username"
    return $login.data
}

function Percentile {
    param([int64[]]$Values, [int]$Percentile)
    if ($Values.Count -eq 0) { return 0 }
    $sorted = @($Values | Sort-Object)
    $idx = [Math]::Ceiling(($sorted.Count * $Percentile) / 100.0) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
    return [int64]$sorted[$idx]
}

if ($Iterations -lt 1) {
    throw "Iterations must be >= 1"
}

if (-not $SkipLogin) {
    $caller = Login-User -Username $CallerUsername -Password $CallerPassword -DeviceName "caller"
    $callee = Login-User -Username $CalleeUsername -Password $CalleePassword -DeviceName "callee"
    $CallerToken = [string]$caller.token
    $CalleeUuid = [string]$callee.user.uuid
}

if ([string]::IsNullOrWhiteSpace($CallerToken) -or [string]::IsNullOrWhiteSpace($CalleeUuid)) {
    throw "CallerToken and CalleeUuid are required when SkipLogin is used"
}

$callType = if ($Video) { "video" } else { "voice" }
$latencies = New-Object System.Collections.Generic.List[Int64]
$failures = New-Object System.Collections.Generic.List[object]
$created = 0
$ended = 0

for ($i = 1; $i -le $Iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $create = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/create" -Token $CallerToken -Body @{
            target_user_id = $CalleeUuid
            call_type = $callType
        }
        Assert-Ok -Response $create -Action "create call #$i"
        $created++
        $callID = [uint64]$create.data.call_id

        $end = Invoke-ApiJson -Method "POST" -Path "/api/v1/call/end" -Token $CallerToken -Body @{
            call_id = $callID
            reason = "stress_redial"
        }
        Assert-Ok -Response $end -Action "end call #$i"
        $ended++
        $sw.Stop()
        $latencies.Add([int64]$sw.ElapsedMilliseconds)
    } catch {
        $sw.Stop()
        $failures.Add([pscustomobject]@{
            iteration = $i
            latency_ms = [int64]$sw.ElapsedMilliseconds
            error = $_.Exception.Message
        })
    }

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

$success = $Iterations - $failures.Count
$successRate = [Math]::Round(($success * 100.0) / $Iterations, 4)
$summary = [pscustomobject]@{
    base_url = $BaseUrl
    call_type = $callType
    iterations = $Iterations
    created = $created
    ended = $ended
    success = $success
    failed = $failures.Count
    success_rate_percent = $successRate
    latency_ms = [pscustomobject]@{
        avg = if ($latencies.Count -gt 0) { [int64](($latencies | Measure-Object -Average).Average) } else { 0 }
        p95 = Percentile -Values $latencies.ToArray() -Percentile 95
        p99 = Percentile -Values $latencies.ToArray() -Percentile 99
        max = if ($latencies.Count -gt 0) { [int64](($latencies | Measure-Object -Maximum).Maximum) } else { 0 }
    }
    failures = @($failures)
}

$summary | ConvertTo-Json -Depth 8
if ($failures.Count -gt 0) {
    exit 1
}
