<#
.SYNOPSIS
快速验证 Android 真机上的消息落盘和进程重启恢复。

.DESCRIPTION
在指定设备进入已有测试会话，记录消息状态，执行页面切换或应用重启后再次
检查同一消息，并保存截图与日志。脚本依赖 BaseDir 中已经准备好的测试数据，
会操作目标应用进程和当前页面。

.PARAMETER DeviceB
执行消息持久化检查的 ADB 真机序列号。

.PARAMETER DelayMs
ADB 操作之间的稳定等待毫秒数。

.PARAMETER SkipLogcatClear
保留运行前日志；可能使本轮错误筛选混入旧记录。

.EXAMPLE
pwsh -File scripts/fast_real_device_message_persistence.ps1
#>
param(
    [string]$BaseDir = "artifacts\real-device-test-20260623-233903",
    [string]$DeviceB = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.ma100",
    [int]$DelayMs = 450,
    [switch]$SkipLogcatClear
)

$ErrorActionPreference = "Stop"

function Join-Chars {
    param([int[]]$Codes)
    return -join ($Codes | ForEach-Object { [char]$_ })
}

function New-Timestamp { return (Get-Date).ToString("yyyyMMdd-HHmmss") }
function Get-IsoNow { return (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz") }

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-AdbCommand {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe") }
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe") }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe") }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "adb not found."
}

function Short-Path {
    param([string]$Path)
    return $Path.Replace("/", "\")
}

function Invoke-AdbQuiet {
    param([string]$Adb, [string[]]$Arguments)
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Adb @Arguments 2>$null | Out-Null
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

function Invoke-Tap {
    param([string]$Adb, [string]$Serial, [int]$X, [int]$Y)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "input", "tap", "$X", "$Y")
}

function Invoke-Back {
    param([string]$Adb, [string]$Serial)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "input", "keyevent", "KEYCODE_BACK")
}

function Invoke-Home {
    param([string]$Adb, [string]$Serial)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "input", "keyevent", "KEYCODE_HOME")
}

function Invoke-ForceStop {
    param([string]$Adb, [string]$Serial, [string]$PackageName)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "am", "force-stop", $PackageName)
}

function Invoke-InputText {
    param([string]$Adb, [string]$Serial, [string]$Text)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "input", "text", $Text)
}

function Get-NodeAttribute {
    param([string]$Node, [string]$Name)
    $match = [regex]::Match($Node, "$Name=`"([^`"]*)`"")
    if (-not $match.Success) { return "" }
    return [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
}

function Get-UiNodes {
    param([string]$XmlText)
    return @([regex]::Matches($XmlText, '<node\b[^>]*>') | ForEach-Object { $_.Value })
}

function Get-BoundsObject {
    param([string]$Bounds)
    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { return $null }
    $x1 = [int]$match.Groups[1].Value
    $y1 = [int]$match.Groups[2].Value
    $x2 = [int]$match.Groups[3].Value
    $y2 = [int]$match.Groups[4].Value
    return [pscustomobject]@{
        X1 = $x1; Y1 = $y1; X2 = $x2; Y2 = $y2
        X = [int](($x1 + $x2) / 2)
        Y = [int](($y1 + $y2) / 2)
        Width = $x2 - $x1
        Height = $y2 - $y1
    }
}

function Find-NodeByDesc {
    param([string]$XmlText, [string]$Text, [switch]$Contains, [switch]$ClickableOnly)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($ClickableOnly -and $node -notmatch 'clickable="true"') { continue }
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ($Contains) {
            if ($desc -like "*$Text*") { return $node }
        } elseif ($desc -eq $Text) {
            return $node
        }
    }
    return $null
}

function Find-NodeByClass {
    param([string]$XmlText, [string]$Class)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -match "class=`"$([regex]::Escape($Class))`"") { return $node }
    }
    return $null
}

function Test-VisibleMessageOutsideInput {
    param([string]$XmlText, [string]$Text)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -match 'class="android.widget.EditText"') { continue }
        $nodeText = Get-NodeAttribute -Node $node -Name "text"
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ($nodeText.Contains($Text) -or $desc.Contains($Text)) { return $true }
    }
    return $false
}

function Find-BottomNodeByDesc {
    param([string]$XmlText, [string]$Text, [int]$MinY1)
    $best = $null
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ($desc -ne $Text) { continue }
        $box = Get-BoundsObject -Bounds (Get-NodeAttribute -Node $node -Name "bounds")
        if ($null -eq $box -or $box.Y1 -lt $MinY1) { continue }
        if ($null -eq $best -or $box.Y1 -gt $best.Box.Y1) {
            $best = [pscustomobject]@{ Node = $node; Box = $box }
        }
    }
    if ($best) { return $best.Node }
    return $null
}

function Find-ConversationEntryBySecondLine {
    param([string]$XmlText, [string]$Title)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'clickable="true"') { continue }
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ([string]::IsNullOrWhiteSpace($desc)) { continue }
        $parts = @($desc -split "`n")
        if ($parts.Count -ge 2 -and $parts[1] -eq $Title) { return $node }
    }
    return $null
}

function Tap-Node {
    param([string]$Adb, [string]$Serial, [string]$Node)
    if ([string]::IsNullOrWhiteSpace($Node)) { throw "Tap-Node received an empty node." }
    $box = Get-BoundsObject -Bounds (Get-NodeAttribute -Node $Node -Name "bounds")
    if ($null -eq $box) { throw "Invalid node bounds." }
    Invoke-Tap -Adb $Adb -Serial $Serial -X $box.X -Y $box.Y
    return $box
}

function Get-PhysicalScreenSize {
    param([string]$Adb, [string]$Serial)
    $output = (& $Adb -s $Serial shell wm size) -join "`n"
    $match = [regex]::Match($output, 'Physical size:\s*(\d+)x(\d+)')
    if (-not $match.Success) { return [pscustomobject]@{ Width = 1200; Height = 2640; Raw = $output } }
    return [pscustomobject]@{
        Width = [int]$match.Groups[1].Value
        Height = [int]$match.Groups[2].Value
        Raw = $output
    }
}

function Capture-State {
    param([string]$Adb, [string]$Serial, [string]$Label, [string]$Suffix, [string]$DeviceDir)
    $ts = New-Timestamp
    $safe = "$Label-$Suffix-$ts"
    $remoteXml = "/sdcard/$safe.xml"
    $remotePng = "/sdcard/$safe.png"
    $xmlPath = Join-Path $DeviceDir "$safe.xml"
    $pngPath = Join-Path $DeviceDir "$safe.png"

    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "uiautomator", "dump", $remoteXml)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "pull", $remoteXml, $xmlPath)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "screencap", "-p", $remotePng)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "pull", $remotePng, $pngPath)

    $xmlText = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
    $pngBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $pngPath))
    $pngValid = $pngBytes.Length -ge 8 -and $pngBytes[0] -eq 0x89 -and $pngBytes[1] -eq 0x50 -and $pngBytes[2] -eq 0x4E -and $pngBytes[3] -eq 0x47

    return [pscustomobject]@{
        XmlPath = $xmlPath
        PngPath = $pngPath
        XmlText = $xmlText
        PngValid = $pngValid
    }
}

function Save-Logcat {
    param([string]$Adb, [string]$Serial, [string]$Path)
    & $Adb -s $Serial logcat -d -v time | Out-File -LiteralPath $Path -Encoding UTF8
}

function Scan-LogcatFile {
    param([string]$Path, [string]$Device)
    $fatalPattern = '(FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|ANR in com\.genericim\.app|Process:\s+com\.genericim\.app|AndroidRuntime.*FATAL)'
    $appPattern = '(E/flutter|FlutterError|Unhandled Exception|com\.genericim\.app.*(Exception|Error))'
    $toolPattern = '(com\.android\.uiautomator|AccessibilityNodeInfoDumper|RuntimeInit: Starting tool|Calling main entry com\.android\.commands\.uiautomator\.Launcher)'
    $fatal = @(Select-String -LiteralPath $Path -Pattern $fatalPattern -AllMatches -ErrorAction SilentlyContinue)
    $appRaw = @(Select-String -LiteralPath $Path -Pattern $appPattern -AllMatches -ErrorAction SilentlyContinue)
    $app = @($appRaw | Where-Object {
        $line = $_.Line
        if ($line -match 'D/Watchdog' -and
            $line -match 'app_package"?:"?com\.genericim\.app' -and
            $line -match 'error"?\s*:\s*\{\\?"?code\\?"?\s*:\s*0\s*,\\?"?msg\\?"?\s*:\s*\\?"?ok') {
            return $false
        }
        return $true
    })
    $tool = @(Select-String -LiteralPath $Path -Pattern $toolPattern -AllMatches -ErrorAction SilentlyContinue)
    return [ordered]@{
        device = $Device
        log = Short-Path $Path
        fatal_pattern_count = $fatal.Count
        app_error_pattern_count = $app.Count
        tool_pattern_count = $tool.Count
        fatal_samples = @($fatal | Select-Object -First 8 | ForEach-Object { $_.Line })
        app_error_samples = @($app | Select-Object -First 8 | ForEach-Object { $_.Line })
    }
}

function Add-Event {
    param([string]$EventsPath, [string]$CaseId, [string]$Device, [string]$Module, [string]$Status, [string]$Detail, [int]$DurationSeconds)
    $event = [ordered]@{
        time = Get-IsoNow
        case_id = $CaseId
        device = $Device
        module = $Module
        status = $Status
        detail = $Detail
        duration_seconds = $DurationSeconds
    }
    Add-Content -LiteralPath $EventsPath -Value (($event | ConvertTo-Json -Compress -Depth 6)) -Encoding UTF8
}

function Add-Result {
    param([string]$CaseId, [string]$Device, [string]$Serial, [string]$Flow, [string]$Status, [string[]]$Evidence, [hashtable]$Assertions, [string]$Detail, [int]$DurationSeconds)
    $script:Results.Add([ordered]@{
        case_id = $CaseId
        device = $Device
        serial = $Serial
        flow = $Flow
        status = $Status
        evidence = @($Evidence | ForEach-Object { Short-Path $_ })
        assertions = $Assertions
        detail = $Detail
        duration_seconds = $DurationSeconds
    }) | Out-Null
    Add-Event -EventsPath $script:EventsPath -CaseId $CaseId -Device $Serial -Module $Flow -Status $Status -Detail $Detail -DurationSeconds $DurationSeconds
}

function Run-Flow {
    param([string]$CaseId, [string]$Device, [string]$Serial, [string]$Flow, [scriptblock]$Body)
    $start = Get-Date
    try {
        $result = & $Body
        Add-Result -CaseId $CaseId -Device $Device -Serial $Serial -Flow $Flow -Status $result.Status -Evidence $result.Evidence -Assertions $result.Assertions -Detail $result.Detail -DurationSeconds ([int]((Get-Date) - $start).TotalSeconds)
    } catch {
        Add-Result -CaseId $CaseId -Device $Device -Serial $Serial -Flow $Flow -Status "TOOL_WARN" -Evidence @() -Assertions @{} -Detail "Message-persistence exception: $($_.Exception.Message)" -DurationSeconds ([int]((Get-Date) - $start).TotalSeconds)
    }
}

function New-FlowOutput {
    param([string]$Status, [string[]]$Evidence, [hashtable]$Assertions, [string]$Detail)
    return [pscustomobject]@{
        Status = $Status
        Evidence = @($Evidence)
        Assertions = $Assertions
        Detail = $Detail
    }
}

function Ensure-AppForeground {
    param([string]$Adb, [string]$Serial)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "monkey", "-p", $script:PackageName, "-c", "android.intent.category.LAUNCHER", "1")
    Start-Sleep -Milliseconds $script:DelayMs
}

function Ensure-BottomTab {
    param([string]$Adb, [string]$Serial, [string]$Label, [double]$XRatio, [string]$DeviceLabel)
    Ensure-AppForeground -Adb $Adb -Serial $Serial
    $screen = Get-PhysicalScreenSize -Adb $Adb -Serial $Serial
    $state = $null
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $state = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "persist-nav" -DeviceDir $script:DeviceDir
        if ($state.XmlText -notlike "*package=`"$script:PackageName`"*") {
            Ensure-AppForeground -Adb $Adb -Serial $Serial
            continue
        }
        $node = Find-BottomNodeByDesc -XmlText $state.XmlText -Text $Label -MinY1 ([int]($screen.Height * 0.78))
        if ($node) {
            Tap-Node -Adb $Adb -Serial $Serial -Node $node | Out-Null
            Start-Sleep -Milliseconds $script:DelayMs
            return
        }
        Invoke-Back -Adb $Adb -Serial $Serial
        Start-Sleep -Milliseconds $script:DelayMs
    }
    Invoke-Tap -Adb $Adb -Serial $Serial -X ([int]($screen.Width * $XRatio)) -Y ([Math]::Max(1, $screen.Height - 90))
    Start-Sleep -Milliseconds $script:DelayMs
}

function Open-PrivateChat {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel)
    Ensure-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Messages -XRatio 0.22 -DeviceLabel $DeviceLabel
    $list = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "persist-private-list" -DeviceDir $script:DeviceDir
    $entry = Find-ConversationEntryBySecondLine -XmlText $list.XmlText -Title "Smoke Alice"
    if (-not $entry) { $entry = Find-NodeByDesc -XmlText $list.XmlText -Text "Smoke Alice" -Contains -ClickableOnly }
    if (-not $entry) { throw "Smoke Alice conversation not visible." }
    Tap-Node -Adb $Adb -Serial $Serial -Node $entry | Out-Null
    Start-Sleep -Milliseconds $script:DelayMs
}

function Open-GroupChat {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel)
    Ensure-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Messages -XRatio 0.22 -DeviceLabel $DeviceLabel
    $list = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "persist-group-list" -DeviceDir $script:DeviceDir
    $entry = Find-NodeByDesc -XmlText $list.XmlText -Text "Codex qaGroup" -Contains -ClickableOnly
    if (-not $entry) {
        $groupFilter = Find-NodeByDesc -XmlText $list.XmlText -Text $script:T.Group
        if ($groupFilter) {
            Tap-Node -Adb $Adb -Serial $Serial -Node $groupFilter | Out-Null
            Start-Sleep -Milliseconds $script:DelayMs
            $list = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "persist-group-filter" -DeviceDir $script:DeviceDir
            $entry = Find-NodeByDesc -XmlText $list.XmlText -Text "Codex qaGroup" -Contains -ClickableOnly
        }
    }
    if (-not $entry) { throw "Codex qaGroup conversation not visible." }
    Tap-Node -Adb $Adb -Serial $Serial -Node $entry | Out-Null
    Start-Sleep -Milliseconds $script:DelayMs
    $groupState = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "persist-group-opened" -DeviceDir $script:DeviceDir
    if (-not (Find-NodeByClass -XmlText $groupState.XmlText -Class "android.widget.EditText")) {
        $joinNode = Find-NodeByDesc -XmlText $groupState.XmlText -Text $script:T.JoinGroup -Contains
        if ($joinNode) {
            Tap-Node -Adb $Adb -Serial $Serial -Node $joinNode | Out-Null
            Start-Sleep -Milliseconds 1600
        }
    }
}

function Send-TextInCurrentChat {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel, [string]$Text, [string]$Suffix)
    $before = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "$Suffix-before" -DeviceDir $script:DeviceDir
    $edit = Find-NodeByClass -XmlText $before.XmlText -Class "android.widget.EditText"
    if (-not $edit) { throw "Chat input EditText not found." }
    Tap-Node -Adb $Adb -Serial $Serial -Node $edit | Out-Null
    Start-Sleep -Milliseconds $script:DelayMs
    Invoke-InputText -Adb $Adb -Serial $Serial -Text $Text
    Start-Sleep -Milliseconds $script:DelayMs

    $typed = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "$Suffix-typed" -DeviceDir $script:DeviceDir
    $sendNode = Find-NodeByDesc -XmlText $typed.XmlText -Text $script:T.Send -ClickableOnly
    if (-not $sendNode) { $sendNode = Find-NodeByDesc -XmlText $typed.XmlText -Text $script:T.Send }
    if ($sendNode) {
        Tap-Node -Adb $Adb -Serial $Serial -Node $sendNode | Out-Null
    } else {
        $screen = Get-PhysicalScreenSize -Adb $Adb -Serial $Serial
        $typedEdit = Find-NodeByClass -XmlText $typed.XmlText -Class "android.widget.EditText"
        $typedEditBox = if ($typedEdit) { Get-BoundsObject -Bounds (Get-NodeAttribute -Node $typedEdit -Name "bounds") } else { $null }
        $sendY = if ($typedEditBox) { $typedEditBox.Y } else { [int]($screen.Height * 0.62) }
        Invoke-Tap -Adb $Adb -Serial $Serial -X ([Math]::Max(1, $screen.Width - 92)) -Y $sendY
    }
    Start-Sleep -Milliseconds 1200
    return $typed
}

function Capture-MessageCheck {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel, [string]$Suffix, [string]$Text)
    $state = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix $Suffix -DeviceDir $script:DeviceDir
    return [pscustomobject]@{
        Name = $Suffix
        Visible = (Test-VisibleMessageOutsideInput -XmlText $state.XmlText -Text $Text)
        PngPath = $state.PngPath
        XmlPath = $state.XmlPath
        PngValid = $state.PngValid
    }
}

function Exercise-And-CheckPrivate {
    param([string]$Text)
    $evidence = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.List[object]

    Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    Send-TextInCurrentChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Text $Text -Suffix "persist-private" | Out-Null

    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-after-send" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-list-after-back" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-reopen" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Settings -XRatio 0.78 -DeviceLabel "B-UQG"
    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-list-after-tab-switch" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-after-tab-switch" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Invoke-Home -Adb $adb -Serial $DeviceB
    Start-Sleep -Milliseconds 900
    Ensure-AppForeground -Adb $adb -Serial $DeviceB
    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-list-after-background" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-after-background" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Invoke-ForceStop -Adb $adb -Serial $DeviceB -PackageName $PackageName
    Start-Sleep -Milliseconds 1200
    Ensure-AppForeground -Adb $adb -Serial $DeviceB
    Start-Sleep -Milliseconds 1200
    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-list-after-force-stop" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-private-after-force-stop" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    $missing = @($checks | Where-Object { -not $_.Visible } | ForEach-Object { $_.Name })
    return [pscustomobject]@{
        Evidence = @($evidence.ToArray())
        Checks = @($checks.ToArray())
        Missing = $missing
    }
}

function Exercise-And-CheckGroup {
    param([string]$Text)
    $evidence = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.List[object]

    Open-GroupChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    Send-TextInCurrentChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Text $Text -Suffix "persist-group" | Out-Null

    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-after-send" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-list-after-back" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-GroupChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-reopen" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Settings -XRatio 0.78 -DeviceLabel "B-UQG"
    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-list-after-tab-switch" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-GroupChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-after-tab-switch" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Invoke-Home -Adb $adb -Serial $DeviceB
    Start-Sleep -Milliseconds 900
    Ensure-AppForeground -Adb $adb -Serial $DeviceB
    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-list-after-background" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-GroupChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-after-background" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Invoke-ForceStop -Adb $adb -Serial $DeviceB -PackageName $PackageName
    Start-Sleep -Milliseconds 1200
    Ensure-AppForeground -Adb $adb -Serial $DeviceB
    Start-Sleep -Milliseconds 1200
    Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-list-after-force-stop" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    Open-GroupChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
    $check = Capture-MessageCheck -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG" -Suffix "persist-group-after-force-stop" -Text $Text
    $checks.Add($check) | Out-Null
    $evidence.Add($check.PngPath) | Out-Null
    $evidence.Add($check.XmlPath) | Out-Null

    $missing = @($checks | Where-Object { -not $_.Visible } | ForEach-Object { $_.Name })
    return [pscustomobject]@{
        Evidence = @($evidence.ToArray())
        Checks = @($checks.ToArray())
        Missing = $missing
    }
}

$script:T = [ordered]@{
    Messages = Join-Chars @(0x6D88, 0x606F)
    Settings = Join-Chars @(0x8BBE, 0x7F6E)
    Group = Join-Chars @(0x7FA4, 0x7EC4)
    JoinGroup = Join-Chars @(0x52A0, 0x5165, 0x7FA4, 0x7EC4)
    Send = Join-Chars @(0x53D1, 0x9001)
}

$script:PackageName = $PackageName
$script:DelayMs = $DelayMs
$adb = Get-AdbCommand
$base = $BaseDir
$script:DeviceDir = Join-Path $base "devices"
$logDir = Join-Path $base "logs"
$script:EventsPath = Join-Path $base "events.jsonl"
$reportPath = Join-Path $base "report.md"
Ensure-Dir -Path $base
Ensure-Dir -Path $script:DeviceDir
Ensure-Dir -Path $logDir

$devices = & $adb devices
if (-not ($devices -match "^$([regex]::Escape($DeviceB))\s+device$")) {
    throw "Device $DeviceB is not online."
}

if (-not $SkipLogcatClear) {
    Invoke-AdbQuiet -Adb $adb -Arguments @("-s", $DeviceB, "logcat", "-c")
}

$runTs = New-Timestamp
$privateText = "persistpriv$runTs"
$groupText = "persistgroup$runTs"
$script:Results = New-Object System.Collections.Generic.List[object]

Run-Flow -CaseId "PERSIST-B-PRIVATE-MESSAGE" -Device "B-UQG" -Serial $DeviceB -Flow "Private message persistence" -Body {
    $result = Exercise-And-CheckPrivate -Text $privateText
    $status = if ($result.Missing.Count -eq 0) { "PASS" } else { "FAIL" }
    New-FlowOutput -Status $status -Evidence $result.Evidence -Assertions @{ sent_text = $privateText; missing_stages = $result.Missing; checks = $result.Checks } -Detail "Private test message remains visible after reopen, tab switch, background restore, and force-stop relaunch."
}

Run-Flow -CaseId "PERSIST-B-GROUP-MESSAGE" -Device "B-UQG" -Serial $DeviceB -Flow "Group message persistence" -Body {
    $result = Exercise-And-CheckGroup -Text $groupText
    $status = if ($result.Missing.Count -eq 0) { "PASS" } else { "FAIL" }
    New-FlowOutput -Status $status -Evidence $result.Evidence -Assertions @{ sent_text = $groupText; missing_stages = $result.Missing; checks = $result.Checks } -Detail "Group test message remains visible after reopen, tab switch, background restore, and force-stop relaunch."
}

$finalTs = New-Timestamp
$bLog = Join-Path $logDir "B-UQG-message-persistence-final-$finalTs.log"
Save-Logcat -Adb $adb -Serial $DeviceB -Path $bLog

$scan = [ordered]@{
    generated_at = Get-IsoNow
    package = $PackageName
    suite = "message-persistence-real-device"
    device = "B-UQG"
    scan = Scan-LogcatFile -Path $bLog -Device "B-UQG"
}
$fatalTotal = [int]$scan.scan.fatal_pattern_count
$appTotal = [int]$scan.scan.app_error_pattern_count
$scanStatus = if ($fatalTotal -eq 0 -and $appTotal -eq 0) { "PASS" } else { "FAIL" }
$scanPath = Join-Path $base "message-persistence-final-logcat-scan-$finalTs.json"
$scan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scanPath -Encoding UTF8
Add-Result -CaseId "PERSIST-FINAL-LOGCAT-SCAN" -Device "B-UQG" -Serial $DeviceB -Flow "Message persistence final logcat scan" -Status $scanStatus -Evidence @($scanPath, $bLog) -Assertions @{ fatal_pattern_count = $fatalTotal; app_error_pattern_count = $appTotal } -Detail "fatal=$fatalTotal app_error=$appTotal" -DurationSeconds 1

$resultPath = Join-Path $base "message-persistence-results-$finalTs.json"
$resultArray = @($script:Results.ToArray())
$resultArray | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$passCount = @($resultArray | Where-Object { $_.status -eq "PASS" }).Count
$failCount = @($resultArray | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = @($resultArray | Where-Object { $_.status -eq "TOOL_WARN" }).Count
$totalCount = $resultArray.Count

$latestSummaryJsonPath = Join-Path $base "latest-message-persistence-summary.json"
$latestSummaryMdPath = Join-Path $base "latest-message-persistence-summary.md"
$latestRows = @($resultArray | ForEach-Object {
    [ordered]@{
        case_id = $_.case_id
        device = $_.device
        status = $_.status
        flow = $_.flow
        detail = $_.detail
        first_evidence = if ($_.evidence.Count -gt 0) { $_.evidence[0] } else { "" }
        missing_stages = if ($_.assertions.missing_stages) { @($_.assertions.missing_stages) } else { @() }
    }
})
$summary = [ordered]@{
    generated_at = Get-IsoNow
    authoritative = $true
    suite = "message-persistence-real-device"
    script = "scripts\fast_real_device_message_persistence.ps1"
    command = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fast_real_device_message_persistence.ps1"
    package = $PackageName
    device = $DeviceB
    result_path = Short-Path $resultPath
    scan_path = Short-Path $scanPath
    report_path = Short-Path $reportPath
    events_path = Short-Path $script:EventsPath
    private_text = $privateText
    group_text = $groupText
    total = $totalCount
    pass = $passCount
    fail = $failCount
    tool_warn = $warnCount
    fatal_pattern_count = $fatalTotal
    app_error_pattern_count = $appTotal
    results = $latestRows
}
$summary | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $latestSummaryJsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Latest Message Persistence Real-Device Suite")
$md.Add("")
$md.Add("Generated: $($summary.generated_at)")
$md.Add("")
$md.Add("Command: ``$($summary.command)``")
$md.Add("")
$md.Add("Summary: total=$totalCount, pass=$passCount, fail=$failCount, tool_warn=$warnCount, fatal=$fatalTotal, app_error=$appTotal.")
$md.Add("")
$md.Add("Private text: ``$privateText``")
$md.Add("Group text: ``$groupText``")
$md.Add("")
$md.Add("Artifacts: ``$(Short-Path $resultPath)``, ``$(Short-Path $scanPath)``.")
$md.Add("")
$md.Add("| Case | Device | Result | Missing stages | Evidence |")
$md.Add("| --- | --- | --- | --- | --- |")
foreach ($r in $latestRows) {
    $missing = if ($r.missing_stages.Count -gt 0) { $r.missing_stages -join ", " } else { "" }
    $md.Add("| $($r.case_id) | $($r.device) | $($r.status) | $missing | $($r.first_evidence) |")
}
Set-Content -LiteralPath $latestSummaryMdPath -Value ($md -join [Environment]::NewLine) -Encoding UTF8

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("")
$reportLines.Add("## Message Persistence Real-Device Automation Suite ($((Get-Date).ToString('yyyy-MM-dd HH:mm')) +08:00)")
$reportLines.Add("")
$reportLines.Add("Script: `scripts/fast_real_device_message_persistence.ps1`. This suite sends timestamped private/group test messages and verifies they remain visible after reopen, tab switching, background restore, and force-stop relaunch.")
$reportLines.Add("")
$reportLines.Add("Summary: total=$totalCount, pass=$passCount, fail=$failCount, tool_warn=$warnCount, fatal=$fatalTotal, app_error=$appTotal.")
$reportLines.Add("")
$reportLines.Add("Private text: `$privateText`; group text: `$groupText`.")
$reportLines.Add("Artifacts: ``$(Short-Path $resultPath)``, ``$(Short-Path $scanPath)``, ``$(Short-Path $latestSummaryJsonPath)``, ``$(Short-Path $latestSummaryMdPath)``.")
Add-Content -LiteralPath $reportPath -Value ($reportLines -join [Environment]::NewLine) -Encoding UTF8

[ordered]@{
    result_path = Short-Path $resultPath
    scan_path = Short-Path $scanPath
    latest_summary_json = Short-Path $latestSummaryJsonPath
    latest_summary_md = Short-Path $latestSummaryMdPath
    report_path = Short-Path $reportPath
    events_path = Short-Path $script:EventsPath
    private_text = $privateText
    group_text = $groupText
    total = $totalCount
    pass = $passCount
    fail = $failCount
    tool_warn = $warnCount
    fatal_pattern_count = $fatalTotal
    app_error_pattern_count = $appTotal
} | ConvertTo-Json -Depth 6
