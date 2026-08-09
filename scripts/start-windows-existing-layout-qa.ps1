#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Pwsh = 'pwsh',
    [string]$ArtifactDir = 'artifacts\cross-platform-media-acceptance-20260728\windows-layout'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$artifactPath = [IO.Path]::GetFullPath((Join-Path $repo $ArtifactDir))
$runner = Join-Path $PSScriptRoot 'run-windows-existing-layout-qa.ps1'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutPath = Join-Path $artifactPath "windows-layout-qa-$timestamp.stdout.log"
$stderrPath = Join-Path $artifactPath "windows-layout-qa-$timestamp.stderr.log"
New-Item -ItemType Directory -Force -Path $artifactPath | Out-Null

$process = Start-Process `
    -FilePath $Pwsh `
    -ArgumentList @('-NoProfile', '-File', $runner) `
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
