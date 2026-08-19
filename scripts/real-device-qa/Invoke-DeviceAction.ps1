param(
    [string]$Serial = "",
    [string]$PackageName = "com.genericim.ma100",
    [string]$Adb = "",
    [string]$VenvPath = "",
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$DriverArguments
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "QaCommon.ps1")

$repoRoot = Get-QaRepositoryRoot
if ([string]::IsNullOrWhiteSpace($VenvPath)) { $VenvPath = Join-Path $repoRoot ".tools\real-device-qa" }
$adbPath = Resolve-QaAdbPath -Adb $Adb
$device = Select-QaDevice -Devices @(Get-QaDevices -Adb $adbPath) -Serial $Serial
$python = Resolve-QaPythonPath -VenvPath $VenvPath
$driver = Join-Path $PSScriptRoot "device_driver.py"

if ($null -eq $DriverArguments -or $DriverArguments.Count -eq 0) {
    $DriverArguments = @("probe")
}
$arguments = @($driver, "--serial", $device.Serial, "--package", $PackageName) + @($DriverArguments)
$result = Invoke-QaProcess -FilePath $python -Arguments $arguments -TimeoutSeconds 180
if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) { Write-Host $result.StdOut.TrimEnd() }
if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) { Write-Error $result.StdErr.TrimEnd() }
exit $result.ExitCode
