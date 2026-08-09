<#
.SYNOPSIS
根据品牌 Logo 生成指定尺寸的 Flutter 启动图。

.DESCRIPTION
在透明画布上按比例居中 Logo，并覆盖 Output 指向的 PNG。Width/Height 为 0
时由脚本使用项目默认尺寸；该操作会修改受版本控制的品牌资源。

.PARAMETER Logo
启动图使用的透明背景 Logo。

.PARAMETER Output
生成的启动图路径，现有文件会被覆盖。

.PARAMETER Width
画布宽度；0 使用默认值。

.EXAMPLE
pwsh -File scripts/generate-p3-splash.ps1
#>
[CmdletBinding()]
param(
    [string]$Logo = "assets\brand\generic-im-icon.png",
    [string]$Output = "assets\splash.png",
    [int]$Width = 0,
    [int]$Height = 0
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot

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

function New-SplashBitmap {
    param(
        [Parameter(Mandatory = $true)][string]$LogoPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$CanvasWidth,
        [Parameter(Mandatory = $true)][int]$CanvasHeight
    )

    Ensure-ParentDirectory $OutputPath

    $logoImage = [System.Drawing.Image]::FromFile($LogoPath)
    $bitmap = [System.Drawing.Bitmap]::new($CanvasWidth, $CanvasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $rect = [System.Drawing.RectangleF]::new(0, 0, $CanvasWidth, $CanvasHeight)
            $bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                $rect,
                [System.Drawing.ColorTranslator]::FromHtml("#030712"),
                [System.Drawing.ColorTranslator]::FromHtml("#27272A"),
                [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
            )
            try {
                $blend = [System.Drawing.Drawing2D.ColorBlend]::new()
                $blend.Positions = [single[]](0, 0.54, 1)
                $blend.Colors = [System.Drawing.Color[]]@(
                    [System.Drawing.ColorTranslator]::FromHtml("#030712"),
                    [System.Drawing.ColorTranslator]::FromHtml("#111827"),
                    [System.Drawing.ColorTranslator]::FromHtml("#3F3F46")
                )
                $bgBrush.InterpolationColors = $blend
                $graphics.FillRectangle($bgBrush, $rect)
            }
            finally {
                $bgBrush.Dispose()
            }

            $logoSize = [int][Math]::Round([Math]::Min($CanvasWidth, $CanvasHeight) * 0.28)
            $logoSize = [Math]::Max(168, [Math]::Min($logoSize, 420))
            $logoX = [int][Math]::Round(($CanvasWidth - $logoSize) / 2)
            $logoY = [int][Math]::Round(($CanvasHeight - $logoSize) * 0.44)

            $shadowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(72, 0, 0, 0))
            try {
                $graphics.FillEllipse($shadowBrush, $logoX + 22, $logoY + $logoSize + 24, $logoSize - 44, [int]($logoSize * 0.10))
            }
            finally {
                $shadowBrush.Dispose()
            }

            $graphics.DrawImage($logoImage, $logoX, $logoY, $logoSize, $logoSize)
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
        $logoImage.Dispose()
    }
}

$logoPath = Resolve-ProjectPath $Logo
if (-not (Test-Path -LiteralPath $logoPath)) {
    throw "Logo not found: $logoPath"
}

$outputPath = Resolve-ProjectPath $Output

if ($Width -le 0 -or $Height -le 0) {
    if (Test-Path -LiteralPath $outputPath) {
        $existing = [System.Drawing.Image]::FromFile($outputPath)
        try {
            $Width = $existing.Width
            $Height = $existing.Height
        }
        finally {
            $existing.Dispose()
        }
    }
    else {
        $Width = 1242
        $Height = 2688
    }
}

New-SplashBitmap -LogoPath $logoPath -OutputPath $outputPath -CanvasWidth $Width -CanvasHeight $Height

$androidLaunchImage = Join-Path $ProjectRoot "android\app\src\main\res\drawable-nodpi\launch_image.png"
Copy-Item -LiteralPath $outputPath -Destination $androidLaunchImage -Force

$iosLaunchRoot = Join-Path $ProjectRoot "ios\Runner\Assets.xcassets\LaunchImage.imageset"
if (Test-Path -LiteralPath $iosLaunchRoot) {
    New-SplashBitmap -LogoPath $logoPath -OutputPath (Join-Path $iosLaunchRoot "LaunchImage.png") -CanvasWidth 168 -CanvasHeight 185
    New-SplashBitmap -LogoPath $logoPath -OutputPath (Join-Path $iosLaunchRoot "LaunchImage@2x.png") -CanvasWidth 336 -CanvasHeight 370
    New-SplashBitmap -LogoPath $logoPath -OutputPath (Join-Path $iosLaunchRoot "LaunchImage@3x.png") -CanvasWidth 504 -CanvasHeight 555
}

Write-Host "Generated $outputPath"
Write-Host "Updated $androidLaunchImage"
Write-Host "Updated iOS LaunchImage imageset"
