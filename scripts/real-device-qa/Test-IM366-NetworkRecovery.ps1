param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    [string]$PackageName = "com.genericim.ma100",
    [string]$OutputDir = "artifacts/real-device-qa/im366-network-recovery"
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

function Set-NetworkState {
    # Wi-Fi 与移动数据同时切换，确保测试阶段没有备用网络继续承载连接。
    param([bool]$WifiEnabled, [bool]$DataEnabled)
    $wifiAction = if ($WifiEnabled) { "enable" } else { "disable" }
    $dataAction = if ($DataEnabled) { "enable" } else { "disable" }
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "svc", "wifi", $wifiAction) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "svc", "data", $dataAction) | Out-Null
}

function Has-OfflineBanner {
    param([xml]$Document)
    $raw = $Document.OuterXml
    return ($raw -match '网络不可用|连接中断') -and ($raw -match '重试')
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

$wifiWasEnabled = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "settings", "get", "global", "wifi_on") | Select-Object -First 1).Trim() -eq "1"
$dataWasEnabled = (Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "settings", "get", "global", "mobile_data") | Select-Object -First 1).Trim() -eq "1"
# 上面记录设备原始网络状态，finally 中按原值恢复，避免测试污染后续真机用例。
$restored = $false
$recovered = $false

try {
    # 先建立在线基线，再制造断网并验证离线提示，最后恢复网络验证自动重连。
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "force-stop", $PackageName) | Out-Null
    Invoke-Adb -Arguments @("-s", $DeviceId, "shell", "am", "start", "-S", "-W", "-n", "$PackageName/.MainActivity") | Out-Null
    Start-Sleep -Seconds 10
    $online = Save-Ui -Name "01-online"
    if (Has-OfflineBanner -Document $online) {
        throw "Offline banner was already visible before network interruption"
    }

    Set-NetworkState -WifiEnabled $false -DataEnabled $false
    Start-Sleep -Seconds 8
    $offline = Save-Ui -Name "02-offline-banner"
    if (-not (Has-OfflineBanner -Document $offline)) {
        throw "Offline banner with retry action was not visible"
    }
} finally {
    Set-NetworkState -WifiEnabled $wifiWasEnabled -DataEnabled $dataWasEnabled
    $restored = $true
}

for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Seconds 3
    $probe = Save-Ui -Name ("03-recovery-probe-{0:D2}" -f $attempt)
    if (-not (Has-OfflineBanner -Document $probe)) {
        $recovered = $true
        break
    }
}

if (-not $recovered) {
    throw "Offline banner did not disappear after network restoration"
}

$summary = [ordered]@{
    case_id = "IM-366"
    status = "PASS"
    device_id = $DeviceId
    offline_banner_visible = $true
    retry_action_visible = $true
    original_wifi_enabled = $wifiWasEnabled
    original_mobile_data_enabled = $dataWasEnabled
    network_state_restored = $restored
    banner_disappeared_after_restore = $recovered
    output_dir = $script:RunDir
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:RunDir "summary.json") -Encoding utf8
$summary | ConvertTo-Json -Depth 4
