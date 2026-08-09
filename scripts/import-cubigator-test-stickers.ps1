#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet("cubigator", "duck", "premium_gifts")]
    [string]$Pack = "cubigator",
    [int]$Limit = 30,
    [switch]$StaticWebp
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$packConfig = switch ($Pack) {
    "cubigator" {
        @{
            Directory = "cubigator"
            FilePrefix = "cubigator"
            SourcePrefix = "https://data.chpic.su/stickers/c/Crocosaurus/Crocosaurus_"
        }
    }
    "duck" {
        @{
            Directory = "duck"
            FilePrefix = "duck"
            SourcePrefix = "https://data.chpic.su/stickers/u/UtyaDuckFull/UtyaDuckFull_"
        }
    }
    "premium_gifts" {
        @{
            Directory = "premium_gifts"
            FilePrefix = "premium_gifts"
            SourcePrefix = "https://data.chpic.su/stickers/p/PremiumGifts/PremiumGifts_"
        }
    }
}

$outDir = Join-Path $repoRoot ("backend\assets\sticker_sources\" + $packConfig.Directory)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$uploadDir = Join-Path $repoRoot ("backend\uploads\stickers\" + $packConfig.Directory)
New-Item -ItemType Directory -Force -Path $uploadDir | Out-Null

$sourceExtension = if ($StaticWebp) { "webp" } else { "tgs" }
$assetExtension = if ($StaticWebp) { "webp" } else { "json" }

$selected = 1..30 |
    ForEach-Object {
        "$($packConfig.SourcePrefix){0:D3}.$sourceExtension" -f $_
    } |
    Select-Object -First $Limit
$manifest = @()
$index = 1
foreach ($url in $selected) {
    $baseName = "$($packConfig.FilePrefix)_{0:D2}" -f $index
    $downloadPath = Join-Path $outDir "$baseName.$sourceExtension"
    $assetPath = Join-Path $outDir "$baseName.$assetExtension"

    try {
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing
    } catch {
        Write-Warning "Skipped missing sticker: $url"
        continue
    }

    if (-not $StaticWebp) {
        $inputStream = [System.IO.File]::OpenRead($downloadPath)
        try {
            $gzip = [System.IO.Compression.GZipStream]::new(
                $inputStream,
                [System.IO.Compression.CompressionMode]::Decompress
            )
            try {
                $reader = [System.IO.StreamReader]::new($gzip, [System.Text.Encoding]::UTF8)
                try {
                    $json = $reader.ReadToEnd()
                } finally {
                    $reader.Dispose()
                }
            } finally {
                $gzip.Dispose()
            }
        } finally {
            $inputStream.Dispose()
        }

        Set-Content -Path $assetPath -Value $json -Encoding UTF8
    }

    Copy-Item -LiteralPath $assetPath -Destination (Join-Path $uploadDir "$baseName.$assetExtension") -Force
    if (-not $StaticWebp) {
        Copy-Item -LiteralPath $downloadPath -Destination (Join-Path $uploadDir "$baseName.tgs") -Force
    }

    $manifest += [ordered]@{
        name = $baseName
        path = "backend/assets/sticker_sources/$($packConfig.Directory)/$baseName.$assetExtension"
        tgs_path = if ($StaticWebp) { $null } else { "backend/assets/sticker_sources/$($packConfig.Directory)/$baseName.tgs" }
        upload_path = "backend/uploads/stickers/$($packConfig.Directory)/$baseName.$assetExtension"
        source = if ($StaticWebp) { "/uploads/stickers/$($packConfig.Directory)/$baseName.$assetExtension" } else { "/uploads/stickers/$($packConfig.Directory)/$baseName.tgs" }
    }
    $index++
}

$manifestPath = Join-Path $outDir "manifest.json"
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "Imported $($manifest.Count) $Pack stickers to $outDir"
