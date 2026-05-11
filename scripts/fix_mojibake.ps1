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

$suspiciousChars = "闂鏆妗瑙鍒鐢缂鎴顫閲鍙娑璇鎺娆欐堕瀹绛锛銆鈥鑱绾鍚鐣娼閫鏁鐗鐧灏钃绗鐝澧鍐顕妫娲焽瀣鍎樀鍦鐑濮炲"
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
