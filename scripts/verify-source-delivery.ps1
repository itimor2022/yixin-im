<#
.SYNOPSIS
Checks that a GenericIM source tree is suitable for customer handoff.

.DESCRIPTION
Validates required handoff documents, rejects private/generated files and
scans source text for common private-key and credential markers. The command
does not alter the repository.

.EXAMPLE
pwsh -File scripts/verify-source-delivery.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $Root

$requiredFiles = @(
    "README.md",
    "NOTICE.md",
    "SOURCE_DELIVERY.md",
    "pubspec.yaml",
    "pubspec.lock",
    "compose.yaml",
    "backend/go.mod",
    "docs/ARCHITECTURE.md",
    "docs/CONFIGURATION.md",
    "docs/SECURITY.md",
    "docs/OPERATIONS.md"
)

$missing = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) })
if ($missing.Count -gt 0) {
    throw "Required delivery files are missing:`n$($missing -join "`n")"
}

$allowedRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    ".vscode", "admin", "admin-kf", "android", "assets", "backend", "docker", "docs",
    "h5", "integration_test", "ios", "lib", "macos", "scripts", "test", "third_party",
    "web", "windows"
) | ForEach-Object { [void]$allowedRoots.Add($_) }

$allowedRootFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    ".dockerignore", ".gitignore", "analysis_options.yaml", "compose.yaml",
    "deploy-online-prebuilt.sh", "deploy-online-update.sh", "deploy.sh", "pubspec.lock",
    "pubspec.yaml", "README.md", "NOTICE.md", "SOURCE_DELIVERY.md",
    "SOURCE_DELIVERY_README.md", "SOURCE_MANIFEST.sha256", "MANIFEST-SHA256.txt",
    "replace_icons.cmd", "shorebird.yaml"
) | ForEach-Object { [void]$allowedRootFiles.Add($_) }

function Test-IncludeDeliveryFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = $RelativePath.Replace('\', '/').TrimStart('/')
    if (-not $path) { return $false }

    $parts = $path.Split('/')
    $rootName = $parts[0]
    if ($parts.Count -eq 1) {
        if (-not $allowedRootFiles.Contains($path)) { return $false }
    }
    elseif (-not $allowedRoots.Contains($rootName)) {
        return $false
    }

    if ($path -match '(^|/)(node_modules|dist|build|\.dart_tool|\.gradle|\.idea|\.cache|\.gocache|__pycache__|\.pytest_cache|coverage)(/|$)') { return $false }
    if ($path -match '(^|/)(artifacts|release-archives)(/|$)') { return $false }
    if ($path -match '^uploads/') { return $false }
    if ($path -match '^backend/uploads/' -and $path -notmatch '^backend/uploads/stickers/') { return $false }
    if ($path -ieq 'docs/project/ROOT_ORGANIZATION.md') { return $false }
    if ($path -match '(^|/)(\.env|\.env\.[^/]+)$' -and $path -notmatch '\.(example|sample)$') { return $false }
    if ($path -match '(?i)(^|/)(google-services\.json|GoogleService-Info\.plist|key\.properties|local\.properties)$') { return $false }
    if ($path -match '(?i)\.(jks|keystore|p12|pfx|pem|key|apk|aab|ipa|msix|dmp|log|pid)$') { return $false }
    if ($path -match '(?i)(^|/)(dump|backup)[^/]*\.(sql|db|sqlite|sqlite3)$') { return $false }
    if ($path -match '(?i)\.(zip|tar|tgz|gz|7z|rar)$') { return $false }
    return $true
}

$allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
    $relative = $_.FullName.Substring($Root.Length).TrimStart("\", "/")
    Test-IncludeDeliveryFile $relative
})

$forbiddenNamePattern = "(?i)(^|[\\/])(\.env($|\.)|google-services\.json|GoogleService-Info\.plist|key\.properties|local\.properties|.*\.(jks|keystore|p12|pfx|pem|key|apk|aab|ipa|msix|dmp|log|pid))$"
$forbiddenFiles = @($allFiles | Where-Object { $_.FullName.Substring($Root.Length).TrimStart("\", "/") -match $forbiddenNamePattern })
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden delivery files found:`n$($forbiddenFiles.FullName -join "`n")"
}

$textExtensions = @(".dart", ".go", ".ts", ".tsx", ".vue", ".js", ".json", ".yaml", ".yml", ".md", ".ps1", ".sh", ".xml", ".kt", ".java", ".gradle", ".kts")
$textFiles = @($allFiles | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() })
$sensitivePatterns = @(
    # Require a plausible encoded body so documentation/test placeholders do not fail the scan.
    "-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----[\s\\n]+[A-Za-z0-9+/=]{40,}",
    "(?i)aws_secret_access_key\s*[:=]\s*['""]?[A-Za-z0-9\/+=]{16,}",
    "(?i)(client_secret|api_secret|private_key)\s*[:=]\s*['""][^'""]{12,}['""]"
)
$findings = @()
foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($content)) { continue }
    foreach ($pattern in $sensitivePatterns) {
        if ($content -match $pattern) {
            $relative = $file.FullName.Substring($Root.Length).TrimStart("\", "/")
            $findings += "$relative matches $pattern"
        }
    }
}
if ($findings.Count -gt 0) {
    throw "Possible secrets or private keys found. Review before delivery:`n$($findings -join "`n")"
}

$notice = Get-Content -LiteralPath (Join-Path $Root "NOTICE.md") -Raw
if ($notice -notmatch "neutral, rebrandable" -or $notice -match ('t' + 'g@')) {
    throw "NOTICE.md is not the expected neutral delivery notice."
}

Write-Host "[OK] Required delivery documents present: $($requiredFiles.Count)"
Write-Host "[OK] Delivery whitelist excludes private/generated files"
Write-Host "[OK] No common private-key or credential markers found"
Write-Host "[OK] NOTICE.md contains neutral delivery guidance"
Write-Host "[OK] Source delivery verification passed"
