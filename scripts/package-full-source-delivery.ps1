<#
.SYNOPSIS
生成经过敏感文件过滤的完整源码交付包。

.DESCRIPTION
从 Git 文件列表和允许目录中收集源码，排除构建产物、环境文件、签名证书、
数据库备份和发布包，再生成带时间戳的 ZIP。交付前仍需人工检查包清单和
敏感信息扫描结果，不能仅依赖扩展名过滤。

.PARAMETER OutputRoot
交付目录；脚本会在其中创建带时间戳的新目录和 ZIP。

.PARAMETER PackageName
交付目录及 ZIP 的名称前缀。

.EXAMPLE
pwsh -File scripts/package-full-source-delivery.ps1
#>
param(
    [string]$OutputRoot = "release-archives\source-delivery",
    [string]$PackageName = "GenericIM-full-source"
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputRootPath = Join-Path $repo $OutputRoot
$packageDir = Join-Path $outputRootPath "$PackageName-$stamp"
$zipPath = "$packageDir.zip"

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
    "replace_icons.cmd", "shorebird.yaml"
) | ForEach-Object { [void]$allowedRootFiles.Add($_) }

function Test-IncludeSourceFile {
    # 这是交付白名单的最终边界；新增敏感格式时必须先在此排除再打包。
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = $RelativePath.Replace('\', '/').TrimStart('/')
    if (-not $path) { return $false }

    $parts = $path.Split('/')
    $root = $parts[0]
    if ($parts.Count -eq 1) {
        if (-not $allowedRootFiles.Contains($path)) { return $false }
    }
    elseif (-not $allowedRoots.Contains($root)) {
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

New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

function Get-GitFileList {
    param([string]$ExtraArguments = "")

    $git = (Get-Command git -ErrorAction Stop).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $git
    $startInfo.Arguments = "-C `"$repo`" -c core.quotepath=false ls-files -z $ExtraArguments"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $output = $process.StandardOutput.ReadToEnd()
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Unable to enumerate the Git working tree: $errorOutput"
    }
    return @($output.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries))
}

$tracked = @(Get-GitFileList)
$untracked = @(Get-GitFileList "--others --exclude-standard")
$sourceFiles = @($tracked + $untracked | Where-Object { $_ } | Sort-Object -Unique | Where-Object { Test-IncludeSourceFile $_ })
foreach ($relative in $sourceFiles) {
    $normalized = $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $source = Join-Path $repo $normalized
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $destination = Join-Path $packageDir $normalized
    $destinationParent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$deliveryReadme = @(
    '# 通用 IM 客户完整源码交付说明',
    '',
    '本包是当前已审核工作区的源码快照，包含：',
    '',
    '- Android、iOS、Web、Windows、macOS 的 Flutter 客户端源码。',
    '- Go 后端源码、数据库迁移和配置模板。',
    '- 运营管理后台源码（admin）。',
    '- 客服管理后台源码（admin-kf）。',
    '- H5、Docker、宝塔部署和构建脚本。',
    '- 产品图片、字体和表情资源。',
    '',
    "源码基线提交：$(git -C $repo rev-parse HEAD)",
    '',
    '本包不包含生产环境凭据、私钥、云服务私密配置或项目方线上域名。源码及部署示例仅使用保留的示例域名，正式部署前必须替换为客户自有域名。',
    '',
    '安全边界：已排除 Git 历史、node_modules、构建缓存、二进制文件、数据库备份、日志、用户上传、Android 签名文件、SSL 证书、私钥和本地环境配置。',
    '',
    '开始使用前请依次阅读 README.md、SOURCE_DELIVERY.md、NOTICE.md、docs/CONFIGURATION.md 和 docs/OPERATIONS.md。'
) -join "`n"
[System.IO.File]::WriteAllText(
    (Join-Path $packageDir "SOURCE_DELIVERY_README.md"),
    ($deliveryReadme -replace "`r`n", "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

# Remove workstation-specific paths from copied documentation and QA helpers.
$pathReplacements = @(
    @{ Pattern = '(?i)C:\\Users\\[^\\]+\\AppData\\Local\\Android\\Sdk'; Value = '$env:LOCALAPPDATA\Android\Sdk' },
    @{ Pattern = '(?i)C:\\Users\\[^\\]+\\\.codex\\bin\\pwsh\.cmd'; Value = 'pwsh' },
    @{ Pattern = '(?i)[A-Z]:\\(?:[^\\\r\n]+\\)*genericim-tongba'; Value = '<PROJECT_ROOT>' },
    @{ Pattern = '(?i)C:\\Users\\[^\\\r\n]+'; Value = '<USER_HOME>' }
)
Get-ChildItem -LiteralPath $packageDir -Recurse -File | Where-Object {
    $_.Extension -match '^\.(dart|go|ts|tsx|vue|js|json|yaml|yml|md|txt|ps1|sh|xml|kt|java|gradle|kts)$'
} | ForEach-Object {
    $file = $_.FullName
    $content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    $updated = $content
    foreach ($replacement in $pathReplacements) {
        $updated = [System.Text.RegularExpressions.Regex]::Replace($updated, $replacement.Pattern, $replacement.Value)
    }
    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($file, $updated, [System.Text.UTF8Encoding]::new($false))
    }
}

$forbiddenFiles = @(Get-ChildItem -LiteralPath $packageDir -Recurse -File | Where-Object {
    $_.Name -match '(?i)^\.env($|\.)' -or
    $_.Name -match '(?i)^(google-services\.json|GoogleService-Info\.plist|key\.properties|local\.properties)$' -or
    $_.Name -match '(?i)\.(jks|keystore|p12|pfx|pem|key|apk|aab|ipa|msix|dmp|log|pid)$'
})
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden files found in delivery package:`n$($forbiddenFiles.FullName -join "`n")"
}

$forbiddenDirectories = @(Get-ChildItem -LiteralPath $packageDir -Recurse -Directory | Where-Object {
    $_.Name -match '^(\.git|node_modules|\.dart_tool|\.gradle|\.gocache|__pycache__|\.pytest_cache|build|dist|artifacts|release-archives)$'
})
if ($forbiddenDirectories.Count -gt 0) {
    throw "Generated/private directories found in delivery package:`n$($forbiddenDirectories.FullName -join "`n")"
}

$manifestLines = Get-ChildItem -LiteralPath $packageDir -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($packageDir.Length).TrimStart('\', '/').Replace('\', '/')
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    "$hash  $relative"
}
[System.IO.File]::WriteAllLines(
    (Join-Path $packageDir "MANIFEST-SHA256.txt"),
    $manifestLines,
    [System.Text.UTF8Encoding]::new($false)
)

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
    $zipPath,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    # Archive only files recorded by the manifest. IDE/Dart watchers can create
    # .dart_tool after the source copy, and those late cache files must not leak
    # into a customer delivery ZIP.
    foreach ($line in $manifestLines) {
        if ($line -notmatch '^[0-9A-F]{64}  (.+)$') {
            throw "Invalid manifest entry while creating ZIP: $line"
        }
        $relative = $Matches[1]
        $source = Join-Path $packageDir $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $source,
            $relative,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,
        (Join-Path $packageDir "MANIFEST-SHA256.txt"),
        "MANIFEST-SHA256.txt",
        [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
}
finally {
    $archive.Dispose()
}

$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
$zipSize = (Get-Item -LiteralPath $zipPath).Length
$zipHashPath = "$zipPath.sha256.txt"
[System.IO.File]::WriteAllText(
    $zipHashPath,
    "$zipHash  $(Split-Path -Leaf $zipPath)`n",
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "[OK] Full source delivery package created"
Write-Host "  Directory: $packageDir"
Write-Host "  Zip:       $zipPath"
Write-Host "  SHA file:  $zipHashPath"
Write-Host "  Files:     $((Get-ChildItem -LiteralPath $packageDir -Recurse -File).Count)"
Write-Host "  Size:      $zipSize bytes"
Write-Host "  SHA256:    $zipHash"
