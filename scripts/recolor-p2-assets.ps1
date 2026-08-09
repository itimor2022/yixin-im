<#
.SYNOPSIS
按 P2 配色表批量替换指定 PNG 资源颜色。

.DESCRIPTION
读取脚本内维护的文件与目标色映射，在保留 Alpha 的同时覆盖原 PNG。
该操作直接修改资源且没有自动备份；首次运行必须使用 DryRun 核对清单，
正式执行后通过 Git diff 逐张检查。

.PARAMETER DryRun
只输出文件和目标颜色，不写入 PNG。

.EXAMPLE
pwsh -File scripts/recolor-p2-assets.ps1 -DryRun
#>
param(
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')

function Resolve-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Resolve-Path -LiteralPath (Join-Path $Root $RelativePath)).Path
}

function Convert-HexColor {
  param([Parameter(Mandatory = $true)][string]$Hex)

  $clean = $Hex.Trim().TrimStart('#')
  if ($clean.Length -ne 6) {
    throw "Expected 6-digit hex color, got: $Hex"
  }

  return [System.Drawing.Color]::FromArgb(
    255,
    [Convert]::ToInt32($clean.Substring(0, 2), 16),
    [Convert]::ToInt32($clean.Substring(2, 2), 16),
    [Convert]::ToInt32($clean.Substring(4, 2), 16)
  )
}

function Recolor-Png {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string]$HexColor
  )

  $path = Resolve-RepoPath $RelativePath
  $target = Convert-HexColor $HexColor

  if ($DryRun) {
    Write-Output "DRY $RelativePath -> $HexColor"
    return
  }

  $source = $null
  $output = $null
  $graphics = $null
  $tmp = "$path.tmp"

  try {
    $source = [System.Drawing.Bitmap]::new($path)
    $output = [System.Drawing.Bitmap]::new(
      $source.Width,
      $source.Height,
      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($output)
    $graphics.Clear([System.Drawing.Color]::Transparent)

    for ($x = 0; $x -lt $source.Width; $x++) {
      for ($y = 0; $y -lt $source.Height; $y++) {
        $pixel = $source.GetPixel($x, $y)
        if ($pixel.A -gt 0) {
          $output.SetPixel(
            $x,
            $y,
            [System.Drawing.Color]::FromArgb($pixel.A, $target.R, $target.G, $target.B)
          )
        }
      }
    }

    $output.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    if ($graphics) { $graphics.Dispose() }
    if ($output) { $output.Dispose() }
    if ($source) { $source.Dispose() }
  }

  Move-Item -LiteralPath $tmp -Destination $path -Force
  Write-Output "OK  $RelativePath -> $HexColor"
}

function Convert-BlueLogoToGraphite {
  param([Parameter(Mandatory = $true)][string]$RelativePath)

  $path = Resolve-RepoPath $RelativePath
  $dark = Convert-HexColor '#111827'
  $light = Convert-HexColor '#3F3F46'

  if ($DryRun) {
    Write-Output "DRY $RelativePath blue-logo -> graphite"
    return
  }

  $source = $null
  $output = $null
  $graphics = $null
  $tmp = "$path.tmp"

  try {
    $source = [System.Drawing.Bitmap]::new($path)
    $output = [System.Drawing.Bitmap]::new(
      $source.Width,
      $source.Height,
      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($output)
    $graphics.Clear([System.Drawing.Color]::Transparent)

    for ($x = 0; $x -lt $source.Width; $x++) {
      for ($y = 0; $y -lt $source.Height; $y++) {
        $pixel = $source.GetPixel($x, $y)
        if ($pixel.A -eq 0) {
          continue
        }

        $max = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
        $min = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
        $isNearWhite = $min -gt 224 -and ($max - $min) -lt 36
        if ($isNearWhite) {
          $output.SetPixel($x, $y, $pixel)
          continue
        }

        $isBlueBrandPixel = $pixel.B -gt ($pixel.R + 18) -and $pixel.B -gt 110
        if (-not $isBlueBrandPixel) {
          $output.SetPixel($x, $y, $pixel)
          continue
        }

        $brightness = $max / 255.0
        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, ($brightness - 0.35) / 0.65))
        $r = [int]($dark.R + (($light.R - $dark.R) * $ratio))
        $g = [int]($dark.G + (($light.G - $dark.G) * $ratio))
        $b = [int]($dark.B + (($light.B - $dark.B) * $ratio))
        $output.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($pixel.A, $r, $g, $b))
      }
    }

    $output.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    if ($graphics) { $graphics.Dispose() }
    if ($output) { $output.Dispose() }
    if ($source) { $source.Dispose() }
  }

  Move-Item -LiteralPath $tmp -Destination $path -Force
  Write-Output "OK  $RelativePath blue-logo -> graphite"
}

$activeTabIcons = @(
  'assets/icons/tab_chat_active.png',
  'assets/icons/tab_contacts_active.png',
  'assets/icons/tab_moments_active.png',
  'assets/icons/tab_settings_active.png',
  'h5/public/assets/icons/tab_chat_active.png',
  'h5/public/assets/icons/tab_contacts_active.png',
  'h5/public/assets/icons/tab_moments_active.png',
  'h5/public/assets/icons/tab_settings_active.png'
)

$normalTabIcons = @(
  'assets/icons/tab_chat.png',
  'assets/icons/tab_contacts.png',
  'assets/icons/tab_moments.png',
  'assets/icons/tab_settings.png',
  'h5/public/assets/icons/tab_chat.png',
  'h5/public/assets/icons/tab_contacts.png',
  'h5/public/assets/icons/tab_moments.png',
  'h5/public/assets/icons/tab_settings.png'
)

$groupProfileIcons = Get-ChildItem -LiteralPath (Resolve-RepoPath 'assets/icons/group_profile') -Filter '*.png' |
  ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') }

$attachmentIcons = Get-ChildItem -LiteralPath (Resolve-RepoPath 'assets/images/attachment_actions') -Filter '*.png' |
  ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') }

foreach ($icon in $activeTabIcons) {
  Recolor-Png -RelativePath $icon -HexColor '#111827'
}

foreach ($icon in $normalTabIcons) {
  Recolor-Png -RelativePath $icon -HexColor '#8A8A8A'
}

foreach ($icon in $groupProfileIcons) {
  Recolor-Png -RelativePath $icon -HexColor '#374151'
}

foreach ($icon in $attachmentIcons) {
  Recolor-Png -RelativePath $icon -HexColor '#374151'
}

Convert-BlueLogoToGraphite -RelativePath 'h5/public/assets/logo.png'
