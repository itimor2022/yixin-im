// 文件用途：定义应用根组件，装配全局主题、路由、本地化以及应用级生命周期处理。
// 核心逻辑：在根组件中装配全局 Provider、主题、本地化和路由，并监听应用生命周期以协调后台任务、通知与会话状态。
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_preset.dart';
import 'core/config/runtime_flags.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/i18n/app_localizations.dart';
import 'core/services/call_service.dart';
import 'core/services/app_lock_service.dart';
import 'core/services/background_service.dart';
import 'core/services/background_keep_alive_policy.dart';
import 'core/services/app_badge_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/notification_sound_service.dart';
import 'core/services/android_message_notification_service.dart';
import 'core/services/api/websocket_service.dart';
import 'core/services/api/api_client.dart' show apiClientProvider;
import 'core/services/desktop_notification_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/desktop/tray_service.dart';
import 'core/services/api/auth_service.dart';
import 'core/services/api/chat_service.dart' hide ChatType;
import 'core/services/api/meeting_service.dart';
import 'core/services/offline_message_queue.dart';
import 'core/services/account_session_coordinator.dart';
import 'core/services/force_logout_notice.dart';
import 'core/services/new_device_login_notice.dart';
import 'core/services/performance_trace_service.dart';
import 'core/services/storage/isar_service.dart';
import 'core/services/storage/models/message_model.dart'
    if (dart.library.js_interop) 'core/services/storage/models/message_model_web.dart';
import 'core/services/device_service.dart';
import 'core/services/time_zone_refresh_service.dart';
import 'core/utils/platform_utils.dart';
import 'core/utils/browser_title.dart';
import 'core/services/api/system_settings_service.dart';
import 'features/call/widgets/call_overlay.dart';
import 'features/meeting/widgets/meeting_overlay.dart';
import 'features/moments/providers/moment_provider.dart';
import 'features/settings/pages/app_lock_gate_page.dart';
import 'features/call/pages/incoming_call_page.dart';
import 'features/call/pages/call_page.dart';
import 'features/chat/pages/chat_detail_page.dart' show ChatType;
import 'features/chat/providers/chat_provider.dart';
import 'features/chat/providers/message_provider.dart';
import 'features/discover/pages/discover_page.dart';
import 'core/services/meeting_session_service.dart';
import 'core/services/voice_record_service.dart';
import 'features/chat/providers/folder_provider.dart';
import 'features/chat/services/emoji_store_service.dart';
import 'features/chat/widgets/message_bubble.dart' show WalletStatusCache;
import 'features/contacts/providers/contact_provider.dart';
import 'features/settings/pages/privacy_settings_page.dart';
import 'features/settings/pages/devices_page.dart';
import 'features/settings/pages/settings_page.dart' show deviceCountProvider;
import 'features/vip/providers/vip_provider.dart';
import 'features/wallet/providers/wallet_provider.dart';

// 关键声明：根应用状态对象负责把全局监听器绑定到 Flutter 生命周期，退出时必须按相反顺序解除订阅并释放资源。
class GenericIMApp extends ConsumerStatefulWidget {
  const GenericIMApp({super.key});

  @override
  ConsumerState<GenericIMApp> createState() => _GenericIMAppState();
}

class _GenericIMAppState extends ConsumerState<GenericIMApp>
    with WidgetsBindingObserver {
  bool _hasNavigatedToCallPage = false;
  CallState? _lastCallState;
  bool _pushRegistered = false;
  String? _discoverItemsUpdatedHandlerId;
  String? _systemSettingsUpdatedHandlerId;
  String? _announcementHandlerId;
  String? _forceLogoutHandlerId;
  String? _newDeviceLoginHandlerId;
  String? _meetingInviteHandlerId;
  String? _meetingJoinRequestHandlerId;
  String? _meetingEndedHandlerId;
  String? _meetingTitleUpdatedHandlerId;
  ProviderSubscription<AsyncValue<SystemSettings>>? _systemSettingsTitleSub;
  ProviderSubscription<AsyncValue<SystemSettings>>? _keepAliveSettingsSub;
  ProviderSubscription<AuthState>? _keepAliveAuthSub;
  ProviderSubscription<AuthState>? _missedMessageSyncAuthSub;
  ProviderSubscription<AuthState>? _appLockAuthSub;
  ProviderSubscription<AuthState>? _loginNoticeAuthSub;
  ProviderSubscription<AppLanguage>? _trayLanguageSub;
  ProviderSubscription<AsyncValue<SystemSettings>>? _traySettingsSub;
  ProviderSubscription<AccountSessionState>? _accountSessionSub;
  StreamSubscription<String>? _deepLinkSubscription;
  late final WebSocketService _webSocketService;
  String? _lastHandledDeepLink;
  final Set<String> _shownMeetingInviteIds = {};
  final Set<String> _shownMeetingJoinRequestIds = {};
  final Set<String> _shownNewDeviceLoginEventIds = {};
  Duration _lastTimeZoneOffset = DateTime.now().timeZoneOffset;

  Map<String, dynamic> _asStringKeyMap(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      try {
        return _asStringKeyMap(jsonDecode(value));
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _normalizePushPayload(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{...data};
    final nested = _asStringKeyMap(data['data']);
    if (nested.isNotEmpty) {
      normalized.addAll(nested);
    }

    final aps = _asStringKeyMap(data['aps']);
    final alert = _asStringKeyMap(aps['alert']);
    if (alert.isNotEmpty) {
      normalized['title'] ??= alert['title'];
      normalized['body'] ??= alert['body'];
    }
    return normalized;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  AccountContext? _captureActiveAccount() {
    final session = ref.read(accountSessionCoordinatorProvider);
    return session.isActive ? session.context : null;
  }

  bool _isCurrentAccount(AccountContext context) {
    return ref
        .read(accountSessionCoordinatorProvider.notifier)
        .isCurrent(context);
  }

  String _pushPayloadSummary(Map<String, dynamic> data) {
    final payload = _normalizePushPayload(data);
    final keys = payload.keys.map((key) => key.toString()).toList()..sort();
    final type = payload['type']?.toString() ?? '-';
    return 'type=$type keys=${keys.join(',')}';
  }

  Map<String, dynamic> _incomingCallDataFromPush(Map<String, dynamic> data) {
    final isVideoPush = data['is_video'] == true ||
        data['is_video']?.toString().toLowerCase() == 'true';
    final pushCallType = data['call_type']?.toString() == 'video' || isVideoPush
        ? 'video'
        : 'voice';
    return <String, dynamic>{
      'type': 'incoming_call',
      'call_id': data['call_id'] ?? data['callId'],
      'caller_name': data['caller_name'] ?? data['title'] ?? '',
      'caller_avatar': data['caller_avatar'] ?? '',
      'call_type': pushCallType,
      'channel_name': data['channel_name'] ?? data['room_name'] ?? '',
      'room_name': data['room_name'] ?? data['channel_name'] ?? '',
      'provider': data['provider'] ?? data['rtc_provider'] ?? '',
      'rtc_provider': data['rtc_provider'] ?? data['provider'] ?? '',
      'server_url': data['server_url'] ?? data['livekit_server_url'] ?? '',
      'livekit_server_url':
          data['livekit_server_url'] ?? data['server_url'] ?? '',
      'caller_id': data['caller_id'] ?? '',
    };
  }

  String _localizedText({
    AppLocalizations? l10n,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    final locale =
        (l10n ?? AppLocalizations(ref.read(languageProvider))).language;
    switch (locale.code) {
      case 'en':
        return en;
      case 'zh_TW':
        return zhTW ?? zhCN;
      default:
        return zhCN;
    }
  }

  void _runStartupTask(String name, VoidCallback action) {
    try {
      final span = PerformanceTraceService.start('app_startup.$name');
      action();
      span.finish();
    } catch (e) {
      debugPrint('[App] $name error: $e');
    }
  }

  void _setupInitialBindingsAfterFirstFrame() {
    _runStartupTask('setup_call_callbacks', _setupCallCallbacks);
    _runStartupTask('setup_unread_badge_sync', _setupUnreadBadgeSync);
    _runStartupTask(
        'setup_keep_alive_settings_sync', _setupKeepAliveSettingsSync);
    _runStartupTask('setup_missed_message_sync', _setupMissedMessageSync);
    _runStartupTask('setup_app_lock_sync', _setupAppLockSync);
    _runStartupTask('setup_login_notice', _setupLoginNotice);
    _runStartupTask('setup_force_logout_handler', _setupForceLogoutHandler);
    _runStartupTask(
      'setup_new_device_login_handler',
      _setupNewDeviceLoginHandler,
    );
    _runStartupTask(
      'setup_system_settings_updated_handler',
      _setupSystemSettingsUpdatedHandler,
    );
    _runStartupTask(
      'bind_api_token_refresh_to_websocket',
      _bindApiTokenRefreshToWebSocket,
    );
    _runStartupTask('bind_phone_required_redirect', _bindPhoneRequiredRedirect);
  }

  void _setupKeepAliveSettingsSync() {
    if (!PlatformUtils.supportsBackgroundService) return;

    _keepAliveSettingsSub?.close();
    _keepAliveAuthSub?.close();

    _keepAliveAuthSub = ref.listenManual<AuthState>(
      authServiceProvider,
      (previous, next) {
        if (next.status == AuthStatus.authenticated &&
            previous?.status != AuthStatus.authenticated) {
          _ensureForceKeepAliveRunningIfAuthenticated(
            reason: 'force_keep_alive_auth_ready',
          );
        }
      },
      fireImmediately: true,
    );

    _keepAliveSettingsSub = ref.listenManual<AsyncValue<SystemSettings>>(
      systemSettingsProvider,
      (previous, next) {
        final previousEnabled = previous?.valueOrNull?.forceKeepAliveEnabled;
        final nextEnabled = next.valueOrNull?.forceKeepAliveEnabled;
        if (nextEnabled == null || previousEnabled == nextEnabled) return;

        final mode = nextEnabled
            ? BackgroundKeepAliveMode.enhanced
            : BackgroundKeepAliveMode.balanced;
        unawaited(BackgroundKeepAlivePolicyStore.instance.save(mode));
        BackgroundService.instance.applyPolicy(mode);
        if (nextEnabled) {
          _ensureForceKeepAliveRunningIfAuthenticated(
            reason: 'force_keep_alive_enabled',
          );
        }
      },
      fireImmediately: true,
    );
  }

  void _ensureForceKeepAliveRunningIfAuthenticated({required String reason}) {
    if (!PlatformUtils.supportsBackgroundService) return;

    final authState = ref.read(authServiceProvider);
    if (authState.status != AuthStatus.authenticated ||
        authState.token == null) {
      return;
    }
    if (BackgroundKeepAlivePolicyStore.instance.mode !=
        BackgroundKeepAliveMode.enhanced) {
      return;
    }

    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        final currentAuthState = ref.read(authServiceProvider);
        if (currentAuthState.status != AuthStatus.authenticated ||
            currentAuthState.token == null) {
          return;
        }
        if (BackgroundKeepAlivePolicyStore.instance.mode !=
            BackgroundKeepAliveMode.enhanced) {
          return;
        }
        await BackgroundService.instance.ensureRunning(reason: reason);
      }),
    );
  }

  void _setupMissedMessageSync() {
    _missedMessageSyncAuthSub?.close();
    _missedMessageSyncAuthSub = ref.listenManual<AuthState>(
      authServiceProvider,
      (previous, next) {
        if (next.status != AuthStatus.authenticated || next.token == null) {
          return;
        }
        if (previous?.status == AuthStatus.authenticated) {
          return;
        }

        _scheduleMissedMessageSync(
          reason: previous == null ? 'startup_auth_ready' : 'login_auth_ready',
          delay: const Duration(milliseconds: 900),
          force: true,
        );
      },
      fireImmediately: true,
    );
  }

  void _setupAppLockSync() {
    _appLockAuthSub?.close();
    _appLockAuthSub = ref.listenManual<AuthState>(
      authServiceProvider,
      (previous, next) {
        if (next.status == AuthStatus.authenticated) {
          final appLockState = ref.read(appLockServiceProvider);
          if (!shouldInitializeAppLockForAuthTransition(
            previousStatus: previous?.status,
            nextStatus: next.status,
            initialized: appLockState.initialized,
          )) {
            return;
          }
          final lockOnStart = previous?.status != AuthStatus.authenticated;
          unawaited(
            ref
                .read(appLockServiceProvider.notifier)
                .initialize(lockOnStart: lockOnStart),
          );
          return;
        }

        if (next.status == AuthStatus.unauthenticated) {
          unawaited(ref.read(appLockServiceProvider.notifier).reset());
        }
      },
      fireImmediately: true,
    );
  }

  void _setupLoginNotice() {
    _loginNoticeAuthSub?.close();
    _loginNoticeAuthSub = ref.listenManual<AuthState>(
      authServiceProvider,
      (previous, next) {
        final notice = next.loginNotice;
        if (next.status != AuthStatus.authenticated || notice == null) return;
        if (identical(previous?.loginNotice, notice)) return;

        ref.read(authServiceProvider.notifier).clearLoginNotice();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final context = rootNavigatorKey.currentContext;
          if (context == null || !context.mounted) return;
          final l10n = AppLocalizations.of(context);
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(_localizedText(
                l10n: l10n,
                zhCN: '多端登录提醒',
                zhTW: '多端登入提醒',
                en: 'Multiple Devices Signed In',
              )),
              content: Text(_localizedText(
                l10n: l10n,
                zhCN:
                    '当前账号还在 ${notice.otherActiveDeviceCount} 台其他设备上保持登录。系统允许多端共存；可前往“设置 > 设备管理”检查并下线陌生设备。',
                zhTW:
                    '目前帳號仍在 ${notice.otherActiveDeviceCount} 台其他裝置上保持登入。系統允許多端共存；可前往「設定 > 裝置管理」檢查並下線陌生裝置。',
                en: 'This account is still signed in on ${notice.otherActiveDeviceCount} other device(s). Multiple devices may coexist. Review and remove unfamiliar devices in Settings > Devices.',
              )),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_localizedText(
                    l10n: l10n,
                    zhCN: '我知道了',
                    zhTW: '我知道了',
                    en: 'Got it',
                  )),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _scheduleMissedMessageSync({
    required String reason,
    Duration delay = Duration.zero,
    bool force = false,
  }) {
    unawaited(
      Future<void>.delayed(delay, () async {
        if (!mounted) return;
        final authState = ref.read(authServiceProvider);
        if (authState.status != AuthStatus.authenticated ||
            authState.token == null) {
          return;
        }
        await ref.read(chatListProvider.notifier).syncMissedMessages(
              reason: reason,
              force: force,
            );
      }).catchError((Object error) {
        debugPrint('[App] Missed message sync failed ($reason): $error');
      }),
    );
  }

  void _setupDeferredBindingsAfterFirstFrame() {
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _runStartupTask('bind_offline_message_queue', _bindOfflineMessageQueue);
      _runStartupTask('setup_announcement_handler', _setupAnnouncementHandler);
    });

    Future<void>.delayed(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      _runStartupTask(
        'setup_meeting_join_request_handler',
        _setupMeetingJoinRequestHandler,
      );
      _runStartupTask(
          'setup_meeting_state_handlers', _setupMeetingStateHandlers);
    });

    Future<void>.delayed(const Duration(milliseconds: 5000), () {
      if (!mounted) return;
      _runStartupTask('setup_discover_sync', _setupDiscoverSync);
      _runStartupTask('setup_push_notifications', _setupPushNotifications);
      _runStartupTask(
          'setup_meeting_invite_handler', _setupMeetingInviteHandler);
      _runStartupTask('setup_browser_title_sync', _setupBrowserTitleSync);
      _runStartupTask(
          'setup_tray_presentation_sync', _setupTrayPresentationSync);
    });
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    // Cache provider dependencies before dispose, when ConsumerState.ref is valid.
    _webSocketService = ref.read(webSocketServiceProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    CallService.navigatorKey = rootNavigatorKey;
    _setupAccountSessionBoundary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformanceTraceService.mark('app_first_frame_bindings_start');
      _setupInitialBindingsAfterFirstFrame();
      _setupDeferredBindingsAfterFirstFrame();
      _setupDeepLinks();
    });
  }

  void _setupAccountSessionBoundary() {
    _accountSessionSub?.close();
    _accountSessionSub = ref.listenManual<AccountSessionState>(
      accountSessionCoordinatorProvider,
      (previous, next) {
        final previousAccountId = previous?.accountId ?? '';
        if (next.isActive &&
            previous?.isActive == true &&
            previousAccountId.isNotEmpty &&
            previousAccountId != next.accountId) {
          _teardownAccountRuntime(previousAccountId);
        }

        if (next.isActive) {
          EmojiStoreService.activateAccount(next.accountId);
          WalletStatusCache.instance.activateAccount(next.accountId);
          unawaited(OfflineMessageQueue().activateAccount(next.accountId));
          return;
        }

        final exitingAccountId =
            next.accountId.isNotEmpty ? next.accountId : previousAccountId;
        if (exitingAccountId.isEmpty) return;
        _teardownAccountRuntime(exitingAccountId);
      },
      fireImmediately: true,
    );
  }

  void _teardownAccountRuntime(String accountId) {
    EmojiStoreService.freezeAccount(accountId);
    WalletStatusCache.instance.freezeAccount(accountId);
    unawaited(OfflineMessageQueue().freezeAccount(accountId));
    ref.read(pushNotificationServiceProvider).quarantinePendingInteractions();
    _pushRegistered = false;
    _shownMeetingInviteIds.clear();
    _shownMeetingJoinRequestIds.clear();

    ref.invalidate(chatListProvider);
    ref.invalidate(messageListProvider);
    ref.invalidate(contactListProvider);
    ref.invalidate(walletProvider);
    ref.invalidate(vipStatusProvider);
    ref.invalidate(vipOrdersProvider);
    ref.invalidate(deviceCountProvider);
    ref.invalidate(privacySettingsProvider);
    ref.invalidate(folderProvider);
    ref.invalidate(momentProvider);
    ref.read(meetingSessionProvider.notifier).clear();
    unawaited(ref.read(voiceRecordProvider.notifier).cancelRecording());
    unawaited(
      ref
          .read(callServiceProvider.notifier)
          .endCall(reason: 'account_exit', notifyServer: false),
    );
    _syncUnreadBadgeCount(0);
  }

  void _setupDeepLinks() {
    if (kIsWeb) return;
    final service = DeepLinkService.instance;
    _deepLinkSubscription?.cancel();
    _deepLinkSubscription = service.links.listen(_handleDeepLink);
    unawaited(service.initialize());
  }

  void _handleDeepLink(String rawLink) {
    if (!mounted || rawLink == _lastHandledDeepLink) return;
    final route = appRouteFromExternalLink(rawLink);
    if (route == null) return;
    _lastHandledDeepLink = rawLink;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appRouterProvider).go(route);
    });
  }

  void _setupBrowserTitleSync() {
    if (!PlatformUtils.isWeb) {
      return;
    }

    _applyBrowserTitle(defaultAppDisplayName());

    final cachedSettings =
        ref.read(systemSettingsServiceProvider).cachedSettings;
    if (cachedSettings != null) {
      _applyBrowserTitle(cachedSettings.displayName);
    }

    unawaited(
      ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true)
          .then((_) {
        if (!mounted) return;
        ref.invalidate(systemSettingsProvider);
      }).catchError((Object error) {
        debugPrint('[App] Browser title refresh failed: $error');
      }),
    );

    _systemSettingsTitleSub?.close();
    _systemSettingsTitleSub = ref.listenManual<AsyncValue<SystemSettings>>(
      systemSettingsProvider,
      (previous, next) {
        next.whenData((settings) {
          _applyBrowserTitle(settings.displayName);
        });
      },
      fireImmediately: true,
    );
  }

  void _setupTrayPresentationSync() {
    if (!PlatformUtils.isPhysicalDesktop) {
      return;
    }

    unawaited(TrayService.instance.refreshLabels());

    _trayLanguageSub?.close();
    _trayLanguageSub = ref.listenManual<AppLanguage>(
      languageProvider,
      (previous, next) {
        if (previous == next) return;
        unawaited(TrayService.instance.refreshLabels());
      },
      fireImmediately: true,
    );

    _traySettingsSub?.close();
    _traySettingsSub = ref.listenManual<AsyncValue<SystemSettings>>(
      systemSettingsProvider,
      (previous, next) {
        final previousName = previous?.valueOrNull?.displayName.trim();
        final nextName = next.valueOrNull?.displayName.trim();
        if (previousName == nextName) return;
        unawaited(TrayService.instance.refreshLabels());
      },
      fireImmediately: true,
    );
  }

  void _applyBrowserTitle(String title) {
    final normalized =
        title.trim().isEmpty ? defaultAppDisplayName() : title.trim();
    setBrowserTitle(normalized);
  }

  int _computeUnreadChatCount(ChatListState state) {
    return state.pinnedChats
            .where((c) => c.unreadCount > 0)
            .fold<int>(0, (sum, c) => sum + c.unreadCount) +
        state.regularChats
            .where((c) => c.unreadCount > 0)
            .fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  void _syncUnreadBadgeCount(int count) {
    if (PlatformUtils.isMobile) {
      unawaited(AppBadgeService().updateBadge(count));
      BackgroundService.instance.updateNotification(unreadCount: count);
    }
    if (DesktopNotificationService.isDesktop) {
      unawaited(DesktopNotificationService().updateBadge(count));
    }
    if (PlatformUtils.isPhysicalDesktop) {
      unawaited(TrayService.instance.updateUnreadCount(count));
    }
  }

  void _setupUnreadBadgeSync() {
    final initialUnread = _computeUnreadChatCount(ref.read(chatListProvider));
    _syncUnreadBadgeCount(initialUnread);

    ref.listenManual(chatListProvider, (previous, next) {
      final previousUnread =
          previous == null ? -1 : _computeUnreadChatCount(previous);
      final unread = _computeUnreadChatCount(next);
      if (previousUnread == unread) return;
      _syncUnreadBadgeCount(unread);
    });
  }

  void _bindApiTokenRefreshToWebSocket() {
    ref.read(apiClientProvider).onAccessTokenRefreshed = (String newToken) {
      debugPrint('[App] HTTP token refreshed -> WebSocket reconnect');
      ref
          .read(webSocketServiceProvider.notifier)
          .applyRefreshedHttpToken(newToken);
    };
  }

  void _bindPhoneRequiredRedirect() {
    ref.read(apiClientProvider).onPhoneBindRequired = () {
      unawaited(
        ref.read(systemSettingsServiceProvider).clearCache().then((_) {
          ref.invalidate(systemSettingsProvider);
        }),
      );
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      try {
        if (GoRouterState.of(context).matchedLocation == '/bind-phone') return;
      } catch (_) {}
      context.go('/bind-phone');
    };
  }

  void _bindOfflineMessageQueue() {
    OfflineMessageQueue().onSendMessage = (OfflineMessage m) async {
      final coordinator = ref.read(accountSessionCoordinatorProvider.notifier);
      if (!coordinator.isActiveAccount(m.accountId)) {
        return OfflineMessageSendResult.retry;
      }
      if (m.type != OfflineMessageType.text ||
          m.content == null ||
          m.content!.trim().isEmpty) {
        return OfflineMessageSendResult.permanentFailure;
      }
      try {
        final chat = ref.read(chatServiceProvider);
        final response = await chat.sendMessage(
          chatId: m.chatId,
          type: 1,
          content: MessageContent(text: m.content!),
          msgId: m.id,
        );
        if (!coordinator.isActiveAccount(m.accountId)) {
          return OfflineMessageSendResult.retry;
        }
        if (response.isSuccess && response.data != null) {
          try {
            ref
                .read(messageListProvider(m.chatId).notifier)
                .markQueuedMessageSent(response.data!);
          } catch (e) {
            debugPrint('[App] Failed to update active queued message ACK: $e');
          }
          return OfflineMessageSendResult.success;
        }
        if (response.code > 0) {
          return OfflineMessageSendResult.permanentFailure;
        }
        return OfflineMessageSendResult.retry;
      } catch (e) {
        debugPrint('[App] Offline queue send failed: $e');
        return OfflineMessageSendResult.retry;
      }
    };
    OfflineMessageQueue().onMessageFailed = _markQueuedOfflineMessageFailed;
    unawaited(OfflineMessageQueue().processPending());
  }

  Future<void> _markQueuedOfflineMessageFailed(OfflineMessage message) async {
    if (!ref
        .read(accountSessionCoordinatorProvider.notifier)
        .isActiveAccount(message.accountId)) {
      return;
    }
    try {
      ref
          .read(messageListProvider(message.chatId).notifier)
          .markQueuedMessageFailed(message.id);
    } catch (e) {
      debugPrint('[App] Failed to update active offline message state: $e');
    }

    if (PlatformUtils.isWeb || !IsarService.instance.isAvailable) return;

    final accountId = ref.read(authServiceProvider).user?.uuid ?? '';
    if (accountId.isEmpty) return;

    try {
      await IsarService.instance.isar.writeTxn(() async {
        final model = await IsarService.instance.isar.messageModels
            .filter()
            .accountIdEqualTo(accountId)
            .idEqualTo(message.id)
            .findFirst();
        if (model == null) return;
        model.status = MsgStatus.failed;
        await IsarService.instance.isar.messageModels.put(model);
      });
    } catch (e) {
      debugPrint('[App] Failed to mark offline message failed: $e');
    }
  }

  void _setupDiscoverSync() {
    final wsService = ref.read(webSocketServiceProvider.notifier);
    _discoverItemsUpdatedHandlerId ??= wsService.registerHandler(
      WSMessageType.discoverItemsUpdated,
      (_) {
        debugPrint('[Discover] Received discover_items_updated, refreshing');
        unawaited(refreshDiscoverEntries(ref));
      },
    );
  }

  void _setupSystemSettingsUpdatedHandler() {
    final wsService = ref.read(webSocketServiceProvider.notifier);
    _systemSettingsUpdatedHandlerId ??= wsService.registerHandler(
      WSMessageType.systemSettingsUpdated,
      (_) => unawaited(_refreshSystemSettings(reason: 'websocket_event')),
    );
  }

  Future<void> _refreshSystemSettings({required String reason}) async {
    try {
      await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true);
      if (!mounted) return;
      ref.invalidate(systemSettingsProvider);
      debugPrint('[SystemSettings] Refreshed after $reason');
    } catch (e) {
      debugPrint('[SystemSettings] Refresh failed after $reason: $e');
    }
  }

  void _showAnnouncementDialog(String title, String content) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  _localizedText(
                    l10n: l10n,
                    zhCN: '我知道了',
                    zhTW: '我知道了',
                    en: 'Got it',
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  void _setupForceLogoutHandler() {
    final wsService = ref.read(webSocketServiceProvider.notifier);

    _forceLogoutHandlerId ??= wsService.registerHandler(
      WSMessageType.forceLogout,
      (data) async {
        try {
          final currentDeviceId = await DeviceService.getDeviceId();
          final deviceIds = (data['device_ids'] as List?)
                  ?.map((value) => value.toString())
                  .toList() ??
              [];
          if (deviceIds.contains(currentDeviceId)) {
            debugPrint('[App] Force logout triggered for this device');
            final notice = ForceLogoutNotice.fromPayload(data);
            await ref.read(authServiceProvider.notifier).logout(
                  reason: SessionExitReason.deviceTerminated,
                  notifyServer: false,
                  errorMessage: notice.localizedMessage(
                    AppLocalizations.currentLanguage,
                  ),
                );
          }
        } catch (e) {
          debugPrint('[App] Force logout handler error: $e');
        }
      },
    );
  }

  void _setupNewDeviceLoginHandler() {
    final wsService = ref.read(webSocketServiceProvider.notifier);

    _newDeviceLoginHandlerId ??= wsService.registerHandler(
      WSMessageType.newDeviceLogin,
      (data) async {
        try {
          if (data is! Map<String, dynamic>) return;
          final notice = NewDeviceLoginNotice.fromPayload(data);
          final currentDeviceId = await DeviceService.getDeviceId();
          if (notice.deviceId.isNotEmpty &&
              notice.deviceId == currentDeviceId) {
            return;
          }
          if (notice.eventId.isNotEmpty &&
              !_shownNewDeviceLoginEventIds.add(notice.eventId)) {
            return;
          }

          final context = rootNavigatorKey.currentContext;
          if (context == null || !context.mounted) return;
          final language = AppLocalizations.of(context).language;
          final openDevices = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                _localizedText(
                  l10n: AppLocalizations.of(dialogContext),
                  zhCN: '新设备登录提醒',
                  zhTW: '新裝置登入提醒',
                  en: 'New device sign-in',
                ),
              ),
              content: Text(notice.localizedMessage(language)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(
                    _localizedText(
                      l10n: AppLocalizations.of(dialogContext),
                      zhCN: '我知道了',
                      zhTW: '我知道了',
                      en: 'Got it',
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.devices_outlined),
                  label: Text(
                    _localizedText(
                      l10n: AppLocalizations.of(dialogContext),
                      zhCN: '设备管理',
                      zhTW: '裝置管理',
                      en: 'Manage devices',
                    ),
                  ),
                ),
              ],
            ),
          );
          if (openDevices == true && context.mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DevicesPage()),
            );
          }
        } catch (e) {
          debugPrint('[App] New device login handler error: $e');
        }
      },
    );
  }

  void _setupAnnouncementHandler() {
    final wsService = ref.read(webSocketServiceProvider.notifier);

    _announcementHandlerId ??= wsService.registerHandler(
      WSMessageType.systemAnnouncement,
      (data) {
        final appName =
            ref.read(systemSettingsProvider).valueOrNull?.displayName ??
                defaultAppDisplayName();
        final l10n = rootNavigatorKey.currentContext != null
            ? AppLocalizations.of(rootNavigatorKey.currentContext!)
            : null;
        _showAnnouncementDialog(
          data['title'] as String? ??
              _localizedText(
                l10n: l10n,
                zhCN: '$appName 系统公告',
                zhTW: '$appName 系統公告',
                en: '$appName Announcement',
              ),
          data['content'] as String? ?? '',
        );
      },
    );
  }

  void _setupMeetingInviteHandler() {
    final wsService = ref.read(webSocketServiceProvider.notifier);
    _meetingInviteHandlerId ??= wsService.registerHandler(
      WSMessageType.meetingInvite,
      (data) {
        final meetingId = data['meeting_id']?.toString() ?? '';
        if (meetingId.isEmpty) return;
        final chatId = data['chat_id']?.toString() ?? '';
        final activeChatId =
            ref.read(chatListProvider.notifier).activeChatId ?? '';
        if (chatId.isNotEmpty && chatId == activeChatId) {
          return;
        }

        final inviteKey = '$meetingId:${data['inviter_id']?.toString() ?? ''}';
        if (!_shownMeetingInviteIds.add(inviteKey)) return;

        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final l10n = AppLocalizations.of(ctx);

        final inviterName = data['inviter_name']?.toString() ??
            _localizedText(
              l10n: l10n,
              zhCN: '成员',
              zhTW: '成員',
              en: 'Member',
            );
        final title = data['title']?.toString() ?? '';
        final meetingType = data['meeting_type']?.toString() ?? 'video';
        final label = meetingType == 'voice'
            ? _localizedText(
                l10n: l10n,
                zhCN: '语音群会议',
                zhTW: '語音群會議',
                en: 'Voice Group Meeting',
              )
            : _localizedText(
                l10n: l10n,
                zhCN: '视频群会议',
                zhTW: '視頻群會議',
                en: 'Video Group Meeting',
              );
        final content = title.trim().isNotEmpty
            ? _localizedText(
                l10n: l10n,
                zhCN: '$inviterName 邀请你加入$label：$title',
                zhTW: '$inviterName 邀請你加入$label：$title',
                en: '$inviterName invited you to join $label: $title',
              )
            : _localizedText(
                l10n: l10n,
                zhCN: '$inviterName 邀请你加入$label',
                zhTW: '$inviterName 邀請你加入$label',
                en: '$inviterName invited you to join $label',
              );

        showDialog<void>(
          context: ctx,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              _localizedText(
                l10n: l10n,
                zhCN: '群会议邀请',
                zhTW: '群會議邀請',
                en: 'Group Meeting Invitation',
              ),
            ),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  _localizedText(
                    l10n: l10n,
                    zhCN: '稍后',
                    zhTW: '稍後',
                    en: 'Later',
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Future.delayed(const Duration(milliseconds: 200), () {
                    ref.read(appRouterProvider).push('/meeting/$meetingId');
                  });
                },
                child: Text(
                  _localizedText(
                    l10n: l10n,
                    zhCN: '加入',
                    zhTW: '加入',
                    en: 'Join',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setupMeetingJoinRequestHandler() {
    final wsService = ref.read(webSocketServiceProvider.notifier);
    _meetingJoinRequestHandlerId ??= wsService.registerHandler(
      WSMessageType.meetingJoinRequest,
      (data) {
        final meetingId = data['meeting_id']?.toString() ?? '';
        if (meetingId.isEmpty) return;
        final chatId = data['chat_id']?.toString() ?? '';
        final activeChatId =
            ref.read(chatListProvider.notifier).activeChatId ?? '';
        if (chatId.isNotEmpty && chatId == activeChatId) {
          return;
        }

        final requestUserId = data['request_user_id']?.toString() ?? '';
        final requestKey = '$meetingId:$requestUserId';
        if (!_shownMeetingJoinRequestIds.add(requestKey)) return;

        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final l10n = AppLocalizations.of(ctx);

        final requestName = data['request_name']?.toString() ??
            _localizedText(
              l10n: l10n,
              zhCN: '成员',
              zhTW: '成員',
              en: 'Member',
            );
        final meetingService = ref.read(meetingServiceProvider);
        showDialog<void>(
          context: ctx,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              _localizedText(
                l10n: l10n,
                zhCN: '入会申请',
                zhTW: '入會申請',
                en: 'Join Request',
              ),
            ),
            content: Text(
              _localizedText(
                l10n: l10n,
                zhCN: '$requestName 申请加入群会议，是否同意？',
                zhTW: '$requestName 申請加入群會議，是否同意？',
                en: '$requestName requested to join the group meeting. Approve?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  _localizedText(
                    l10n: l10n,
                    zhCN: '稍后',
                    zhTW: '稍後',
                    en: 'Later',
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (requestUserId.isEmpty) return;
                  await meetingService.reviewJoinRequest(
                    meetingId: meetingId,
                    targetUserId: requestUserId,
                    approve: false,
                  );
                },
                child: Text(
                  _localizedText(
                    l10n: l10n,
                    zhCN: '拒绝',
                    zhTW: '拒絕',
                    en: 'Decline',
                  ),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (requestUserId.isEmpty) return;
                  await meetingService.reviewJoinRequest(
                    meetingId: meetingId,
                    targetUserId: requestUserId,
                    approve: true,
                  );
                },
                child: Text(
                  _localizedText(
                    l10n: l10n,
                    zhCN: '同意',
                    zhTW: '同意',
                    en: 'Approve',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setupMeetingStateHandlers() {
    final wsService = ref.read(webSocketServiceProvider.notifier);
    final session = ref.read(meetingSessionProvider.notifier);

    _meetingEndedHandlerId ??= wsService.registerHandler(
      WSMessageType.meetingEnded,
      (data) {
        final meetingId = data['meeting_id']?.toString() ?? '';
        if (meetingId.isEmpty) return;
        if (ref.read(meetingSessionProvider).meetingId == meetingId) {
          session.clear();
        }
      },
    );

    _meetingTitleUpdatedHandlerId ??= wsService.registerHandler(
      WSMessageType.meetingTitleUpdated,
      (data) {
        final meetingId = data['meeting_id']?.toString() ?? '';
        final title = data['title']?.toString() ?? '';
        if (meetingId.isEmpty || title.trim().isEmpty) return;
        session.updateTitle(meetingId, title);
      },
    );
  }

  void _setupPushNotifications() {
    if (RuntimeFlags.smokeTest) {
      _debugLog('[Push] Skipped in smoke test mode');
      return;
    }

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().onNotificationTap = (payload) {
        final account = _captureActiveAccount();
        if (account == null) return;
        _debugLog('[DesktopNotification] Notification tapped');
        if (payload != null && payload.isNotEmpty) {
          if (payload.startsWith('call:')) {
            return;
          }
          Future.delayed(const Duration(milliseconds: 300), () {
            _navigateToChat(payload, 'private', account);
          });
        }
      };
    }

    final pushService = ref.read(pushNotificationServiceProvider);

    pushService.onNativeCallKitEvent = (event, data) {
      if (_captureActiveAccount() == null) return Future<void>.value();
      return ref
          .read(callServiceProvider.notifier)
          .handleNativeCallKitEvent(event, data);
    };

    pushService.onNotificationReceived = (data) {
      if (_captureActiveAccount() == null) return;
      _debugLog('[Push] Notification received: ${_pushPayloadSummary(data)}');
      final payload = _normalizePushPayload(data);
      final type = payload['type']?.toString();
      if (type == 'incoming_call') {
        debugPrint(
          '[Push] Incoming call push received, triggering CallService',
        );
        ref
            .read(callServiceProvider.notifier)
            .handleIncomingCall(_incomingCallDataFromPush(payload));
      }
    };

    pushService.onNotificationTapped = (data) {
      final account = _captureActiveAccount();
      if (account == null) return;
      _debugLog('[Push] Notification tapped: ${_pushPayloadSummary(data)}');
      final payload = _normalizePushPayload(data);
      final type = payload['type']?.toString();

      if (type == 'incoming_call') {
        ref
            .read(callServiceProvider.notifier)
            .handleIncomingCall(_incomingCallDataFromPush(payload));
        return;
      }
      if (type == 'system_announcement') {
        final title = payload['title']?.toString().trim();
        final content =
            (payload['content'] ?? payload['body'])?.toString().trim() ?? '';
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!_isCurrentAccount(account) || content.isEmpty) return;
          final appName =
              ref.read(systemSettingsProvider).valueOrNull?.displayName ??
                  defaultAppDisplayName();
          _showAnnouncementDialog(
            title?.isNotEmpty == true ? title! : '$appName 系统公告',
            content,
          );
        });
        return;
      }
      if (isMeetingNotificationType(type)) {
        final meetingId = payload['meeting_id']?.toString();
        if (meetingId != null && meetingId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 250), () {
            if (!_isCurrentAccount(account)) return;
            ref.read(appRouterProvider).push('/meeting/$meetingId');
          });
        }
        return;
      }

      final chatId = payload['chat_id']?.toString();
      final chatType = payload['chat_type']?.toString();

      if (chatId != null && chatId.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _navigateToChat(chatId, chatType ?? 'private', account);
        });
      }
    };

    pushService.onNotificationReply = (data) async {
      final chatId = data['chat_id']?.toString().trim() ?? '';
      final text = data['reply_text']?.toString().trim() ?? '';
      final msgId = data['client_msg_id']?.toString().trim() ?? '';
      if (chatId.isEmpty || text.isEmpty || msgId.isEmpty) {
        await pushService.recordNotificationReplyTrace(
          'app_payload_rejected',
          data: data,
          fields: <String, Object?>{
            'reason': chatId.isEmpty
                ? 'missing_chat_id'
                : text.isEmpty
                    ? 'missing_reply_text'
                    : 'missing_client_msg_id',
            'reply_length': text.length,
          },
        );
        return true;
      }

      var account = _captureActiveAccount();
      if (account == null) {
        final authBefore = ref.read(authServiceProvider).status.name;
        await pushService.recordNotificationReplyTrace(
          'app_session_recovery_start',
          data: data,
          fields: <String, Object?>{
            'account_active': false,
            'auth_status': authBefore,
          },
        );
        await ref
            .read(authServiceProvider.notifier)
            .ensureSessionRecoveredOnResume();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        account = _captureActiveAccount();
        if (account == null) {
          await pushService.recordNotificationReplyTrace(
            'app_session_not_ready',
            data: data,
            fields: <String, Object?>{
              'account_active': false,
              'auth_status': ref.read(authServiceProvider).status.name,
            },
          );
          return false;
        }
      }
      try {
        await pushService.recordNotificationReplyTrace(
          'app_send_start',
          data: data,
          fields: const <String, Object?>{'account_active': true},
        );
        final result = await ref.read(chatServiceProvider).sendMessage(
              chatId: chatId,
              type: 1,
              content: MessageContent(text: text),
              msgId: msgId,
            );
        await pushService.recordNotificationReplyTrace(
          'app_send_result',
          data: data,
          fields: <String, Object?>{
            'code': result.code,
            'result': result.isSuccess ? 'success' : 'failed',
          },
        );
        if (!result.isSuccess) return false;
        await AndroidMessageNotificationService.instance
            .cancelMessageNotification(chatId: chatId, markRevoked: false);
        return true;
      } catch (error) {
        await pushService.recordNotificationReplyTrace(
          'app_send_exception',
          data: data,
          fields: <String, Object?>{
            'reason': error.runtimeType.toString(),
          },
        );
        debugPrint('[Push] Notification reply failed: $error');
        return false;
      }
    };

    ref.listenManual(authServiceProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && !_pushRegistered) {
        _pushRegistered = true;
        final account = _captureActiveAccount();
        if (account == null) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isCurrentAccount(account)) return;
          ref.read(pushNotificationServiceProvider).register();
          ref
              .read(notificationSoundServiceProvider.notifier)
              .syncSettingsToServer();
        });
        unawaited(pushService.retryPendingNotificationReply());
      } else if (next.status == AuthStatus.unauthenticated) {
        _pushRegistered = false;
        ref.invalidate(chatListProvider);
        _syncUnreadBadgeCount(0);
      }
    });

    final authState = ref.read(authServiceProvider);
    if (authState.status == AuthStatus.authenticated) {
      _pushRegistered = true;
      final account = _captureActiveAccount();
      if (account == null) return;
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isCurrentAccount(account)) return;
        ref.read(pushNotificationServiceProvider).register();
        ref
            .read(notificationSoundServiceProvider.notifier)
            .syncSettingsToServer();
        unawaited(pushService.retryPendingNotificationReply());
      });
    }
  }

  void _navigateToChat(
    String chatId,
    String chatType,
    AccountContext account,
  ) {
    if (!_isCurrentAccount(account)) return;
    _debugLog('[Push] Navigating to chat type=$chatType');
    final router = ref.read(appRouterProvider);

    ChatType type;
    switch (chatType) {
      case 'group':
        type = ChatType.group;
        break;
      case 'channel':
        type = ChatType.channel;
        break;
      default:
        type = ChatType.private;
    }

    router.push('/chat/$chatId?type=${type.name}');
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    _deepLinkSubscription = null;
    unawaited(DeepLinkService.instance.dispose());
    _systemSettingsTitleSub?.close();
    _keepAliveSettingsSub?.close();
    _keepAliveAuthSub?.close();
    _missedMessageSyncAuthSub?.close();
    _appLockAuthSub?.close();
    _loginNoticeAuthSub?.close();
    _trayLanguageSub?.close();
    _traySettingsSub?.close();
    _accountSessionSub?.close();
    if (_discoverItemsUpdatedHandlerId != null) {
      _webSocketService.unregisterHandler(_discoverItemsUpdatedHandlerId!);
      _discoverItemsUpdatedHandlerId = null;
    }
    if (_systemSettingsUpdatedHandlerId != null) {
      _webSocketService.unregisterHandler(_systemSettingsUpdatedHandlerId!);
      _systemSettingsUpdatedHandlerId = null;
    }
    if (_announcementHandlerId != null) {
      _webSocketService.unregisterHandler(_announcementHandlerId!);
      _announcementHandlerId = null;
    }
    if (_meetingInviteHandlerId != null) {
      _webSocketService.unregisterHandler(_meetingInviteHandlerId!);
      _meetingInviteHandlerId = null;
    }
    if (_meetingJoinRequestHandlerId != null) {
      _webSocketService.unregisterHandler(_meetingJoinRequestHandlerId!);
      _meetingJoinRequestHandlerId = null;
    }
    if (_meetingEndedHandlerId != null) {
      _webSocketService.unregisterHandler(_meetingEndedHandlerId!);
      _meetingEndedHandlerId = null;
    }
    if (_meetingTitleUpdatedHandlerId != null) {
      _webSocketService.unregisterHandler(_meetingTitleUpdatedHandlerId!);
      _meetingTitleUpdatedHandlerId = null;
    }
    if (_forceLogoutHandlerId != null) {
      _webSocketService.unregisterHandler(_forceLogoutHandlerId!);
      _forceLogoutHandlerId = null;
    }
    if (_newDeviceLoginHandlerId != null) {
      _webSocketService.unregisterHandler(_newDeviceLoginHandlerId!);
      _newDeviceLoginHandlerId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      ref.read(appLockServiceProvider.notifier).handleLifecycleChange(state),
    );
    if (state == AppLifecycleState.resumed) {
      final currentOffset = DateTime.now().timeZoneOffset;
      if (didTimeZoneOffsetChange(_lastTimeZoneOffset, currentOffset)) {
        _lastTimeZoneOffset = currentOffset;
        ref.read(timeZoneRefreshProvider.notifier).state++;
      }
      unawaited(_refreshSystemSettings(reason: 'app_resumed'));
      unawaited(
        ref.read(authServiceProvider.notifier).ensureSessionRecoveredOnResume(),
      );
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated) {
        unawaited(OfflineMessageQueue().processPending());
      }
      if (authState.status == AuthStatus.authenticated &&
          PlatformUtils.isMobile) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 3500), () {
            return ref
                .read(pushNotificationServiceProvider)
                .ensureTokenSynced();
          }),
        );
        _scheduleMissedMessageSync(
          reason: 'app_resumed',
          delay: const Duration(milliseconds: 700),
        );
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 3000), () {
            return OfflineMessageQueue().processPending();
          }),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref
            .read(callServiceProvider.notifier)
            .restoreIncomingCallFromSystem();
        await ref
            .read(callServiceProvider.notifier)
            .syncActiveCallStateWithServer();
        if (!mounted) return;
        final callState = ref.read(callServiceProvider);
        final navigator = rootNavigatorKey.currentState;
        if (navigator == null) return;

        if (callState.state == CallState.connecting ||
            callState.state == CallState.connected ||
            callState.state == CallState.reconnecting) {
          _showCallPagePreservingStack();
          return;
        }

        if (callState.state == CallState.incoming &&
            callState.callInfo != null) {
          _showIncomingCallPage(callState.callInfo!, resetStack: true);
        }
      });
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      ref.read(chatListProvider.notifier).setActiveChatId(null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureBackgroundPersistence();
      });
    }
  }

  Future<void> _ensureBackgroundPersistence() async {
    final authState = ref.read(authServiceProvider);
    if (authState.status != AuthStatus.authenticated ||
        authState.token == null) {
      return;
    }
    try {
      final backgroundService = BackgroundService.instance;
      final running = await backgroundService.isRunning();
      if (!running) await backgroundService.start();
    } catch (_) {}
  }

  bool _hasCallPageRoute(NavigatorState navigator) {
    var hasCallPage = false;
    navigator.popUntil((route) {
      if (route.settings.name == '/call') {
        hasCallPage = true;
      }
      return true;
    });
    return hasCallPage;
  }

  void _dismissTopIncomingCallPage(NavigatorState navigator) {
    navigator.popUntil((route) => route.settings.name != '/incoming-call');
  }

  void _showCallPagePreservingStack() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      debugPrint('[App] ERROR: Navigator is null!');
      return;
    }

    _dismissTopIncomingCallPage(navigator);
    if (_hasCallPageRoute(navigator)) {
      debugPrint('[App] CallPage already visible, preserving current stack');
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => const CallPage(),
        settings: const RouteSettings(name: '/call'),
      ),
    );
  }

  void _showIncomingCallPage(CallInfo callInfo, {bool resetStack = false}) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      debugPrint('[App] ERROR: Navigator is null!');
      return;
    }

    var isAlreadyOnIncomingCallPage = false;
    navigator.popUntil((route) {
      if (route.settings.name == '/incoming-call') {
        isAlreadyOnIncomingCallPage = true;
      }
      return true;
    });
    if (isAlreadyOnIncomingCallPage) {
      debugPrint('[App] IncomingCallPage already visible, skipping push');
      return;
    }

    if (resetStack) {
      navigator.popUntil((route) => route.isFirst);
    }

    navigator.push(
      PageRouteBuilder(
        settings: const RouteSettings(name: '/incoming-call'),
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => IncomingCallPage(callInfo: callInfo),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _setupCallCallbacks() {
    final callService = ref.read(callServiceProvider.notifier);

    callService.onIncomingCall = (callInfo) {
      _debugLog('[App] onIncomingCall triggered, showing IncomingCallPage');

      if (DesktopNotificationService.isDesktop) {
        DesktopNotificationService().showIncomingCallNotification(
          callerName: callInfo.remoteName,
          isVideo: callInfo.type == CallType.video,
          payload: 'call:${callInfo.callId}',
        );
      }

      _debugLog(
          '[App] Navigator available: ${rootNavigatorKey.currentState != null}');
      _showIncomingCallPage(callInfo);
    };

    callService.onCallAccepted = () {
      debugPrint('[App] onCallAccepted triggered');
      Future.delayed(const Duration(milliseconds: 100), () {
        debugPrint('[App] Navigating to CallPage');
        if (rootNavigatorKey.currentState != null) {
          _showCallPagePreservingStack();
        } else {
          debugPrint('[App] Navigator is null, retrying...');
          Future.delayed(const Duration(milliseconds: 150), () {
            _showCallPagePreservingStack();
          });
        }
      });
    };

    callService.onCallFailed = (error) {
      debugPrint('[App] onCallFailed: $error');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final themePreset = ref.watch(appThemePresetProvider);
    final presetColors = AppThemePresets.of(themePreset);
    debugPrint('[Theme] preset=$themePreset primary=${presetColors.primaryA}');
    final router = ref.watch(appRouterProvider);

    final callState = ref.watch(callServiceProvider);

    final newState = callState.state;
    if (_lastCallState != newState) {
      final wasIncoming = _lastCallState == CallState.incoming;
      final isNowConnecting = newState == CallState.connecting ||
          newState == CallState.connected ||
          newState == CallState.reconnecting;

      if (wasIncoming && isNowConnecting && !_hasNavigatedToCallPage) {
        _hasNavigatedToCallPage = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navigator = rootNavigatorKey.currentState;
          if (navigator == null) return;

          bool isAlreadyOnCallPage = false;
          navigator.popUntil((route) {
            if (route.settings.name == '/call' ||
                route.settings.name?.contains('call') == true) {
              isAlreadyOnCallPage = true;
            }
            return true;
          });

          if (isAlreadyOnCallPage) {
            debugPrint('[App] Already on CallPage, skipping auto-navigation');
            return;
          }

          debugPrint(
            '[App] Auto-navigating to CallPage: $_lastCallState -> $newState',
          );
          _showCallPagePreservingStack();
        });
      }

      if (newState == CallState.idle) {
        _hasNavigatedToCallPage = false;
      }

      _lastCallState = newState;
    }

    final language = ref.watch(languageProvider);
    final appLockState = ref.watch(appLockServiceProvider);
    final configuredAppTitle =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName.trim();
    final materialAppTitle =
        configuredAppTitle != null && configuredAppTitle.isNotEmpty
            ? configuredAppTitle
            : AppLocalizations(language).appName;

    return MaterialApp.router(
      title: materialAppTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(presetColors, Brightness.light),
      darkTheme: AppTheme.build(presetColors, Brightness.dark),
      themeMode: themeMode,
      locale: language.locale,
      supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Stack(
            children: [
              MeetingOverlayWrapper(
                child: CallOverlayWrapper(child: child!),
              ),
              if (appLockState.isLocked) const AppLockGatePage(),
            ],
          ),
        );
      },
    );
  }
}
