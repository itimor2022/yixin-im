#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ApkPath = "build/app/outputs/flutter-apk/app-release.apk",
    [int]$Top = 40
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$resolvedApk = Resolve-Path (Join-Path $repoRoot $ApkPath)
$apkFile = Get-Item -LiteralPath $resolvedApk

# APK 本质上是 ZIP 容器，直接读取中央目录即可统计，无需先解压到磁盘。
Add-Type -AssemblyName System.IO.Compression.FileSystem

Write-Host "APK: $($apkFile.FullName)"
Write-Host ("Total: {0:N2} MB ({1:N0} bytes)" -f ($apkFile.Length / 1MB), $apkFile.Length)
Write-Host ""

$zip = [System.IO.Compression.ZipFile]::OpenRead($apkFile.FullName)
try {
    # 顶层目录汇总用于判断体积主要来自 native 库、资源还是 Dart/Java 代码。
    Write-Host "Top-level groups:"
    $zip.Entries |
        Group-Object { ($_.FullName -split "/")[0] } |
        ForEach-Object {
            [pscustomobject]@{
                Group = $_.Name
                Count = $_.Count
                MB = [math]::Round((($_.Group | Measure-Object Length -Sum).Sum) / 1MB, 2)
                CompressedMB = [math]::Round((($_.Group | Measure-Object CompressedLength -Sum).Sum) / 1MB, 2)
            }
        } |
        Sort-Object CompressedMB -Descending |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Largest files:"
    # 以压缩后大小排序更接近 APK 下载体积，原始大小仅作为解压占用参考。
    $zip.Entries |
        Where-Object { -not $_.FullName.EndsWith("/") } |
        Sort-Object CompressedLength -Descending |
        Select-Object -First $Top `
            @{n = "CompressedMB"; e = { [math]::Round($_.CompressedLength / 1MB, 2) } },
            @{n = "MB"; e = { [math]::Round($_.Length / 1MB, 2) } },
            FullName |
        Format-Table -AutoSize
} finally {
    # ZipArchive 持有 APK 文件句柄，必须释放后才能覆盖或删除构建产物。
    $zip.Dispose()
}
