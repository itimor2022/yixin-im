param(
    [string]$CustomerName = "",
    [string]$AdminDomain = "",
    [string]$ApiDomain = "",
    [string]$H5Domain = "",
    [string]$KfDomain = "support.example.com",
    [ValidateSet("http", "https")]
    [string]$Scheme = "https",
    [string]$InstallDir = "",
    [string]$AdminPassword = "123456",
    [string]$OutputRoot = "artifacts"
)

$ErrorActionPreference = "Stop"

function Read-RequiredValue {
    param(
        [string]$Label,
        [string]$Value,
        [string]$DefaultValue = ""
    )

    if ($Value.Trim()) {
        return $Value.Trim()
    }

    if ($DefaultValue.Trim()) {
        $inputValue = Read-Host "$Label [$DefaultValue]"
        if ($inputValue.Trim()) {
            return $inputValue.Trim()
        }
        return $DefaultValue.Trim()
    }

    do {
        $inputValue = Read-Host $Label
    } while (-not $inputValue.Trim())

    return $inputValue.Trim()
}

function Convert-ToSlug {
    param([string]$Value)

    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
    $slug = $slug -replace '^-+|-+$', ''
    if ($slug) {
        return $slug
    }
    return "customer"
}

$CustomerName = Read-RequiredValue -Label "客户名称，用于包名" -Value $CustomerName -DefaultValue "customer"
$ApiDomain = Read-RequiredValue -Label "API/媒体域名，例如 imapi.customer.com" -Value $ApiDomain
$AdminDomain = Read-RequiredValue -Label "后台域名，例如 imadmin.customer.com" -Value $AdminDomain
$H5Domain = Read-RequiredValue -Label "Web/H5/PC域名，例如 imh5.customer.com" -Value $H5Domain
$KfDomain = Read-RequiredValue -Label "客服后台域名，例如 kf.customer.com" -Value $KfDomain -DefaultValue "support.example.com"

$customerSlug = Convert-ToSlug $CustomerName
$packageName = "genericim-$customerSlug-online-prebuilt"

Write-Host ""
Write-Host "客户打包参数："
Write-Host "  客户名称: $CustomerName"
Write-Host "  后台域名: $AdminDomain"
Write-Host "  API域名 : $ApiDomain"
Write-Host "  Web域名 : $H5Domain"
Write-Host "  客服域名: $KfDomain"
Write-Host "  协议    : $Scheme"
Write-Host "  包名前缀: $packageName"
Write-Host ""

$builder = Join-Path $PSScriptRoot "build-online-prebuilt-package.ps1"
& $builder `
    -OutputRoot $OutputRoot `
    -PackageName $packageName `
    -CustomerName $CustomerName `
    -AdminDomain $AdminDomain `
    -ApiDomain $ApiDomain `
    -H5Domain $H5Domain `
    -KfDomain $KfDomain `
    -Scheme $Scheme `
    -InstallDir $InstallDir `
    -DefaultAdminPassword $AdminPassword
