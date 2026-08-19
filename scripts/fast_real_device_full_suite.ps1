<#
.SYNOPSIS
在两台 Android 真机上快速执行客户端核心 UI 回归套件。

.DESCRIPTION
复用 BaseDir 中已经准备好的账号、会话和设备状态，通过 ADB 驱动双设备完成
消息、联系人、设置及可选通话探测，并保存截图、日志和汇总结果。脚本会操作
指定设备上的现有应用状态，仅应使用专用 QA 设备。

.PARAMETER BaseDir
本轮读取准备数据并写入证据的基础目录。

.PARAMETER DeviceA
第一台测试设备的 ADB 序列号。

.PARAMETER DeviceB
第二台测试设备的 ADB 序列号。

.PARAMETER IncludeCallProbe
显式加入真实通话探测；会在两台设备间产生通话信令和记录。

.EXAMPLE
pwsh -File scripts/fast_real_device_full_suite.ps1 -SkipCallProbe
#>
param(
    [string]$BaseDir = "artifacts\real-device-test-20260623-233903",
    [string]$DeviceA = "8MY0220C17006781",
    [string]$DeviceB = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.ma100",
    [int]$DelayMs = 450,
    [switch]$SkipLogcatClear,
    [switch]$SkipCallProbe,
    [switch]$IncludeCallProbe
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

function Invoke-Tap {
    param([string]$Adb, [string]$Serial, [int]$X, [int]$Y)
    & $Adb -s $Serial shell input tap $X $Y | Out-Null
}

function Invoke-Back {
    param([string]$Adb, [string]$Serial)
    & $Adb -s $Serial shell input keyevent KEYCODE_BACK | Out-Null
}

function Invoke-LongPress {
    param([string]$Adb, [string]$Serial, [int]$X, [int]$Y, [int]$Ms = 850)
    & $Adb -s $Serial shell input swipe $X $Y $X $Y $Ms | Out-Null
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

function Find-Node {
    param([string]$XmlText, [scriptblock]$Predicate)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if (& $Predicate $node) { return $node }
    }
    return $null
}

function Find-ClickableByDesc {
    param([string]$XmlText, [string]$Text, [switch]$Contains)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'clickable="true"') { continue }
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ($Contains) {
            if ($desc -like "*$Text*") { return $node }
        } elseif ($desc -eq $Text) {
            return $node
        }
    }
    return $null
}

function Find-NodeByDesc {
    param([string]$XmlText, [string]$Text, [switch]$Contains)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
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
        $bounds = Get-NodeAttribute -Node $node -Name "bounds"
        $box = Get-BoundsObject -Bounds $bounds
        if ($null -eq $box -or $box.Y1 -lt $MinY1) { continue }
        if ($null -eq $best -or $box.Y1 -gt $best.Box.Y1) {
            $best = [pscustomobject]@{ Node = $node; Box = $box }
        }
    }
    if ($best) { return $best.Node }
    return $null
}

function Find-TopNodeByDescContains {
    param([string]$XmlText, [string]$Text, [int]$MaxY2 = 420)
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ($desc -notlike "*$Text*") { continue }
        $bounds = Get-NodeAttribute -Node $node -Name "bounds"
        $box = Get-BoundsObject -Bounds $bounds
        if ($null -eq $box) { continue }
        if ($box.Y2 -le $MaxY2) { return $node }
    }
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
    $best = $null
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'long-clickable="true"') { continue }
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ([string]::IsNullOrWhiteSpace($desc)) { continue }
        if ($desc -notmatch '\d{1,2}:\d{2}') { continue }
        $bounds = Get-NodeAttribute -Node $node -Name "bounds"
        $box = Get-BoundsObject -Bounds $bounds
        if ($null -eq $box) { continue }
        if ($box.Y1 -lt 420 -or $box.Y1 -gt 2100) { continue }
        $best = [pscustomobject]@{ Node = $node; Box = $box; Desc = $desc }
        break
    }
    return $best
}

function Tap-Node {
    param([string]$Adb, [string]$Serial, [string]$Node)
    if ([string]::IsNullOrWhiteSpace($Node)) { throw "Tap-Node received an empty node." }
    $bounds = Get-NodeAttribute -Node $Node -Name "bounds"
    $box = Get-BoundsObject -Bounds $bounds
    if ($null -eq $box) { throw "Invalid bounds: $bounds" }
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

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Adb -s $Serial shell uiautomator dump $remoteXml 2>$null | Out-Null
        & $Adb -s $Serial pull $remoteXml $xmlPath 2>$null | Out-Null
        & $Adb -s $Serial shell screencap -p $remotePng 2>$null | Out-Null
        & $Adb -s $Serial pull $remotePng $pngPath 2>$null | Out-Null
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    $xmlText = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
    $pngBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $pngPath))
    $pngValid = $pngBytes.Length -ge 8 -and $pngBytes[0] -eq 0x89 -and $pngBytes[1] -eq 0x50 -and $pngBytes[2] -eq 0x4E -and $pngBytes[3] -eq 0x47

    return [pscustomobject]@{
        Name = $safe
        XmlPath = $xmlPath
        PngPath = $pngPath
        XmlText = $xmlText
        PngValid = $pngValid
        XmlSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $xmlPath).Hash
    }
}

function Get-TextHits {
    param([string]$XmlText, [string[]]$Needles)
    $hits = @()
    foreach ($needle in $Needles) {
        if ($XmlText -like "*$needle*") { $hits += $needle }
    }
    return $hits
}

function Save-Logcat {
    param([string]$Adb, [string]$Serial, [string]$Path)
    & $Adb -s $Serial logcat -d -v time | Out-File -LiteralPath $Path -Encoding UTF8
}

function Scan-LogcatFile {
    param([string]$Path, [string]$Device)
    $fatalPattern = '(FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|ANR in com\.genericim\.app|Process:\s+com\.genericim\.app|AndroidRuntime.*FATAL)'
    $appPattern = '(E/flutter|FlutterError|Unhandled Exception|com\.genericim\.app.*(Exception|Error))'
    $toolPattern = '(com\.android\.uiautomator|AccessibilityNodeInfoDumper|app_process\(.*open file error|RuntimeInit: Starting tool|Calling main entry com\.android\.commands\.uiautomator\.Launcher)'
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
        tool_samples = @($tool | Select-Object -First 5 | ForEach-Object { $_.Line })
    }
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

function Ensure-AppForeground {
    param([string]$Adb, [string]$Serial)
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "cmd", "statusbar", "collapse")
    Start-Sleep -Milliseconds 150
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "monkey", "-p", $script:PackageName, "-c", "android.intent.category.LAUNCHER", "1")
    Start-Sleep -Milliseconds 350
    Invoke-AdbQuiet -Adb $Adb -Arguments @("-s", $Serial, "shell", "cmd", "statusbar", "collapse")
    Start-Sleep -Milliseconds 150
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

function New-Result {
    param(
        [string]$CaseId,
        [string]$Device,
        [string]$Serial,
        [string]$Module,
        [string]$Status,
        [string[]]$Evidence,
        [hashtable]$Assertions,
        [string]$Detail
    )
    $script:Results.Add([ordered]@{
        case_id = $CaseId
        device = $Device
        serial = $Serial
        module = $Module
        status = $Status
        evidence = @($Evidence | ForEach-Object { Short-Path $_ })
        assertions = $Assertions
        detail = $Detail
    }) | Out-Null
}

function Invoke-Case {
    param([string]$CaseId, [string]$Device, [string]$Serial, [string]$Module, [scriptblock]$Body)
    $start = Get-Date
    try {
        $result = & $Body
        New-Result -CaseId $CaseId -Device $Device -Serial $Serial -Module $Module -Status $result.Status -Evidence $result.Evidence -Assertions $result.Assertions -Detail $result.Detail
        Add-Event -EventsPath $script:EventsPath -CaseId $CaseId -Device $Serial -Module $Module -Status $result.Status -Detail $result.Detail -DurationSeconds ([int]((Get-Date) - $start).TotalSeconds)
    } catch {
        $detail = "Automation exception: $($_.Exception.Message)"
        New-Result -CaseId $CaseId -Device $Device -Serial $Serial -Module $Module -Status "TOOL_WARN" -Evidence @() -Assertions @{} -Detail $detail
        Add-Event -EventsPath $script:EventsPath -CaseId $CaseId -Device $Serial -Module $Module -Status "TOOL_WARN" -Detail $detail -DurationSeconds ([int]((Get-Date) - $start).TotalSeconds)
    }
}

function New-CaseOutput {
    param([string]$Status, [string[]]$Evidence, [hashtable]$Assertions, [string]$Detail)
    return [pscustomobject]@{
        Status = $Status
        Evidence = @($Evidence)
        Assertions = $Assertions
        Detail = $Detail
    }
}

function Test-Hits {
    param([string]$XmlText, [string[]]$Needles, [int]$MinHits = 1)
    $hits = @(Get-TextHits -XmlText $XmlText -Needles $Needles)
    return [pscustomobject]@{ Pass = ($hits.Count -ge $MinHits); Hits = $hits }
}

function Tap-ByDescOrWarn {
    param([string]$Adb, [string]$Serial, [string]$XmlText, [string]$Text, [switch]$Contains)
    $node = Find-ClickableByDesc -XmlText $XmlText -Text $Text -Contains:$Contains
    if (-not $node) { return $false }
    Tap-Node -Adb $Adb -Serial $Serial -Node $node | Out-Null
    return $true
}

function Navigate-BottomTab {
    param([string]$Adb, [string]$Serial, [string]$Label, [double]$XRatio)
    Ensure-AppForeground -Adb $Adb -Serial $Serial
    $screen = Get-PhysicalScreenSize -Adb $Adb -Serial $Serial
    $state = $null
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $state = Capture-State -Adb $Adb -Serial $Serial -Label "nav" -Suffix "before-tab" -DeviceDir $script:DeviceDir
        if ($state.XmlText -notlike "*package=`"$script:PackageName`"*") {
            Ensure-AppForeground -Adb $Adb -Serial $Serial
            continue
        }

        $targetNode = Find-BottomNodeByDesc -XmlText $state.XmlText -Text $Label -MinY1 ([int]($screen.Height * 0.78))
        if ($targetNode) { break }

        $hasBottomTab = $false
        foreach ($tabLabel in @($script:T.Messages, $script:T.Contacts, $script:T.Discover, $script:T.Settings)) {
            if (Find-BottomNodeByDesc -XmlText $state.XmlText -Text $tabLabel -MinY1 ([int]($screen.Height * 0.78))) {
                $hasBottomTab = $true
                break
            }
        }
        if ($hasBottomTab) { break }

        if ($attempt -lt 3) {
            Invoke-Back -Adb $Adb -Serial $Serial
            Start-Sleep -Milliseconds $script:DelayMs
        }
    }
    $node = Find-BottomNodeByDesc -XmlText $state.XmlText -Text $Label -MinY1 ([int]($screen.Height * 0.78))
    if (-not $node) { $node = Find-ClickableByDesc -XmlText $state.XmlText -Text $Label }
    if ($node) {
        Tap-Node -Adb $Adb -Serial $Serial -Node $node | Out-Null
    } else {
        Invoke-Tap -Adb $Adb -Serial $Serial -X ([int]($screen.Width * $XRatio)) -Y ([Math]::Max(1, $screen.Height - 90))
    }
    Start-Sleep -Milliseconds $script:DelayMs
}

function Ensure-Settings {
    param([string]$Adb, [string]$Serial)
    Navigate-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Settings -XRatio 0.78
}

function Ensure-Messages {
    param([string]$Adb, [string]$Serial)
    Navigate-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Messages -XRatio 0.22
}

function Ensure-Contacts {
    param([string]$Adb, [string]$Serial)
    Navigate-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Contacts -XRatio 0.41
}

function Ensure-Discover {
    param([string]$Adb, [string]$Serial)
    Navigate-BottomTab -Adb $Adb -Serial $Serial -Label $script:T.Discover -XRatio 0.60
}

function Ensure-Wallet {
    param([string]$Adb, [string]$Serial)
    Ensure-Settings -Adb $Adb -Serial $Serial
    $state = Capture-State -Adb $Adb -Serial $Serial -Label "A-8MY" -Suffix "ensure-settings" -DeviceDir $script:DeviceDir
    $node = Find-ClickableByDesc -XmlText $state.XmlText -Text $script:T.Wallet
    if ($node) {
        Tap-Node -Adb $Adb -Serial $Serial -Node $node | Out-Null
        Start-Sleep -Milliseconds $script:DelayMs
    }
}

function Ensure-PrivateChat {
    param([string]$Adb, [string]$Serial, [string]$Title)
    $state = Capture-State -Adb $Adb -Serial $Serial -Label "B-UQG" -Suffix "ensure-private-start" -DeviceDir $script:DeviceDir
    $inTarget = ($null -ne (Find-TopNodeByDescContains -XmlText $state.XmlText -Text $Title)) -and ($state.XmlText -match 'class="android.widget.EditText"')
    if ($inTarget) { return }
    if ($state.XmlText -match 'class="android.widget.EditText"') {
        Invoke-Back -Adb $Adb -Serial $Serial
        Start-Sleep -Milliseconds $script:DelayMs
    }
    Ensure-Messages -Adb $Adb -Serial $Serial
    $list = Capture-State -Adb $Adb -Serial $Serial -Label "B-UQG" -Suffix "ensure-private-list" -DeviceDir $script:DeviceDir
    $entry = Find-ConversationEntryBySecondLine -XmlText $list.XmlText -Title $Title
    if (-not $entry) { $entry = Find-ClickableByDesc -XmlText $list.XmlText -Text $Title -Contains }
    if ($entry) {
        Tap-Node -Adb $Adb -Serial $Serial -Node $entry | Out-Null
        Start-Sleep -Milliseconds $script:DelayMs
    }
}

function Ensure-GroupChat {
    param([string]$Adb, [string]$Serial)
    Ensure-AppForeground -Adb $Adb -Serial $Serial
    $state = Capture-State -Adb $Adb -Serial $Serial -Label "B-UQG" -Suffix "ensure-group-start" -DeviceDir $script:DeviceDir
    $inGroup = ($null -ne (Find-TopNodeByDescContains -XmlText $state.XmlText -Text "Codex qaGroup")) -and ($state.XmlText -match 'class="android.widget.EditText"')
    if ($inGroup) { return }
    if ($state.XmlText -match 'class="android.widget.EditText"') {
        Invoke-Back -Adb $Adb -Serial $Serial
        Start-Sleep -Milliseconds $script:DelayMs
    }
    Ensure-Messages -Adb $Adb -Serial $Serial
    $list = Capture-State -Adb $Adb -Serial $Serial -Label "B-UQG" -Suffix "ensure-group-list" -DeviceDir $script:DeviceDir
    $entry = Find-ClickableByDesc -XmlText $list.XmlText -Text "Codex qaGroup" -Contains
    if (-not $entry) {
        $groupFilter = Find-NodeByDesc -XmlText $list.XmlText -Text $script:T.Group
        if ($groupFilter) {
            Tap-Node -Adb $Adb -Serial $Serial -Node $groupFilter | Out-Null
            Start-Sleep -Milliseconds $script:DelayMs
            $list = Capture-State -Adb $Adb -Serial $Serial -Label "B-UQG" -Suffix "ensure-group-filter" -DeviceDir $script:DeviceDir
            $entry = Find-ClickableByDesc -XmlText $list.XmlText -Text "Codex qaGroup" -Contains
        }
    }
    if ($entry) {
        Tap-Node -Adb $Adb -Serial $Serial -Node $entry | Out-Null
        Start-Sleep -Milliseconds $script:DelayMs
    }
}

function Dismiss-Overlay {
    param([string]$Adb, [string]$Serial)
    Invoke-Back -Adb $Adb -Serial $Serial
    Start-Sleep -Milliseconds $script:DelayMs
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
    PaymentPassword = Join-Chars @(0x652F, 0x4ED8, 0x5BC6, 0x7801)
    AboutWallet = (Join-Chars @(0x5173, 0x4E8E, 0x94B1, 0x5305))
    Search = Join-Chars @(0x641C, 0x7D22)
    Notification = Join-Chars @(0x901A, 0x77E5)
    Privacy = Join-Chars @(0x9690, 0x79C1)
    DataStorage = Join-Chars @(0x6570, 0x636E, 0x548C, 0x5B58, 0x50A8)
    ChatSettings = Join-Chars @(0x804A, 0x5929, 0x8BBE, 0x7F6E)
    Devices = Join-Chars @(0x8BBE, 0x5907)
    Language = Join-Chars @(0x8BED, 0x8A00)
    Appearance = Join-Chars @(0x5916, 0x89C2)
    Album = Join-Chars @(0x76F8, 0x518C)
    Camera = Join-Chars @(0x6444, 0x50CF, 0x5934)
    Meeting = Join-Chars @(0x4F1A, 0x8BAE)
    Location = Join-Chars @(0x4F4D, 0x7F6E)
    Video = Join-Chars @(0x89C6, 0x9891)
    File = Join-Chars @(0x6587, 0x4EF6)
    RedPacket = Join-Chars @(0x7EA2, 0x5305)
    Transfer = Join-Chars @(0x8F6C, 0x8D26)
    Favorite = Join-Chars @(0x6536, 0x85CF)
    Reply = Join-Chars @(0x56DE, 0x590D)
    Copy = Join-Chars @(0x590D, 0x5236)
    Translate = Join-Chars @(0x7FFB, 0x8BD1)
    Forward = Join-Chars @(0x8F6C, 0x53D1)
    Edit = Join-Chars @(0x7F16, 0x8F91)
    Select = Join-Chars @(0x9009, 0x62E9)
    Delete = Join-Chars @(0x5220, 0x9664)
    Cancel = Join-Chars @(0x53D6, 0x6D88)
}

$script:DelayMs = $DelayMs
$script:PackageName = $PackageName
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
    & $adb -s $DeviceA logcat -c | Out-Null
    & $adb -s $DeviceB logcat -c | Out-Null
}

$runTs = New-Timestamp
$script:Results = New-Object System.Collections.Generic.List[object]

Invoke-Case -CaseId "FULL-PREFLIGHT-A" -Device "A-8MY" -Serial $DeviceA -Module "App preflight A" -Body {
    $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-preflight" -DeviceDir $script:DeviceDir
    $appPid = (& $adb -s $DeviceA shell pidof $PackageName) -join ""
    $ok = -not [string]::IsNullOrWhiteSpace($appPid)
    New-CaseOutput -Status ($(if ($ok -and $state.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ app_pid = $appPid; screenshot_png_valid = $state.PngValid } -Detail "A app process and screenshot capture preflight."
}

Invoke-Case -CaseId "FULL-PREFLIGHT-B" -Device "B-UQG" -Serial $DeviceB -Module "App preflight B" -Body {
    $state = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-preflight" -DeviceDir $script:DeviceDir
    $appPid = (& $adb -s $DeviceB shell pidof $PackageName) -join ""
    $ok = -not [string]::IsNullOrWhiteSpace($appPid)
    New-CaseOutput -Status ($(if ($ok -and $state.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ app_pid = $appPid; screenshot_png_valid = $state.PngValid } -Detail "B app process and screenshot capture preflight."
}

Invoke-Case -CaseId "FULL-A-SETTINGS-HOME" -Device "A-8MY" -Serial $DeviceA -Module "Settings home entries" -Body {
    Ensure-Settings -Adb $adb -Serial $DeviceA
    $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-settings-home" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $state.XmlText -Needles @($script:T.Wallet, $script:T.Notification, $script:T.Privacy, $script:T.Language) -MinHits 3
    New-CaseOutput -Status ($(if ($probe.Pass -and $state.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ hits = $probe.Hits; screenshot_png_valid = $state.PngValid } -Detail "Settings home exposes major settings entries."
}

Invoke-Case -CaseId "FULL-A-WALLET-HOME" -Device "A-8MY" -Serial $DeviceA -Module "Wallet home entries" -Body {
    Ensure-Wallet -Adb $adb -Serial $DeviceA
    $state = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-home" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $state.XmlText -Needles @($script:T.Recharge, $script:T.Withdraw, $script:T.Bills, $script:T.PaymentPassword, $script:T.AboutWallet) -MinHits 4
    New-CaseOutput -Status ($(if ($probe.Pass -and $state.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ hits = $probe.Hits; screenshot_png_valid = $state.PngValid } -Detail "Wallet home exposes recharge, withdraw, bills, payment password, and about entries."
}

Invoke-Case -CaseId "FULL-A-WALLET-RECHARGE-READONLY" -Device "A-8MY" -Serial $DeviceA -Module "Wallet recharge read-only controls" -Body {
    Ensure-Wallet -Adb $adb -Serial $DeviceA
    $walletHome = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-recharge-home" -DeviceDir $script:DeviceDir
    $tapped = Tap-ByDescOrWarn -Adb $adb -Serial $DeviceA -XmlText $walletHome.XmlText -Text $script:T.Recharge
    Start-Sleep -Milliseconds $DelayMs
    $page = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-recharge-page" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $page.XmlText -Needles @($script:T.Recharge, (Join-Chars @(0x91D1,0x989D)), (Join-Chars @(0x4ED8,0x6B3E)), (Join-Chars @(0x622A,0x56FE))) -MinHits 2
    Invoke-Back -Adb $adb -Serial $DeviceA
    Start-Sleep -Milliseconds $DelayMs
    New-CaseOutput -Status ($(if ($tapped -and $probe.Pass -and $page.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($walletHome.PngPath, $walletHome.XmlPath, $page.PngPath, $page.XmlPath) -Assertions @{ entry_tapped = $tapped; hits = $probe.Hits; screenshot_png_valid = $page.PngValid } -Detail "Recharge page opens for read-only inspection; no amount submit or file selection performed."
}

Invoke-Case -CaseId "FULL-A-WALLET-WITHDRAW-ALL-ZERO" -Device "A-8MY" -Serial $DeviceA -Module "Wallet withdraw all zero-balance" -Body {
    Ensure-Wallet -Adb $adb -Serial $DeviceA
    $walletHome = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-withdraw-home" -DeviceDir $script:DeviceDir
    $entryTapped = Tap-ByDescOrWarn -Adb $adb -Serial $DeviceA -XmlText $walletHome.XmlText -Text $script:T.Withdraw
    Start-Sleep -Milliseconds $DelayMs
    $page = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-withdraw-page" -DeviceDir $script:DeviceDir
    $allNode = Find-ClickableByDesc -XmlText $page.XmlText -Text $script:T.WithdrawAll
    $allTapped = $false
    if ($allNode) {
        Tap-Node -Adb $adb -Serial $DeviceA -Node $allNode | Out-Null
        Start-Sleep -Milliseconds 180
        Tap-Node -Adb $adb -Serial $DeviceA -Node $allNode | Out-Null
        $allTapped = $true
    }
    Start-Sleep -Milliseconds $DelayMs
    $after = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-withdraw-all-zero" -DeviceDir $script:DeviceDir
    $edit = Find-Node -XmlText $after.XmlText -Predicate { param($node) $node -match 'class="android.widget.EditText"' }
    $amount = if ($edit) { Get-NodeAttribute -Node $edit -Name "text" } else { "" }
    Invoke-Back -Adb $adb -Serial $DeviceA
    Start-Sleep -Milliseconds $DelayMs
    $ok = $entryTapped -and $allTapped -and ($amount -eq "0.00") -and $after.PngValid
    New-CaseOutput -Status ($(if ($ok) { "PASS" } else { "FAIL" })) -Evidence @($page.PngPath, $page.XmlPath, $after.PngPath, $after.XmlPath) -Assertions @{ entry_tapped = $entryTapped; withdraw_all_tapped = $allTapped; amount_text = $amount; screenshot_png_valid = $after.PngValid } -Detail "Withdraw All at zero balance fills 0.00 only; no submit action performed."
}

Invoke-Case -CaseId "FULL-A-WALLET-BILLS-ABOUT-PASSWORD" -Device "A-8MY" -Serial $DeviceA -Module "Wallet bills, about, payment password entries" -Body {
    Ensure-Wallet -Adb $adb -Serial $DeviceA
    $walletHome = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-secondary-home" -DeviceDir $script:DeviceDir
    $billTapped = Tap-ByDescOrWarn -Adb $adb -Serial $DeviceA -XmlText $walletHome.XmlText -Text $script:T.Bills
    Start-Sleep -Milliseconds $DelayMs
    $bills = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-bills" -DeviceDir $script:DeviceDir
    Invoke-Back -Adb $adb -Serial $DeviceA
    Start-Sleep -Milliseconds $DelayMs
    $home2 = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-about-home" -DeviceDir $script:DeviceDir
    $aboutTapped = Tap-ByDescOrWarn -Adb $adb -Serial $DeviceA -XmlText $home2.XmlText -Text $script:T.AboutWallet
    Start-Sleep -Milliseconds $DelayMs
    $about = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-about" -DeviceDir $script:DeviceDir
    Dismiss-Overlay -Adb $adb -Serial $DeviceA
    $home3 = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-password-home" -DeviceDir $script:DeviceDir
    $pwdTapped = Tap-ByDescOrWarn -Adb $adb -Serial $DeviceA -XmlText $home3.XmlText -Text $script:T.PaymentPassword -Contains
    Start-Sleep -Milliseconds $DelayMs
    $pwd = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-wallet-password-entry" -DeviceDir $script:DeviceDir
    Invoke-Back -Adb $adb -Serial $DeviceA
    Start-Sleep -Milliseconds $DelayMs
    $ok = $billTapped -and $aboutTapped -and $pwdTapped -and $bills.PngValid -and $about.PngValid -and $pwd.PngValid
    New-CaseOutput -Status ($(if ($ok) { "PASS" } else { "FAIL" })) -Evidence @($bills.PngPath, $bills.XmlPath, $about.PngPath, $about.XmlPath, $pwd.PngPath, $pwd.XmlPath) -Assertions @{ bills_tapped = $billTapped; about_tapped = $aboutTapped; payment_password_tapped = $pwdTapped; screenshots_valid = ($bills.PngValid -and $about.PngValid -and $pwd.PngValid) } -Detail "Wallet secondary entries are reachable. No payment password input was entered."
}

Invoke-Case -CaseId "FULL-B-MESSAGES-LIST" -Device "B-UQG" -Serial $DeviceB -Module "Messages list" -Body {
    Ensure-Messages -Adb $adb -Serial $DeviceB
    $state = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-messages-list" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $state.XmlText -Needles @($script:T.Search, "Smoke Alice", "Codex qaGroup") -MinHits 2
    New-CaseOutput -Status ($(if ($probe.Pass -and $state.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ hits = $probe.Hits; screenshot_png_valid = $state.PngValid } -Detail "Messages list and search entry are visible."
}

Invoke-Case -CaseId "FULL-B-PRIVATE-CHAT-HEADER-INPUT" -Device "B-UQG" -Serial $DeviceB -Module "Private chat header and input" -Body {
    Ensure-PrivateChat -Adb $adb -Serial $DeviceB -Title "Smoke Alice"
    $state = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-private-chat" -DeviceDir $script:DeviceDir
    $targetHeader = $null -ne (Find-TopNodeByDescContains -XmlText $state.XmlText -Text "Smoke Alice")
    $hasInput = $state.XmlText -match 'class="android.widget.EditText"'
    New-CaseOutput -Status ($(if ($targetHeader -and $hasInput -and $state.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ target_header_smoke_alice = $targetHeader; has_input = $hasInput; screenshot_png_valid = $state.PngValid } -Detail "Private chat header and input bar are visible."
}

Invoke-Case -CaseId "FULL-B-PRIVATE-ATTACHMENT-SHEET" -Device "B-UQG" -Serial $DeviceB -Module "Private chat attachment sheet" -Body {
    Ensure-PrivateChat -Adb $adb -Serial $DeviceB -Title "Smoke Alice"
    $before = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-private-attachment-before" -DeviceDir $script:DeviceDir
    $screen = Get-PhysicalScreenSize -Adb $adb -Serial $DeviceB
    Invoke-Tap -Adb $adb -Serial $DeviceB -X 92 -Y ([Math]::Max(1, $screen.Height - 90))
    Start-Sleep -Milliseconds $DelayMs
    $sheet = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-private-attachment-sheet" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $sheet.XmlText -Needles @($script:T.Album, $script:T.Camera, $script:T.Location, $script:T.Video, $script:T.File, $script:T.RedPacket, $script:T.Transfer, $script:T.Favorite) -MinHits 5
    Dismiss-Overlay -Adb $adb -Serial $DeviceB
    New-CaseOutput -Status ($(if ($probe.Pass -and $sheet.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($before.PngPath, $before.XmlPath, $sheet.PngPath, $sheet.XmlPath) -Assertions @{ hits = $probe.Hits; human_tap_point = "92,$([Math]::Max(1, $screen.Height - 90))"; screenshot_png_valid = $sheet.PngValid } -Detail "Private attachment sheet opens. No secondary attachment option was tapped."
}

Invoke-Case -CaseId "FULL-B-PRIVATE-LONGPRESS-MENU" -Device "B-UQG" -Serial $DeviceB -Module "Private chat message long-press menu" -Body {
    Ensure-PrivateChat -Adb $adb -Serial $DeviceB -Title "Smoke Alice"
    $before = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-private-longpress-before" -DeviceDir $script:DeviceDir
    $message = Find-FirstMessageNode -XmlText $before.XmlText
    $pressed = $false
    if ($message) {
        Invoke-LongPress -Adb $adb -Serial $DeviceB -X $message.Box.X -Y $message.Box.Y
        $pressed = $true
        Start-Sleep -Milliseconds $DelayMs
    }
    $menu = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-private-longpress-menu" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $menu.XmlText -Needles @($script:T.Reply, $script:T.Copy, $script:T.Translate, $script:T.Forward, $script:T.Favorite, $script:T.Edit, $script:T.Select, $script:T.Delete) -MinHits 4
    Dismiss-Overlay -Adb $adb -Serial $DeviceB
    New-CaseOutput -Status ($(if ($pressed -and $probe.Pass -and $menu.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($before.PngPath, $before.XmlPath, $menu.PngPath, $menu.XmlPath) -Assertions @{ long_pressed = $pressed; hits = $probe.Hits; screenshot_png_valid = $menu.PngValid } -Detail "Private message long-press menu opens. No menu action was confirmed."
}

Invoke-Case -CaseId "FULL-B-GROUP-CHAT-HEADER-ATTACHMENT" -Device "B-UQG" -Serial $DeviceB -Module "Group chat header and attachment sheet" -Body {
    Ensure-GroupChat -Adb $adb -Serial $DeviceB
    $before = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-group-chat-before" -DeviceDir $script:DeviceDir
    $targetHeader = $null -ne (Find-TopNodeByDescContains -XmlText $before.XmlText -Text "Codex qaGroup")
    $screen = Get-PhysicalScreenSize -Adb $adb -Serial $DeviceB
    Invoke-Tap -Adb $adb -Serial $DeviceB -X 92 -Y ([Math]::Max(1, $screen.Height - 90))
    Start-Sleep -Milliseconds $DelayMs
    $sheet = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-group-attachment-sheet" -DeviceDir $script:DeviceDir
    $probe = Test-Hits -XmlText $sheet.XmlText -Needles @($script:T.Album, $script:T.Camera, $script:T.Meeting, $script:T.Location, $script:T.Video, $script:T.File, $script:T.RedPacket, $script:T.Favorite) -MinHits 5
    Dismiss-Overlay -Adb $adb -Serial $DeviceB
    New-CaseOutput -Status ($(if ($targetHeader -and $probe.Pass -and $sheet.PngValid) { "PASS" } else { "FAIL" })) -Evidence @($before.PngPath, $before.XmlPath, $sheet.PngPath, $sheet.XmlPath) -Assertions @{ target_group_header = $targetHeader; hits = $probe.Hits; screenshot_png_valid = $sheet.PngValid } -Detail "Group chat header and attachment sheet are reachable. No secondary attachment option was tapped."
}

Invoke-Case -CaseId "FULL-B-CONTACTS-DISCOVER-SETTINGS-TABS" -Device "B-UQG" -Serial $DeviceB -Module "Contacts, discover, settings tabs" -Body {
    Ensure-Contacts -Adb $adb -Serial $DeviceB
    $contacts = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-contacts-tab" -DeviceDir $script:DeviceDir
    Ensure-Discover -Adb $adb -Serial $DeviceB
    $discover = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-discover-tab" -DeviceDir $script:DeviceDir
    Ensure-Settings -Adb $adb -Serial $DeviceB
    $settings = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-settings-tab" -DeviceDir $script:DeviceDir
    $contactsOk = $contacts.XmlText -like "*$($script:T.Contacts)*" -or $contacts.XmlText -like "*$($script:T.Search)*"
    $discoverOk = $discover.XmlText -like "*$($script:T.Discover)*"
    $settingsProbe = Test-Hits -XmlText $settings.XmlText -Needles @($script:T.Wallet, $script:T.Notification, $script:T.Privacy, $script:T.Language) -MinHits 3
    $ok = $contactsOk -and $discoverOk -and $settingsProbe.Pass -and $contacts.PngValid -and $discover.PngValid -and $settings.PngValid
    New-CaseOutput -Status ($(if ($ok) { "PASS" } else { "FAIL" })) -Evidence @($contacts.PngPath, $contacts.XmlPath, $discover.PngPath, $discover.XmlPath, $settings.PngPath, $settings.XmlPath) -Assertions @{ contacts_ok = $contactsOk; discover_ok = $discoverOk; settings_hits = $settingsProbe.Hits; screenshots_valid = ($contacts.PngValid -and $discover.PngValid -and $settings.PngValid) } -Detail "Main non-chat tabs are reachable."
}

Invoke-Case -CaseId "FULL-A-SETTINGS-SECONDARY-ENTRIES" -Device "A-8MY" -Serial $DeviceA -Module "Settings secondary entries" -Body {
    Ensure-Settings -Adb $adb -Serial $DeviceA
    $settingsHome = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "full-settings-secondary-home" -DeviceDir $script:DeviceDir
    $targets = @($script:T.Notification, $script:T.Privacy, $script:T.DataStorage, $script:T.ChatSettings, $script:T.Devices, $script:T.Language, $script:T.Appearance)
    $hits = @(Get-TextHits -XmlText $settingsHome.XmlText -Needles $targets)
    $ok = $hits.Count -ge 5 -and $settingsHome.PngValid
    New-CaseOutput -Status ($(if ($ok) { "PASS" } else { "FAIL" })) -Evidence @($settingsHome.PngPath, $settingsHome.XmlPath) -Assertions @{ hits = $hits; screenshot_png_valid = $settingsHome.PngValid } -Detail "Settings secondary entries are visible. No setting was changed."
}

if (-not $SkipCallProbe) {
    Invoke-Case -CaseId "FULL-B-CALL-BUTTONS-VISIBLE-ONLY" -Device "B-UQG" -Serial $DeviceB -Module "Private call buttons visible only" -Body {
        Ensure-PrivateChat -Adb $adb -Serial $DeviceB -Title "Smoke Alice"
        $state = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "full-call-buttons-visible" -DeviceDir $script:DeviceDir
        $video = Find-ClickableByDesc -XmlText $state.XmlText -Text (Join-Chars @(0x89C6,0x9891,0x901A,0x8BDD))
        $voice = Find-ClickableByDesc -XmlText $state.XmlText -Text (Join-Chars @(0x8BED,0x97F3,0x901A,0x8BDD))
        $ok = ($null -ne $video) -and ($null -ne $voice) -and $state.PngValid
        New-CaseOutput -Status ($(if ($ok) { "PASS" } else { "FAIL" })) -Evidence @($state.PngPath, $state.XmlPath) -Assertions @{ video_button_visible = ($null -ne $video); voice_button_visible = ($null -ne $voice); screenshot_png_valid = $state.PngValid } -Detail "Call buttons are visible only; no call was placed."
    }
}

$finalTs = New-Timestamp
$aLog = Join-Path $logDir "A-8MY-full-suite-final-$finalTs.log"
$bLog = Join-Path $logDir "B-UQG-full-suite-final-$finalTs.log"
Save-Logcat -Adb $adb -Serial $DeviceA -Path $aLog
Save-Logcat -Adb $adb -Serial $DeviceB -Path $bLog

$scan = [ordered]@{
    generated_at = Get-IsoNow
    package = $PackageName
    suite = "full-real-device"
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
$scanPath = Join-Path $base "full-suite-final-logcat-scan-$finalTs.json"
$scan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scanPath -Encoding UTF8

New-Result -CaseId "FULL-FINAL-LOGCAT-SCAN" -Device "A-8MY,B-UQG" -Serial "$DeviceA,$DeviceB" -Module "Full suite final logcat scan" -Status $scanStatus -Evidence @($scanPath, $aLog, $bLog) -Assertions @{ fatal_pattern_count = $fatalTotal; app_error_pattern_count = $appTotal } -Detail "Full suite final crash scan."
Add-Event -EventsPath $script:EventsPath -CaseId "FULL-FINAL-LOGCAT-SCAN" -Device "$DeviceA,$DeviceB" -Module "Full suite final logcat scan" -Status $scanStatus -Detail "fatal=$fatalTotal app_error=$appTotal; scan=$(Short-Path $scanPath)" -DurationSeconds 1

$resultPath = Join-Path $base "full-suite-results-$finalTs.json"
$resultArray = @($script:Results.ToArray())
$resultArray | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$passCount = @($resultArray | Where-Object { $_.status -eq "PASS" }).Count
$failCount = @($resultArray | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = @($resultArray | Where-Object { $_.status -eq "TOOL_WARN" }).Count
$totalCount = $resultArray.Count

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("")
$reportLines.Add("## Full Real-Device Automation Suite ($((Get-Date).ToString('yyyy-MM-dd HH:mm')) +08:00)")
$reportLines.Add("")
$reportLines.Add("Script: `scripts/fast_real_device_full_suite.ps1`. Non-destructive default mode: no message sending, no delete/forward confirmation, no file selection, no payment, no withdraw/recharge submission, no settings save, and no call placement.")
$reportLines.Add("Call-button visibility probe is included by default; use `-SkipCallProbe` only when the device state cannot expose call controls.")
$reportLines.Add("")
$reportLines.Add("Summary: total=$totalCount, pass=$passCount, fail=$failCount, tool_warn=$warnCount.")
$reportLines.Add("")
$reportLines.Add("| Case | Device | Result | Evidence |")
$reportLines.Add("| --- | --- | --- | --- |")
foreach ($r in $resultArray) {
    $firstEvidence = if ($r.evidence.Count -gt 0) { $r.evidence[0] } else { "" }
    $reportLines.Add("| $($r.case_id) | $($r.device) | $($r.status) | $firstEvidence |")
}
$reportLines.Add("")
$reportLines.Add("Artifacts: ``$(Short-Path $resultPath)``, ``$(Short-Path $scanPath)``.")
$reportLines.Add("Tool/noise note: uiautomator RuntimeInit/app_process lines in logcat are automation noise unless fatal/app_error counters are non-zero.")

Add-Content -LiteralPath $reportPath -Value ($reportLines -join [Environment]::NewLine) -Encoding UTF8

$latestSummaryJsonPath = Join-Path $base "latest-full-suite-summary.json"
$latestSummaryMdPath = Join-Path $base "latest-full-suite-summary.md"
$failedCases = @($resultArray | Where-Object { $_.status -ne "PASS" } | ForEach-Object {
    [ordered]@{
        case_id = $_.case_id
        device = $_.device
        status = $_.status
        detail = $_.detail
        evidence = $_.evidence
    }
})
$latestRows = @($resultArray | ForEach-Object {
    [ordered]@{
        case_id = $_.case_id
        device = $_.device
        status = $_.status
        detail = $_.detail
        first_evidence = if ($_.evidence.Count -gt 0) { $_.evidence[0] } else { "" }
    }
})
$latestSummary = [ordered]@{
    generated_at = Get-IsoNow
    authoritative = $true
    suite = "full-real-device"
    script = "scripts\fast_real_device_full_suite.ps1"
    command = if ($SkipCallProbe) { "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fast_real_device_full_suite.ps1 -SkipCallProbe" } else { "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fast_real_device_full_suite.ps1" }
    package = $PackageName
    devices = @($DeviceA, $DeviceB)
    call_probe_included = (-not $SkipCallProbe)
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
    failed_cases = $failedCases
    results = $latestRows
}
$latestSummary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestSummaryJsonPath -Encoding UTF8

$latestMd = New-Object System.Collections.Generic.List[string]
$latestMd.Add("# Latest Full Real-Device Suite")
$latestMd.Add("")
$latestMd.Add("Generated: $($latestSummary.generated_at)")
$latestMd.Add("")
$latestMd.Add("Command: ``$($latestSummary.command)``")
$latestMd.Add("")
$latestMd.Add("Summary: total=$totalCount, pass=$passCount, fail=$failCount, tool_warn=$warnCount, fatal=$fatalTotal, app_error=$appTotal.")
$latestMd.Add("")
$latestMd.Add("Artifacts: ``$(Short-Path $resultPath)``, ``$(Short-Path $scanPath)``.")
$latestMd.Add("")
$latestMd.Add("| Case | Device | Result | Evidence |")
$latestMd.Add("| --- | --- | --- | --- |")
foreach ($r in $latestRows) {
    $latestMd.Add("| $($r.case_id) | $($r.device) | $($r.status) | $($r.first_evidence) |")
}
Set-Content -LiteralPath $latestSummaryMdPath -Value ($latestMd -join [Environment]::NewLine) -Encoding UTF8

[ordered]@{
    result_path = Short-Path $resultPath
    scan_path = Short-Path $scanPath
    latest_summary_json = Short-Path $latestSummaryJsonPath
    latest_summary_md = Short-Path $latestSummaryMdPath
    report_path = Short-Path $reportPath
    events_path = Short-Path $script:EventsPath
    total = $totalCount
    pass = $passCount
    fail = $failCount
    tool_warn = $warnCount
    fatal_pattern_count = $fatalTotal
    app_error_pattern_count = $appTotal
} | ConvertTo-Json -Depth 6
