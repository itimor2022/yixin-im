param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Device = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDir = Join-Path $repoRoot "artifacts\real-device-qa\search-filter-ui-$timestamp"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# UIAutomator 偶尔会生成空文件，因此同时检查命令状态、拉取结果和最小文件大小。
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

function Get-NodeCenter($node) {
    # 点击坐标统一从控件 bounds 中心计算，避免脚本绑定到单一分辨率。
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
    $center = Get-NodeCenter $node
    & $Adb -s $Device shell input tap $center[0] $center[1] | Out-Null
    Start-Sleep -Seconds 3
}

& $Adb -s $Device shell am force-stop com.genericim.app | Out-Null
& $Adb -s $Device shell am start -W -n com.genericim.app/.MainActivity | Out-Null
Start-Sleep -Seconds 15

# 按“会话列表 -> 私聊详情 -> 用户资料 -> 搜索筛选”逐层进入目标页面。
$chatList = Get-UiXml '01-chat-list'
$chatNode = @($chatList.SelectNodes("//node[@clickable='true']")) |
    Where-Object { [string]$_.GetAttribute('content-desc') -match 'SW_ClockPeer' } |
    Select-Object -First 1
if ($null -eq $chatNode) { throw 'Seed private chat was not found' }
Tap-Node $chatNode

$detail = Get-UiXml '02-chat-detail'
$profileNode = @($detail.SelectNodes("//node[@clickable='true']")) |
    Where-Object {
        $description = [string]$_.GetAttribute('content-desc')
        $bounds = [string]$_.GetAttribute('bounds')
        $description -match 'SW_ClockPeer' -and $bounds -match '^\[\d+,(1\d\d|2\d\d)\]'
    } |
    Select-Object -First 1
if ($null -eq $profileNode) { throw 'Private chat profile header was not found' }
Tap-Node $profileNode

$profile = Get-UiXml '03-profile'
$searchNode = @($profile.SelectNodes("//node[@clickable='true' and @content-desc='搜索']")) |
    Select-Object -First 1
if ($null -eq $searchNode) { throw 'Profile search action was not found' }
Tap-Node $searchNode

$searchPage = Get-UiXml '04-search-filters'
# 这里验证的是筛选入口契约；具体筛选结果由 API/功能用例覆盖。
$filterLabels = @('联系人', '日期', '类型')
foreach ($label in $filterLabels) {
    $node = @($searchPage.SelectNodes("//node[@content-desc='$label']")) | Select-Object -First 1
    if ($null -eq $node) { throw "Search filter $label was not visible" }
}

$remotePng = "/sdcard/im400-search-filters-$timestamp.png"
$localPng = Join-Path $outputDir '04-search-filters.png'
& $Adb -s $Device shell screencap -p $remotePng | Out-Null
& $Adb -s $Device pull $remotePng $localPng | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $localPng)) {
    throw 'Search filter screenshot failed'
}

$typeNode = @($searchPage.SelectNodes("//node[@content-desc='类型']")) | Select-Object -First 1
Tap-Node $typeNode
$typeSheet = Get-UiXml '05-type-filter-sheet'
foreach ($label in @('全部类型', '文字', '图片', '视频', '语音', '文件')) {
    $node = @($typeSheet.SelectNodes("//node[@content-desc='$label']")) | Select-Object -First 1
    if ($null -eq $node) { throw "Message type option $label was not visible" }
}

$report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    device = $Device
    status = 'PASS'
    case_ids = @('IM-233', 'IM-234', 'IM-235')
    detail = 'Private-chat search exposed sender, date and type filters; type sheet exposed all supported message categories.'
    evidence = @(
        (Join-Path $outputDir '04-search-filters.xml')
        $localPng
        (Join-Path $outputDir '05-type-filter-sheet.xml')
    )
}
$reportPath = Join-Path $outputDir 'results.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $reportPath
$report | ConvertTo-Json -Depth 6
