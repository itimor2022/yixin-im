#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url
)

$ErrorActionPreference = "Stop"
$page = Invoke-WebRequest -Uri $Url -UseBasicParsing
$html = $page.Content
[regex]::Matches($html, 'https?://[^"''\s<>]+') |
    ForEach-Object { $_.Value -replace '&amp;', '&' } |
    Select-Object -Unique
