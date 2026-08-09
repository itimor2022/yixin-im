param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.app",
    [string]$OutputDir = "artifacts/real-device-qa/im379-background-restriction"
)

$ErrorActionPreference = "Stop"

# 优先复用 PATH 中的 adb，缺失时回退到 Android SDK 的标准安装位置。
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
    # XML 用于断言，PNG 用于人工复核；两类证据以相同名称成对保存。
    param([string]$Name)
    $remoteXml = "/sdcard/$Name.xml"
    $remotePng = "/sdcard/$Name.png"
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "uiautomator", "dump", $remoteXml) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "screencap", "-p", $remotePng) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remoteXml, (Join-Path $script:RunDir "$Name.xml")) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "pull", $remotePng, (Join-Path $script:RunDir "$Name.png")) | Out-Null
    return [xml](Get-Content -LiteralPath (Join-Path $script:RunDir "$Name.xml") -Raw -Encoding utf8)
}

function Tap-Description {
    # 通过 content-desc 定位控件，使用例不依赖绝对坐标和设备分辨率。
    param([string]$Description, [string]$EvidenceName)
    $document = Save-Ui -Name $EvidenceName
    $node = $document.SelectSingleNode("//node[@content-desc='$Description']")
    if (-not $node) { throw "App node not found: $Description" }
    $match = [regex]::Match($node.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid node bounds: $($node.bounds)" }
    $x = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
    $y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "input", "tap", "$x", "$y") | Out-Null
    Start-Sleep -Seconds 2
}

$script:Adb = Get-Adb
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedOutput = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
$script:RunDir = Join-Path $resolvedOutput (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $script:RunDir | Out-Null

$devices = Invoke-Adb -Arguments @("devices", "-l")
# 在产生任何设备状态变化前确认目标序列号确实在线。
if (-not ($devices | Where-Object { $_ -match "^$([regex]::Escape($DeviceId))\s+device\b" })) {
    throw "Device $DeviceId is not online"
}

Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "force-stop", $PackageName) | Out-Null
Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "start", "-S", "-W", "-n", "$PackageName/.MainActivity") | Out-Null
Start-Sleep -Seconds 8
Tap-Description -Description "设置" -EvidenceName "01-home"
Tap-Description -Description "通知和声音" -EvidenceName "02-settings"
Start-Sleep -Seconds 4
$page = Save-Ui -Name "03-background-restriction-warning"
$raw = $page.OuterXml

$hasEntry = $raw -match '打开电池设置'
$hasWarning = $raw -match '已检测到后台/电池限制，点击处理'
if (-not $hasEntry) { throw "Battery settings entry is not visible" }
if (-not $hasWarning) { throw "Background or battery restriction warning is not visible" }

Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "dumpsys", "deviceidle") |
    Set-Content -LiteralPath (Join-Path $script:RunDir "04-deviceidle.txt") -Encoding utf8
Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "cmd", "appops", "get", $PackageName) |
    Set-Content -LiteralPath (Join-Path $script:RunDir "05-appops.txt") -Encoding utf8

$summary = [ordered]@{
    case_id = "IM-379"
    status = "PASS"
    device_id = $DeviceId
    battery_settings_entry_visible = $hasEntry
    actual_background_or_battery_restriction_warning_visible = $hasWarning
    output_dir = $script:RunDir
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:RunDir "summary.json") -Encoding utf8
$summary | ConvertTo-Json -Depth 4
