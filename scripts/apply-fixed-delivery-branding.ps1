<#
.SYNOPSIS
把固定交付品牌资源应用到 Flutter 及各原生平台工程。

.DESCRIPTION
读取仓库品牌源图并生成不同尺寸的 Android、iOS、Web 和桌面图标。
脚本会直接覆盖工程内现有品牌图片，属于批量资源写入操作；运行前应确认
当前客户版本确实使用固定交付品牌，并保留可审查的 Git 差异。

.EXAMPLE
pwsh -File scripts/apply-fixed-delivery-branding.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
Set-Location -LiteralPath $ProjectRoot

Add-Type -AssemblyName System.Drawing

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
}

function Get-LogoContentBounds {
    # 忽略透明和近白背景，按实际图形边界居中缩放，避免不同源图产生视觉偏移。
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [int]$WhiteThreshold = 248,
        [int]$AlphaThreshold = 8
    )

    $minX = $Bitmap.Width
    $minY = $Bitmap.Height
    $maxX = -1
    $maxY = -1

    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            $pixel = $Bitmap.GetPixel($x, $y)
            if ($pixel.A -le $AlphaThreshold) {
                continue
            }

            $isNearWhite =
                $pixel.R -ge $WhiteThreshold -and
                $pixel.G -ge $WhiteThreshold -and
                $pixel.B -ge $WhiteThreshold
            if ($isNearWhite) {
                continue
            }

            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }

    if ($maxX -lt $minX -or $maxY -lt $minY) {
        return [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    }

    return [System.Drawing.Rectangle]::new(
        $minX,
        $minY,
        ($maxX - $minX + 1),
        ($maxY - $minY + 1)
    )
}

function Save-CoverPng {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    Ensure-ParentDirectory $OutputPath
    $source = [System.Drawing.Bitmap]::new($InputPath)
    try {
        $sourceRect = Get-LogoContentBounds -Bitmap $source
        $bitmap = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.Clear([System.Drawing.Color]::Transparent)

                $scale = [Math]::Max($Width / $sourceRect.Width, $Height / $sourceRect.Height)
                $drawWidth = [int][Math]::Ceiling($sourceRect.Width * $scale)
                $drawHeight = [int][Math]::Ceiling($sourceRect.Height * $scale)
                $x = [int][Math]::Floor(($Width - $drawWidth) / 2)
                $y = [int][Math]::Floor(($Height - $drawHeight) / 2)
                $destRect = [System.Drawing.Rectangle]::new($x, $y, $drawWidth, $drawHeight)
                $graphics.DrawImage(
                    $source,
                    $destRect,
                    $sourceRect.X,
                    $sourceRect.Y,
                    $sourceRect.Width,
                    $sourceRect.Height,
                    [System.Drawing.GraphicsUnit]::Pixel
                )
            }
            finally {
                $graphics.Dispose()
            }

            $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }
}

function Save-ContainPng {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    Ensure-ParentDirectory $OutputPath
    $source = [System.Drawing.Bitmap]::new($InputPath)
    try {
        $sourceRect = Get-LogoContentBounds -Bitmap $source
        $bitmap = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.Clear([System.Drawing.Color]::Transparent)

                $scale = [Math]::Min($Width / $sourceRect.Width, $Height / $sourceRect.Height)
                $drawWidth = [int][Math]::Round($sourceRect.Width * $scale)
                $drawHeight = [int][Math]::Round($sourceRect.Height * $scale)
                $x = [int][Math]::Floor(($Width - $drawWidth) / 2)
                $y = [int][Math]::Floor(($Height - $drawHeight) / 2)
                $graphics.DrawImage(
                    $source,
                    [System.Drawing.Rectangle]::new($x, $y, $drawWidth, $drawHeight),
                    $sourceRect.X,
                    $sourceRect.Y,
                    $sourceRect.Width,
                    $sourceRect.Height,
                    [System.Drawing.GraphicsUnit]::Pixel
                )
            }
            finally {
                $graphics.Dispose()
            }
            $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }
}

function Save-SolidPng {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$Color
    )

    Ensure-ParentDirectory $OutputPath
    $bitmap = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try { $graphics.Clear($Color) } finally { $graphics.Dispose() }
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Copy-File {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    Ensure-ParentDirectory $OutputPath
    Copy-Item -LiteralPath $InputPath -Destination $OutputPath -Force
}

$logo = Join-Path $ProjectRoot "assets\branding\source\genericimlogo.png"

if (-not (Test-Path -LiteralPath $logo)) {
    throw "Missing required logo source: $logo"
}

Save-CoverPng -InputPath $logo -OutputPath (Join-Path $ProjectRoot "assets\logo.png") -Width 1024 -Height 1024
Save-CoverPng -InputPath $logo -OutputPath (Join-Path $ProjectRoot "assets\brand\generic-im-icon.png") -Width 1024 -Height 1024
Save-CoverPng -InputPath $logo -OutputPath (Join-Path $ProjectRoot "admin\src\assets\images\common\logo.png") -Width 1024 -Height 1024

$androidRes = Join-Path $ProjectRoot "android\app\src\main\res"
$launcherSizes = @{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
}
$foregroundSizes = @{
    "drawable-mdpi" = 108
    "drawable-hdpi" = 162
    "drawable-xhdpi" = 216
    "drawable-xxhdpi" = 324
    "drawable-xxxhdpi" = 432
}
$adaptiveLayerSizes = @{
    "mipmap-mdpi" = 108
    "mipmap-hdpi" = 162
    "mipmap-xhdpi" = 216
    "mipmap-xxhdpi" = 324
    "mipmap-xxxhdpi" = 432
}

foreach ($entry in $launcherSizes.GetEnumerator()) {
    $dir = Join-Path $androidRes $entry.Key
    $size = [int]$entry.Value
    Save-CoverPng -InputPath $logo -OutputPath (Join-Path $dir "ic_launcher.png") -Width $size -Height $size
    Save-CoverPng -InputPath $logo -OutputPath (Join-Path $dir "ic_launcher_foreground.png") -Width $size -Height $size
    Save-CoverPng -InputPath $logo -OutputPath (Join-Path $dir "ic_launcher_monochrome.png") -Width $size -Height $size
}

foreach ($entry in $foregroundSizes.GetEnumerator()) {
    $dir = Join-Path $androidRes $entry.Key
    Save-CoverPng -InputPath $logo -OutputPath (Join-Path $dir "ic_launcher_foreground.png") -Width ([int]$entry.Value) -Height ([int]$entry.Value)
}

$brandBackground = [System.Drawing.ColorTranslator]::FromHtml("#3F8FEF")
foreach ($entry in $adaptiveLayerSizes.GetEnumerator()) {
    $dir = Join-Path $androidRes $entry.Key
    Save-SolidPng `
        -OutputPath (Join-Path $dir "ic_launcher_background.png") `
        -Width ([int]$entry.Value) `
        -Height ([int]$entry.Value) `
        -Color $brandBackground
}

# Override the third-party CallKit wordmark with the customer's square logo.
Save-ContainPng `
    -InputPath $logo `
    -OutputPath (Join-Path $androidRes "drawable-xxxhdpi\ic_logo.png") `
    -Width 150 `
    -Height 50

$colorsXml = Join-Path $androidRes "values\colors.xml"
Set-Content -LiteralPath $colorsXml -Encoding UTF8 -Value @(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<resources>'
    '    <color name="ic_launcher_background">#3F8FEF</color>'
    '</resources>'
)

$adaptiveIconXml = Join-Path $androidRes "mipmap-anydpi-v26\ic_launcher.xml"
Set-Content -LiteralPath $adaptiveIconXml -Encoding UTF8 -Value @(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
    '  <background android:drawable="@color/ic_launcher_background"/>'
    '  <foreground android:drawable="@drawable/ic_launcher_foreground"/>'
    '</adaptive-icon>'
)

Write-Host "[OK] Applied fixed delivery branding from assets\branding\source\genericimlogo.png without splash image"
