param(
  [switch]$Apply,
  [string[]]$Roots = @("lib", "backend", "admin", "android", "ios", "windows", "macos", "web")
)

$ErrorActionPreference = "Stop"

$extensions = @(
  ".dart", ".go", ".vue", ".kt", ".kts", ".java", ".xml",
  ".yaml", ".yml", ".json", ".md", ".txt", ".gradle",
  ".properties", ".swift", ".m", ".h", ".js", ".ts", ".tsx"
)

$suspiciousChars = -join (@(
  0x95c2, 0x93c6, 0x5987, 0x7459, 0x9352, 0x9422, 0x7f02, 0x93b4, 0x986b, 0x95b2,
  0x9359, 0x5a11, 0x7487, 0x93ba, 0x6b06, 0x6b39, 0x5815, 0x7029, 0x7b1b, 0xff0c,
  0x9286, 0x3006, 0x9225, 0x9471, 0x7efe, 0x935a, 0x9423, 0x6f7c, 0x95ab, 0x93c1,
  0x9417, 0x9427, 0x704f, 0x9483, 0x7b17, 0x941d, 0x6fa7, 0x9350, 0x9855, 0x68eb,
  0x6d32, 0x713d, 0x7023, 0x934e, 0x6a00, 0x9366, 0x9411, 0x6fee, 0x708a, 0x95b2
) | ForEach-Object { [char]$_ })
$suspiciousRegex = "[" + [Regex]::Escape($suspiciousChars) + "]"
$cp936 = [System.Text.Encoding]::GetEncoding(936)
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Count-Suspicious([string]$text) {
  return ([regex]::Matches($text, $suspiciousRegex)).Count
}

function Repair-Tail([string]$tail) {
  try {
    $bytes = $cp936.GetBytes($tail)
    return $utf8.GetString($bytes)
  } catch {
    return $null
  }
}

function Should-Replace([string]$before, [string]$after) {
  if ([string]::IsNullOrEmpty($after)) { return $false }
  if ($after.Contains([char]0xFFFD)) { return $false }

  $beforeCount = Count-Suspicious $before
  $afterCount = Count-Suspicious $after
  if ($beforeCount -le 0) { return $false }
  if ($afterCount -ge $beforeCount) { return $false }
  if ($after -notmatch "[\p{IsCJKUnifiedIdeographs}]") { return $false }
  return $true
}

$filesChanged = New-Object System.Collections.Generic.List[string]
$linesChanged = 0

$targetFiles = foreach ($root in $Roots) {
  if (Test-Path $root) {
    Get-ChildItem -Path $root -Recurse -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
  }
}

foreach ($file in $targetFiles) {
  $original = [System.IO.File]::ReadAllText($file.FullName, $utf8)
  $normalized = $original -replace "`r`n", "`n"
  $lines = $normalized -split "`n", -1
  $changed = $false

  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line -notmatch $suspiciousRegex) { continue }

    $match = [regex]::Match($line, $suspiciousRegex)
    if (-not $match.Success) { continue }

    $prefix = $line.Substring(0, $match.Index)
    $tail = $line.Substring($match.Index)
    $repaired = Repair-Tail $tail

    if (Should-Replace $tail $repaired) {
      $lines[$i] = $prefix + $repaired
      $changed = $true
      $linesChanged++
    }
  }

  if ($changed) {
    $filesChanged.Add($file.FullName)
    if ($Apply) {
      $newText = [string]::Join("`n", $lines)
      [System.IO.File]::WriteAllText($file.FullName, $newText, $utf8)
    }
  }
}

Write-Output ("files_changed=" + $filesChanged.Count)
Write-Output ("lines_changed=" + $linesChanged)
foreach ($path in $filesChanged) {
  Write-Output $path
}
