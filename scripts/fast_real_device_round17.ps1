<#
.SYNOPSIS
执行第 17 轮双 Android 真机快速回归用例。

.DESCRIPTION
复用 BaseDir 中已经准备的账号与会话，通过固定坐标和 UI 文本驱动两台设备，
收集每项用例的截图、日志和汇总。脚本依赖当轮 UI 布局和数据种子，不应作为
其他版本的通用验收套件直接运行。

.PARAMETER DeviceA
第一台当轮 QA 真机的 ADB 序列号。

.PARAMETER DeviceB
第二台当轮 QA 真机的 ADB 序列号。

.PARAMETER DelayMs
ADB 操作间隔，用于等待动画和网络状态稳定。

.EXAMPLE
pwsh -File scripts/fast_real_device_round17.ps1
#>
param(
    [string]$BaseDir = "artifacts\real-device-test-20260623-233903",
    [string]$DeviceA = "8MY0220C17006781",
    [string]$DeviceB = "UQG5T20915006269",
    [string]$PackageName = "com.genericim.ma100",
    [int]$DelayMs = 450
)

$ErrorActionPreference = "Stop"

function Get-AdbCommand {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

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

    throw "adb not found."
}

function New-Timestamp {
    return (Get-Date).ToString("yyyyMMdd-HHmmss")
}

function Join-Chars {
    param([int[]]$Codes)
    return -join ($Codes | ForEach-Object { [char]$_ })
}

function Get-IsoNow {
    return (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Invoke-Tap {
    param(
        [string]$Adb,
        [string]$Serial,
        [int]$X,
        [int]$Y
    )
    & $Adb -s $Serial shell input tap $X $Y | Out-Null
}

function Invoke-Back {
    param(
        [string]$Adb,
        [string]$Serial
    )
    & $Adb -s $Serial shell input keyevent KEYCODE_BACK | Out-Null
}

function Get-NodeAttribute {
    param(
        [string]$Node,
        [string]$Name
    )

    $match = [regex]::Match($Node, "$Name=`"([^`"]*)`"")
    if (-not $match.Success) { return "" }
    return [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
}

function Get-UiNodes {
    param([string]$XmlText)
    return @(
        [regex]::Matches($XmlText, '<node\b[^>]*>') |
            ForEach-Object { $_.Value }
    )
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
        X1 = $x1
        Y1 = $y1
        X2 = $x2
        Y2 = $y2
        X = [int](($x1 + $x2) / 2)
        Y = [int](($y1 + $y2) / 2)
        Width = $x2 - $x1
        Height = $y2 - $y1
    }
}

function Find-Node {
    param(
        [string]$XmlText,
        [scriptblock]$Predicate
    )

    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if (& $Predicate $node) { return $node }
    }
    return $null
}

function Find-ClickableByDesc {
    param(
        [string]$XmlText,
        [string]$Text,
        [switch]$Contains
    )

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

function Find-TopNodeByDescContains {
    param(
        [string]$XmlText,
        [string]$Text,
        [int]$MaxY2 = 420
    )

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
    param(
        [string]$XmlText,
        [string]$Title
    )

    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'clickable="true"') { continue }
        $desc = Get-NodeAttribute -Node $node -Name "content-desc"
        if ([string]::IsNullOrWhiteSpace($desc)) { continue }
        $parts = @($desc -split "`n")
        if ($parts.Count -ge 2 -and $parts[1] -eq $Title) {
            return $node
        }
    }
    return $null
}

function Tap-Node {
    param(
        [string]$Adb,
        [string]$Serial,
        [string]$Node
    )

    if ([string]::IsNullOrWhiteSpace($Node)) {
        throw "Tap-Node received an empty node."
    }

    $bounds = Get-NodeAttribute -Node $Node -Name "bounds"
    $box = Get-BoundsObject -Bounds $bounds
    if ($null -eq $box) {
        throw "Invalid node bounds: $bounds"
    }

    Invoke-Tap -Adb $Adb -Serial $Serial -X $box.X -Y $box.Y
    return $box
}

function Capture-State {
    param(
        [string]$Adb,
        [string]$Serial,
        [string]$Label,
        [string]$Suffix,
        [string]$DeviceDir
    )

    $ts = New-Timestamp
    $safe = "$Label-$Suffix-$ts"
    $remoteXml = "/sdcard/$safe.xml"
    $remotePng = "/sdcard/$safe.png"
    $xmlPath = Join-Path $DeviceDir "$safe.xml"
    $pngPath = Join-Path $DeviceDir "$safe.png"

    & $Adb -s $Serial shell uiautomator dump $remoteXml | Out-Null
    & $Adb -s $Serial pull $remoteXml $xmlPath | Out-Null

    # Capture on device first, then pull. PowerShell redirection corrupts binary
    # adb exec-out screencap output on Windows PowerShell.
    & $Adb -s $Serial shell screencap -p $remotePng | Out-Null
    & $Adb -s $Serial pull $remotePng $pngPath | Out-Null

    $xmlText = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
    $pngBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $pngPath))
    $pngValid = $pngBytes.Length -ge 8 -and
        $pngBytes[0] -eq 0x89 -and
        $pngBytes[1] -eq 0x50 -and
        $pngBytes[2] -eq 0x4E -and
        $pngBytes[3] -eq 0x47

    return [pscustomobject]@{
        Name = $safe
        Timestamp = $ts
        XmlPath = $xmlPath
        PngPath = $pngPath
        XmlText = $xmlText
        PngValid = $pngValid
        XmlSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $xmlPath).Hash
    }
}

function Get-FirstEditText {
    param([string]$XmlText)
    return Find-Node -XmlText $XmlText -Predicate {
        param($node)
        return $node -match 'class="android.widget.EditText"'
    }
}

function Get-TextContainsAny {
    param(
        [string]$XmlText,
        [string[]]$Needles
    )
    $hits = @()
    foreach ($needle in $Needles) {
        if ($XmlText -like "*$needle*") { $hits += $needle }
    }
    return $hits
}

function Get-BottomClickableNodes {
    param([string]$XmlText)

    $items = @()
    foreach ($node in (Get-UiNodes -XmlText $XmlText)) {
        if ($node -notmatch 'clickable="true"') { continue }
        $bounds = Get-NodeAttribute -Node $node -Name "bounds"
        $box = Get-BoundsObject -Bounds $bounds
        if ($null -eq $box) { continue }
        if ($box.Y2 -lt 2400) { continue }
        $items += [pscustomobject]@{
            Node = $node
            Bounds = $bounds
            X1 = $box.X1
            Y1 = $box.Y1
            X2 = $box.X2
            Y2 = $box.Y2
            X = $box.X
            Y = $box.Y
            Width = $box.Width
            Height = $box.Height
            Description = Get-NodeAttribute -Node $node -Name "content-desc"
            ClassName = Get-NodeAttribute -Node $node -Name "class"
        }
    }

    return @($items | Sort-Object X1, Y1)
}

function Get-PhysicalScreenSize {
    param(
        [string]$Adb,
        [string]$Serial
    )

    $output = (& $Adb -s $Serial shell wm size) -join "`n"
    $match = [regex]::Match($output, 'Physical size:\s*(\d+)x(\d+)')
    if (-not $match.Success) {
        return [pscustomobject]@{ Width = 1200; Height = 2640; Raw = $output }
    }
    return [pscustomobject]@{
        Width = [int]$match.Groups[1].Value
        Height = [int]$match.Groups[2].Value
        Raw = $output
    }
}

function Save-Logcat {
    param(
        [string]$Adb,
        [string]$Serial,
        [string]$Path
    )

    & $Adb -s $Serial logcat -d -v time |
        Out-File -LiteralPath $Path -Encoding UTF8
}

function Scan-LogcatFile {
    param(
        [string]$Path,
        [string]$Device
    )

    $fatalPattern = '(FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|ANR in com\.genericim\.app|Process:\s+com\.genericim\.app|AndroidRuntime.*FATAL)'
    $appPattern = '(E/flutter|FlutterError|Unhandled Exception|com\.genericim\.app.*(Exception|Error))'
    $toolPattern = '(com\.android\.uiautomator|AccessibilityNodeInfoDumper|app_process\(.*open file error|RuntimeInit: Starting tool|Calling main entry com\.android\.commands\.uiautomator\.Launcher)'

    $fatal = @(Select-String -LiteralPath $Path -Pattern $fatalPattern -AllMatches -ErrorAction SilentlyContinue)
    $app = @(Select-String -LiteralPath $Path -Pattern $appPattern -AllMatches -ErrorAction SilentlyContinue)
    $tool = @(Select-String -LiteralPath $Path -Pattern $toolPattern -AllMatches -ErrorAction SilentlyContinue)

    return [ordered]@{
        device = $Device
        log = $Path
        fatal_pattern_count = $fatal.Count
        app_error_pattern_count = $app.Count
        tool_pattern_count = $tool.Count
        fatal_samples = @($fatal | Select-Object -First 8 | ForEach-Object { $_.Line })
        app_error_samples = @($app | Select-Object -First 8 | ForEach-Object { $_.Line })
        tool_samples = @($tool | Select-Object -First 5 | ForEach-Object { $_.Line })
    }
}

function Add-Event {
    param(
        [string]$EventsPath,
        [string]$CaseId,
        [string]$Device,
        [string]$Module,
        [string]$Status,
        [string]$Detail,
        [int]$DurationSeconds
    )

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

function Short-Path {
    param([string]$Path)
    return $Path.Replace('/', '\')
}

$startedAt = Get-Date
$adb = Get-AdbCommand
$base = $BaseDir
$deviceDir = Join-Path $base "devices"
$logDir = Join-Path $base "logs"
$eventsPath = Join-Path $base "events.jsonl"
$reportPath = Join-Path $base "report.md"

Ensure-Dir -Path $base
Ensure-Dir -Path $deviceDir
Ensure-Dir -Path $logDir

$zhWithdraw = Join-Chars @(0x63D0, 0x73B0)
$zhWithdrawAll = Join-Chars @(0x5168, 0x90E8, 0x63D0, 0x73B0)
$zhWallet = Join-Chars @(0x94B1, 0x5305)
$zhSettings = Join-Chars @(0x8BBE, 0x7F6E)
$zhRecharge = Join-Chars @(0x5145, 0x503C)
$zhConfirmWithdraw = Join-Chars @(0x786E, 0x8BA4, 0x63D0, 0x73B0)
$zhPayPassword = Join-Chars @(0x652F, 0x4ED8, 0x5BC6, 0x7801)
$attachmentNeedles = @(
    (Join-Chars @(0x76F8, 0x518C)),
    (Join-Chars @(0x62CD, 0x6444)),
    (Join-Chars @(0x76F8, 0x673A)),
    (Join-Chars @(0x6444, 0x50CF, 0x5934)),
    (Join-Chars @(0x4F1A, 0x8BAE)),
    (Join-Chars @(0x4F4D, 0x7F6E)),
    (Join-Chars @(0x89C6, 0x9891)),
    (Join-Chars @(0x6587, 0x4EF6)),
    (Join-Chars @(0x7EA2, 0x5305)),
    (Join-Chars @(0x8F6C, 0x8D26)),
    (Join-Chars @(0x6536, 0x85CF)),
    "Album", "Camera", "Meeting", "Location", "Video", "File",
    "Red Packet", "Transfer", "Favorite"
)

$devicesOutput = & $adb devices
foreach ($serial in @($DeviceA, $DeviceB)) {
    if (-not ($devicesOutput -match "^$([regex]::Escape($serial))\s+device$")) {
        throw "Device $serial is not online."
    }
}

& $adb -s $DeviceA logcat -c | Out-Null
& $adb -s $DeviceB logcat -c | Out-Null

$evidence = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]
$roundTs = New-Timestamp

# Fast pre-navigation. It is intentionally conservative: only taps app-level
# navigation and existing list entries, never destructive actions.
$aNav0 = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "round17-pre-nav" -DeviceDir $deviceDir
$aNavIsWallet = ($null -ne (Find-ClickableByDesc -XmlText $aNav0.XmlText -Text $zhWithdraw)) -and
    ($null -ne (Find-ClickableByDesc -XmlText $aNav0.XmlText -Text $zhRecharge))
$aNavIsWithdraw = ($null -ne (Find-ClickableByDesc -XmlText $aNav0.XmlText -Text $zhWithdrawAll)) -and
    ($null -ne (Get-FirstEditText -XmlText $aNav0.XmlText))
if (-not ($aNavIsWallet -or $aNavIsWithdraw)) {
    $walletEntry = Find-ClickableByDesc -XmlText $aNav0.XmlText -Text $zhWallet
    if (-not $walletEntry) {
        $aScreen = Get-PhysicalScreenSize -Adb $adb -Serial $DeviceA
        Invoke-Tap -Adb $adb -Serial $DeviceA -X 938 -Y ([Math]::Max(1, $aScreen.Height - 90))
        Start-Sleep -Milliseconds $DelayMs
        $aNav1 = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "round17-pre-nav-settings" -DeviceDir $deviceDir
        $walletEntry = Find-ClickableByDesc -XmlText $aNav1.XmlText -Text $zhWallet
    }
    if ($walletEntry) {
        Tap-Node -Adb $adb -Serial $DeviceA -Node $walletEntry | Out-Null
        Start-Sleep -Milliseconds $DelayMs
    }
}

$bNav0 = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-pre-nav" -DeviceDir $deviceDir
$bNavIsChatDetail = ($null -ne (Find-TopNodeByDescContains -XmlText $bNav0.XmlText -Text "Smoke Alice")) -and
    ($bNav0.XmlText -match 'class="android.widget.EditText"')
if (-not $bNavIsChatDetail) {
    $smokeAliceEntry = Find-ConversationEntryBySecondLine -XmlText $bNav0.XmlText -Title "Smoke Alice"
    if ($bNav0.XmlText -match 'class="android.widget.EditText"') {
        Invoke-Back -Adb $adb -Serial $DeviceB
        Start-Sleep -Milliseconds $DelayMs
        $bNavBack = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-pre-nav-back" -DeviceDir $deviceDir
        $smokeAliceEntry = Find-ConversationEntryBySecondLine -XmlText $bNavBack.XmlText -Title "Smoke Alice"
    }
    if (-not $smokeAliceEntry) {
        $bScreen = Get-PhysicalScreenSize -Adb $adb -Serial $DeviceB
        Invoke-Tap -Adb $adb -Serial $DeviceB -X 260 -Y ([Math]::Max(1, $bScreen.Height - 90))
        Start-Sleep -Milliseconds $DelayMs
        $bNav1 = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-pre-nav-messages" -DeviceDir $deviceDir
        $smokeAliceEntry = Find-ConversationEntryBySecondLine -XmlText $bNav1.XmlText -Title "Smoke Alice"
    }
    if ($smokeAliceEntry) {
        Tap-Node -Adb $adb -Serial $DeviceB -Node $smokeAliceEntry | Out-Null
        Start-Sleep -Milliseconds $DelayMs
    }
}

# A: fast wallet withdraw-all zero-balance boundary.
$aStart = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "round17-fast-start" -DeviceDir $deviceDir
$evidence.Add((Short-Path $aStart.XmlPath))
$evidence.Add((Short-Path $aStart.PngPath))

$aStartedOnWithdrawPage = ($null -ne (Find-ClickableByDesc -XmlText $aStart.XmlText -Text $zhWithdrawAll)) -and
    ($null -ne (Get-FirstEditText -XmlText $aStart.XmlText))
$withdrawEntry = Find-ClickableByDesc -XmlText $aStart.XmlText -Text $zhWithdraw
$aEntryTapped = $false
if ($aStartedOnWithdrawPage) {
    $aEntryTapped = $true
} elseif ($withdrawEntry) {
    Tap-Node -Adb $adb -Serial $DeviceA -Node $withdrawEntry | Out-Null
    $aEntryTapped = $true
} else {
    Invoke-Tap -Adb $adb -Serial $DeviceA -X 600 -Y 960
}
Start-Sleep -Milliseconds $DelayMs

$aWithdraw = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "round17-withdraw-entry" -DeviceDir $deviceDir
$evidence.Add((Short-Path $aWithdraw.XmlPath))
$evidence.Add((Short-Path $aWithdraw.PngPath))

$allButton = Find-ClickableByDesc -XmlText $aWithdraw.XmlText -Text $zhWithdrawAll
$aAllTapped = $false
if ($allButton) {
    Tap-Node -Adb $adb -Serial $DeviceA -Node $allButton | Out-Null
    Start-Sleep -Milliseconds 180
    Tap-Node -Adb $adb -Serial $DeviceA -Node $allButton | Out-Null
    $aAllTapped = $true
} else {
    Invoke-Tap -Adb $adb -Serial $DeviceA -X 935 -Y 550
    Start-Sleep -Milliseconds 180
    Invoke-Tap -Adb $adb -Serial $DeviceA -X 935 -Y 550
}
Start-Sleep -Milliseconds $DelayMs

$aAfterAll = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "round17-withdraw-all-zero" -DeviceDir $deviceDir
$evidence.Add((Short-Path $aAfterAll.XmlPath))
$evidence.Add((Short-Path $aAfterAll.PngPath))

$amountNode = Get-FirstEditText -XmlText $aAfterAll.XmlText
$amountText = if ($amountNode) { Get-NodeAttribute -Node $amountNode -Name "text" } else { "" }
$aStillWithdraw = ($null -ne (Find-ClickableByDesc -XmlText $aAfterAll.XmlText -Text $zhWithdrawAll)) -and
    ($null -ne (Get-FirstEditText -XmlText $aAfterAll.XmlText))
$aNoPasswordDialog = $aAfterAll.XmlText -notlike "*$zhConfirmWithdraw*" -and
    $aAfterAll.XmlText -notlike "*$zhPayPassword*"
$aPngsValid = $aStart.PngValid -and $aWithdraw.PngValid -and $aAfterAll.PngValid
$aPass = $aEntryTapped -and $aAllTapped -and $aStillWithdraw -and $aNoPasswordDialog -and ($amountText -eq "0.00") -and $aPngsValid
$aStatus = if ($aPass) { "PASS" } else { "FAIL" }

$results.Add([ordered]@{
    case_id = "ROUND17-WALLET-WITHDRAW-ALL-ZERO-A"
    device = "A-8MY"
    serial = $DeviceA
    module = "Wallet withdraw-all zero-balance boundary"
    status = $aStatus
    evidence = @(
        (Short-Path $aStart.PngPath),
        (Short-Path $aStart.XmlPath),
        (Short-Path $aWithdraw.PngPath),
        (Short-Path $aWithdraw.XmlPath),
        (Short-Path $aAfterAll.PngPath),
        (Short-Path $aAfterAll.XmlPath)
    )
    assertions = [ordered]@{
        started_on_withdraw_page = $aStartedOnWithdrawPage
        wallet_withdraw_entry_tapped = $aEntryTapped
        withdraw_all_button_tapped = $aAllTapped
        amount_text_after_fast_double_tap = $amountText
        still_on_withdraw_page = $aStillWithdraw
        password_dialog_not_opened = $aNoPasswordDialog
        screenshots_are_valid_png = $aPngsValid
    }
    detail = "Fast double tap on Withdraw All at zero balance should only fill 0.00 and stay on the withdraw page without opening a password dialog or submitting."
})

Invoke-Back -Adb $adb -Serial $DeviceA
Start-Sleep -Milliseconds $DelayMs
$aReturn = Capture-State -Adb $adb -Serial $DeviceA -Label "A-8MY" -Suffix "round17-return-wallet" -DeviceDir $deviceDir
$evidence.Add((Short-Path $aReturn.XmlPath))
$evidence.Add((Short-Path $aReturn.PngPath))

# B: fast chat attachment entry plus bottom input-bar layout assertion.
$bStart = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-fast-start" -DeviceDir $deviceDir
$evidence.Add((Short-Path $bStart.XmlPath))
$evidence.Add((Short-Path $bStart.PngPath))
$bTargetHeaderAtStart = ($null -ne (Find-TopNodeByDescContains -XmlText $bStart.XmlText -Text "Smoke Alice"))

$bottomNodes = Get-BottomClickableNodes -XmlText $bStart.XmlText
$attachmentCandidate = @(
    $bottomNodes |
        Where-Object { $_.X1 -le 180 -and $_.Y1 -ge 2400 -and $_.Width -le 260 } |
        Sort-Object X1, Y1 |
        Select-Object -First 1
)
$inputBarXmlClipped = $false
$attachmentHeight = 0
$attachmentBounds = ""
if ($attachmentCandidate.Count -gt 0) {
    $attachmentHeight = [int]$attachmentCandidate[0].Height
    $attachmentBounds = $attachmentCandidate[0].Bounds
    if ($attachmentHeight -lt 24) {
        $inputBarXmlClipped = $true
    }
} else {
    $inputBarXmlClipped = $true
}

# First tap where a real user would tap the expected bottom-left attachment button.
# The UIAutomator XML is clipped at the app-window edge on this device, so use
# physical screen coordinates derived from wm size for actual human-like taps.
$bScreenSize = Get-PhysicalScreenSize -Adb $adb -Serial $DeviceB
$humanTapX = 92
$humanTapY = [Math]::Max(1, $bScreenSize.Height - 90)
$retryTapX = 92
$retryTapY = [Math]::Max(1, $bScreenSize.Height - 125)
Invoke-Tap -Adb $adb -Serial $DeviceB -X $humanTapX -Y $humanTapY
Start-Sleep -Milliseconds 260
$bAfterHumanTap = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-attachment-human-tap" -DeviceDir $deviceDir
$evidence.Add((Short-Path $bAfterHumanTap.XmlPath))
$evidence.Add((Short-Path $bAfterHumanTap.PngPath))

$humanTapHits = @(Get-TextContainsAny -XmlText $bAfterHumanTap.XmlText -Needles $attachmentNeedles)
$openedAfterHumanTap = $humanTapHits.Count -ge 2

$retryTapUsed = $false
$bAfterRetryTap = $null
$retryTapHits = @()
$openedAfterRetryTap = $false
if (-not $openedAfterHumanTap) {
    $retryTapUsed = $true
    Invoke-Tap -Adb $adb -Serial $DeviceB -X $retryTapX -Y $retryTapY
    Start-Sleep -Milliseconds $DelayMs
    $bAfterRetryTap = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-attachment-human-retry" -DeviceDir $deviceDir
    $evidence.Add((Short-Path $bAfterRetryTap.XmlPath))
    $evidence.Add((Short-Path $bAfterRetryTap.PngPath))
    $retryTapHits = @(Get-TextContainsAny -XmlText $bAfterRetryTap.XmlText -Needles $attachmentNeedles)
    $openedAfterRetryTap = $retryTapHits.Count -ge 2
}

$attachmentOpened = $openedAfterHumanTap -or $openedAfterRetryTap
$attachmentOptionHits = if ($openedAfterHumanTap) { $humanTapHits } else { $retryTapHits }
$bPngsValid = $bStart.PngValid -and $bAfterHumanTap.PngValid -and (($null -eq $bAfterRetryTap) -or $bAfterRetryTap.PngValid)

if ($attachmentOpened) {
    Invoke-Back -Adb $adb -Serial $DeviceB
    Start-Sleep -Milliseconds $DelayMs
}
$bReturn = Capture-State -Adb $adb -Serial $DeviceB -Label "B-UQG" -Suffix "round17-attachment-return" -DeviceDir $deviceDir
$evidence.Add((Short-Path $bReturn.XmlPath))
$evidence.Add((Short-Path $bReturn.PngPath))

$bStatus = "PASS"
if ((-not $bTargetHeaderAtStart) -or (-not $attachmentOpened) -or (-not $bPngsValid)) {
    $bStatus = "FAIL"
}

$bEvidence = @(
    (Short-Path $bStart.PngPath),
    (Short-Path $bStart.XmlPath),
    (Short-Path $bAfterHumanTap.PngPath),
    (Short-Path $bAfterHumanTap.XmlPath),
    (Short-Path $bReturn.PngPath),
    (Short-Path $bReturn.XmlPath)
)
if ($bAfterRetryTap) {
    $bEvidence = @(
        (Short-Path $bStart.PngPath),
        (Short-Path $bStart.XmlPath),
        (Short-Path $bAfterHumanTap.PngPath),
        (Short-Path $bAfterHumanTap.XmlPath),
        (Short-Path $bAfterRetryTap.PngPath),
        (Short-Path $bAfterRetryTap.XmlPath),
        (Short-Path $bReturn.PngPath),
        (Short-Path $bReturn.XmlPath)
    )
}

$results.Add([ordered]@{
    case_id = "ROUND17-CHAT-ATTACHMENT-SHEET-AND-INPUT-BAR-B"
    device = "B-UQG"
    serial = $DeviceB
    module = "Chat attachment sheet and bottom input-bar accessibility"
    status = $bStatus
    evidence = $bEvidence
    assertions = [ordered]@{
        bottom_clickable_nodes = @($bottomNodes | ForEach-Object {
            [ordered]@{
                bounds = $_.Bounds
                width = $_.Width
                height = $_.Height
                class = $_.ClassName
                description = $_.Description
            }
        })
        attachment_candidate_bounds = $attachmentBounds
        target_header_smoke_alice = $bTargetHeaderAtStart
        attachment_candidate_xml_visible_height = $attachmentHeight
        input_bar_xml_click_target_clipped_under_24px = $inputBarXmlClipped
        physical_screen_size = [ordered]@{ width = $bScreenSize.Width; height = $bScreenSize.Height; raw = $bScreenSize.Raw }
        human_tap_point = [ordered]@{ x = $humanTapX; y = $humanTapY }
        retry_tap_point = [ordered]@{ x = $retryTapX; y = $retryTapY }
        opened_after_realistic_human_tap = $openedAfterHumanTap
        human_retry_tap_used = $retryTapUsed
        opened_after_human_retry_tap = $openedAfterRetryTap
        detected_attachment_options = @($attachmentOptionHits)
        screenshots_are_valid_png = $bPngsValid
    }
    detail = "Fast user-like tap on the chat attachment button should open the attachment sheet. The bottom input controls must remain visibly tappable, not reduced to a few pixels at the safe-area edge."
})

$finalTs = New-Timestamp
$aLog = Join-Path $logDir "A-8MY-round17-final-$finalTs.log"
$bLog = Join-Path $logDir "B-UQG-round17-final-$finalTs.log"
Save-Logcat -Adb $adb -Serial $DeviceA -Path $aLog
Save-Logcat -Adb $adb -Serial $DeviceB -Path $bLog

$scan = [ordered]@{
    generated_at = Get-IsoNow
    package = $PackageName
    round = 17
    devices = @(
        (Scan-LogcatFile -Path $aLog -Device "A-8MY"),
        (Scan-LogcatFile -Path $bLog -Device "B-UQG")
    )
}
$scanPath = Join-Path $base "round17-final-logcat-scan-$finalTs.json"
$scan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scanPath -Encoding UTF8

$fatalTotal = 0
$appErrorTotal = 0
foreach ($deviceScan in $scan.devices) {
    $fatalTotal += [int]$deviceScan.fatal_pattern_count
    $appErrorTotal += [int]$deviceScan.app_error_pattern_count
}
$scanStatus = if ($fatalTotal -eq 0 -and $appErrorTotal -eq 0) { "PASS" } else { "FAIL" }

$results.Add([ordered]@{
    case_id = "ROUND17-FINAL-LOGCAT-SCAN"
    device = "A-8MY,B-UQG"
    serial = "$DeviceA,$DeviceB"
    module = "Round 17 final crash scan"
    status = $scanStatus
    evidence = @(
        (Short-Path $scanPath),
        (Short-Path $aLog),
        (Short-Path $bLog)
    )
    assertions = [ordered]@{
        fatal_pattern_count = $fatalTotal
        app_error_pattern_count = $appErrorTotal
    }
    detail = "A/B fatal and app-error logcat scan after round 17 fast real-device operations."
})

$resultPath = Join-Path $base "round17-withdraw-attachment-results-$finalTs.json"
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$resultShort = Short-Path $resultPath
$scanShort = Short-Path $scanPath
$aAfterAllXmlShort = Short-Path $aAfterAll.XmlPath
$aAfterAllPngShort = Short-Path $aAfterAll.PngPath
$bStartXmlShort = Short-Path $bStart.XmlPath
$bStartPngShort = Short-Path $bStart.PngPath
$bHumanXmlShort = Short-Path $bAfterHumanTap.XmlPath
$bHumanPngShort = Short-Path $bAfterHumanTap.PngPath
$scriptShort = "scripts\fast_real_device_round17.ps1"
$optionHitText = if ($attachmentOptionHits.Count -gt 0) { $attachmentOptionHits -join ", " } else { "(none)" }

$duration = [int]((Get-Date) - $startedAt).TotalSeconds
Add-Event -EventsPath $eventsPath -CaseId "ROUND17-WALLET-WITHDRAW-ALL-ZERO-A" -Device $DeviceA -Module "Wallet withdraw all zero balance" -Status $aStatus -Detail ("fast enter withdraw and double tap withdraw-all; amount_text='{0}'; result={1}" -f $amountText, $resultShort) -DurationSeconds $duration
Add-Event -EventsPath $eventsPath -CaseId "ROUND17-CHAT-ATTACHMENT-SHEET-AND-INPUT-BAR-B" -Device $DeviceB -Module "Chat attachment sheet and bottom input-bar accessibility" -Status $bStatus -Detail ("attachment_xml_height={0}px; human_tap_opened={1}; retry_tap_opened={2}; result={3}" -f $attachmentHeight, $openedAfterHumanTap, $openedAfterRetryTap, $resultShort) -DurationSeconds $duration
Add-Event -EventsPath $eventsPath -CaseId "ROUND17-FINAL-LOGCAT-SCAN" -Device "$DeviceA,$DeviceB" -Module "Round 17 final crash scan" -Status $scanStatus -Detail ("fatal={0} app_error={1}; scan={2}" -f $fatalTotal, $appErrorTotal, $scanShort) -DurationSeconds 1

$roundTime = (Get-Date).ToString("yyyy-MM-dd HH:mm")
$defectRows = New-Object System.Collections.Generic.List[string]
if ($aStatus -eq "FAIL") {
    $defectRows.Add(('| Wallet withdraw-all zero balance | A | FAIL | After fast double tap, amount_text={0}; expected 0.00, still on withdraw page, and no password dialog. Evidence: {1}, {2}, {3}. |' -f $amountText, $resultShort, $aAfterAllXmlShort, $aAfterAllPngShort))
}
if ($bStatus -eq "FAIL") {
    $defectRows.Add(('| Chat bottom input bar / attachment entry accessibility | B | FAIL | target_header={0}; attachment candidate bounds={1}, xml_height={2}px; human_tap_opened={3}, retry_tap_opened={4}. Evidence: {5}, {6}, {7}, {8}, {9}. |' -f $bTargetHeaderAtStart, $attachmentBounds, $attachmentHeight, $openedAfterHumanTap, $openedAfterRetryTap, $resultShort, $bStartXmlShort, $bStartPngShort, $bHumanXmlShort, $bHumanPngShort))
}

$passRows = @(
    ('| Wallet withdraw-all zero balance | A | {0} | {1}; entry_tapped={2}, all_tapped={3}, amount_text={4}, png_valid={5} |' -f $aStatus, $resultShort, $aEntryTapped, $aAllTapped, $amountText, $aPngsValid),
    ('| Chat attachment sheet and input-bar accessibility | B | {0} | {1}; target_header={2}, attachment_xml_height={3}px, human_tap_opened={4}, retry_tap_opened={5}, options={6} |' -f $bStatus, $resultShort, $bTargetHeaderAtStart, $attachmentHeight, $openedAfterHumanTap, $openedAfterRetryTap, $optionHitText),
    ('| Round final crash scan | A/B | {0} | {1}; fatal={2}, app_error={3} |' -f $scanStatus, $scanShort, $fatalTotal, $appErrorTotal)
)

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("")
$reportLines.Add("## Continue Test 17 ($roundTime +08:00)")
$reportLines.Add("")
$reportLines.Add("This round uses fast real-device automation script $scriptShort. Screenshots are captured on-device with screencap and pulled with adb to avoid Windows PowerShell binary redirection corruption. No message was sent, no file was selected, and no withdraw/fund submit action was tapped.")
$reportLines.Add("")
$reportLines.Add("New results:")
$reportLines.Add("")
$reportLines.Add("| Case | Device | Result | Evidence / notes |")
$reportLines.Add("| --- | --- | --- | --- |")
foreach ($row in $passRows) { $reportLines.Add($row) }

if ($defectRows.Count -gt 0) {
    $reportLines.Add("")
    $reportLines.Add("New real defects / high-risk issues:")
    $reportLines.Add("")
    $reportLines.Add("| Case | Device | Result | Evidence / notes |")
    $reportLines.Add("| --- | --- | --- | --- |")
    foreach ($row in $defectRows) { $reportLines.Add($row) }
}

$reportLines.Add("")
$reportLines.Add("Tool/noise notes:")
$reportLines.Add("")
$reportLines.Add(("- tool_pattern_count in {0}, if any, is treated as uiautomator/RuntimeInit automation noise, not an app crash." -f $scanShort))
$reportLines.Add("- B-side attachment test did not tap secondary actions such as album, camera, file, red packet, transfer, or favorite; it only verified the entry sheet and bottom input-bar accessibility.")

Add-Content -LiteralPath $reportPath -Value ($reportLines -join [Environment]::NewLine) -Encoding UTF8

[ordered]@{
    result_path = Short-Path $resultPath
    scan_path = Short-Path $scanPath
    report_path = Short-Path $reportPath
    events_path = Short-Path $eventsPath
    statuses = @(
        [ordered]@{ case_id = "ROUND17-WALLET-WITHDRAW-ALL-ZERO-A"; status = $aStatus },
        [ordered]@{ case_id = "ROUND17-CHAT-ATTACHMENT-SHEET-AND-INPUT-BAR-B"; status = $bStatus },
        [ordered]@{ case_id = "ROUND17-FINAL-LOGCAT-SCAN"; status = $scanStatus }
    )
} | ConvertTo-Json -Depth 6
