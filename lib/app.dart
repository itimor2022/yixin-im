import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/i18n/app_localizations.dart';
import 'core/services/call_service.dart';
import 'core/services/background_service.dart';
import 'core/services/app_badge_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/notification_sound_service.dart';
import 'core/services/api/websocket_service.dart';
import 'core/services/api/api_client.dart' show apiClientProvider;
import 'core/services/desktop_notification_service.dart';
import 'core/services/desktop/tray_service.dart';
import 'core/services/api/auth_service.dart';
import 'core/services/api/chat_service.dart' hide ChatType;
import 'core/services/api/meeting_service.dart';
import 'core/services/offline_message_queue.dart';
import 'core/services/storage/isar_service.dart';
import 'core/services/storage/models/message_model.dart';
import 'core/services/device_service.dart';
import 'core/utils/platform_utils.dart';
import 'core/utils/browser_title.dart';
import 'core/services/api/system_settings_service.dart';
import 'features/call/widgets/call_overlay.dart';
import 'features/meeting/widgets/meeting_overlay.dart';
import 'features/call/pages/incoming_call_page.dart';
import 'features/call/pages/call_page.dart';
import 'features/chat/pages/chat_detail_page.dart' show ChatType;
import 'features/chat/providers/chat_provider.dart';
import 'features/chat/providers/message_provider.dart';
import 'features/discover/pages/discover_page.dart';
import 'core/services/meeting_session_service.dart';

class GaoRanIMApp extends ConsumerStatefulWidget {
  const GaoRanIMApp({super.key});

  @override
  ConsumerState<GaoRanIMApp> createState() => _GaoRanIMAppState();
}

class _GaoRanIMAppState extends ConsumerState<GaoRanIMApp>
    with WidgetsBindingObserver {
  bool _hasNavigatedToCallPage = false;
  CallState? _lastCallState;
  bool _pushRegistered = false;
  String? _discoverItemsUpdatedHandlerId;
  String? _announcementHandlerId;
  String? _forceLogoutHandlerId;
  String? _meetingInviteHandlerId;
  String? _meetingJoinRequestHandlerId;
  String? _meetingEndedHandlerId;
  String? _meetingTitleUpdatedHandlerId;
  ProviderSubscription<AsyncValue<SystemSettings>>? _systemSettingsTitleSub;
  final Set<String> _shownMeetingInviteIds = {};
  final Set<String> _shownMeetingJoinRequestIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallService.navigatorKey = rootNavigatorKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _setupCallCallbacks();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupCallCallbacks error: $e');
      }
      try {
        _setupPushNotifications();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupPushNotifications error: $e');
      }
      try {
        _setupUnreadBadgeSync();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupUnreadBadgeSync error: $e');
      }
      try {
        _setupDiscoverSync();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupDiscoverSync error: $e');
      }
      try {
        _setupAnnouncementHandler();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupAnnouncementHandler error: $e');
      }
      try {
        _setupMeetingInviteHandler();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupMeetingInviteHandler error: $e');
      }
      try {
        _setupMeetingJoinRequestHandler();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupMeetingJoinRequestHandler error: $e');
      }
      try {
        _setupMeetingStateHandlers();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupMeetingStateHandlers error: $e');
      }
      try {
        _setupForceLogoutHandler();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupForceLogoutHandler error: $e');
      }
      try {
        _bindOfflineMessageQueue();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _bindOfflineMessageQueue error: $e');
      }
      try {
        _bindApiTokenRefreshToWebSocket();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _bindApiTokenRefreshToWebSocket error: $e');
      }
      try {
        _bindPhoneRequiredRedirect();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _bindPhoneRequiredRedirect error: $e');
      }
      try {
        _setupBrowserTitleSync();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] _setupBrowserTitleSync error: $e');
      }
    });
  }

  void _setupBrowserTitleSync() {
    if (!PlatformUtils.isWeb) {
      return;
    }

    _applyBrowserTitle(kDefaultAppDisplayName);

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
        if (kDebugMode) debugPrint('[App] Browser title refresh failed: $error');
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

  void _applyBrowserTitle(String title) {
    final normalized =
        title.trim().isEmpty ? kDefaultAppDisplayName : title.trim();
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
      if (kDebugMode) debugPrint('[App] HTTP token refreshed -> WebSocket reconnect');
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
        if (response.isSuccess && response.data != null) {
          return OfflineMessageSendResult.success;
        }
        if (response.code > 0) {
          return OfflineMessageSendResult.permanentFailure;
        }
        return OfflineMessageSendResult.retry;
      } catch (e) {
        if (kDebugMode) debugPrint('[App] Offline queue send failed: $e');
        return OfflineMessageSendResult.retry;
      }
    };
    OfflineMessageQueue().onMessageFailed = _markQueuedOfflineMessageFailed;
    unawaited(OfflineMessageQueue().processPending());
  }

  Future<void> _markQueuedOfflineMessageFailed(OfflineMessage message) async {
    try {
      ref
          .read(messageListProvider(message.chatId).notifier)
          .markQueuedMessageFailed(message.id);
    } catch (e) {
      if (kDebugMode) debugPrint('[App] Failed to update active offline message state: $e');
    }

    if (PlatformUtils.isWeb || !IsarService.instance.isAvailable) return;

    try {
      await IsarService.instance.isar.writeTxn(() async {
        final model = await IsarService.instance.isar.messageModels
            .where()
            .idEqualTo(message.id)
            .findFirst();
        if (model == null) return;
        model.status = MsgStatus.failed;
        await IsarService.instance.isar.messageModels.put(model);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[App] Failed to mark offline message failed: $e');
    }
  }

  void _setupDiscoverSync() {
    final wsService = ref.read(webSocketServiceProvider.notifier);
    _discoverItemsUpdatedHandlerId ??= wsService.registerHandler(
      WSMessageType.discoverItemsUpdated,
      (_) {
        if (kDebugMode) debugPrint('[Discover] Received discover_items_updated, refreshing');
        unawaited(refreshDiscoverEntries(ref));
      },
    );
  }

  void _showAnnouncementDialog(String title, String content) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
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
          final deviceIds = (data['device_ids'] as List?)?.cast<String>() ?? [];
          if (deviceIds.contains(currentDeviceId)) {
            if (kDebugMode) debugPrint('[App] Force logout triggered for this device');
            await ref.read(authServiceProvider.notifier).logout();
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[App] Force logout handler error: $e');
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
                kDefaultAppDisplayName;
        _showAnnouncementDialog(
          data['title'] as String? ?? '$appName 系统公告',
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

        final inviterName = data['inviter_name']?.toString() ?? '成员';
        final title = data['title']?.toString() ?? '';
        final meetingType = data['meeting_type']?.toString() ?? 'video';
        final label = meetingType == 'voice' ? '语音群会议' : '视频群会议';
        final content = title.trim().isNotEmpty
            ? '$inviterName 邀请你加入$label：$title'
            : '$inviterName 邀请你加入$label';

        showDialog<void>(
          context: ctx,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('群会议邀请'),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Future.delayed(const Duration(milliseconds: 200), () {
                    ref.read(appRouterProvider).push('/meeting/$meetingId');
                  });
                },
                child: const Text('加入'),
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

        final requestName = data['request_name']?.toString() ?? '成员';
        final meetingService = ref.read(meetingServiceProvider);
        showDialog<void>(
          context: ctx,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('入会申请'),
            content: Text('$requestName 申请加入群会议，是否同意？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
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
                child: const Text('拒绝'),
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
                child: const Text('同意'),
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
    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().onNotificationTap = (payload) {
        if (kDebugMode) debugPrint('[DesktopNotification] Notification tapped: $payload');
        if (payload != null && payload.isNotEmpty) {
          if (payload.startsWith('call:')) {
            return;
          }
          Future.delayed(const Duration(milliseconds: 300), () {
            _navigateToChat(payload, 'private');
          });
        }
      };
    }

    final pushService = ref.read(pushNotificationServiceProvider);

    pushService.onNotificationReceived = (data) {
      if (kDebugMode) debugPrint('[Push] Notification received: $data');
      final type = data['type'] as String?;
      if (type == 'incoming_call') {
        if (kDebugMode) debugPrint(
          '[Push] Incoming call push received, triggering CallService',
        );
        final isVideoPush =
            data['is_video'] == true || data['is_video'] == 'true';
        final pushCallType =
            data['call_type']?.toString() == 'video' || isVideoPush
                ? 'video'
                : 'voice';
        final callData = <String, dynamic>{
          'call_id': data['call_id'],
          'caller_name': data['caller_name'] ?? data['title'] ?? '',
          'caller_avatar': data['caller_avatar'] ?? '',
          'call_type': pushCallType,
          'channel_name': data['channel_name'] ?? '',
          'caller_id': data['caller_id'] ?? '',
        };
        ref.read(callServiceProvider.notifier).handleIncomingCall(callData);
      } else {
        // 普通消息：仅在 WS 离线时弹本地通知，在线时 WS 已直推无需重复
        final wsOnline = ref.read(webSocketServiceProvider.notifier).state == WSConnectionState.connected;
        if (!wsOnline) {
          final title = data['title'] as String? ?? '';
          final body = data['body'] as String? ?? '';
          if (title.isNotEmpty || body.isNotEmpty) {
            pushService.showLocalMessageNotification(
              title: title.isNotEmpty ? title : '新消息',
              body: body,
              data: data,
            );
          }
        }
      }
    };

    pushService.onNotificationTapped = (data) {
      if (kDebugMode) debugPrint('[Push] Notification tapped: $data');
      final type = data['type'] as String?;

      if (type == 'incoming_call') {
        final isVideoPush =
            data['is_video'] == true || data['is_video'] == 'true';
        final pushCallType =
            data['call_type']?.toString() == 'video' || isVideoPush
                ? 'video'
                : 'voice';
        ref.read(callServiceProvider.notifier).handleIncomingCall({
          'call_id': data['call_id'],
          'caller_name': data['caller_name'] ?? data['title'] ?? '',
          'caller_avatar': data['caller_avatar'] ?? '',
          'call_type': pushCallType,
          'channel_name': data['channel_name'] ?? '',
          'caller_id': data['caller_id'] ?? '',
        });
        return;
      }
      if (type == 'meeting_invite') {
        final meetingId = data['meeting_id'] as String?;
        if (meetingId != null && meetingId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 250), () {
            ref.read(appRouterProvider).push('/meeting/$meetingId');
          });
        }
        return;
      }
      if (type == 'meeting_join_request') {
        final meetingId = data['meeting_id'] as String?;
        if (meetingId != null && meetingId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 250), () {
            ref.read(appRouterProvider).push('/meeting/$meetingId');
          });
        }
        return;
      }
      if (type == 'meeting_join_request_reviewed') {
        final meetingId = data['meeting_id'] as String?;
        if (meetingId != null && meetingId.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 250), () {
            ref.read(appRouterProvider).push('/meeting/$meetingId');
          });
        }
        return;
      }

      final chatId = data['chat_id'] as String?;
      final chatType = data['chat_type'] as String?;

      if (chatId != null && chatId.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _navigateToChat(chatId, chatType ?? 'private');
        });
      }
    };

    ref.listenManual(authServiceProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && !_pushRegistered) {
        _pushRegistered = true;
        Future.delayed(const Duration(seconds: 2), () {
          ref.read(pushNotificationServiceProvider).register();
          ref
              .read(notificationSoundServiceProvider.notifier)
              .syncSettingsToServer();
        });
      } else if (next.status == AuthStatus.unauthenticated) {
        _pushRegistered = false;
        _syncUnreadBadgeCount(0);
      }
    });

    final authState = ref.read(authServiceProvider);
    if (authState.status == AuthStatus.authenticated) {
      _pushRegistered = true;
      Future.delayed(const Duration(seconds: 2), () {
        ref.read(pushNotificationServiceProvider).register();
        ref
            .read(notificationSoundServiceProvider.notifier)
            .syncSettingsToServer();
      });
    }
  }

  void _navigateToChat(String chatId, String chatType) {
    if (kDebugMode) debugPrint('[Push] Navigating to chat: $chatId (type: $chatType)');
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
    _systemSettingsTitleSub?.close();
    final wsService = ref.read(webSocketServiceProvider.notifier);
    if (_discoverItemsUpdatedHandlerId != null) {
      wsService.unregisterHandler(_discoverItemsUpdatedHandlerId!);
      _discoverItemsUpdatedHandlerId = null;
    }
    if (_announcementHandlerId != null) {
      wsService.unregisterHandler(_announcementHandlerId!);
      _announcementHandlerId = null;
    }
    if (_meetingInviteHandlerId != null) {
      wsService.unregisterHandler(_meetingInviteHandlerId!);
      _meetingInviteHandlerId = null;
    }
    if (_meetingJoinRequestHandlerId != null) {
      wsService.unregisterHandler(_meetingJoinRequestHandlerId!);
      _meetingJoinRequestHandlerId = null;
    }
    if (_meetingEndedHandlerId != null) {
      wsService.unregisterHandler(_meetingEndedHandlerId!);
      _meetingEndedHandlerId = null;
    }
    if (_meetingTitleUpdatedHandlerId != null) {
      wsService.unregisterHandler(_meetingTitleUpdatedHandlerId!);
      _meetingTitleUpdatedHandlerId = null;
    }
    if (_forceLogoutHandlerId != null) {
      wsService.unregisterHandler(_forceLogoutHandlerId!);
      _forceLogoutHandlerId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(authServiceProvider.notifier).ensureSessionRecoveredOnResume(),
      );
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated &&
          PlatformUtils.isMobile) {
        unawaited(
          ref.read(pushNotificationServiceProvider).ensureTokenSynced(),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref
            .read(callServiceProvider.notifier)
            .restoreIncomingCallFromSystem();
        if (!mounted) return;
        final callState = ref.read(callServiceProvider);
        final navigator = rootNavigatorKey.currentState;
        if (navigator == null) return;

        if (callState.state == CallState.connecting ||
            callState.state == CallState.connected) {
          navigator.popUntil((route) => route.isFirst);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const CallPage(),
              settings: const RouteSettings(name: '/call'),
            ),
          );
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
        state == AppLifecycleState.inactive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureBackgroundPersistence();
      });
    }
  }

  Future<void> _ensureBackgroundPersistence() async {
    try {
      final backgroundService = BackgroundService.instance;
      final running = await backgroundService.isRunning();
      if (!running) await backgroundService.start();
    } catch (_) {}
  }

  void _showIncomingCallPage(CallInfo callInfo, {bool resetStack = false}) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      if (kDebugMode) debugPrint('[App] ERROR: Navigator is null!');
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
      if (kDebugMode) debugPrint('[App] IncomingCallPage already visible, skipping push');
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
      if (kDebugMode) debugPrint('[App] onIncomingCall triggered, showing IncomingCallPage');

      if (DesktopNotificationService.isDesktop) {
        DesktopNotificationService().showIncomingCallNotification(
          callerName: callInfo.remoteName,
          isVideo: callInfo.type == CallType.video,
          payload: 'call:${callInfo.callId}',
        );
      }

      if (kDebugMode) debugPrint('[App] Navigator: ${rootNavigatorKey.currentState}');
      _showIncomingCallPage(callInfo);
    };

    callService.onCallAccepted = () {
      if (kDebugMode) debugPrint('[App] onCallAccepted triggered');
      Future.delayed(const Duration(milliseconds: 100), () {
        if (kDebugMode) debugPrint('[App] Navigating to CallPage');
        final navigator = rootNavigatorKey.currentState;
        if (navigator != null) {
          navigator.popUntil((route) => route.isFirst);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const CallPage(),
              settings: const RouteSettings(name: '/call'),
            ),
          );
          if (kDebugMode) debugPrint('[App] CallPage pushed');
        } else {
          if (kDebugMode) debugPrint('[App] Navigator is null, retrying...');
          Future.delayed(const Duration(milliseconds: 150), () {
            final nav = rootNavigatorKey.currentState;
            if (nav != null) {
              nav.popUntil((route) => route.isFirst);
              nav.push(
                MaterialPageRoute(
                  builder: (_) => const CallPage(),
                  settings: const RouteSettings(name: '/call'),
                ),
              );
            }
          });
        }
      });
    };

    callService.onCallFailed = (error) {
      if (kDebugMode) debugPrint('[App] onCallFailed: $error');
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
    final router = ref.watch(appRouterProvider);

    final callState = ref.watch(callServiceProvider);

    final newState = callState.state;
    if (_lastCallState != newState) {
      final wasIncoming = _lastCallState == CallState.incoming;
      final isNowConnecting =
          newState == CallState.connecting || newState == CallState.connected;

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
            if (kDebugMode) debugPrint('[App] Already on CallPage, skipping auto-navigation');
            return;
          }

          if (kDebugMode) debugPrint(
            '[App] Auto-navigating to CallPage: $_lastCallState -> $newState',
          );
          navigator.popUntil((route) => route.isFirst);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const CallPage(),
              settings: const RouteSettings(name: '/call'),
            ),
          );
        });
      }

      if (newState == CallState.idle) {
        _hasNavigatedToCallPage = false;
      }

      _lastCallState = newState;
    }

    final language = ref.watch(languageProvider);

    return MaterialApp.router(
      title: '壹信IM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
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
          child: MeetingOverlayWrapper(
            child: CallOverlayWrapper(child: child!),
          ),
        );
      },
    );
  }
}
