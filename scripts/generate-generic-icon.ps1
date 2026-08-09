[CmdletBinding()]
param(
    [string]$Output = "assets\brand\generic-im-icon.png",
    [int]$Size = 1024
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

$scriptRoot = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptRoot
$outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
    [System.IO.Path]::GetFullPath($Output)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot $Output))
}

function New-RoundedRectanglePath {
    param([float]$X, [float]$Y, [float]$Width, [float]$Height, [float]$Radius)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

$parent = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}

$bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
try {
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.ScaleTransform($Size / 1024.0, $Size / 1024.0)

        $backgroundRect = [System.Drawing.RectangleF]::new(0, 0, 1024, 1024)
        $backgroundPath = New-RoundedRectanglePath -X 20 -Y 20 -Width 984 -Height 984 -Radius 220
        $backgroundBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $backgroundRect,
            [System.Drawing.ColorTranslator]::FromHtml('#2563EB'),
            [System.Drawing.ColorTranslator]::FromHtml('#06B6D4'),
            [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
        )
        try {
            $graphics.FillPath($backgroundBrush, $backgroundPath)
        }
        finally {
            $backgroundBrush.Dispose()
            $backgroundPath.Dispose()
        }

        $bubblePath = New-RoundedRectanglePath -X 176 -Y 220 -Width 672 -Height 500 -Radius 150
        $bubbleBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        try {
            $graphics.FillPath($bubbleBrush, $bubblePath)
            $tail = [System.Drawing.PointF[]]@(
                [System.Drawing.PointF]::new(312, 666),
                [System.Drawing.PointF]::new(246, 830),
                [System.Drawing.PointF]::new(444, 716)
            )
            $graphics.FillPolygon($bubbleBrush, $tail)
        }
        finally {
            $bubbleBrush.Dispose()
            $bubblePath.Dispose()
        }

        $dotBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#2563EB'))
        try {
            foreach ($x in @(330, 472, 614)) {
                $graphics.FillEllipse($dotBrush, $x, 420, 80, 80)
            }
        }
        finally {
            $dotBrush.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
    }

    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $bitmap.Dispose()
}

Copy-Item -LiteralPath $outputPath -Destination (Join-Path $projectRoot "assets\logo.png") -Force
Copy-Item -LiteralPath $outputPath -Destination (Join-Path $projectRoot "assets\icon_foreground.png") -Force
Write-Host "Generated generic icon: $outputPath"

