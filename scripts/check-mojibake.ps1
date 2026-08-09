#Requires -Version 7.0
[CmdletBinding()]
param(
    [string[]]$Roots = @(
        "lib",
        "backend",
        "android/app/src/main",
        "admin/src",
        "ios",
        "macos",
        "windows",
        "web",
        "scripts",
        "docker",
        "pubspec.yaml",
        "analysis_options.yaml",
        "compose.yaml"
    )
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function New-TextFromCodePoints {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$badFragments = @(
    @{ Name = "legacy_voice_call"; Text = New-TextFromCodePoints @(0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d) },
    @{ Name = "legacy_video_call"; Text = New-TextFromCodePoints @(0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d) },
    @{ Name = "legacy_system_sender"; Text = New-TextFromCodePoints @(0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05) },
    @{ Name = "legacy_call_suffix"; Text = New-TextFromCodePoints @(0x95ab, 0x6c33, 0x763d) },
    @{ Name = "replacement_character"; Text = [string][char]0xfffd },
    @{ Name = "latin_mojibake_c3"; Text = [string][char]0x00c3 },
    @{ Name = "latin_mojibake_c2"; Text = [string][char]0x00c2 }
)

$suspiciousCodePoints = @(
    0x95c2, 0x93c6, 0x5987, 0x7459, 0x9352, 0x9422, 0x7f02, 0x93b4,
    0x986b, 0x95b2, 0x9359, 0x5a11, 0x7487, 0x93ba, 0x6b06, 0x6b39,
    0x5815, 0x7029, 0x7b1b, 0x9286, 0x9225, 0x9471, 0x7efe, 0x935a,
    0x9423, 0x6f7c, 0x95ab, 0x93c1, 0x9417, 0x9427, 0x704f, 0x9483,
    0x7b17, 0x941d, 0x6fa7, 0x9350, 0x9855, 0x68eb, 0x6d32, 0x713d,
    0x7023, 0x934e, 0x6a00, 0x9366, 0x9411, 0x6fee, 0x708a, 0x95b8,
    0x95b9, 0x95ba, 0x95bb, 0x95bc, 0x95bd, 0x95be, 0x95bf, 0x941a,
    0x9429, 0x942b, 0x942d, 0x942e, 0x942f, 0x9430, 0x9431, 0x9432,
    0x9433, 0x9434, 0x9435, 0x9436, 0x9437, 0x9438, 0x9439, 0x943a,
    0x943b, 0x943c, 0x943d, 0x943e, 0x943f, 0x93b5, 0x93b6, 0x93b7,
    0x93b8, 0x93b9, 0x93bb, 0x93bc, 0x93bd, 0x93be, 0x93bf
)
$suspiciousChars = -join ($suspiciousCodePoints | ForEach-Object { [char]$_ })

$extensions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    ".dart", ".go", ".kt", ".kts", ".java", ".xml", ".yaml", ".yml", ".json",
    ".md", ".txt", ".gradle", ".properties", ".swift", ".m", ".h", ".js",
    ".ts", ".tsx", ".vue", ".sql", ".ps1", ".py"
) | ForEach-Object { [void]$extensions.Add($_) }

$excludedDirs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(".git", "build", ".dart_tool", "node_modules", "dist", "artifacts", "tmp") |
    ForEach-Object { [void]$excludedDirs.Add($_) }

function Test-IsExcludedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $Path)
    foreach ($part in ($relative -split '[\\/]')) {
        if ($excludedDirs.Contains($part)) {
            return $true
        }
    }
    return $false
}

function Get-TargetFiles {
    foreach ($root in $Roots) {
        $path = Join-Path $repoRoot $root
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Recurse -File | Where-Object {
                -not (Test-IsExcludedPath $_.FullName) -and $extensions.Contains($_.Extension)
            }
        } else {
            if (-not (Test-IsExcludedPath $item.FullName) -and $extensions.Contains($item.Extension)) {
                $item
            }
        }
    }
}

$findings = New-Object System.Collections.Generic.List[string]

foreach ($file in Get-TargetFiles) {
    try {
        $text = [System.IO.File]::ReadAllText($file.FullName, $utf8)
    } catch {
        continue
    }
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($fragment in $badFragments) {
            if ($fragment.Text -ne "" -and $lines[$i].Contains($fragment.Text)) {
                $relative = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName)
                $findings.Add(("{0}:{1}: {2}" -f $relative, ($i + 1), $fragment.Name))
            }
        }
        foreach ($ch in $suspiciousChars.ToCharArray()) {
            if ($lines[$i].Contains([string]$ch)) {
                $relative = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName)
                $findings.Add(("{0}:{1}: suspicious_mojibake_char U+{2:X4}" -f $relative, ($i + 1), [int][char]$ch))
                break
            }
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Error ("Mojibake check failed. Findings:`n" + ($findings -join "`n"))
}

Write-Host "Mojibake check passed."
