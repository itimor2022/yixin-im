#Requires -Version 7.0
<#
.SYNOPSIS
临时移除品牌图标并构建客户无品牌 Android 测试 APK。

.DESCRIPTION
备份当前 Logo、颜色和 Android 图标，写入中性占位资源后调用线上 APK 构建，
最后把原资源恢复并复制测试产物。脚本中断可能留下临时资源或备份目录；
交付前必须检查 Git 状态确认品牌文件已完整恢复。

.PARAMETER ServerUrl
写入测试 APK 的 REST 服务地址。

.PARAMETER OutputRoot
最终无品牌 APK 和构建说明的输出目录。

.EXAMPLE
pwsh -File scripts/build-customer-unbranded-test-apk.ps1
#>
[CmdletBinding()]
param(
    [string]$ServerUrl = "https://api.example.com",
    [string]$WsUrl = "wss://api.example.com/api/v1/ws",
    [string]$PublicH5Url = "https://h5.example.com",
    [string]$OutputRoot = "artifacts"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$buildRoot = Join-Path $repoRoot "build"
$backupRoot = Join-Path $buildRoot ("unbranded-apk-backup-" + [guid]::NewGuid().ToString("N"))
$logoPath = Join-Path $repoRoot "assets\logo.png"
$colorsPath = Join-Path $repoRoot "android\app\src\main\res\values\colors.xml"
$callkitLogoOverride = Join-Path $repoRoot "android\app\src\main\res\drawable-xxxhdpi\ic_logo.png"
$callkitLogoExisted = Test-Path -LiteralPath $callkitLogoOverride -PathType Leaf
$iconFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "android\app\src\main\res") -Recurse -File |
    Where-Object { $_.Name -like "ic_launcher*.png" })
$sourceFiles = @($logoPath, $colorsPath) + @($iconFiles.FullName)
if ($callkitLogoExisted) {
    $sourceFiles += $callkitLogoOverride
}
$sourceRootWithSeparator = $repoRoot.TrimEnd('\') + '\'
$backupRootWithSeparator = $backupRoot.TrimEnd('\') + '\'
$onlineArtifactBefore = @()
$builtOnlineApk = $null
$finalApk = $null

function Save-SolidPng {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$Color
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear($Color)
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Backup-SourceFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not $Path.StartsWith($sourceRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to back up a file outside the repository: $Path"
    }
    $relative = $Path.Substring($sourceRootWithSeparator.Length)
    $backup = Join-Path $backupRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $backup -Force
}

function Restore-SourceFiles {
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) { return }
    Get-ChildItem -LiteralPath $backupRoot -Recurse -File | ForEach-Object {
        if (-not $_.FullName.StartsWith($backupRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected backup path: $($_.FullName)"
        }
        $relative = $_.FullName.Substring($backupRootWithSeparator.Length)
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $repoRoot $relative) -Force
    }
}

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
foreach ($sourceFile in $sourceFiles) {
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required branding source is missing: $sourceFile"
    }
    Backup-SourceFile -Path $sourceFile
}

try {
    # Keep the Flutter asset path valid while ensuring no artwork remains in it.
    Save-SolidPng -Path $logoPath -Width 64 -Height 64 -Color ([System.Drawing.Color]::Transparent)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $callkitLogoOverride) | Out-Null
    Save-SolidPng -Path $callkitLogoOverride -Width 150 -Height 50 -Color ([System.Drawing.Color]::Transparent)

    foreach ($icon in $iconFiles) {
        $image = [System.Drawing.Image]::FromFile($icon.FullName)
        try {
            $width = $image.Width
            $height = $image.Height
        }
        finally {
            $image.Dispose()
        }

        $color = if ($icon.Name -eq "ic_launcher.png" -or $icon.Name -like "*background*") {
            [System.Drawing.ColorTranslator]::FromHtml("#607D8B")
        }
        else {
            [System.Drawing.Color]::Transparent
        }
        Save-SolidPng -Path $icon.FullName -Width $width -Height $height -Color $color
    }

    $colors = [System.IO.File]::ReadAllText($colorsPath, [System.Text.Encoding]::UTF8)
    $colors = [regex]::Replace(
        $colors,
        '(<color\s+name="ic_launcher_background">)#[0-9A-Fa-f]{6,8}(</color>)',
        '${1}#607D8B${2}'
    )
    [System.IO.File]::WriteAllText($colorsPath, $colors, [System.Text.UTF8Encoding]::new($false))

    $onlineArtifactRoot = Join-Path $repoRoot "artifacts"
    if (Test-Path -LiteralPath $onlineArtifactRoot) {
        $onlineArtifactBefore = @(Get-ChildItem -LiteralPath $onlineArtifactRoot -Directory -Filter "online-android-apk-*" |
            Select-Object -ExpandProperty FullName)
    }

    & (Join-Path $PSScriptRoot "build-online-android-apk.ps1") `
        -ServerUrl $ServerUrl `
        -WsUrl $WsUrl `
        -PublicH5Url $PublicH5Url `
        -DisableReleaseShrink `
        -DisableSplashImage
    if ($LASTEXITCODE -ne 0) {
        throw "Unbranded customer test APK build failed with exit code $LASTEXITCODE"
    }

    $onlineArtifact = Get-ChildItem -LiteralPath $onlineArtifactRoot -Directory -Filter "online-android-apk-*" |
        Where-Object { $onlineArtifactBefore -notcontains $_.FullName } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $onlineArtifact) {
        throw "The online Android build did not create a new artifact directory"
    }
    $builtOnlineApk = Join-Path $onlineArtifact.FullName "genericim-online-release.apk"
    if (-not (Test-Path -LiteralPath $builtOnlineApk -PathType Leaf)) {
        throw "Built APK was not found: $builtOnlineApk"
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $finalDir = Join-Path $repoRoot (Join-Path $OutputRoot "customer-android-test-no-logo-$stamp")
    New-Item -ItemType Directory -Force -Path $finalDir | Out-Null
    $finalApk = Join-Path $finalDir "GenericIM-customer-test-no-logo.apk"
    Copy-Item -LiteralPath $builtOnlineApk -Destination $finalApk -Force
}
finally {
    Restore-SourceFiles
    if (-not $callkitLogoExisted -and (Test-Path -LiteralPath $callkitLogoOverride -PathType Leaf)) {
        Remove-Item -LiteralPath $callkitLogoOverride -Force
    }
    if (Test-Path -LiteralPath $backupRoot -PathType Container) {
        $resolvedBackup = (Resolve-Path -LiteralPath $backupRoot).Path
        $resolvedBuild = (Resolve-Path -LiteralPath $buildRoot).Path.TrimEnd('\') + '\'
        if (-not $resolvedBackup.StartsWith($resolvedBuild, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to delete a backup outside the build directory: $resolvedBackup"
        }
        Remove-Item -LiteralPath $resolvedBackup -Recurse -Force
    }
}

if ([string]::IsNullOrWhiteSpace($finalApk) -or -not (Test-Path -LiteralPath $finalApk -PathType Leaf)) {
    throw "Final unbranded APK was not created"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $finalApk).Hash
Write-Host "[OK] Customer no-logo test APK created"
Write-Host "  APK:       $finalApk"
Write-Host "  Server:    $ServerUrl"
Write-Host "  WebSocket: $WsUrl"
Write-Host "  H5:        $PublicH5Url"
Write-Host "  SHA256:    $hash"
