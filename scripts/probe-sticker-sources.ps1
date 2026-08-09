#Requires -Version 7.0
[CmdletBinding()]
param(
    [string[]]$Urls
)

$ErrorActionPreference = "Continue"
foreach ($url in ($Urls -split ',')) {
    $url = $url.Trim()
    if ([string]::IsNullOrWhiteSpace($url)) {
        continue
    }
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 10
        Write-Host "OK $($response.StatusCode) $url"
    } catch {
        Write-Host "MISS $url"
    }
}
