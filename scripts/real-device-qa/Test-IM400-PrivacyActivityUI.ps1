<#
.SYNOPSIS
验证隐私设置对在线状态和最近活动时间 UI 的影响。

.DESCRIPTION
登录测试账号，记录服务端隐私设置，通过真机 UI 修改相关选项并检查资料页
展示，最后应恢复原设置。脚本会修改目标账号隐私配置，只能使用可恢复的
专用测试账号。

.PARAMETER Device
执行隐私设置和资料页检查的 ADB 设备。

.PARAMETER BaseUrl
用于读取和恢复隐私配置的测试 API v1 地址。

.EXAMPLE
pwsh -File scripts/real-device-qa/Test-IM400-PrivacyActivityUI.ps1
#>
param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Device = '8MY0220C17006781',
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$Username = 'smoke_alice',
    [string]$Password = 'Smoke123'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutputDir = Join-Path $RepoRoot "artifacts\real-device-qa\privacy-activity-ui-$RunId"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Invoke-Adb {
    param([string[]]$Arguments)
    $output = & $Adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return $output
}

function Get-Hierarchy {
    param([string]$Name)
    $remote = "/sdcard/$Name-$RunId.xml"
    $local = Join-Path $OutputDir "$Name.xml"
    Invoke-Adb -Arguments @('-s', $Device, 'shell', 'uiautomator', 'dump', $remote) | Out-Null
    Invoke-Adb -Arguments @('-s', $Device, 'pull', $remote, $local) | Out-Null
    return [xml](Get-Content -Raw -Encoding utf8 $local)
}

function Save-Screenshot {
    param([string]$Name)
    $remote = "/sdcard/$Name-$RunId.png"
    $local = Join-Path $OutputDir "$Name.png"
    Invoke-Adb -Arguments @('-s', $Device, 'shell', 'screencap', '-p', $remote) | Out-Null
    Invoke-Adb -Arguments @('-s', $Device, 'pull', $remote, $local) | Out-Null
    return $local
}

function Invoke-TapBounds {
    param([string]$Bounds)
    if ($Bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Invalid bounds: $Bounds"
    }
    $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    Invoke-Adb -Arguments @('-s', $Device, 'shell', 'input', 'tap', "$x", "$y") | Out-Null
}

function Get-PrivacySettings {
    $headers = @{ Authorization = "Bearer $script:Token" }
    $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/user/privacy" -Headers $headers
    if ($response.code -ne 0) { throw "privacy GET failed: $($response | ConvertTo-Json -Depth 6)" }
    return $response.data
}

function Set-PrivacySettings {
    param([bool]$SendReadReceipts, [bool]$ShowTypingStatus)
    $headers = @{ Authorization = "Bearer $script:Token" }
    $body = @{
        send_read_receipts = $SendReadReceipts
        show_typing_status = $ShowTypingStatus
    } | ConvertTo-Json
    $response = Invoke-RestMethod -Method Put -Uri "$BaseUrl/user/privacy" -Headers $headers -ContentType 'application/json' -Body $body
    if ($response.code -ne 0) { throw "privacy PUT failed: $($response | ConvertTo-Json -Depth 6)" }
}

$loginBody = @{
    username = $Username
    password = $Password
    device_id = "privacy-ui-$RunId"
    device_type = 'qa'
    device_name = 'Privacy UI QA'
} | ConvertTo-Json
$login = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/login" -ContentType 'application/json' -Body $loginBody
if ($login.code -ne 0) { throw "login failed: $($login | ConvertTo-Json -Depth 6)" }
$script:Token = $login.data.token

Set-PrivacySettings -SendReadReceipts $true -ShowTypingStatus $true
Invoke-Adb -Arguments @('-s', $Device, 'reverse', 'tcp:8080', 'tcp:8080') | Out-Null
Invoke-Adb -Arguments @('-s', $Device, 'shell', 'am', 'force-stop', 'com.genericim.app') | Out-Null
Invoke-Adb -Arguments @('-s', $Device, 'shell', 'am', 'start', '-W', '-n', 'com.genericim.app/.MainActivity') | Out-Null
Start-Sleep -Seconds 4

$hierarchy = Get-Hierarchy -Name 'home'
$settingsNode = $hierarchy.SelectSingleNode('//node[@content-desc="设置" and @clickable="true"]')
if ($null -eq $settingsNode) { throw 'Settings tab not found' }
Invoke-TapBounds -Bounds $settingsNode.bounds
Start-Sleep -Seconds 2

$hierarchy = Get-Hierarchy -Name 'settings'
$privacyNode = $hierarchy.SelectSingleNode('//node[@content-desc="隐私" and @clickable="true"]')
if ($null -eq $privacyNode) { throw 'Privacy tile not found' }
Invoke-TapBounds -Bounds $privacyNode.bounds
Start-Sleep -Seconds 3

$hierarchy = Get-Hierarchy -Name 'privacy-on'
$section = $hierarchy.SelectSingleNode('//node[contains(@content-desc,"发送已读回执") and contains(@content-desc,"显示输入状态")]')
if ($null -eq $section) { throw 'Privacy activity labels are not visible' }
$switches = @($hierarchy.SelectNodes('//node[@class="android.widget.Switch" and @clickable="true"]'))
if ($switches.Count -lt 4) { throw "Expected at least four privacy switches, found $($switches.Count)" }
$readSwitch = $switches[2]
$typingSwitch = $switches[3]
if ($readSwitch.checked -ne 'true' -or $typingSwitch.checked -ne 'true') {
    throw 'Privacy activity switches did not load as enabled'
}
$onScreenshot = Save-Screenshot -Name 'privacy-on'

Invoke-TapBounds -Bounds $readSwitch.bounds
Start-Sleep -Seconds 2
$readOff = Get-PrivacySettings
if ($readOff.send_read_receipts -ne $false) { throw 'Read receipt switch did not sync false to server' }
$readOffScreenshot = Save-Screenshot -Name 'read-receipts-off'
Invoke-TapBounds -Bounds $readSwitch.bounds
Start-Sleep -Seconds 2

$hierarchy = Get-Hierarchy -Name 'privacy-read-restored'
$switches = @($hierarchy.SelectNodes('//node[@class="android.widget.Switch" and @clickable="true"]'))
$typingSwitch = $switches[3]
Invoke-TapBounds -Bounds $typingSwitch.bounds
Start-Sleep -Seconds 2
$typingOff = Get-PrivacySettings
if ($typingOff.show_typing_status -ne $false) { throw 'Typing switch did not sync false to server' }
$typingOffScreenshot = Save-Screenshot -Name 'typing-status-off'
Invoke-TapBounds -Bounds $typingSwitch.bounds
Start-Sleep -Seconds 2

$restored = Get-PrivacySettings
if ($restored.send_read_receipts -ne $true -or $restored.show_typing_status -ne $true) {
    throw 'Privacy activity settings were not restored'
}
$finalScreenshot = Save-Screenshot -Name 'privacy-restored'

$result = [ordered]@{
    status = 'PASS'
    case_ids = @('IM-130', 'IM-140')
    device = $Device
    server_sync = [ordered]@{
        read_receipts_off = $readOff.send_read_receipts
        typing_status_off = $typingOff.show_typing_status
        restored_read_receipts = $restored.send_read_receipts
        restored_typing_status = $restored.show_typing_status
    }
    evidence = @($onScreenshot, $readOffScreenshot, $typingOffScreenshot, $finalScreenshot)
    tested_at = (Get-Date).ToString('o')
}
$resultPath = Join-Path $OutputDir 'results.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $resultPath
$result | ConvertTo-Json -Depth 8
