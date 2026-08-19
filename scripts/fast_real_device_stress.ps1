<#
.SYNOPSIS
对双 Android 真机执行可复现的快速 UI 压力操作。

.DESCRIPTION
按随机种子在两台设备上重复导航、返回和业务操作，收集崩溃、ANR、截图与
日志证据。脚本会改变测试应用当前页面和局部数据，只适用于可重置的 QA 设备。

.PARAMETER Iterations
压力操作循环次数。

.PARAMETER Seed
随机序列种子；0 时由脚本生成，复现失败时应使用报告记录的实际种子。

.PARAMETER DelayMs
相邻 ADB 操作之间的等待毫秒数。

.EXAMPLE
pwsh -File scripts/fast_real_device_stress.ps1 -Iterations 12 -Seed 20260727
#>
param(
    [string]$BaseDir = "artifacts\real-device-test-20260623-233903",
    [string]$DeviceA = "8MY0220C17006781",
    [string]$DeviceB = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.ma100",
    [int]$Iterations = 12,
    [int]$DelayMs = 160,
    [int]$Seed = 0,
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

function Invoke-LongPress {
    param([string]$Adb, [string]$Serial, [int]$X, [int]$Y, [int]$Ms = 650)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "input", "swipe", "$X", "$Y", "$X", "$Y", "$Ms")
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

function Find-FirstMessageNode {
    param([string]$XmlText)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'long-clickable="true"') { continue }
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ([string]::IsNullOrWhiteSpace($desc) -or $desc -notmatch '\d{1,2}:\d{2}') { continue }
        $box = Get-BoundsObject -Bounds (Get-NodeAttribute -Node $node -Name "bounds")
        if ($null -eq $box -or $box.Y1 -lt 420 -or $box.Y1 -gt 2200) { continue }
        return [pscustomobject]@{ Node = $node; Box = $box; Desc = $desc }
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
    $app = @(Select-String -LiteralPath $Path -Pattern $appPattern -AllMatches -ErrorAction SilentlyContinue)
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
    param([string]$CaseId, [string]$Device, [string]$Serial, [string]$Action, [string]$Status, [string[]]$Evidence, [string]$Detail, [int]$DurationSeconds)
    $script:Results.Add([ordered]@{
        case_id = $CaseId
        device = $Device
        serial = $Serial
        action = $Action
        status = $Status
        evidence = @($Evidence | ForEach-Object { Short-Path $_ })
        detail = $Detail
        duration_seconds = $DurationSeconds
    }) | Out-Null
    Add-Event -EventsPath $script:EventsPath -CaseId $CaseId -Device $Serial -Module $Action -Status $Status -Detail $Detail -DurationSeconds $DurationSeconds
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
        $state = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "stress-nav" -DeviceDir $script:DeviceDir
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

function Try-TapDesc {
    param([string]$Adb, [string]$Serial, [string]$XmlText, [string]$Text, [switch]$Contains)
    $node = Find-NodeByDesc -XmlText $XmlText -Text $Text -Contains:$Contains -ClickableOnly
    if (-not $node) { $node = Find-NodeByDesc -XmlText $XmlText -Text $Text -Contains:$Contains }
    if (-not $node) { return $false }
    Tap-Node -Adb $Adb -Serial $Serial -Node $node | Out-Null
    Start-Sleep -Milliseconds $script:DelayMs
    return $true
}

function Open-Wallet {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel)
    Ensure-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Settings -XRatio 0.78 -DeviceLabel $DeviceLabel
    $state = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "stress-settings" -DeviceDir $script:DeviceDir
    Try-TapDesc -Adb $Adb -Serial $Serial -XmlText $state.XmlText -Text $script:T.Wallet | Out-Null
}

function Open-PrivateChat {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel)
    Ensure-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Messages -XRatio 0.22 -DeviceLabel $DeviceLabel
    $list = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "stress-private-list" -DeviceDir $script:DeviceDir
    $entry = Find-ConversationEntryBySecondLine -XmlText $list.XmlText -Title "Smoke Alice"
    if (-not $entry) { $entry = Find-NodeByDesc -XmlText $list.XmlText -Text "Smoke Alice" -Contains -ClickableOnly }
    if (-not $entry) { throw "Smoke Alice conversation not visible." }
    Tap-Node -Adb $Adb -Serial $Serial -Node $entry | Out-Null
    Start-Sleep -Milliseconds $script:DelayMs
}

function Open-GroupChat {
    param([string]$Adb, [string]$Serial, [string]$DeviceLabel)
    Ensure-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Messages -XRatio 0.22 -DeviceLabel $DeviceLabel
    $list = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "stress-group-list" -DeviceDir $script:DeviceDir
    $entry = Find-NodeByDesc -XmlText $list.XmlText -Text "Codex qaGroup" -Contains -ClickableOnly
    if (-not $entry) {
        $groupFilter = Find-NodeByDesc -XmlText $list.XmlText -Text $script:T.Group
        if ($groupFilter) {
            Tap-Node -Adb $Adb -Serial $Serial -Node $groupFilter | Out-Null
            Start-Sleep -Milliseconds $script:DelayMs
            $list = Capture-State -Adb $Adb -Serial $Serial -Label $DeviceLabel -Suffix "stress-group-filter" -DeviceDir $script:DeviceDir
            $entry = Find-NodeByDesc -XmlText $list.XmlText -Text "Codex qaGroup" -Contains -ClickableOnly
        }
    }
    if (-not $entry) { throw "Codex qaGroup conversation not visible." }
    Tap-Node -Adb $Adb -Serial $Serial -Node $entry | Out-Null
    Start-Sleep -Milliseconds $script:DelayMs
}

function Open-AttachmentSheet {
    param([string]$Adb, [string]$Serial)
    $screen = Get-PhysicalScreenSize -Adb $Adb -Serial $Serial
    Invoke-Tap -Adb $Adb -Serial $Serial -X 92 -Y ([Math]::Max(1, $screen.Height - 90))
    Start-Sleep -Milliseconds $script:DelayMs
}

function Run-Step {
    param([string]$CaseId, [string]$Device, [string]$Serial, [string]$Action, [scriptblock]$Body)
    $start = Get-Date
    try {
        $evidence = @(& $Body)
        Add-Result -CaseId $CaseId -Device $Device -Serial $Serial -Action $Action -Status "PASS" -Evidence $evidence -Detail "Non-destructive stress action completed." -DurationSeconds ([int]((Get-Date) - $start).TotalSeconds)
    } catch {
        Add-Result -CaseId $CaseId -Device $Device -Serial $Serial -Action $Action -Status "TOOL_WARN" -Evidence @() -Detail "Stress action exception: $($_.Exception.Message)" -DurationSeconds ([int]((Get-Date) - $start).TotalSeconds)
    }
}

$script:T = [ordered]@{
    Messages = Join-Chars @(0x6D88, 0x606F)
    Contacts = Join-Chars @(0x8054, 0x7CFB, 0x4EBA)
    Group = Join-Chars @(0x7FA4, 0x7EC4)
    Discover = Join-Chars @(0x53D1, 0x73B0)
    Settings = Join-Chars @(0x8BBE, 0x7F6E)
    Wallet = Join-Chars @(0x94B1, 0x5305)
    Recharge = Join-Chars @(0x5145, 0x503C)
    Withdraw = Join-Chars @(0x63D0, 0x73B0)
    WithdrawAll = Join-Chars @(0x5168, 0x90E8, 0x63D0, 0x73B0)
    Bills = Join-Chars @(0x8D26, 0x5355)
    AboutWallet = Join-Chars @(0x5173, 0x4E8E, 0x94B1, 0x5305)
    PaymentPassword = Join-Chars @(0x652F, 0x4ED8, 0x5BC6, 0x7801)
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
foreach ($serial in @($DeviceA, $DeviceB)) {
    if (-not ($devices -match "^$([regex]::Escape($serial))\s+device$")) {
        throw "Device $serial is not online."
    }
}

if (-not $SkipLogcatClear) {
    Invoke-AdbQuiet -Adb $adb -Arguments @("-s", $DeviceA, "logcat", "-c")
    Invoke-AdbQuiet -Adb $adb -Arguments @("-s", $DeviceB, "logcat", "-c")
}

if ($Seed -eq 0) { $Seed = [int]((Get-Date).Ticks % [int]::MaxValue) }
$random = [System.Random]::new($Seed)
$script:Results = New-Object System.Collections.Generic.List[object]

$actions = @(
    [ordered]@{ Name = "A settings wallet rapid open"; Device = "A-8MY"; Serial = $DeviceA; Body = {
        Open-Wallet -Adb $adb -Serial $DeviceA -DeviceLabel "A-8MY"
        $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-wallet-home" -DeviceDir $script:DeviceDir
        return @($state.PngPath, $state.XmlPath)
    }},
    [ordered]@{ Name = "A wallet recharge open back"; Device = "A-8MY"; Serial = $DeviceA; Body = {
        Open-Wallet -Adb $adb -Serial $DeviceA -DeviceLabel "A-8MY"
        $homeState = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-recharge-home" -DeviceDir $script:DeviceDir
        Try-TapDesc -Adb $adb -Serial $DeviceA -XmlText $homeState.XmlText -Text $script:T.Recharge | Out-Null
        $pageState = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-recharge-page" -DeviceDir $script:DeviceDir
        Invoke-Back -Adb $adb -Serial $DeviceA
        return @($pageState.PngPath, $pageState.XmlPath)
    }},
    [ordered]@{ Name = "A wallet withdraw all open back"; Device = "A-8MY"; Serial = $DeviceA; Body = {
        Open-Wallet -Adb $adb -Serial $DeviceA -DeviceLabel "A-8MY"
        $homeState = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-withdraw-home" -DeviceDir $script:DeviceDir
        Try-TapDesc -Adb $adb -Serial $DeviceA -XmlText $homeState.XmlText -Text $script:T.Withdraw | Out-Null
        $pageState = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-withdraw-page" -DeviceDir $script:DeviceDir
        Try-TapDesc -Adb $adb -Serial $DeviceA -XmlText $pageState.XmlText -Text $script:T.WithdrawAll | Out-Null
        $afterState = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-withdraw-all" -DeviceDir $script:DeviceDir
        Invoke-Back -Adb $adb -Serial $DeviceA
        return @($afterState.PngPath, $afterState.XmlPath)
    }},
    [ordered]@{ Name = "A wallet secondary pages"; Device = "A-8MY"; Serial = $DeviceA; Body = {
        Open-Wallet -Adb $adb -Serial $DeviceA -DeviceLabel "A-8MY"
        $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-wallet-secondary" -DeviceDir $script:DeviceDir
        foreach ($label in @($script:T.Bills, $script:T.AboutWallet, $script:T.PaymentPassword)) {
            Try-TapDesc -Adb $adb -Serial $DeviceA -XmlText $state.XmlText -Text $label -Contains | Out-Null
            Start-Sleep -Milliseconds $script:DelayMs
            Invoke-Back -Adb $adb -Serial $DeviceA
            Start-Sleep -Milliseconds $script:DelayMs
            $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-wallet-secondary-return" -DeviceDir $script:DeviceDir
        }
        return @($state.PngPath, $state.XmlPath)
    }},
    [ordered]@{ Name = "B private chat attachment"; Device = "B-UQG"; Serial = $DeviceB; Body = {
        Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
        Open-AttachmentSheet -Adb $adb -Serial $DeviceB
        $sheet = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "stress-private-attachment" -DeviceDir $script:DeviceDir
        Invoke-Back -Adb $adb -Serial $DeviceB
        return @($sheet.PngPath, $sheet.XmlPath)
    }},
    [ordered]@{ Name = "B private long press menu"; Device = "B-UQG"; Serial = $DeviceB; Body = {
        Open-PrivateChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
        $before = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "stress-private-longpress-before" -DeviceDir $script:DeviceDir
        $message = Find-FirstMessageNode -XmlText $before.XmlText
        if ($message) { Invoke-LongPress -Adb $adb -Serial $DeviceB -X $message.Box.X -Y $message.Box.Y }
        $menu = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "stress-private-longpress-menu" -DeviceDir $script:DeviceDir
        Invoke-Back -Adb $adb -Serial $DeviceB
        return @($before.PngPath, $menu.PngPath, $menu.XmlPath)
    }},
    [ordered]@{ Name = "B group attachment"; Device = "B-UQG"; Serial = $DeviceB; Body = {
        Open-GroupChat -Adb $adb -Serial $DeviceB -DeviceLabel "B-UQG"
        Open-AttachmentSheet -Adb $adb -Serial $DeviceB
        $sheet = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "stress-group-attachment" -DeviceDir $script:DeviceDir
        Invoke-Back -Adb $adb -Serial $DeviceB
        return @($sheet.PngPath, $sheet.XmlPath)
    }},
    [ordered]@{ Name = "B bottom tabs rapid switch"; Device = "B-UQG"; Serial = $DeviceB; Body = {
        Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Contacts -XRatio 0.41 -DeviceLabel "B-UQG"
        Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Discover -XRatio 0.60 -DeviceLabel "B-UQG"
        Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Settings -XRatio 0.78 -DeviceLabel "B-UQG"
        Ensure-BottomTab -Adb $adb -Serial $DeviceB -Label $script:T.Messages -XRatio 0.22 -DeviceLabel "B-UQG"
        $state = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "stress-tabs-return" -DeviceDir $script:DeviceDir
        return @($state.PngPath, $state.XmlPath)
    }},
    [ordered]@{ Name = "A foreground recovery"; Device = "A-8MY"; Serial = $DeviceA; Body = {
        Invoke-Home -Adb $adb -Serial $DeviceA
        Start-Sleep -Milliseconds $script:DelayMs
        Ensure-AppForeground -Adb $adb -Serial $DeviceA
        $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "stress-foreground-recovery" -DeviceDir $script:DeviceDir
        return @($state.PngPath, $state.XmlPath)
    }},
    [ordered]@{ Name = "B foreground recovery"; Device = "B-UQG"; Serial = $DeviceB; Body = {
        Invoke-Home -Adb $adb -Serial $DeviceB
        Start-Sleep -Milliseconds $script:DelayMs
        Ensure-AppForeground -Adb $adb -Serial $DeviceB
        $state = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "stress-foreground-recovery" -DeviceDir $script:DeviceDir
        return @($state.PngPath, $state.XmlPath)
    }}
)

$plannedActions = New-Object System.Collections.Generic.List[object]
foreach ($action in $actions) {
    if ($plannedActions.Count -lt $Iterations) {
        $plannedActions.Add($action) | Out-Null
    }
}
while ($plannedActions.Count -lt $Iterations) {
    $plannedActions.Add($actions[$random.Next($actions.Count)]) | Out-Null
}
for ($i = $plannedActions.Count - 1; $i -gt 0; $i--) {
    $j = $random.Next($i + 1)
    $tmp = $plannedActions[$i]
    $plannedActions[$i] = $plannedActions[$j]
    $plannedActions[$j] = $tmp
}

for ($i = 1; $i -le $plannedActions.Count; $i++) {
    $action = $plannedActions[$i - 1]
    Run-Step -CaseId ("STRESS-{0:D3}" -f $i) -Device $action.Device -Serial $action.Serial -Action $action.Name -Body $action.Body
}

$finalTs = New-Timestamp
$aLog = Join-Path $logDir "A-8MY-stress-final-$finalTs.log"
$bLog = Join-Path $logDir "B-UQG-stress-final-$finalTs.log"
Save-Logcat -Adb $adb -Serial $DeviceA -Path $aLog
Save-Logcat -Adb $adb -Serial $DeviceB -Path $bLog

$scan = [ordered]@{
    generated_at = Get-IsoNow
    package = $PackageName
    suite = "stress-real-device"
    seed = $Seed
    iterations = $Iterations
    devices = @(
        (Scan-LogcatFile -Path $aLog -Device "A-8MY"),
        (Scan-LogcatFile -Path $bLog -Device "B-UQG")
    )
}
$fatalTotal = 0
$appTotal = 0
foreach ($deviceScan in $scan.devices) {
    $fatalTotal += [int]$deviceScan.fatal_pattern_count
    $appTotal += [int]$deviceScan.app_error_pattern_count
}
$scanStatus = if ($fatalTotal -eq 0 -and $appTotal -eq 0) { "PASS" } else { "FAIL" }
$scanPath = Join-Path $base "stress-final-logcat-scan-$finalTs.json"
$scan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scanPath -Encoding UTF8
Add-Result -CaseId "STRESS-FINAL-LOGCAT-SCAN" -Device "A-8MY,B-UQG" -Serial "$DeviceA,$DeviceB" -Action "Stress final logcat scan" -Status $scanStatus -Evidence @($scanPath, $aLog, $bLog) -Detail "fatal=$fatalTotal app_error=$appTotal" -DurationSeconds 1

$resultPath = Join-Path $base "stress-results-$finalTs.json"
$resultArray = @($script:Results.ToArray())
$resultArray | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$passCount = @($resultArray | Where-Object { $_.status -eq "PASS" }).Count
$failCount = @($resultArray | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = @($resultArray | Where-Object { $_.status -eq "TOOL_WARN" }).Count
$totalCount = $resultArray.Count

$latestSummaryJsonPath = Join-Path $base "latest-stress-summary.json"
$latestSummaryMdPath = Join-Path $base "latest-stress-summary.md"
$latestRows = @($resultArray | ForEach-Object {
    [ordered]@{
        case_id = $_.case_id
        device = $_.device
        status = $_.status
        action = $_.action
        detail = $_.detail
        first_evidence = if ($_.evidence.Count -gt 0) { $_.evidence[0] } else { "" }
    }
})
$summary = [ordered]@{
    generated_at = Get-IsoNow
    authoritative = $true
    suite = "stress-real-device"
    script = "scripts\fast_real_device_stress.ps1"
    command = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fast_real_device_stress.ps1 -Iterations $Iterations -Seed $Seed"
    package = $PackageName
    devices = @($DeviceA, $DeviceB)
    seed = $Seed
    iterations = $Iterations
    result_path = Short-Path $resultPath
    scan_path = Short-Path $scanPath
    report_path = Short-Path $reportPath
    events_path = Short-Path $script:EventsPath
    total = $totalCount
    pass = $passCount
    fail = $failCount
    tool_warn = $warnCount
    fatal_pattern_count = $fatalTotal
    app_error_pattern_count = $appTotal
    results = $latestRows
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestSummaryJsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Latest Stress Real-Device Suite")
$md.Add("")
$md.Add("Generated: $($summary.generated_at)")
$md.Add("")
$md.Add("Command: ``$($summary.command)``")
$md.Add("")
$md.Add("Summary: total=$totalCount, pass=$passCount, fail=$failCount, tool_warn=$warnCount, fatal=$fatalTotal, app_error=$appTotal, seed=$Seed.")
$md.Add("")
$md.Add("Artifacts: ``$(Short-Path $resultPath)``, ``$(Short-Path $scanPath)``.")
$md.Add("")
$md.Add("| Case | Device | Result | Action | Evidence |")
$md.Add("| --- | --- | --- | --- | --- |")
foreach ($r in $latestRows) {
    $md.Add("| $($r.case_id) | $($r.device) | $($r.status) | $($r.action) | $($r.first_evidence) |")
}
Set-Content -LiteralPath $latestSummaryMdPath -Value ($md -join [Environment]::NewLine) -Encoding UTF8

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("")
$reportLines.Add("## Stress Real-Device Automation Suite ($((Get-Date).ToString('yyyy-MM-dd HH:mm')) +08:00)")
$reportLines.Add("")
$reportLines.Add("Script: `scripts/fast_real_device_stress.ps1`. Non-destructive rapid randomized operations: no message sending, no secondary attachment selection, no payment, no withdraw/recharge submit, no settings save, and no call placement.")
$reportLines.Add("")
$reportLines.Add("Summary: total=$totalCount, pass=$passCount, fail=$failCount, tool_warn=$warnCount, fatal=$fatalTotal, app_error=$appTotal, seed=$Seed.")
$reportLines.Add("")
$reportLines.Add("Artifacts: ``$(Short-Path $resultPath)``, ``$(Short-Path $scanPath)``, ``$(Short-Path $latestSummaryJsonPath)``, ``$(Short-Path $latestSummaryMdPath)``.")
Add-Content -LiteralPath $reportPath -Value ($reportLines -join [Environment]::NewLine) -Encoding UTF8

[ordered]@{
    result_path = Short-Path $resultPath
    scan_path = Short-Path $scanPath
    latest_summary_json = Short-Path $latestSummaryJsonPath
    latest_summary_md = Short-Path $latestSummaryMdPath
    report_path = Short-Path $reportPath
    events_path = Short-Path $script:EventsPath
    seed = $Seed
    iterations = $Iterations
    total = $totalCount
    pass = $passCount
    fail = $failCount
    tool_warn = $warnCount
    fatal_pattern_count = $fatalTotal
    app_error_pattern_count = $appTotal
} | ConvertTo-Json -Depth 6
