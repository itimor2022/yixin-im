#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ApiContainer = "genericim-api",
    [string]$MySqlContainer = "genericim-mysql",
    [string]$Database = "genericim",
    [string]$DatabaseUser = "genericim",
    [string]$DatabasePassword = "genericim"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$corsFile = Join-Path $repoRoot "scripts\s3-cors-local-media-qa.json"
if (-not (Test-Path -LiteralPath $corsFile)) {
    throw "Missing S3 CORS configuration: $corsFile"
}

function Get-ContainerEnvironmentValue {
    param(
        [Parameter(Mandatory)]
        [string]$Container,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $lines = & docker inspect $Container --format '{{range .Config.Env}}{{println .}}{{end}}'
    $entry = $lines |
        Where-Object { $_.StartsWith("$Name=", [StringComparison]::Ordinal) } |
        Select-Object -First 1
    if (-not $entry) {
        return ""
    }
    return $entry.Substring($Name.Length + 1)
}

function ConvertFrom-RawBase64 {
    param([Parameter(Mandatory)][string]$Value)

    $padded = $Value
    while (($padded.Length % 4) -ne 0) {
        $padded += "="
    }
    return [Convert]::FromBase64String($padded)
}

function Unprotect-StorageSecret {
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$MasterKey
    )

    $prefix = "enc:v1:"
    if (-not $Value.StartsWith($prefix, [StringComparison]::Ordinal)) {
        return $Value
    }
    $payload = ConvertFrom-RawBase64 $Value.Substring($prefix.Length)
    if ($payload.Length -le 28) {
        throw "Encrypted storage credential payload is invalid."
    }

    $material = [Text.Encoding]::UTF8.GetBytes(
        "genericim-storage-settings-v1:$MasterKey"
    )
    $key = [Security.Cryptography.SHA256]::HashData($material)
    $nonce = $payload[0..11]
    $ciphertextLength = $payload.Length - 12 - 16
    $ciphertext = New-Object byte[] $ciphertextLength
    [Array]::Copy($payload, 12, $ciphertext, 0, $ciphertextLength)
    $tag = New-Object byte[] 16
    [Array]::Copy($payload, 12 + $ciphertextLength, $tag, 0, 16)
    $plaintext = New-Object byte[] $ciphertextLength
    $aes = [Security.Cryptography.AesGcm]::new($key, 16)
    try {
        $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext)
    }
    finally {
        $aes.Dispose()
    }
    return [Text.Encoding]::UTF8.GetString($plaintext)
}

$mysqlArgs = @(
    "exec",
    "-e",
    "MYSQL_PWD=$DatabasePassword",
    $MySqlContainer,
    "mysql",
    "-u$DatabaseUser",
    $Database,
    "-N",
    "-B",
    "-e",
    "SELECT value FROM system_settings WHERE system_settings.key='cloud_storage' LIMIT 1;"
)
$storageJson = (& docker @mysqlArgs | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($storageJson)) {
    throw "Failed to load cloud_storage settings."
}
$storage = $storageJson | ConvertFrom-Json
$masterKey = Get-ContainerEnvironmentValue `
    -Container $ApiContainer `
    -Name "GENERIC_IM_SETTINGS_ENCRYPTION_KEY"
if ([string]::IsNullOrWhiteSpace($masterKey)) {
    throw "Missing GENERIC_IM_SETTINGS_ENCRYPTION_KEY in $ApiContainer."
}

$accessKey = Unprotect-StorageSecret `
    -Value ([string]$storage.s3.access_key_id) `
    -MasterKey $masterKey
$secretKey = Unprotect-StorageSecret `
    -Value ([string]$storage.s3.secret_access_key) `
    -MasterKey $masterKey
$bucket = [string]$storage.s3.bucket
$region = [string]$storage.s3.region
if (
    [string]::IsNullOrWhiteSpace($accessKey) -or
    [string]::IsNullOrWhiteSpace($secretKey) -or
    [string]::IsNullOrWhiteSpace($bucket) -or
    [string]::IsNullOrWhiteSpace($region)
) {
    throw "Amazon S3 runtime settings are incomplete."
}

& docker cp $corsFile "${ApiContainer}:/tmp/s3-cors-local-media-qa.json"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy S3 CORS configuration into $ApiContainer."
}

$dockerArgs = @(
    "exec",
    "-e",
    "AWS_ACCESS_KEY_ID=$accessKey",
    "-e",
    "AWS_SECRET_ACCESS_KEY=$secretKey",
    "-e",
    "AWS_SESSION_TOKEN=",
    $ApiContainer,
    "aws",
    "s3api",
    "put-bucket-cors",
    "--bucket",
    $bucket,
    "--region",
    $region,
    "--cors-configuration",
    "file:///tmp/s3-cors-local-media-qa.json"
)
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure S3 CORS for local media QA."
}

$verifyArgs = @(
    "exec",
    "-e",
    "AWS_ACCESS_KEY_ID=$accessKey",
    "-e",
    "AWS_SECRET_ACCESS_KEY=$secretKey",
    "-e",
    "AWS_SESSION_TOKEN=",
    $ApiContainer,
    "aws",
    "s3api",
    "get-bucket-cors",
    "--bucket",
    $bucket,
    "--region",
    $region,
    "--query",
    "CORSRules[0].{Origins:AllowedOrigins,Methods:AllowedMethods,Headers:AllowedHeaders}"
)
& docker @verifyArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to verify S3 CORS for local media QA."
}
