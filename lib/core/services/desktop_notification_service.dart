// 文件用途：封装 DesktopNotificationService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 DesktopNotificationService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../utils/platform_utils.dart';
import 'api/system_settings_service.dart';

String _desktopNotificationText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：desktop notification service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 桌面系统通知投递服务。
///
/// 是否应展示、是否隐藏预览等业务决策由上层完成，本服务只适配平台通知能力。
class DesktopNotificationService {
  static final DesktopNotificationService _instance =
      DesktopNotificationService._internal();
  factory DesktopNotificationService() => _instance;
  DesktopNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool _isDisposed = false;
  String _appDisplayName = defaultAppDisplayName();

  // 通知点击回调
  Function(String? payload)? onNotificationTap;

  /// 是否是桌面端
  static bool get isDesktop => PlatformUtils.isPhysicalDesktop;

  /// 初始化通知服务
  Future<void> initialize() async {
    if (!isDesktop || _isInitialized) return;

    // 初始化阶段允许使用缓存品牌名；通知投递不应因在线设置暂时不可用而阻塞。
    final cachedSettings = await loadCachedSystemSettings();
    if (cachedSettings != null) {
      _appDisplayName = cachedSettings.displayName;
    }

    try {
      // macOS 设置
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );

      // Linux 设置
      final linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open',
        defaultIcon: AssetsLinuxIcon('assets/logo.png'),
      );

      // Windows 设置
      final windowsSettings = WindowsInitializationSettings(
        appName: _appDisplayName,
        appUserModelId: 'com.genericim.ma100',
        guid: 'd3b07384-d9a3-4d3a-8a5c-1234567890ab',
      );

      // 初始化设置
      final initSettings = InitializationSettings(
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      _isInitialized = true;
      debugPrint('[DesktopNotification] Initialized successfully');
    } catch (e) {
      debugPrint('[DesktopNotification] Failed to initialize: $e');
    }
  }

  /// 处理通知点击
  void _onNotificationResponse(NotificationResponse response) {
    debugPrint(
      '[DesktopNotification] Notification tapped: ${response.payload}',
    );
    onNotificationTap?.call(response.payload);
  }

  /// 显示消息通知
  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? payload,
    String? avatar,
  }) async {
    if (!isDesktop || !_isInitialized) return;

    try {
      // macOS 通知详情（禁用系统声音，由应用统一播放铃声）
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false, // 禁用系统声音，避免与应用铃声重复
        threadIdentifier: 'messages',
        interruptionLevel: InterruptionLevel.active,
      );

      // Linux 通知详情
      const linuxDetails = LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.normal,
        category: LinuxNotificationCategory.imReceived,
      );

      // Windows 通知详情
      final windowsDetails =
          WindowsNotificationDetails(subtitle: _appDisplayName);

      final details = NotificationDetails(
        macOS: darwinDetails,
        linux: linuxDetails,
        windows: windowsDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: payload,
      );

      debugPrint('[DesktopNotification] Message notification shown: $title');
    } catch (e) {
      debugPrint('[DesktopNotification] Failed to show notification: $e');
    }
  }

  /// 显示来电通知
  Future<void> showIncomingCallNotification({
    required String callerName,
    required bool isVideo,
    String? payload,
  }) async {
    if (!isDesktop || !_isInitialized) return;

    try {
      // 禁用系统声音，由应用统一播放来电铃声
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
        threadIdentifier: 'calls',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      const linuxDetails = LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.critical,
      );

      // Windows 通知详情（来电）
      final windowsDetails =
          WindowsNotificationDetails(subtitle: _appDisplayName);

      final details = NotificationDetails(
        macOS: darwinDetails,
        linux: linuxDetails,
        windows: windowsDetails,
      );

      await _notifications.show(
        9999, // 固定ID用于来电
        isVideo
            ? _desktopNotificationText(
                zhCN: '视频来电',
                zhTW: '視訊來電',
                en: 'Incoming video call',
              )
            : _desktopNotificationText(
                zhCN: '语音来电',
                zhTW: '語音來電',
                en: 'Incoming voice call',
              ),
        _desktopNotificationText(
          zhCN: '$callerName 正在呼叫您',
          zhTW: '$callerName 正在呼叫您',
          en: '$callerName is calling you',
        ),
        details,
        payload: payload,
      );

      debugPrint('[DesktopNotification] Call notification shown: $callerName');
    } catch (e) {
      debugPrint('[DesktopNotification] Failed to show call notification: $e');
    }
  }

  /// 取消来电通知
  Future<void> cancelCallNotification() async {
    if (!isDesktop || !_isInitialized) return;
    await _notifications.cancel(9999);
  }

  /// 显示动态互动通知
  Future<void> showMomentNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!isDesktop || !_isInitialized) return;

    try {
      // 禁用系统声音，由应用统一播放铃声
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
        threadIdentifier: 'moments',
        interruptionLevel: InterruptionLevel.active,
      );

      const linuxDetails = LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.normal,
      );

      // Windows 通知详情（动态）
      final windowsDetails =
          WindowsNotificationDetails(subtitle: _appDisplayName);

      final details = NotificationDetails(
        macOS: darwinDetails,
        linux: linuxDetails,
        windows: windowsDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: payload,
      );

      debugPrint('[DesktopNotification] Moment notification shown: $title');
    } catch (e) {
      debugPrint(
        '[DesktopNotification] Failed to show moment notification: $e',
      );
    }
  }

  /// 清除所有通知
  Future<void> cancelAll() async {
    if (!isDesktop || !_isInitialized) return;
    await _notifications.cancelAll();
  }

  /// 请求 macOS 系统通知权限。
  ///
  /// 系统授权和应用内通知总开关相互独立，返回值只代表本次系统权限请求结果。
  Future<bool> requestPermission() async {
    if (!PlatformUtils.isMacOS || !_isInitialized) return true;

    try {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    } catch (e) {
      debugPrint('[DesktopNotification] Failed to request permission: $e');
      return false;
    }
  }

  /// 更新应用角标（macOS）
  Future<void> updateBadge(int count) async {
    if (!PlatformUtils.isMacOS || !_isInitialized) return;

    try {
      // macOS 需要通过通知来更新角标
      if (count > 0) {
        final darwinDetails = DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: true,
          presentSound: false,
          badgeNumber: count,
        );

        await _notifications.show(
          0,
          '',
          '',
          NotificationDetails(macOS: darwinDetails),
        );
        // macOS 通过无弹窗通知写入角标，随后取消空通知，仅保留角标状态。
        await _notifications.cancel(0);
      } else {
        // 清除角标
        final darwinDetails = DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: true,
          presentSound: false,
          badgeNumber: 0,
        );

        await _notifications.show(
          0,
          '',
          '',
          NotificationDetails(macOS: darwinDetails),
        );
        await _notifications.cancel(0);
      }
    } catch (e) {
      debugPrint('[DesktopNotification] Failed to update badge: $e');
    }
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  /// 释放资源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    onNotificationTap = null;
    _isInitialized = false;
    debugPrint('[DesktopNotification] Disposed');
  }
}

/// Provider
final desktopNotificationServiceProvider = Provider<DesktopNotificationService>(
  (ref) {
    final service = DesktopNotificationService();
    ref.onDispose(() {
      service.dispose();
    });
    return service;
  },
);
