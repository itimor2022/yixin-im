<#
.SYNOPSIS
扫描 Flutter 业务代码中的深色模式硬编码颜色风险。

.DESCRIPTION
使用维护好的正则和允许列表，把命中项分为必须复核与可能合理两类，并覆盖写入
Markdown 报告。脚本不修改 Dart 源码，但会替换 OutputPath 指向的现有报告。

.PARAMETER OutputPath
风险报告路径；相对路径按仓库根目录解析。

.EXAMPLE
pwsh -File scripts/scan-dark-mode-risk.ps1 -OutputPath artifacts/dark-mode-risk.md
#>
param(
  [string]$OutputPath = "docs/dark-mode-risk-scan-20260626.md"
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$pattern = 'AppColors\.primary\b|AppColors\.(lightTextPrimary|lightTextSecondary|lightTextTertiary)\b|Colors\.(black|white)(10|12|24|26|30|38|45|54|60|70|87)?\b|Color\(0xFF(0B0D12|0E0E0E|111827|121212|15171A|161B22|17212B|1C1C1E|1D1D1F|20242B|232E3C|252932|2C2C2E|38383A|F2F2F7|F5F5F5|FFFFFF)\)|color:\s*_[A-Za-z0-9]+Ink\b|foregroundColor:\s*_[A-Za-z0-9]+Ink\b|activeColor:\s*_[A-Za-z0-9]+Ink\b'
$paths = @('lib/features', 'lib/shared/widgets')
$raw = & rg -n --no-heading $pattern @paths

$allowPatterns = @(
  # 这些场景允许固定黑白色，但仍保留在报告中供人工确认上下文。
  'barrierColor',
  'SnackBar',
  'Colors\.red',
  'Colors\.black\.withOpacity',
  'Colors\.white\.withOpacity',
  'backgroundColor: Colors\.black',
  'ImageViewer',
  'VideoPlayer',
  'camera',
  'QRCode',
  'QrImage',
  'backgroundColor: Colors\.white\)',
  'red_packet_bubble',
  'transfer_bubble'
)

$mustReview = @()
$likelyAllowed = @()
foreach ($line in $raw) {
  $allowed = $false
  foreach ($allow in $allowPatterns) {
    if ($line -match $allow) {
      $allowed = $true
      break
    }
  }
  if ($allowed) {
    $likelyAllowed += $line
  } else {
    $mustReview += $line
  }
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add('# 深色模式硬编码风险扫描 2026-06-26')
$out.Add('')
$out.Add('## 规则')
$out.Add('')
$out.Add('- 必须复核：`AppColors.primary`、`AppColors.lightText*`、弱灰 `Colors.white38/54/24`、旧深色块 `0xFF17212B/232E3C/2C2C2E/161B22`、深色 UI 中的 `Colors.black*`。')
$out.Add('- 可保留但需人工确认：图片/视频遮罩、全屏相机/视频/通话黑底、Snackbar/错误红底白字、二维码白底、红包/转账品牌气泡。')
$out.Add('')
$out.Add("## 必须复核命中 $($mustReview.Count)")
$out.Add('')
foreach ($line in $mustReview) {
  $out.Add('- `' + $line + '`')
}
$out.Add('')
$out.Add("## 暂列可保留命中 $($likelyAllowed.Count)")
$out.Add('')
foreach ($line in $likelyAllowed) {
  $out.Add('- `' + $line + '`')
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $repoRoot $OutputPath), $out, $utf8NoBom)
Write-Host "Wrote $OutputPath"
Write-Host "MustReview=$($mustReview.Count) LikelyAllowed=$($likelyAllowed.Count)"
