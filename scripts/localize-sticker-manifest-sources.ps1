#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$manifestFiles = Get-ChildItem -Path @(
    "backend/assets/sticker_sources",
    "backend/uploads/stickers"
) -Recurse -Filter "manifest.json"

$changed = 0
foreach ($file in $manifestFiles) {
    $items = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $fileChanged = $false

    foreach ($item in $items) {
        $uploadPath = [string]$item.upload_path
        if ([string]::IsNullOrWhiteSpace($uploadPath)) {
            continue
        }

        $localSource = ($uploadPath -replace "^backend/uploads", "/uploads") -replace "\.json$", ".tgs"
        $localFile = Join-Path $repoRoot ("backend" + ($localSource -replace "/", [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $localFile)) {
            continue
        }

        if ([string]$item.source -ne $localSource) {
            $item.source = $localSource
            $fileChanged = $true
        }
    }

    if ($fileChanged) {
        $items | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file.FullName -Encoding UTF8
        $changed++
    }
}

Write-Host "Localized sticker manifest files: $changed"
