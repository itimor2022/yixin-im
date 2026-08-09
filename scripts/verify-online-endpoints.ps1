#Requires -Version 7.0
<#
.SYNOPSIS
检查 APK 或 Web 产物是否固化了预期的线上服务地址。

.DESCRIPTION
从 APK 的 libapp.so 或 Web 产物中搜索 REST、WebSocket 和 Bootstrap
地址，防止把 localhost、10.0.2.2 等开发地址带入线上包。该检查只读取
产物，不会修改 APK、Web 目录或服务端配置。

.PARAMETER Path
待检查的 APK 文件或 Flutter Web 产物目录。

.PARAMETER ServerUrl
产物必须包含的 REST 服务地址。

.PARAMETER WsUrl
产物必须包含的 WebSocket 地址。

.PARAMETER BootstrapUrl
产物必须包含的客户端 Bootstrap 地址。

.PARAMETER AllowLoopback
显式允许回环或模拟器地址，仅用于本地测试产物。

.EXAMPLE
pwsh -File scripts/verify-online-endpoints.ps1 -Path build/app/outputs/flutter-apk/app-release.apk -ServerUrl https://api.example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$BootstrapUrl = "https://api.example.com/api/v1/client/bootstrap",
    [switch]$AllowLoopback
)

$ErrorActionPreference = "Stop"

function Read-ApkAppBytes {
    # Dart AOT 字符串位于 ABI 对应的 libapp.so，检查 APK 时无需解包到磁盘。
    param([Parameter(Mandatory = $true)][string]$ArtifactPath)

    $resolved = Resolve-Path -LiteralPath $ArtifactPath
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved.Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq "lib/arm64-v8a/libapp.so" } | Select-Object -First 1
        if ($null -eq $entry) {
            throw "APK does not contain lib/arm64-v8a/libapp.so"
        }
        $stream = $entry.Open()
        try {
            $memory = [System.IO.MemoryStream]::new()
            $stream.CopyTo($memory)
            return $memory.ToArray()
        }
        finally {
            $stream.Dispose()
            if ($memory) { $memory.Dispose() }
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Test-BytesContainAscii {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Needle
    )
    $text = [System.Text.Encoding]::ASCII.GetString($Bytes)
    return $text.Contains($Needle)
}

function Test-FileContainsAscii {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Needle
    )
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -eq 0) {
        return $false
    }
    return Test-BytesContainAscii -Bytes $bytes -Needle $Needle
}

function Test-ArtifactContainsAscii {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$Needle
    )

    $resolved = Resolve-Path -LiteralPath $ArtifactPath
    $item = Get-Item -LiteralPath $resolved.Path
    if ($item.PSIsContainer) {
        foreach ($file in Get-ChildItem -LiteralPath $item.FullName -Recurse -File) {
            if (Test-FileContainsAscii -FilePath $file.FullName -Needle $Needle) {
                return $true
            }
        }
        return $false
    }

    $extension = [System.IO.Path]::GetExtension($resolved.Path).ToLowerInvariant()
    if ($extension -eq ".apk") {
        $bytes = Read-ApkAppBytes -ArtifactPath $resolved.Path
        return Test-BytesContainAscii -Bytes $bytes -Needle $Needle
    }

    return Test-FileContainsAscii -FilePath $resolved.Path -Needle $Needle
}

$required = @($ServerUrl, $WsUrl, $BootstrapUrl) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$missing = @($required | Where-Object { -not (Test-ArtifactContainsAscii -ArtifactPath $Path -Needle $_) })
if ($missing.Count -gt 0) {
    throw "Artifact is missing expected online endpoint(s): $($missing -join ', ')"
}

$loopbacks = @("10.0.2.2", "127.0.0.1", "localhost")
if (-not $AllowLoopback) {
    $foundLoopbacks = @($loopbacks | Where-Object { Test-ArtifactContainsAscii -ArtifactPath $Path -Needle $_ })
    if ($foundLoopbacks.Count -gt 0) {
        throw "Artifact still contains loopback/local endpoint(s): $($foundLoopbacks -join ', ')"
    }
}

Write-Host "Endpoint verification passed: $Path"
foreach ($item in $required) {
    Write-Host "  contains: $item"
}
