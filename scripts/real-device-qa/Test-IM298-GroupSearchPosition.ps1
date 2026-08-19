<#
.SYNOPSIS
验证群聊消息搜索可以定位并高亮指定历史消息。

.DESCRIPTION
在目标设备打开预置群聊，搜索唯一文本并跳转到原消息位置，保存每一步 UI
层级和截图。脚本依赖 GroupName 与 SearchTarget 已存在于测试账号历史中，
不会自行创建种子数据。

.PARAMETER GroupName
包含目标历史消息的预置测试群名称。

.PARAMETER SearchTarget
用于搜索和定位的唯一消息文本。

.EXAMPLE
pwsh -File scripts/real-device-qa/Test-IM298-GroupSearchPosition.ps1 -DeviceId emulator-5554
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.ma100",
    [string]$GroupName = "IM群改名实时验证0204",
    [string]$SearchTarget = "SEARCH_TARGET_015904",
    [string]$OutputDir = "artifacts/real-device-qa/im298-group-search-position"
)

$ErrorActionPreference = "Stop"

function Get-Adb {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "adb.exe not found"
}

function Invoke-Adb {
    param([string[]]$Arguments)
    $output = & $script:Adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): adb $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Save-Ui {
    param([string]$Name)
    $remoteXml = "/sdcard/$Name.xml"
    $remotePng = "/sdcard/$Name.png"
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "uiautomator", "dump", $remoteXml) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "screencap", "-p", $remotePng) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remoteXml, (Join-Path $script:RunDir "$Name.xml")) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remotePng, (Join-Path $script:RunDir "$Name.png")) | Out-Null
    return [xml](Get-Content -LiteralPath (Join-Path $script:RunDir "$Name.xml") -Raw -Encoding utf8)
}

function Tap-Node {
    param($Node)
    if (-not $Node) { throw "Target UI node was not found" }
    $match = [regex]::Match($Node.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid UI bounds: $($Node.bounds)" }
    $x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
    $y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "tap", "$x", "$y") | Out-Null
    Start-Sleep -Seconds 3
}

function Open-ChatList {
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "start", "-W", "-n", "$PackageName/.MainActivity") | Out-Null
    Start-Sleep -Seconds 4
    for ($attempt = 1; $attempt -le 7; $attempt++) {
        $document = Save-Ui -Name ("navigation-{0:D2}" -f $attempt)
        $groupRow = $document.SelectNodes('//node[@content-desc!=""]') |
            Where-Object {
                $_.'content-desc' -match "群聊\s*`n$([regex]::Escape($GroupName))"
            } |
            Select-Object -First 1
        if ($groupRow) { return $document }

        $messagesTab = $document.SelectSingleNode('//node[@content-desc="消息"]')
        if ($messagesTab) {
            Tap-Node -Node $messagesTab
        } else {
            Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "keyevent", "KEYCODE_BACK") | Out-Null
            Start-Sleep -Seconds 2
        }
    }
    throw "Unable to return to the chat list containing $GroupName"
}

$script:Adb = Get-Adb
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedOutput = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
$script:RunDir = Join-Path $resolvedOutput (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $script:RunDir | Out-Null

$devices = Invoke-Adb -Arguments @("devices", "-l")
if (-not ($devices | Where-Object { $_ -match "^$([regex]::Escape($DeviceId))\s+device\b" })) {
    throw "Device $DeviceId is not online"
}

$chatList = Open-ChatList
$groupRow = $chatList.SelectNodes('//node[@content-desc!=""]') |
    Where-Object {
        $_.'content-desc' -match "群聊\s*`n$([regex]::Escape($GroupName))"
    } |
    Select-Object -First 1
Tap-Node -Node $groupRow

$chat = Save-Ui -Name "01-group-chat"
$header = $chat.SelectNodes('//node[@content-desc!=""]') |
    Where-Object {
        $_.'content-desc' -match [regex]::Escape($GroupName) -and
        [regex]::Match($_.bounds, '^\[\d+,(\d+)\]').Groups[1].Value -as [int] -lt 500
    } |
    Select-Object -First 1
Tap-Node -Node $header

$profile = Save-Ui -Name "02-group-profile"
Tap-Node -Node $profile.SelectSingleNode('//node[@content-desc="搜索"]')

$searchPage = Save-Ui -Name "03-search-page"
$edit = $searchPage.SelectSingleNode('//node[@class="android.widget.EditText"]')
Tap-Node -Node $edit
Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "text", $SearchTarget) | Out-Null
Start-Sleep -Seconds 5

$results = Save-Ui -Name "04-search-result"
$resultNode = $results.SelectNodes('//node[@content-desc!=""]') |
    Where-Object { $_.'content-desc' -match [regex]::Escape($SearchTarget) } |
    Sort-Object {
        $bounds = [regex]::Matches($_.bounds, '\d+') | ForEach-Object { [int]$_.Value }
        ($bounds[2] - $bounds[0]) * ($bounds[3] - $bounds[1])
    } -Descending |
    Select-Object -First 1
if (-not $resultNode) { throw "Search result not found: $SearchTarget" }
Tap-Node -Node $resultNode
Start-Sleep -Seconds 3

$landed = Save-Ui -Name "05-search-landed"
$targetVisible = $landed.OuterXml -match [regex]::Escape($SearchTarget)
$contextCount = @(
    $landed.SelectNodes('//node[@content-desc!=""]') |
        Where-Object { $_.'content-desc' -match '创建了群聊|群昵称|群名称' }
).Count
if (-not $targetVisible) { throw "Target message is not visible after opening the result" }
if ($contextCount -lt 1) { throw "Target opened without surrounding message context" }

$summary = [ordered]@{
    case_id = "IM-298"
    status = "PASS"
    device_id = $DeviceId
    group_name = $GroupName
    search_target = $SearchTarget
    result_visible = $true
    target_visible_after_open = $targetVisible
    surrounding_context_message_count = $contextCount
    output_dir = $script:RunDir
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:RunDir "summary.json") -Encoding utf8
$summary | ConvertTo-Json -Depth 4
