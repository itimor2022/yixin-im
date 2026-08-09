<#
.SYNOPSIS
验证账号切换后缓存、实时连接和业务 Provider 不会跨账号复用数据。

.DESCRIPTION
对账号隔离相关 Dart 文件执行格式化、静态分析和定向测试。注意：默认会
直接格式化清单中的源码文件；只需检查时应先确认工作区差异或在隔离分支运行。

.PARAMETER SkipCodegen
跳过脚本后续定义的代码生成步骤。

.PARAMETER SkipAnalyze
跳过 Flutter 静态分析。

.PARAMETER SkipTests
跳过账号隔离定向测试。

.EXAMPLE
pwsh -File scripts/validate-account-isolation-p0.ps1 -SkipCodegen
#>
[CmdletBinding()]
param(
    [switch]$SkipCodegen,
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
    'lib/app.dart',
    'lib/core/services/account_session_coordinator.dart',
    'lib/core/services/api/auth_service.dart',
    'lib/core/services/api/api_client.dart',
    'lib/core/services/api/websocket_service.dart',
    'lib/core/services/offline_message_queue.dart',
    'lib/core/services/notification_sound_service.dart',
    'lib/core/services/push_notification_service.dart',
    'lib/core/services/storage/models/user_model.dart',
    'lib/core/services/storage/models/user_model_web.dart',
    'lib/features/chat/providers/folder_provider.dart',
    'lib/features/chat/providers/chat_provider.dart',
    'lib/features/chat/providers/message_provider.dart',
    'lib/features/chat/services/emoji_store_service.dart',
    'lib/features/chat/services/favorite_message_service.dart',
    'lib/features/chat/widgets/message_bubble.dart',
    'lib/features/chat/widgets/message_bubble_wallet.dart',
    'lib/features/chat/widgets/message_context_menu.dart',
    'lib/features/contacts/providers/contact_provider.dart',
    'lib/features/moments/pages/moments_page.dart',
    'lib/features/moments/providers/moment_provider.dart',
    'lib/features/settings/pages/privacy_settings_page.dart',
    'lib/features/settings/pages/settings_page.dart',
    'lib/features/settings/pages/stickers_page.dart',
    'lib/features/vip/providers/vip_provider.dart',
    'lib/features/wallet/providers/wallet_provider.dart',
    'test/core/services/account_session_coordinator_test.dart',
    'test/core/services/offline_message_account_test.dart',
    'test/features/chat/favorite_message_account_isolation_test.dart',
    'test/features/contacts/contact_refresh_after_add_test.dart',
    'integration_test/ios_chat_ui_smoke_test.dart'
)

Push-Location $repoRoot
try {
    & $dart format @files
    if ($LASTEXITCODE -ne 0) { throw 'dart format failed' }

    if (-not $SkipCodegen) {
        & $flutter pub run build_runner build --delete-conflicting-outputs
        if ($LASTEXITCODE -ne 0) { throw 'Isar code generation failed' }
    }

    if (-not $SkipAnalyze) {
        & $flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    }

    if (-not $SkipTests) {
        $tests = @(
            'test/core/services/account_session_coordinator_test.dart',
            'test/core/services/offline_message_account_test.dart',
            'test/features/chat/favorite_message_account_isolation_test.dart'
        )
        & $flutter test @tests
        if ($LASTEXITCODE -ne 0) { throw 'P0 account isolation tests failed' }
    }
}
finally {
    Pop-Location
}
