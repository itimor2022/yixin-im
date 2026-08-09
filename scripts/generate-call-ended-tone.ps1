$ErrorActionPreference = 'Stop'

$sampleRate = 44100
$durationSeconds = 0.46
$sampleCount = [int]($sampleRate * $durationSeconds)
$outputPath = Join-Path $PSScriptRoot '..\assets\sounds\call_ended.wav'
$outputPath = [System.IO.Path]::GetFullPath($outputPath)

$stream = [System.IO.File]::Open(
    $outputPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
)
$writer = [System.IO.BinaryWriter]::new($stream)

try {
    $dataLength = $sampleCount * 2
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([int](36 + $dataLength))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
    $writer.Write([int]16)
    $writer.Write([int16]1)
    $writer.Write([int16]1)
    $writer.Write([int]$sampleRate)
    $writer.Write([int]($sampleRate * 2))
    $writer.Write([int16]2)
    $writer.Write([int16]16)
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([int]$dataLength)

    for ($i = 0; $i -lt $sampleCount; $i++) {
        $time = $i / $sampleRate
        $value = 0.0

        if ($time -lt 0.16) {
            $localTime = $time
            $envelope = [Math]::Sin([Math]::PI * $localTime / 0.16)
            $value = 0.28 * $envelope * [Math]::Sin(2 * [Math]::PI * 620 * $localTime)
        }
        elseif ($time -ge 0.22 -and $time -lt 0.46) {
            $localTime = $time - 0.22
            $envelope = [Math]::Sin([Math]::PI * $localTime / 0.24)
            $value = 0.24 * $envelope * [Math]::Sin(2 * [Math]::PI * 440 * $localTime)
        }

        $sample = [int16]([Math]::Round($value * [int16]::MaxValue))
        $writer.Write($sample)
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output $outputPath
