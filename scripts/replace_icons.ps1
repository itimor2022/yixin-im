<#
.SYNOPSIS
从单一源图生成并替换各平台应用图标。

.DESCRIPTION
按 Android、iOS、Web、Windows 和 macOS 的尺寸规则生成图标资源，并可调用
Flutter 图标流程。脚本会覆盖工程内现有图标文件；运行前应确认 Source 属于
当前品牌版本，并通过 Git 差异检查所有输出。

.PARAMETER Source
作为全部平台图标来源的 PNG 文件。

.PARAMETER SkipFlutter
只执行脚本内资源生成，不调用 Flutter 图标工具。

.EXAMPLE
pwsh -File scripts/replace_icons.ps1 -Source assets/logo.png
#>
[CmdletBinding()]
param(
    [string]$Source = "assets\logo.png",
    [switch]$SkipFlutter
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
Set-Location -LiteralPath $ProjectRoot

Add-Type -AssemblyName System.Drawing

function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $Path))
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
}

function Copy-IconFile {
    param(
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To
    )

    Ensure-ParentDirectory $To
    $fromFull = [System.IO.Path]::GetFullPath($From)
    $toFull = [System.IO.Path]::GetFullPath($To)
    if ([string]::Equals($fromFull, $toFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    Copy-Item -LiteralPath $From -Destination $To -Force
}

function Get-SquarePngBytes {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][int]$Size,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$Background
    )

    $sourceImage = [System.Drawing.Image]::FromFile($InputPath)
    try {
        $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.Clear($Background)

                $scale = [Math]::Min($Size / $sourceImage.Width, $Size / $sourceImage.Height)
                $width = [int][Math]::Round($sourceImage.Width * $scale)
                $height = [int][Math]::Round($sourceImage.Height * $scale)
                $x = [int][Math]::Floor(($Size - $width) / 2)
                $y = [int][Math]::Floor(($Size - $height) / 2)

                $graphics.DrawImage($sourceImage, $x, $y, $width, $height)
            }
            finally {
                $graphics.Dispose()
            }

            $stream = New-Object System.IO.MemoryStream
            try {
                $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
                return $stream.ToArray()
            }
            finally {
                $stream.Dispose()
            }
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $sourceImage.Dispose()
    }
}

function New-SquarePng {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$Size,
        [System.Drawing.Color]$Background = [System.Drawing.Color]::Transparent
    )

    Ensure-ParentDirectory $OutputPath
    $bytes = Get-SquarePngBytes -InputPath $InputPath -Size $Size -Background $Background
    [System.IO.File]::WriteAllBytes($OutputPath, $bytes)
}

function New-Ico {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [int[]]$Sizes = @(16, 32, 48, 64, 128, 256)
    )

    Ensure-ParentDirectory $OutputPath
    $entries = @()
    foreach ($size in $Sizes) {
        $entries += [pscustomobject]@{
            Size = $size
            Bytes = Get-SquarePngBytes -InputPath $InputPath -Size $size -Background ([System.Drawing.Color]::Transparent)
        }
    }

    $stream = [System.IO.File]::Create($OutputPath)
    try {
        $writer = New-Object System.IO.BinaryWriter $stream
        try {
            $writer.Write([UInt16]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]$entries.Count)

            $offset = 6 + (16 * $entries.Count)
            foreach ($entry in $entries) {
                $dimensionByte = if ($entry.Size -ge 256) { 0 } else { $entry.Size }
                $writer.Write([byte]$dimensionByte)
                $writer.Write([byte]$dimensionByte)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([UInt16]1)
                $writer.Write([UInt16]32)
                $writer.Write([UInt32]$entry.Bytes.Length)
                $writer.Write([UInt32]$offset)
                $offset += $entry.Bytes.Length
            }

            foreach ($entry in $entries) {
                $writer.Write([byte[]]$entry.Bytes)
            }
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-IconPixelSize {
    param([Parameter(Mandatory = $true)]$ImageEntry)

    $baseSize = [decimal](([string]$ImageEntry.size -split "x")[0])
    $scaleText = [string]$ImageEntry.scale
    $scale = [decimal]1
    if ($scaleText -match "^([0-9.]+)x$") {
        $scale = [decimal]$Matches[1]
    }

    return [int][Math]::Round([double]($baseSize * $scale))
}

function New-IconsFromContentsJson {
    param(
        [Parameter(Mandatory = $true)][string]$ContentsPath,
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $ContentsPath)) {
        return
    }

    $contents = Get-Content -Raw -LiteralPath $ContentsPath | ConvertFrom-Json
    foreach ($image in $contents.images) {
        if (-not $image.filename) {
            continue
        }

        $pixels = Get-IconPixelSize $image
        New-SquarePng -InputPath $InputPath -OutputPath (Join-Path $OutputRoot $image.filename) -Size $pixels -Background ([System.Drawing.Color]::White)
    }
}

function Copy-LauncherResources {
    param(
        [Parameter(Mandatory = $true)][string]$FromRoot,
        [Parameter(Mandatory = $true)][string]$ToRoot
    )

    if (-not (Test-Path -LiteralPath $FromRoot)) {
        return
    }

    Get-ChildItem -LiteralPath $FromRoot -Recurse -File |
        Where-Object { $_.Name -like "ic_launcher*" } |
        ForEach-Object {
            $relative = $_.FullName.Substring($FromRoot.Length).TrimStart("\", "/")
            Copy-IconFile -From $_.FullName -To (Join-Path $ToRoot $relative)
        }
}

function Get-BackupIconRoot {
    $assetsRoot = Join-Path $ProjectRoot "assets"
    if (-not (Test-Path -LiteralPath $assetsRoot)) {
        return $null
    }

    $roots = @(
        Get-ChildItem -LiteralPath $assetsRoot -Directory |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName "android")) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName "ios")) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName "web"))
            }
    )

    if ($roots.Count -eq 0) {
        return $null
    }

    return $roots[0].FullName
}

$sourcePath = Resolve-ProjectPath $Source
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Source icon not found: $sourcePath"
}

$assetLogo = Join-Path $ProjectRoot "assets\logo.png"
Copy-IconFile -From $sourcePath -To $assetLogo

Write-Host "[1/5] Source icon: $sourcePath"

if (-not $SkipFlutter) {
    Write-Host "[2/5] Running flutter_launcher_icons..."
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }

    & flutter pub run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) {
        throw "flutter_launcher_icons failed with exit code $LASTEXITCODE"
    }
}
else {
    Write-Host "[2/5] Skipped flutter_launcher_icons."
}

Write-Host "[3/5] Updating Flutter Web icons..."
New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "web\favicon.png") -Size 32
New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "web\icons\Icon-192.png") -Size 192
New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "web\icons\Icon-512.png") -Size 512
New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "web\icons\Icon-maskable-192.png") -Size 192
New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "web\icons\Icon-maskable-512.png") -Size 512

Write-Host "[4/5] Updating backup icon folders..."
$backupIconRoot = Get-BackupIconRoot
if ($null -eq $backupIconRoot) {
    Write-Warning "No backup icon root with android/ios/web folders was found under assets; skipped backup icons."
}
else {
    $backupWebRoot = Join-Path $backupIconRoot "web"
    New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $backupWebRoot "icon-192.png") -Size 192
    New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $backupWebRoot "icon-192-maskable.png") -Size 192
    New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $backupWebRoot "icon-512.png") -Size 512
    New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $backupWebRoot "icon-512-maskable.png") -Size 512
    New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $backupWebRoot "apple-touch-icon.png") -Size 180
    New-Ico -InputPath $assetLogo -OutputPath (Join-Path $backupWebRoot "favicon.ico")

    New-SquarePng -InputPath $assetLogo -OutputPath (Join-Path $backupIconRoot "android\play_store_512.png") -Size 512
    Copy-LauncherResources -FromRoot (Join-Path $ProjectRoot "android\app\src\main\res") -ToRoot (Join-Path $backupIconRoot "android\res")
    New-IconsFromContentsJson -ContentsPath (Join-Path $backupIconRoot "ios\Contents.json") -OutputRoot (Join-Path $backupIconRoot "ios") -InputPath $assetLogo
}

Write-Host "[5/5] Updating admin branding..."
if (Test-Path -LiteralPath (Join-Path $ProjectRoot "admin\public")) {
    New-Ico -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "admin\public\favicon.ico")
}
if (Test-Path -LiteralPath (Join-Path $ProjectRoot "admin\src\assets\images")) {
    New-Ico -InputPath $assetLogo -OutputPath (Join-Path $ProjectRoot "admin\src\assets\images\favicon.ico")
}
if (Test-Path -LiteralPath (Join-Path $ProjectRoot "admin\src\assets\images\common")) {
    Copy-IconFile -From $assetLogo -To (Join-Path $ProjectRoot "admin\src\assets\images\common\logo.png")
}

Write-Host ""
Write-Host "Done. Updated Android, iOS, macOS, Windows, Flutter Web, H5, admin branding, and assets backup icons."
