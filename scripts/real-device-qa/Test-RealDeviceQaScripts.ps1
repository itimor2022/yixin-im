$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# 对整套 QA 脚本做静态语法巡检，避免某个冷门用例直到真机执行时才暴露解析错误。
$failed = $false
Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -gt 0) {
        $failed = $true
        foreach ($parseError in $errors) {
            Write-Error ("{0}: {1}" -f $_.Name, $parseError.Message)
        }
    } else {
        Write-Host ("OK {0}" -f $_.Name)
    }
}

# tasks.json 是真机工作流的统一入口，同时验证它仍是合法 JSON。
$tasksPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) ".vscode\tasks.json"
Get-Content -LiteralPath $tasksPath -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null
Write-Host "OK .vscode/tasks.json"

if ($failed) { exit 1 }
