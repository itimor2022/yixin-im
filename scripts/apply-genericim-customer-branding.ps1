#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SourceIcon = "<USER_HOME>\Downloads\icon.png",
    [string]$ApplicationName = "GenericIM"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = (Resolve-Path -LiteralPath $SourceIcon).Path
$brandSource = Join-Path $repoRoot "assets\branding\source\genericimlogo.png"
$manifestPath = Join-Path $repoRoot "android\app\src\main\AndroidManifest.xml"

# 在覆盖品牌源图前先验证尺寸，避免后续批量生成出不可用的多分辨率图标。
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($source)
try {
    if ($image.Width -lt 192 -or $image.Height -lt 192) {
        throw "Customer icon is too small: $($image.Width)x$($image.Height)"
    }
    if ($image.Width -ne $image.Height) {
        throw "Customer icon must be square: $($image.Width)x$($image.Height)"
    }
}
finally {
    $image.Dispose()
}

Copy-Item -LiteralPath $source -Destination $brandSource -Force
# 固定交付脚本负责把统一源图同步到各平台实际使用的资源目录。
& (Join-Path $PSScriptRoot "apply-fixed-delivery-branding.ps1")

# 只替换首个 application label，避免误改 Manifest 中其他组件的独立标签。
$manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$updatedManifest = [regex]::Replace(
    $manifest,
    'android:label="[^"]*"',
    "android:label=`"$ApplicationName`"",
    1
)
if ($updatedManifest -notmatch ('android:label="' + [regex]::Escape($ApplicationName) + '"')) {
    throw "Could not update the Android application name"
}
# 使用无 BOM UTF-8 保持 Android 工具链期望的文件编码。
[System.IO.File]::WriteAllText($manifestPath, $updatedManifest, [System.Text.UTF8Encoding]::new($false))

Write-Host "[OK] Applied customer branding"
Write-Host "  Name: $ApplicationName"
Write-Host "  Icon: $source"
