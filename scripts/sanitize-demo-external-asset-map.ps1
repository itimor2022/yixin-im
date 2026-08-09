#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$mapPath = Join-Path $repoRoot "backend\uploads\demo\external_asset_map.json"

$items = Get-Content -Raw -LiteralPath $mapPath | ConvertFrom-Json
$sanitized = foreach ($item in $items) {
    [ordered]@{
        source = "localized"
        path = [string]$item.path
    }
}

$sanitized | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $mapPath -Encoding UTF8
Write-Host "Sanitized demo external asset map: $($sanitized.Count) entries"
