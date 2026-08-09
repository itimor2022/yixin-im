param(
    [string]$Adb = '$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe',
    [string]$Device = 'emulator-5554',
    [string]$BaseUrl = 'http://127.0.0.1:8080/api/v1',
    [string]$OutputDir = 'artifacts/real-device-qa/registration-sms-ui'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
# 参数以数组传递，避免设备路径或输出目录中的空格被 PowerShell 重新拆分。
$Arguments = @(
    'scripts/real-device-qa/run_im400_registration_sms_ui.py',
    '--adb', $Adb,
    '--device', $Device,
    '--base-url', $BaseUrl,
    '--output-dir', $OutputDir
)

# Python 用例使用仓库相对路径，临时切换目录并保证异常时也恢复调用方位置。
Push-Location $RepoRoot
try {
    python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Registration SMS UI validation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
