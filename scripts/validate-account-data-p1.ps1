<#
.SYNOPSIS
验证账号退出/删除后的本地数据清理和崩溃恢复流程。

.DESCRIPTION
格式化账号数据清理相关源码，随后执行 Flutter analyze 和定向测试。
脚本会修改被 dart format 触达的文件，脏工作区中运行前必须先检查差异。

.PARAMETER SkipAnalyze
跳过 Flutter 静态分析。

.PARAMETER SkipTests
跳过账号数据清理定向测试。

.EXAMPLE
pwsh -File scripts/validate-account-data-p1.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipAnalyze,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$flutter = 'D:\flutter\bin\flutter.bat'
$dart = 'D:\flutter\bin\dart.bat'

if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter executable not found: $flutter"
}

$files = @(
    'lib/core/services/account_data_cleanup_service.dart',
    'lib/core/services/account_session_coordinator.dart',
    'lib/core/services/api/auth_service.dart',
    'lib/core/services/e2ee/e2ee_service.dart',
    'lib/core/services/media_cache_manager.dart',
    'lib/features/chat/pages/chat_detail_page.dart',
    'lib/features/chat/pages/chat_detail_desktop_file_actions.dart',
    'lib/features/chat/services/emoji_store_service.dart',
    'lib/features/chat/widgets/message_bubble_file.dart',
    'lib/features/settings/pages/data_storage_page.dart',
    'lib/features/settings/pages/privacy_settings_page.dart',
    'test/core/services/account_data_cleanup_service_test.dart'
)

Push-Location $repoRoot
try {
    & $dart format @files
    if ($LASTEXITCODE -ne 0) { throw 'dart format failed' }

    if (-not $SkipAnalyze) {
        & $flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    }

    if (-not $SkipTests) {
        $tests = @(
            'test/core/services/account_data_cleanup_service_test.dart',
            'test/core/services/account_session_coordinator_test.dart',
            'test/core/services/offline_message_account_test.dart',
            'test/features/chat/favorite_message_account_isolation_test.dart'
        )
        & $flutter test @tests
        if ($LASTEXITCODE -ne 0) { throw 'P1 account data tests failed' }
    }
}
finally {
    Pop-Location
}
