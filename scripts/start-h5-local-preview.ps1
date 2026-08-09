<#
.SYNOPSIS
Compatibility wrapper for the retired Vue H5 preview command.

Flutter Web is the only supported H5/PC client. Use
start-web-local-preview.ps1 for new automation.
#>
[CmdletBinding()]
param(
    [int]$Port = 5185,
    [string]$ApiUrl = "http://127.0.0.1:8080",
    [string]$WsUrl = "ws://127.0.0.1:8080/api/v1/ws",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$webScript = Join-Path $PSScriptRoot "start-web-local-preview.ps1"
if (-not (Test-Path -LiteralPath $webScript)) {
    throw "Flutter Web preview script is missing: $webScript"
}

& $webScript -Port $Port -ApiUrl $ApiUrl -WsUrl $WsUrl -NoBuild:$NoBuild
