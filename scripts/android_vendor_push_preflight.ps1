<#
.SYNOPSIS
检查 Android 厂商推送配置是否完整且来源符合预期。

.DESCRIPTION
按 gradle.properties、环境变量、gradle.vendor.local.properties 的优先级
解析各厂商开关和凭据，只输出存在性与来源，不应打印完整密钥。可选 Compile
会触发 Android 编译验证，但不会向设备发送推送。

.PARAMETER Compile
配置检查通过后继续执行 Android 编译验证。

.PARAMETER ForceVendorEnabled
即使配置未显式启用也按启用状态检查全部必需字段，用于上线前预检。

.EXAMPLE
pwsh -File scripts/android_vendor_push_preflight.ps1 -ForceVendorEnabled
#>
param(
    [switch]$Compile,
    [switch]$ForceVendorEnabled
)

$ErrorActionPreference = "Stop"

function Read-PropertiesFile {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line.StartsWith("#") -or $line.StartsWith("!")) { return }

        $idx = $line.IndexOf("=")
        if ($idx -lt 0) {
            $idx = $line.IndexOf(":")
        }
        if ($idx -lt 0) { return }

        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $value
        }
    }

    return $map
}

function Resolve-Prop {
    # 优先级与 Gradle 集成保持一致，返回 Source 便于定位误用的本地配置。
    param(
        [string]$Name,
        [hashtable]$GradleProps,
        [hashtable]$LocalProps
    )

    if ($GradleProps.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace($GradleProps[$Name])) {
        return @{ Value = $GradleProps[$Name]; Source = "gradle.properties" }
    }

    $envValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return @{ Value = $envValue.Trim(); Source = "env" }
    }

    if ($LocalProps.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace($LocalProps[$Name])) {
        return @{ Value = $LocalProps[$Name]; Source = "gradle.vendor.local.properties" }
    }

    return @{ Value = ""; Source = "missing" }
}

function To-Bool {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $false }
    $v = $Raw.Trim().ToLowerInvariant()
    return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on")
}

function Read-ApplicationIdFromGradle {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }
    $content = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($content, 'applicationId\s*=\s*"([^"]+)"')
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return ""
}

function Get-GoogleServicesInfo {
    param(
        [string]$Path,
        [string]$ApplicationId
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            Exists        = $false
            ProjectId     = ""
            MobileSdkAppId = ""
            PackageName   = ""
            MatchedClient = $false
            ParseError    = ""
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $json = $raw | ConvertFrom-Json
        $projectId = [string]$json.project_info.project_id
        $clients = @($json.client)

        $matchedClient = $null
        if (-not [string]::IsNullOrWhiteSpace($ApplicationId)) {
            foreach ($client in $clients) {
                $pkg = [string]$client.client_info.android_client_info.package_name
                if ($pkg -eq $ApplicationId) {
                    $matchedClient = $client
                    break
                }
            }
        }
        if ($null -eq $matchedClient -and $clients.Count -gt 0) {
            $matchedClient = $clients[0]
        }

        $packageName = ""
        $mobileSdkAppId = ""
        if ($null -ne $matchedClient) {
            $packageName = [string]$matchedClient.client_info.android_client_info.package_name
            $mobileSdkAppId = [string]$matchedClient.client_info.mobilesdk_app_id
        }

        return @{
            Exists         = $true
            ProjectId      = $projectId.Trim()
            MobileSdkAppId = $mobileSdkAppId.Trim()
            PackageName    = $packageName.Trim()
            MatchedClient  = ($null -ne $matchedClient -and -not [string]::IsNullOrWhiteSpace($ApplicationId) -and $packageName -eq $ApplicationId)
            ParseError     = ""
        }
    } catch {
        return @{
            Exists         = $true
            ProjectId      = ""
            MobileSdkAppId = ""
            PackageName    = ""
            MatchedClient  = $false
            ParseError     = $_.Exception.Message
        }
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$androidDir = Join-Path $repoRoot "android"
$gradlePropsPath = Join-Path $androidDir "gradle.properties"
$localPropsPath = Join-Path $androidDir "gradle.vendor.local.properties"
$appGradlePath = Join-Path $androidDir "app/build.gradle.kts"
$googleServicesPath = Join-Path $androidDir "app/google-services.json"

$gradleProps = Read-PropertiesFile -Path $gradlePropsPath
$localProps = Read-PropertiesFile -Path $localPropsPath

$requiredWhenEnabled = @(
    "HMS_PUSH_SDK",
    "XIAOMI_PUSH_SDK",
    "OPPO_PUSH_SDK",
    "PUSH_HMS_APP_ID",
    "PUSH_XIAOMI_APP_ID",
    "PUSH_XIAOMI_APP_KEY",
    "PUSH_OPPO_APP_KEY",
    "PUSH_OPPO_APP_SECRET"
)

$optional = @(
    "XIAOMI_PUSH_MAVEN_REPO",
    "OPPO_PUSH_MAVEN_REPO"
)

$enableInfo = Resolve-Prop -Name "ENABLE_VENDOR_PUSH_SDK" -GradleProps $gradleProps -LocalProps $localProps
$vendorEnabled = To-Bool $enableInfo.Value
if ($ForceVendorEnabled) {
    $vendorEnabled = $true
}

Write-Host "[VendorPush] repo: $repoRoot"
Write-Host "[VendorPush] ENABLE_VENDOR_PUSH_SDK = $vendorEnabled (value='$($enableInfo.Value)', source=$($enableInfo.Source))"
Write-Host ""

$applicationId = Read-ApplicationIdFromGradle -Path $appGradlePath
$gsInfo = Get-GoogleServicesInfo -Path $googleServicesPath -ApplicationId $applicationId

Write-Host "[FCM] applicationId = $applicationId"
if (-not $gsInfo.Exists) {
    Write-Host "[FCM] google-services.json = MISSING ($googleServicesPath)"
} elseif (-not [string]::IsNullOrWhiteSpace($gsInfo.ParseError)) {
    Write-Host "[FCM] google-services.json = INVALID_JSON ($($gsInfo.ParseError))"
} else {
    Write-Host "[FCM] google-services.json = FOUND"
    Write-Host "[FCM] project_id = $($gsInfo.ProjectId)"
    Write-Host "[FCM] mobilesdk_app_id = $($gsInfo.MobileSdkAppId)"
    Write-Host "[FCM] package_name = $($gsInfo.PackageName)"

    if (-not [string]::IsNullOrWhiteSpace($applicationId) -and $gsInfo.PackageName -ne $applicationId) {
        Write-Host "[FCM][WARN] package_name does not match applicationId."
    }
}
Write-Host ""

$rows = @()
foreach ($key in ($requiredWhenEnabled + $optional)) {
    $info = Resolve-Prop -Name $key -GradleProps $gradleProps -LocalProps $localProps
    $rows += [PSCustomObject]@{
        Key    = $key
        Status = $(if ([string]::IsNullOrWhiteSpace($info.Value)) { "MISSING" } else { "OK" })
        Source = $info.Source
    }
}

$rows | Format-Table -AutoSize | Out-String | Write-Host

$missingRequired = @()
if ($vendorEnabled) {
    foreach ($key in $requiredWhenEnabled) {
        $info = Resolve-Prop -Name $key -GradleProps $gradleProps -LocalProps $localProps
        if ([string]::IsNullOrWhiteSpace($info.Value)) {
            $missingRequired += $key
        }
    }
}

if ($vendorEnabled -and $missingRequired.Count -gt 0) {
    Write-Error ("[VendorPush] Missing required properties when vendor SDK is enabled: " + ($missingRequired -join ", "))
    exit 1
}

if ($Compile) {
    Write-Host "[VendorPush] compile check: .\gradlew.bat app:compileDebugKotlin"
    Push-Location $androidDir
    try {
        & .\gradlew.bat app:compileDebugKotlin
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle compile check failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Write-Host "[VendorPush] preflight check passed."
