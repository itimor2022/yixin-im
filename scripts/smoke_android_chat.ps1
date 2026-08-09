<#
.SYNOPSIS
在 Android 设备上执行登录、进入私聊和消息可见性 smoke。

.DESCRIPTION
准备 Alice/Bob 测试账号和消息，构建或安装 APK，再通过 ADB 驱动客户端
进入目标聊天并保存证据。默认测试账号只适用于本地测试后端；脚本可能清除
目标包数据，使用 -KeepAppData 才会保留现有登录态。

.PARAMETER DeviceId
运行聊天 smoke 的 ADB 设备。

.PARAMETER Username
客户端登录账号。

.PARAMETER PeerUsername
后端准备并在客户端打开的对端账号。

.PARAMETER KeepAppData
保留应用数据；可能使既有登录态影响测试结果。

.EXAMPLE
pwsh -File scripts/smoke_android_chat.ps1 -DeviceId emulator-5554 -SkipBuild
#>
param(
    [string]$DeviceId = "",
    [string]$PackageName = "com.genericim.app",
    [string]$ApiBaseUrl = "http://127.0.0.1:8080",
    [string]$ServerUrl = "http://10.0.2.2:8080",
    [string]$WsUrl = "ws://10.0.2.2:8080/api/v1/ws",
    [string]$HostHealthUrl = "http://127.0.0.1:8080/health",
    [string]$OutputDir = "build/smoke",
    [string]$ApkPath = "",
    [string]$Username = "smoke_alice",
    [string]$Password = "Smoke123",
    [string]$PeerUsername = "smoke_bob",
    [int]$LaunchWaitSeconds = 30,
    [int]$UiWaitSeconds = 45,
    [switch]$SkipPubGet,
    [switch]$SkipAnalyze,
    [switch]$SkipBuild,
    [switch]$SkipDeviceBackendProbe,
    [switch]$KeepAppData
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RepoRoot {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent $PSCommandPath
    }
    if (-not $scriptDir) {
        throw "Could not determine script directory."
    }
    return (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Get-AdbCommand {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @()
    if ($env:ANDROID_HOME) {
        $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe")
    }
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe")
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Could not find adb. Install Android platform-tools or add adb to PATH."
}

function Resolve-DeviceId {
    param(
        [string]$Adb,
        [string]$PreferredDeviceId
    )

    $devices = & $Adb devices
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices failed."
    }

    $online = @(
        $devices |
            Where-Object { $_ -match "\tdevice$" } |
            ForEach-Object { ($_ -split "\s+")[0] }
    )

    if ($PreferredDeviceId) {
        if ($online -contains $PreferredDeviceId) {
            return $PreferredDeviceId
        }
        throw "Device '$PreferredDeviceId' is not online. Online devices: $($online -join ', ')"
    }

    if ($online.Count -eq 0) {
        throw "No online Android device or emulator found."
    }

    return $online[0]
}

function Invoke-AdbShell {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$Command
    )

    return & $Adb -s $Device shell $Command
}

function Get-BoundsCenter {
    param([string]$Bounds)

    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) {
        return $null
    }

    $x1 = [int]$match.Groups[1].Value
    $y1 = [int]$match.Groups[2].Value
    $x2 = [int]$match.Groups[3].Value
    $y2 = [int]$match.Groups[4].Value

    return [pscustomobject]@{
        X = [int](($x1 + $x2) / 2)
        Y = [int](($y1 + $y2) / 2)
    }
}

function Get-NodeAttribute {
    param(
        [string]$Node,
        [string]$Name
    )

    $match = [regex]::Match($Node, "$Name=`"([^`"]*)`"")
    if (-not $match.Success) {
        return ""
    }
    return $match.Groups[1].Value
}

function Get-UiNodes {
    param([string]$XmlText)

    return @(
        [regex]::Matches($XmlText, '<node\b[^>]*>') |
            ForEach-Object { $_.Value }
    )
}

function Get-UiDump {
    param(
        [string]$Adb,
        [string]$Device
    )

    Invoke-AdbShell -Adb $Adb -Device $Device -Command "uiautomator dump /sdcard/genericim_chat_smoke_window.xml" | Out-Null
    $xml = Invoke-AdbShell -Adb $Adb -Device $Device -Command "cat /sdcard/genericim_chat_smoke_window.xml"
    return ($xml -join "`n")
}

function Tap-Bounds {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$Bounds
    )

    $center = Get-BoundsCenter -Bounds $Bounds
    if ($null -eq $center) {
        throw "Invalid UI bounds: $Bounds"
    }
    Invoke-AdbShell -Adb $Adb -Device $Device -Command "input tap $($center.X) $($center.Y)" | Out-Null
}

function Try-TapRuntimePermissionDialog {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$XmlText
    )

    if ($XmlText -notmatch 'permissioncontroller') {
        return $false
    }

    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'permission_allow_button') {
            continue
        }

        $bounds = Get-NodeAttribute -Node $node -Name "bounds"
        if ([string]::IsNullOrWhiteSpace($bounds)) {
            continue
        }

        Tap-Bounds -Adb $Adb -Device $Device -Bounds $bounds
        Start-Sleep -Seconds 1
        return $true
    }

    return $false
}

function Find-FirstNode {
    param(
        [string]$XmlText,
        [scriptblock]$Predicate
    )

    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if (& $Predicate $node) {
            return $node
        }
    }

    return $null
}

function Escape-AdbInputText {
    param([string]$Text)

    return ($Text -replace ' ', '%s')
}

function Input-TextAtNode {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$Node,
        [string]$Text
    )

    $bounds = Get-NodeAttribute -Node $Node -Name "bounds"
    Tap-Bounds -Adb $Adb -Device $Device -Bounds $bounds
    Start-Sleep -Milliseconds 500
    $deleteKeys = ((1..32 | ForEach-Object { "KEYCODE_DEL" }) -join " ")
    Invoke-AdbShell -Adb $Adb -Device $Device -Command "input keyevent KEYCODE_MOVE_END $deleteKeys" | Out-Null
    Start-Sleep -Milliseconds 200
    $escaped = Escape-AdbInputText -Text $Text
    Invoke-AdbShell -Adb $Adb -Device $Device -Command "input text $escaped" | Out-Null
    Start-Sleep -Milliseconds 500
}

function Scroll-UiUp {
    param(
        [string]$Adb,
        [string]$Device
    )

    $sizeOutput = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "wm size") -join "`n"
    $sizeMatch = [regex]::Matches($sizeOutput, '(\d+)x(\d+)') | Select-Object -Last 1
    $width = if ($null -ne $sizeMatch) { [int]$sizeMatch.Groups[1].Value } else { 1080 }
    $height = if ($null -ne $sizeMatch) { [int]$sizeMatch.Groups[2].Value } else { 1920 }
    $x = [int]($width * 0.5)
    $startY = [int]($height * 0.85)
    $endY = [int]($height * 0.35)
    Invoke-AdbShell -Adb $Adb -Device $Device -Command "input swipe $x $startY $x $endY 500" | Out-Null
}

function Wait-ForUiMatch {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$PackageName,
        [int]$TimeoutSeconds,
        [scriptblock]$Predicate,
        [string]$FailureLabel
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastXml = ""
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2

        $appPid = (Invoke-AdbShell -Adb $Adb -Device $Device -Command "pidof $PackageName") -join ""
        if ([string]::IsNullOrWhiteSpace($appPid)) {
            throw "App process '$PackageName' is not running."
        }

        $lastXml = Get-UiDump -Adb $Adb -Device $Device
        if (Try-TapRuntimePermissionDialog -Adb $Adb -Device $Device -XmlText $lastXml) {
            continue
        }

        if (& $Predicate $lastXml) {
            return $lastXml
        }
    }

    throw "$FailureLabel was not detected within $TimeoutSeconds seconds. Last UI dump: $lastXml"
}

function Login-ThroughUi {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$PackageName,
        [string]$Username,
        [string]$Password,
        [int]$TimeoutSeconds
    )

    $loginButtonLabel = [string]::Concat([char]0x767B, [char]0x5F55)

    $xml = Wait-ForUiMatch -Adb $Adb -Device $Device -PackageName $PackageName -TimeoutSeconds $TimeoutSeconds -FailureLabel "Login form" -Predicate {
        param([string]$XmlText)
        $editTextCount = [regex]::Matches($XmlText, 'class="android\.widget\.EditText"').Count
        return $editTextCount -ge 2 -and
            $XmlText -match 'password="true"' -and
            $XmlText.Contains("content-desc=`"$loginButtonLabel`"")
    }

    $editNodes = @(
        Get-UiNodes -XmlText $xml |
            Where-Object { $_ -match 'class="android\.widget\.EditText"' }
    )
    if ($editNodes.Count -lt 2) {
        throw "Login form did not expose two EditText nodes."
    }

    Input-TextAtNode -Adb $Adb -Device $Device -Node $editNodes[0] -Text $Username
    Input-TextAtNode -Adb $Adb -Device $Device -Node $editNodes[1] -Text $Password

    Invoke-AdbShell -Adb $Adb -Device $Device -Command "input keyevent 4" | Out-Null
    Start-Sleep -Milliseconds 700

    $agreementReady = $false
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $xml = Get-UiDump -Adb $Adb -Device $Device
        $checkbox = Find-FirstNode -XmlText $xml -Predicate {
            param([string]$Node)
            return $Node -match 'class="android\.widget\.CheckBox"'
        }
        if ($null -ne $checkbox) {
            if ($checkbox -match 'checked="false"') {
                Tap-Bounds -Adb $Adb -Device $Device -Bounds (Get-NodeAttribute -Node $checkbox -Name "bounds")
                Start-Sleep -Milliseconds 500
            }
            $agreementReady = $true
            break
        }

        Scroll-UiUp -Adb $Adb -Device $Device
        Start-Sleep -Milliseconds 700
    }
    if (-not $agreementReady) {
        throw "Login agreement checkbox was not found after scrolling."
    }

    $xml = Get-UiDump -Adb $Adb -Device $Device
    $loginButton = Find-FirstNode -XmlText $xml -Predicate {
        param([string]$Node)
        return $Node -match 'class="android\.widget\.Button"' -and $Node.Contains("content-desc=`"$loginButtonLabel`"")
    }
    if ($null -eq $loginButton) {
        throw "Login button was not found."
    }

    Tap-Bounds -Adb $Adb -Device $Device -Bounds (Get-NodeAttribute -Node $loginButton -Name "bounds")
}

function Find-DisplayNode {
    param(
        [string]$XmlText,
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
            $text = Get-NodeAttribute -Node $node -Name "text"
            $desc = Get-NodeAttribute -Node $node -Name "content-desc"
            if ($text.Contains($candidate) -or $desc.Contains($candidate)) {
                return $node
            }
        }
    }

    return $null
}

function Send-MessageThroughUi {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$PackageName,
        [string]$MessageText,
        [int]$TimeoutSeconds
    )

    $xml = Get-UiDump -Adb $Adb -Device $Device
    $inputNode = Find-FirstNode -XmlText $xml -Predicate {
        param([string]$Node)
        return $Node -match 'class="android\.widget\.EditText"' -and
            $Node.Contains("package=`"$PackageName`"")
    }
    if ($null -eq $inputNode) {
        throw "Chat input field was not found."
    }

    Input-TextAtNode -Adb $Adb -Device $Device -Node $inputNode -Text $MessageText
    Start-Sleep -Milliseconds 800

    $xml = Get-UiDump -Adb $Adb -Device $Device
    $inputNode = Find-FirstNode -XmlText $xml -Predicate {
        param([string]$Node)
        return $Node -match 'class="android\.widget\.EditText"' -and
            $Node.Contains("package=`"$PackageName`"")
    }
    if ($null -eq $inputNode) {
        throw "Chat input field disappeared after typing."
    }

    $inputBounds = Get-NodeAttribute -Node $inputNode -Name "bounds"
    $inputMatch = [regex]::Match($inputBounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $inputMatch.Success) {
        throw "Chat input bounds are invalid: $inputBounds"
    }
    $inputRight = [int]$inputMatch.Groups[3].Value
    $inputTop = [int]$inputMatch.Groups[2].Value
    $inputBottom = [int]$inputMatch.Groups[4].Value

    $sendCandidates = foreach ($node in (Get-UiNodes -XmlText $xml)) {
        if (-not $node.Contains("package=`"$PackageName`"") -or
            $node -notmatch 'clickable="true"' -or
            $node -match 'class="android\.widget\.EditText"') {
            continue
        }
        $bounds = Get-NodeAttribute -Node $node -Name "bounds"
        $match = [regex]::Match($bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        if (-not $match.Success) { continue }
        $left = [int]$match.Groups[1].Value
        $top = [int]$match.Groups[2].Value
        $right = [int]$match.Groups[3].Value
        $bottom = [int]$match.Groups[4].Value
        $overlapsInput = $bottom -gt $inputTop -and $top -lt $inputBottom
        if ($left -ge $inputRight -and $overlapsInput) {
            [pscustomobject]@{
                Node = $node
                Bounds = $bounds
                Left = $left
                Right = $right
            }
        }
    }

    $sendNode = $sendCandidates | Sort-Object Right -Descending | Select-Object -First 1
    if ($null -eq $sendNode) {
        throw "Send button was not found to the right of the chat input."
    }
    Tap-Bounds -Adb $Adb -Device $Device -Bounds $sendNode.Bounds

    return (Wait-ForUiMatch -Adb $Adb -Device $Device -PackageName $PackageName -TimeoutSeconds $TimeoutSeconds -FailureLabel "Android UI sent message" -Predicate {
        param([string]$XmlText)
        return $XmlText.Contains($MessageText)
    })
}

function Assert-MessageThroughBackendApi {
    param(
        [string]$ApiBaseUrl,
        [string]$Username,
        [string]$Password,
        [string]$ChatId,
        [string]$MessageText
    )

    $login = Invoke-RestMethod `
        -Method Post `
        -Uri "$($ApiBaseUrl.TrimEnd('/'))/api/v1/auth/login" `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{
            username = $Username
            password = $Password
            device_id = "codex-smoke-api-$Username"
            device_type = 'android'
            device_name = 'Codex Android UI Smoke'
        } | ConvertTo-Json) `
        -TimeoutSec 20
    if ([int]$login.code -ne 0) {
        throw "Backend verification login failed: code=$($login.code) message=$($login.message)"
    }

    $token = [string]$login.data.token
    $headers = @{ Authorization = "Bearer $token" }
    $messageList = Invoke-RestMethod `
        -Method Get `
        -Uri "$($ApiBaseUrl.TrimEnd('/'))/api/v1/message/list?chat_id=$([uri]::EscapeDataString($ChatId))&limit=50" `
        -Headers $headers `
        -TimeoutSec 20
    if ([int]$messageList.code -ne 0 -or
        (($messageList.data | ConvertTo-Json -Depth 30 -Compress) -notmatch [regex]::Escape($MessageText))) {
        throw "Backend message list does not contain Android UI message: $MessageText"
    }
}

function Assert-NoCrashLogs {
    param(
        [string]$Adb,
        [string]$Device
    )

    $log = & $Adb -s $Device logcat -d -v time
    $legacyPrefix = "gao"
    $legacyPackage = $legacyPrefix + "_ran_im"
    $legacyDomain = "com\." + $legacyPrefix + "ran"
    $failurePattern = "Dart_LookupLibrary|FATAL EXCEPTION|E/flutter\s*\(|FlutterError|package:$legacyPackage|$legacyPackage|$legacyDomain"
    $failures = @(
        $log |
            Select-String -Pattern $failurePattern
    )

    if ($failures.Count -gt 0) {
        $tail = ($failures | Select-Object -Last 40 | ForEach-Object { $_.Line }) -join "`n"
        throw "Crash or legacy-brand log detected:`n$tail"
    }
}

$repoRoot = Get-RepoRoot
$resolvedOutputDir = Join-Path $repoRoot $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

Push-Location $repoRoot
try {
    $runId = Get-Date -Format "yyyyMMdd-HHmmss"
    $apiOutputPath = Join-Path $resolvedOutputDir "chat-api-$runId.json"

    Write-Step "Prepare chat data through backend API"
    $apiScript = Join-Path $repoRoot "scripts\smoke_chat_api.ps1"
    $apiRaw = & $apiScript -BaseUrl $ApiBaseUrl -AliceUsername $Username -BobUsername $PeerUsername -Password $Password -OutputPath $apiOutputPath
    $apiJson = ($apiRaw -join "`n")
    $apiResult = $apiJson | ConvertFrom-Json
    Write-Host "Chat ID: $($apiResult.chat_id)"
    Write-Host "Message: $($apiResult.message_text)"

    Write-Step "Install and launch app to login screen"
    $loginSmokeScript = Join-Path $repoRoot "scripts\smoke_android.ps1"
    $loginSmokeArgs = @{
        PackageName = $PackageName
        ServerUrl = $ServerUrl
        WsUrl = $WsUrl
        HostHealthUrl = $HostHealthUrl
        OutputDir = $OutputDir
        LaunchWaitSeconds = $LaunchWaitSeconds
    }
    if ($DeviceId) { $loginSmokeArgs["DeviceId"] = $DeviceId }
    if ($ApkPath) { $loginSmokeArgs["ApkPath"] = $ApkPath }
    if ($SkipPubGet) { $loginSmokeArgs["SkipPubGet"] = $true }
    if ($SkipAnalyze) { $loginSmokeArgs["SkipAnalyze"] = $true }
    if ($SkipBuild) { $loginSmokeArgs["SkipBuild"] = $true }
    if ($SkipDeviceBackendProbe) { $loginSmokeArgs["SkipDeviceBackendProbe"] = $true }
    if (-not $KeepAppData) { $loginSmokeArgs["ClearAppData"] = $true }

    & $loginSmokeScript @loginSmokeArgs

    $adb = Get-AdbCommand
    $DeviceId = Resolve-DeviceId -Adb $adb -PreferredDeviceId $DeviceId

    Write-Step "Login through Android UI"
    Login-ThroughUi -Adb $adb -Device $DeviceId -PackageName $PackageName -Username $Username -Password $Password -TimeoutSeconds $UiWaitSeconds

    $peerCandidates = @(
        [string]$apiResult.bob_nickname,
        [string]$apiResult.bob,
        $PeerUsername
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    Write-Step "Wait for chat list and open peer chat"
    $listXml = Wait-ForUiMatch -Adb $adb -Device $DeviceId -PackageName $PackageName -TimeoutSeconds $UiWaitSeconds -FailureLabel "Peer chat list item" -Predicate {
        param([string]$XmlText)
        return $null -ne (Find-DisplayNode -XmlText $XmlText -Candidates $peerCandidates)
    }

    $peerNode = Find-DisplayNode -XmlText $listXml -Candidates $peerCandidates
    if ($null -eq $peerNode) {
        throw "Peer chat node was not found after wait."
    }
    Tap-Bounds -Adb $adb -Device $DeviceId -Bounds (Get-NodeAttribute -Node $peerNode -Name "bounds")

    Write-Step "Assert sent message is visible in chat detail"
    $messageText = [string]$apiResult.message_text
    $detailXml = Wait-ForUiMatch -Adb $adb -Device $DeviceId -PackageName $PackageName -TimeoutSeconds $UiWaitSeconds -FailureLabel "Sent chat message" -Predicate {
        param([string]$XmlText)
        return $XmlText.Contains($messageText)
    }

    $uiMessageText = "codex_android_ui_$runId"
    Write-Step "Send a message through Android UI"
    $detailXml = Send-MessageThroughUi `
        -Adb $adb `
        -Device $DeviceId `
        -PackageName $PackageName `
        -MessageText $uiMessageText `
        -TimeoutSeconds $UiWaitSeconds

    Write-Step "Verify Android UI message through backend API"
    Assert-MessageThroughBackendApi `
        -ApiBaseUrl $ApiBaseUrl `
        -Username $Username `
        -Password $Password `
        -ChatId ([string]$apiResult.chat_id) `
        -MessageText $uiMessageText

    Write-Step "Check crash logs"
    Assert-NoCrashLogs -Adb $adb -Device $DeviceId

    $remoteScreenshot = "/sdcard/genericim_chat_smoke_$runId.png"
    $screenshotPath = Join-Path $resolvedOutputDir "android-chat-smoke-$runId.png"
    $xmlPath = Join-Path $resolvedOutputDir "android-chat-smoke-$runId.xml"

    Write-Step "Capture chat smoke evidence"
    Invoke-AdbShell -Adb $adb -Device $DeviceId -Command "screencap -p $remoteScreenshot" | Out-Null
    & $adb -s $DeviceId pull $remoteScreenshot $screenshotPath | Out-Null
    Set-Content -LiteralPath $xmlPath -Value $detailXml -Encoding utf8

    Write-Host ""
    Write-Host "Android chat smoke passed." -ForegroundColor Green
    Write-Host "API data:   $apiOutputPath"
    Write-Host "Screenshot: $screenshotPath"
    Write-Host "UI dump:    $xmlPath"
}
finally {
    Pop-Location
}
