#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Pwsh = 'pwsh',
    [string]$ArtifactDir = 'artifacts\cross-platform-media-acceptance-20260728\windows'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$artifactPath = [IO.Path]::GetFullPath((Join-Path $repo $ArtifactDir))
$runner = Join-Path $PSScriptRoot 'run-windows-media-qa.ps1'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutPath = Join-Path $artifactPath "windows-media-qa-$timestamp.stdout.log"
$stderrPath = Join-Path $artifactPath "windows-media-qa-$timestamp.stderr.log"

if (-not (Test-Path -LiteralPath $Pwsh -PathType Leaf)) {
    throw "PowerShell launcher not found: $Pwsh"
}

New-Item -ItemType Directory -Force -Path $artifactPath | Out-Null
$arguments = @(
    '-NoProfile',
    '-File',
    $runner,
    '-ArtifactDir',
    $ArtifactDir
)
$process = Start-Process `
    -FilePath $Pwsh `
    -ArgumentList $arguments `
    -WorkingDirectory $repo `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -WindowStyle Hidden `
    -PassThru

[pscustomobject]@{
    ProcessId = $process.Id
    StdoutPath = $stdoutPath
    StderrPath = $stderrPath
}
