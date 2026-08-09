<#
真机 QA 脚本的公共函数库。

本文件通过 dot-source 加载，不应直接执行。它统一负责仓库路径、ADB 解析、
子进程超时、设备选择和命令结果结构；调用方必须检查 ExitCode，超时统一返回
124。公共函数不得隐式选择多台在线设备中的任意一台。
#>
Set-StrictMode -Version Latest

function Get-QaRepositoryRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-QaAdbPath {
    param([string]$Adb = "")

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Adb)) { $candidates.Add($Adb) }
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { $candidates.Add($command.Source) }
    if ($env:ANDROID_SDK_ROOT) { $candidates.Add((Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe")) }
    if ($env:ANDROID_HOME) { $candidates.Add((Join-Path $env:ANDROID_HOME "platform-tools\adb.exe")) }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe")) }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "adb not found. Pass -Adb or install Android SDK platform-tools."
}

function Invoke-QaProcess {
    # 同时异步读取 stdout/stderr，避免子进程输出缓冲区写满后互相等待。
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $Arguments) { [void]$psi.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch {}
        return [pscustomobject]@{
            ExitCode = 124
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = "timeout after ${TimeoutSeconds}s`n$($stderrTask.GetAwaiter().GetResult())"
        }
    }
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdoutTask.GetAwaiter().GetResult()
        StdErr = $stderrTask.GetAwaiter().GetResult()
    }
}

function Invoke-QaAdb {
    param(
        [Parameter(Mandatory)][string]$Adb,
        [string]$Serial = "",
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30
    )

    $allArguments = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $allArguments.Add("-s")
        $allArguments.Add($Serial)
    }
    foreach ($argument in $Arguments) { $allArguments.Add($argument) }
    return Invoke-QaProcess -FilePath $Adb -Arguments $allArguments.ToArray() -TimeoutSeconds $TimeoutSeconds
}

function Get-QaDevices {
    param([Parameter(Mandatory)][string]$Adb)

    $result = Invoke-QaAdb -Adb $Adb -Arguments @("devices", "-l")
    if ($result.ExitCode -ne 0) { throw "adb devices failed: $($result.StdErr)" }
    $devices = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($result.StdOut -split "`r?`n")) {
        if ($line -match "^(?<serial>\S+)\s+(?<state>device|offline|unauthorized|recovery|sideload)(?:\s+(?<detail>.*))?$") {
            $devices.Add([pscustomobject]@{
                Serial = $Matches.serial
                State = $Matches.state
                Detail = [string]$Matches.detail
            })
        }
    }
    return @($devices)
}

function Select-QaDevice {
    param(
        [Parameter(Mandatory)][object[]]$Devices,
        [string]$Serial = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $match = @($Devices | Where-Object Serial -eq $Serial)
        if ($match.Count -eq 0) { throw "device '$Serial' is not listed by adb" }
        if ($match[0].State -ne "device") { throw "device '$Serial' state is '$($match[0].State)'" }
        return $match[0]
    }

    $online = @($Devices | Where-Object State -eq "device")
    if ($online.Count -eq 0) { throw "no authorized online Android device found" }
    if ($online.Count -gt 1) { throw "multiple online devices found; pass -Serial explicitly" }
    return $online[0]
}

function Resolve-QaPythonPath {
    param([Parameter(Mandatory)][string]$VenvPath)
    $python = Join-Path $VenvPath "Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw "QA Python environment is missing: $python. Run Initialize-RealDeviceQa.ps1 first."
    }
    return (Resolve-Path -LiteralPath $python).Path
}
