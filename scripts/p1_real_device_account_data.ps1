<#
.SYNOPSIS
在 Android 真机验证缓存、账号数据和加密材料的分级清理。

.DESCRIPTION
通过设置页执行 ClearCache、ClearAccountData 或 ResetEncryption，并使用
UI dump/截图验证结果。后两种操作可能删除登录态、离线消息或本地密钥，
无法撤销，只能在可重新登录和恢复的测试账号上运行。

.PARAMETER DeviceId
被执行数据清理操作的 ADB 设备。

.PARAMETER Operation
需要验证的数据清理级别。

.PARAMETER ExpectedChatMarker
清理前后用于判断聊天数据是否应保留的唯一文本。

.EXAMPLE
pwsh -File scripts/p1_real_device_account_data.ps1 -DeviceId emulator-5554 -Operation ClearCache
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [Parameter(Mandatory = $true)]
    [ValidateSet("ClearCache", "ClearAccountData", "ResetEncryption")]
    [string]$Operation,
    [string]$ExpectedChatMarker = "",
    [string]$PackageName = "com.genericim.ma100",
    [string]$OutputDir = "artifacts/account-data-p1-device-smoke"
)

$ErrorActionPreference = "Stop"

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
    throw "Could not find adb."
}

function Get-UiDump {
    param([string]$Name)

    $remote = "/sdcard/$Name.xml"
    & $adb -s $DeviceId shell uiautomator dump $remote | Out-Null
    $local = Join-Path $resolvedOutputDir "$Name.xml"
    & $adb -s $DeviceId pull $remote $local | Out-Null
    return Get-Content -Raw -Encoding utf8 -LiteralPath $local
}

function Get-Center {
    param([string]$Bounds)

    $match = [regex]::Match($Bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { throw "Invalid bounds: $Bounds" }
    return @(
        [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2),
        [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    )
}

function Find-Node {
    param(
        [string]$XmlText,
        [string]$Label,
        [int]$MaximumWidth = 1200,
        [switch]$AllowNonClickable
    )

    foreach ($match in [regex]::Matches($XmlText, '<node\b[^>]*>')) {
        $node = $match.Value
        $descriptionMatch = [regex]::Match($node, 'content-desc="([^"]*)"')
        if (-not $descriptionMatch.Success) { continue }
        $description = [System.Net.WebUtility]::HtmlDecode($descriptionMatch.Groups[1].Value)
        if (-not $description.StartsWith($Label, [System.StringComparison]::Ordinal)) { continue }
        if (-not $AllowNonClickable -and $node -notmatch 'clickable="true"') { continue }
        $boundsMatch = [regex]::Match($node, 'bounds="([^"]+)"')
        if (-not $boundsMatch.Success) { continue }
        $coordinateMatch = [regex]::Match($boundsMatch.Groups[1].Value, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        if (-not $coordinateMatch.Success) { continue }
        $width = [int]$coordinateMatch.Groups[3].Value - [int]$coordinateMatch.Groups[1].Value
        if ($width -gt $MaximumWidth) { continue }
        return $boundsMatch.Groups[1].Value
    }
    return $null
}

function Tap-Bounds {
    param([string]$Bounds)

    $center = Get-Center -Bounds $Bounds
    & $adb -s $DeviceId shell input tap $center[0] $center[1] | Out-Null
}

function Tap-Label {
    param(
        [string]$XmlText,
        [string]$Label,
        [int]$MaximumWidth = 1200,
        [switch]$AllowNonClickable
    )

    $bounds = Find-Node -XmlText $XmlText -Label $Label -MaximumWidth $MaximumWidth -AllowNonClickable:$AllowNonClickable
    if (-not $bounds) { throw "UI entry '$Label' was not found." }
    Tap-Bounds -Bounds $bounds
}

function Find-ClassNode {
    param(
        [string]$XmlText,
        [string]$ClassName
    )

    foreach ($match in [regex]::Matches($XmlText, '<node\b[^>]*>')) {
        $node = $match.Value
        if ($node -notmatch ('class="' + [regex]::Escape($ClassName) + '"')) { continue }
        $boundsMatch = [regex]::Match($node, 'bounds="([^"]+)"')
        if ($boundsMatch.Success) { return $boundsMatch.Groups[1].Value }
    }
    return $null
}

function Enter-ConfirmationText {
    param(
        [string]$XmlText,
        [string]$Value
    )

    $bounds = Find-ClassNode -XmlText $XmlText -ClassName "android.widget.EditText"
    if (-not $bounds) { throw "Confirmation EditText was not found." }
    Tap-Bounds -Bounds $bounds
    & $adb -s $DeviceId shell input text $Value | Out-Null
}

function Save-Screenshot {
    param([string]$Name)

    $remote = "/sdcard/$Name.png"
    & $adb -s $DeviceId shell screencap -p $remote | Out-Null
    & $adb -s $DeviceId pull $remote (Join-Path $resolvedOutputDir "$Name.png") | Out-Null
}

function Open-DataStorage {
    & $adb -s $DeviceId shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 3

    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $xml = Get-UiDump -Name ("01-navigation-{0:D2}" -f $attempt)
        if ($xml.Contains('content-desc="本机账号数据"')) { return $xml }

        $dataBounds = Find-Node -XmlText $xml -Label "数据和存储"
        if ($dataBounds) {
            Tap-Bounds -Bounds $dataBounds
            Start-Sleep -Seconds 3
            continue
        }

        $settingsBounds = Find-Node -XmlText $xml -Label "设置" -MaximumWidth 400
        if ($settingsBounds) {
            Tap-Bounds -Bounds $settingsBounds
            Start-Sleep -Seconds 2
            continue
        }

        & $adb -s $DeviceId shell input keyevent KEYCODE_BACK | Out-Null
        Start-Sleep -Seconds 1
    }
    throw "Could not navigate to Data and Storage."
}

function Wait-ForLogin {
    $deadline = (Get-Date).AddSeconds(35)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $xml = Get-UiDump -Name "05-after-operation"
        if ($xml.Contains('content-desc="登录您的账号"')) { return $xml }
    }
    throw "Login page was not reached after $Operation."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $repoRoot $OutputDir
}
$resolvedOutputDir = Join-Path $resolvedOutputDir "$DeviceId-$Operation"
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$adb = Get-AdbCommand
$online = (& $adb devices) -join "`n"
if ($online -notmatch "(?m)^$([regex]::Escape($DeviceId))\s+device$") {
    throw "Device '$DeviceId' is not online."
}

& $adb -s $DeviceId logcat -c
$xml = Open-DataStorage
$xml = Get-UiDump -Name "02-data-storage"
Save-Screenshot -Name "02-data-storage"

switch ($Operation) {
    "ClearCache" {
        Tap-Label -XmlText $xml -Label "清除缓存"
        Start-Sleep -Seconds 1
        $xml = Get-UiDump -Name "03-clear-cache-confirm"
        Tap-Label -XmlText $xml -Label "清除" -MaximumWidth 600
        Start-Sleep -Seconds 5
        $xml = Get-UiDump -Name "04-after-clear-cache"
        if ($xml.Contains('content-desc="登录您的账号"')) {
            throw "Clearing cache unexpectedly signed the account out."
        }
        Save-Screenshot -Name "04-after-clear-cache"

        & $adb -s $DeviceId shell input keyevent KEYCODE_BACK | Out-Null
        Start-Sleep -Seconds 2
        $xml = Get-UiDump -Name "05-settings-after-clear-cache"
        $messagesBounds = Find-Node -XmlText $xml -Label "消息" -MaximumWidth 400
        if ($messagesBounds) {
            Tap-Bounds -Bounds $messagesBounds
            Start-Sleep -Seconds 2
        }
        $xml = Get-UiDump -Name "06-chat-after-clear-cache"
        if ($ExpectedChatMarker -and -not $xml.Contains($ExpectedChatMarker)) {
            throw "Expected chat marker was not preserved after clearing cache: $ExpectedChatMarker"
        }
        Save-Screenshot -Name "06-chat-after-clear-cache"
    }
    "ClearAccountData" {
        Tap-Label -XmlText $xml -Label "清除本机账号数据"
        Start-Sleep -Seconds 2
        $xml = Get-UiDump -Name "03-clear-account-confirm"
        Enter-ConfirmationText -XmlText $xml -Value "CLEAR"
        Start-Sleep -Seconds 1
        $xml = Get-UiDump -Name "04-clear-account-enabled"
        Tap-Label -XmlText $xml -Label "清除并退出" -MaximumWidth 700
        $null = Wait-ForLogin
        Save-Screenshot -Name "05-after-operation"
    }
    "ResetEncryption" {
        Tap-Label -XmlText $xml -Label "重置加密身份"
        Start-Sleep -Seconds 2
        $xml = Get-UiDump -Name "03-reset-encryption-confirm"
        Enter-ConfirmationText -XmlText $xml -Value "RESET"
        Start-Sleep -Seconds 1
        $xml = Get-UiDump -Name "04-reset-encryption-enabled"
        Tap-Label -XmlText $xml -Label "重置并退出" -MaximumWidth 700
        $null = Wait-ForLogin
        Save-Screenshot -Name "05-after-operation"
    }
}

$logPath = Join-Path $resolvedOutputDir "logcat.txt"
& $adb -s $DeviceId logcat -d -v time | Set-Content -Encoding utf8 -LiteralPath $logPath
$fatal = Get-Content -Encoding utf8 -LiteralPath $logPath |
    Select-String -Pattern 'FATAL EXCEPTION|ANR in com\.genericim\.app|IsarError|Unhandled Exception'
if ($fatal) {
    throw "Fatal log detected during $Operation`:`n$($fatal.Line -join "`n")"
}

Write-Host "P1 real-device operation passed: $Operation" -ForegroundColor Green
Write-Host "Evidence: $resolvedOutputDir"
