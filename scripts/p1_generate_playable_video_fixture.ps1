param(
    [string]$FixtureUrl = "https://samplelib.com/lib/preview/mp4/sample-5s.mp4",
    [string]$OutputPath = "artifacts/p1-s3-acceptance-20260727/p1-playable-100m.mp4",
    [int]$TargetSizeMB = 100,
    [int]$DurationSeconds = 200,
    [string]$ContainerName = "genericim-api"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ($TargetSizeMB -lt 16) {
    throw "TargetSizeMB must be at least 16"
}
if ($DurationSeconds -lt 10) {
    throw "DurationSeconds must be at least 10"
}

$outputFullPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null

$runID = [guid]::NewGuid().ToString("N")
$sourcePath = Join-Path ([IO.Path]::GetTempPath()) "genericim-p1-source-$runID.mp4"
$containerSource = "/tmp/genericim-p1-source-$runID.mp4"
$containerOutput = "/tmp/genericim-p1-playable-$runID.mp4"
$generatedPath = Join-Path ([IO.Path]::GetTempPath()) "genericim-p1-playable-$runID.mp4"
$targetSize = [int64]$TargetSizeMB * 1024 * 1024

try {
    Invoke-WebRequest -Uri $FixtureUrl -OutFile $sourcePath -UseBasicParsing -TimeoutSec 120

    $copySourceArgs = @("cp", $sourcePath, "${ContainerName}:${containerSource}")
    & docker @copySourceArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy the source fixture into $ContainerName"
    }

    $ffmpegArgs = @(
        "exec", $ContainerName,
        "ffmpeg",
        "-hide_banner", "-loglevel", "error",
        "-stream_loop", "-1",
        "-i", $containerSource,
        "-t", $DurationSeconds.ToString(),
        "-c", "copy",
        "-movflags", "+faststart",
        "-y", $containerOutput
    )
    & docker @ffmpegArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg failed to build the playable fixture"
    }

    $copyOutputArgs = @("cp", "${ContainerName}:${containerOutput}", $generatedPath)
    & docker @copyOutputArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy the generated fixture from $ContainerName"
    }

    $generatedLength = (Get-Item -LiteralPath $generatedPath).Length
    if ($generatedLength -gt $targetSize) {
        throw "Generated video is $generatedLength bytes, larger than target $targetSize bytes"
    }

    $paddingLength = $targetSize - $generatedLength
    if ($paddingLength -lt 8) {
        throw "Generated video leaves only $paddingLength bytes; an MP4 free atom needs at least 8"
    }

    Move-Item -LiteralPath $generatedPath -Destination $outputFullPath -Force
    $stream = [IO.File]::Open(
        $outputFullPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        [void]$stream.Seek(0, [IO.SeekOrigin]::End)
        [byte[]]$freeAtomHeader = @(
            (($paddingLength -shr 24) -band 0xFF),
            (($paddingLength -shr 16) -band 0xFF),
            (($paddingLength -shr 8) -band 0xFF),
            ($paddingLength -band 0xFF),
            [byte][char]"f",
            [byte][char]"r",
            [byte][char]"e",
            [byte][char]"e"
        )
        $stream.Write($freeAtomHeader, 0, $freeAtomHeader.Length)
        $stream.SetLength($targetSize)
    } finally {
        $stream.Dispose()
    }

    $copyVerifyArgs = @("cp", $outputFullPath, "${ContainerName}:${containerOutput}")
    & docker @copyVerifyArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to copy the padded fixture back into $ContainerName"
    }

    $probeArgs = @(
        "exec", $ContainerName,
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height:format=duration,size",
        "-of", "json",
        $containerOutput
    )
    $probeJSON = (& docker @probeArgs) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        throw "FFprobe rejected the generated fixture"
    }
    $probe = $probeJSON | ConvertFrom-Json
    if ($probe.streams[0].codec_name -ne "h264") {
        throw "Expected H.264, got $($probe.streams[0].codec_name)"
    }
    if ([int64]$probe.format.size -ne $targetSize) {
        throw "Expected $targetSize bytes, probe reports $($probe.format.size)"
    }

    $decodeArgs = @(
        "exec", $ContainerName,
        "ffmpeg",
        "-hide_banner", "-loglevel", "error",
        "-ss", ([Math]::Max(1, $DurationSeconds - 5)).ToString(),
        "-i", $containerOutput,
        "-frames:v", "1",
        "-f", "null", "-"
    )
    & docker @decodeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg could not decode a frame near the end of the fixture"
    }

    $sha256 = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        path = $outputFullPath
        size_bytes = $targetSize
        sha256 = $sha256
        codec = [string]$probe.streams[0].codec_name
        width = [int]$probe.streams[0].width
        height = [int]$probe.streams[0].height
        duration_seconds = [double]$probe.format.duration
        late_frame_decoded = $true
        padding_atom = "free"
        padding_bytes = $paddingLength
    } | ConvertTo-Json -Depth 10
} finally {
    Remove-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $generatedPath -Force -ErrorAction SilentlyContinue
    $removeArgs = @(
        "exec", $ContainerName,
        "rm", "-f", $containerSource, $containerOutput
    )
    & docker @removeArgs | Out-Null
}
