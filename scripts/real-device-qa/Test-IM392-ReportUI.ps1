param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Device = 'emulator-5554',
    [string]$Apk = 'build\app\outputs\flutter-apk\app-debug.apk'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$apkPath = (Resolve-Path (Join-Path $repoRoot $Apk)).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDir = Join-Path $repoRoot "artifacts\real-device-qa\im392-report-ui-$timestamp"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# 每一步保留原始 XML，失败时可回看当时的可访问性树而不只依赖截图。
function Get-UiXml([string]$name) {
    $remote = "/sdcard/$name-$timestamp.xml"
    $local = Join-Path $outputDir "$name.xml"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & $Adb -s $Device shell uiautomator dump $remote | Out-Null
        if ($LASTEXITCODE -eq 0) {
            & $Adb -s $Device pull $remote $local | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $local) -and (Get-Item $local).Length -gt 100) {
                return [xml](Get-Content -Raw -Encoding utf8 $local)
            }
        }
        Start-Sleep -Seconds 2
    }
    throw "Unable to capture UI XML for $name"
}

function Get-Center($node) {
    $bounds = [string]$node.GetAttribute('bounds')
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Invalid bounds: $bounds"
    }
    return @(
        [int](([int]$Matches[1] + [int]$Matches[3]) / 2),
        [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    )
}

function Tap-Node($node) {
    $center = Get-Center $node
    & $Adb -s $Device shell input tap $center[0] $center[1] | Out-Null
    Start-Sleep -Seconds 3
}

$install = & $Adb -s $Device install -r -t $apkPath 2>&1
# install 既检查退出码也检查 Success 文本，兼容 adb 返回非结构化输出的行为。
if ($LASTEXITCODE -ne 0 -or ($install -join "`n") -notmatch 'Success') {
    throw 'APK install failed'
}
& $Adb -s $Device shell am force-stop com.genericim.app | Out-Null
& $Adb -s $Device shell am start -W -n com.genericim.app/.MainActivity | Out-Null
Start-Sleep -Seconds 15

$chatList = Get-UiXml '01-chat-list'
$chatNode = @($chatList.SelectNodes("//node[@clickable='true']")) |
    Where-Object { [string]$_.GetAttribute('content-desc') -match 'SW_ClockPeer' } |
    Select-Object -First 1
if ($null -eq $chatNode) { throw 'Seed private chat was not found' }
Tap-Node $chatNode

$detail = Get-UiXml '02-chat-detail'
$incoming = @($detail.SelectNodes("//node[@long-clickable='true']")) |
    Where-Object { [string]$_.GetAttribute('content-desc') -match '^IM040_IN_' } |
    Select-Object -First 1
if ($null -eq $incoming) { throw 'Incoming seed message was not found' }
# 长按通过起终点一致的 swipe 实现，持续时间用于触发 Android 长按手势。
$center = Get-Center $incoming
& $Adb -s $Device shell input swipe $center[0] $center[1] $center[0] $center[1] 1000 | Out-Null
Start-Sleep -Seconds 3

$menu = Get-UiXml '03-message-menu'
$reportNode = @($menu.SelectNodes("//node[@content-desc='举报']")) | Select-Object -First 1
if ($null -eq $reportNode) { throw 'Message report action was not visible' }
Tap-Node $reportNode

$reportPage = Get-UiXml '04-report-page'
# 同时检查标题、提交动作和全部原因项，防止页面只渲染出部分骨架。
foreach ($label in @('举报', '提交', '垃圾信息', '虚假信息或诈骗', '骚扰或欺凌', '其他')) {
    $node = @($reportPage.SelectNodes("//node[@content-desc='$label']")) | Select-Object -First 1
    if ($null -eq $node) { throw "Report page item $label was not visible" }
}

$remotePng = "/sdcard/im392-report-$timestamp.png"
$localPng = Join-Path $outputDir '04-report-page.png'
& $Adb -s $Device shell screencap -p $remotePng | Out-Null
& $Adb -s $Device pull $remotePng $localPng | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $localPng)) { throw 'Screenshot failed' }

$report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    device = $Device
    status = 'PASS'
    case_ids = @('IM-392')
    detail = 'Long-pressing an incoming message exposed Report and opened the validated shared report form.'
    evidence = @(
        (Join-Path $outputDir '03-message-menu.xml')
        (Join-Path $outputDir '04-report-page.xml')
        $localPng
    )
}
$reportPath = Join-Path $outputDir 'results.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $reportPath
$report | ConvertTo-Json -Depth 6
