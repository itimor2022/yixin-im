// 文件用途：封装 SoundOption 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 SoundOption 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_localizations.dart';
import 'api/api_client.dart';
import 'account_session_coordinator.dart';
import 'android_message_notification_service.dart';

// 关键声明：notification sound service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 提示音选项
enum SoundOption {
  coin('弹钱', 'sounds/crisp.mp3'), // 弹钱音效
  crisp('清脆', 'sounds/coin.mp3'), // 清脆音效
  none('无', null);

  final String label;
  final String? assetPath;

  const SoundOption(this.label, this.assetPath);

  String get localizedLabel {
    switch (this) {
      case SoundOption.coin:
        switch (AppLocalizations.currentLanguage) {
          case AppLanguage.en:
            return 'Coin';
          case AppLanguage.zhTW:
            return '金幣';
          case AppLanguage.zhCN:
            return '金币';
        }
      case SoundOption.crisp:
        switch (AppLocalizations.currentLanguage) {
          case AppLanguage.en:
            return 'Crisp';
          case AppLanguage.zhTW:
            return '清脆';
          case AppLanguage.zhCN:
            return '清脆';
        }
      case SoundOption.none:
        switch (AppLocalizations.currentLanguage) {
          case AppLanguage.en:
            return 'None';
          case AppLanguage.zhTW:
            return '無';
          case AppLanguage.zhCN:
            return '无';
        }
    }
  }
}

/// 全局震动控制器
class GlobalHaptics {
  static ProviderContainer? _container;

  /// 初始化（需要在 app 启动时调用）
  static void init(ProviderContainer container) {
    _container = container;
  }

  /// 轻触反馈
  static void light() {
    if (_shouldVibrate()) {
      HapticFeedback.lightImpact();
    }
  }

  /// 选择反馈
  static void selection() {
    if (_shouldVibrate()) {
      HapticFeedback.selectionClick();
    }
  }

  /// 中等反馈
  static void medium() {
    if (_shouldVibrate()) {
      HapticFeedback.mediumImpact();
    }
  }

  /// 重度反馈
  static void heavy() {
    if (_shouldVibrate()) {
      HapticFeedback.heavyImpact();
    }
  }

  /// 检查是否应该震动
  static bool _shouldVibrate() {
    if (_container == null) return true;
    try {
      final settings = _container!.read(notificationSoundServiceProvider);
      return settings.inAppVibrate;
    } catch (e) {
      return true;
    }
  }
}

/// 通知类型
enum NotificationType {
  privateMessage, // 私聊消息
  groupMessage, // 群组消息
  channelMessage, // 频道消息
  momentLike, // 动态点赞
  momentComment, // 动态评论
  momentReply, // 动态回复
}

/// 通知音效设置状态
class NotificationSoundSettings {
  final bool masterEnabled;
  final bool messageNotification;
  final bool groupNotification;
  final bool channelNotification;
  final bool momentNotification; // 动态通知开关
  final bool showPreview;
  final bool soundEnabled;
  final bool vibrateEnabled;
  final bool momentSound; // 动态声音开关
  final bool inAppSound;
  final bool inAppVibrate;
  final SoundOption selectedSound;

  const NotificationSoundSettings({
    this.masterEnabled = true,
    this.messageNotification = true,
    this.groupNotification = true,
    this.channelNotification = true,
    this.momentNotification = true,
    this.showPreview = true,
    this.soundEnabled = true,
    this.vibrateEnabled = true,
    this.momentSound = true,
    this.inAppSound = true,
    this.inAppVibrate = true,
    this.selectedSound = SoundOption.coin,
  });

  NotificationSoundSettings copyWith({
    bool? masterEnabled,
    bool? messageNotification,
    bool? groupNotification,
    bool? channelNotification,
    bool? momentNotification,
    bool? showPreview,
    bool? soundEnabled,
    bool? vibrateEnabled,
    bool? momentSound,
    bool? inAppSound,
    bool? inAppVibrate,
    SoundOption? selectedSound,
  }) {
    return NotificationSoundSettings(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      messageNotification: messageNotification ?? this.messageNotification,
      groupNotification: groupNotification ?? this.groupNotification,
      channelNotification: channelNotification ?? this.channelNotification,
      momentNotification: momentNotification ?? this.momentNotification,
      showPreview: showPreview ?? this.showPreview,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
      momentSound: momentSound ?? this.momentSound,
      inAppSound: inAppSound ?? this.inAppSound,
      inAppVibrate: inAppVibrate ?? this.inAppVibrate,
      selectedSound: selectedSound ?? this.selectedSound,
    );
  }
}

/// 通知音效服务
class NotificationSoundService
    extends StateNotifier<NotificationSoundSettings> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Ref _ref;
  bool _isPlaying = false;
  bool _isDisposed = false;
  final String _accountId;

  NotificationSoundService(this._ref, this._accountId)
      : super(const NotificationSoundSettings()) {
    if (_accountId.isNotEmpty) _loadSettings();
  }

  String _key(String name) {
    // 设置按账号哈希隔离，避免多账号共用通知偏好，也不在本地键名暴露账号 ID。
    final accountHash = sha256.convert(utf8.encode(_accountId));
    return 'acct_v1_${accountHash}_$name';
  }

  bool get _canUseAccount =>
      !_isDisposed &&
      _accountId.isNotEmpty &&
      _ref
          .read(accountSessionCoordinatorProvider.notifier)
          .isActiveAccount(_accountId);

  /// 从本地存储加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 等待存储期间可能发生切号，旧实例不得再覆盖当前账号状态。
      if (!_canUseAccount) return;

      final soundIndex = prefs.getInt(_key('notification_sound_type')) ?? 0;
      final selectedSound = SoundOption
          .values[soundIndex.clamp(0, SoundOption.values.length - 1)];

      state = NotificationSoundSettings(
        masterEnabled:
            prefs.getBool(_key('notification_master_enabled')) ?? true,
        messageNotification:
            prefs.getBool(_key('notification_message')) ?? true,
        groupNotification: prefs.getBool(_key('notification_group')) ?? true,
        channelNotification:
            prefs.getBool(_key('notification_channel')) ?? true,
        momentNotification: prefs.getBool(_key('notification_moment')) ?? true,
        showPreview: prefs.getBool(_key('notification_preview')) ?? true,
        soundEnabled: prefs.getBool(_key('notification_sound')) ?? true,
        vibrateEnabled: prefs.getBool(_key('notification_vibrate')) ?? true,
        momentSound: prefs.getBool(_key('notification_moment_sound')) ?? true,
        inAppSound: prefs.getBool(_key('notification_inapp_sound')) ?? true,
        inAppVibrate: prefs.getBool(_key('notification_inapp_vibrate')) ?? true,
        selectedSound: selectedSound,
      );
      await AndroidMessageNotificationService.instance
          .setMasterEnabled(state.masterEnabled);
    } catch (e) {
      // 使用默认设置
    }
  }

  /// 保存设置
  Future<void> saveSettings(NotificationSoundSettings settings) async {
    if (!_canUseAccount) return;
    final oldShowPreview = state.showPreview;
    final oldMasterEnabled = state.masterEnabled;
    state = settings;

    final prefs = await SharedPreferences.getInstance();
    // 写盘前再次确认账号，避免异步获取存储实例后把设置写到已退出账号。
    if (!_canUseAccount) return;
    await prefs.setBool(
        _key('notification_master_enabled'), settings.masterEnabled);
    await prefs.setBool(
        _key('notification_message'), settings.messageNotification);
    await prefs.setBool(_key('notification_group'), settings.groupNotification);
    await prefs.setBool(
        _key('notification_channel'), settings.channelNotification);
    await prefs.setBool(
        _key('notification_moment'), settings.momentNotification);
    await prefs.setBool(_key('notification_preview'), settings.showPreview);
    await prefs.setBool(_key('notification_sound'), settings.soundEnabled);
    await prefs.setBool(_key('notification_vibrate'), settings.vibrateEnabled);
    await prefs.setBool(
        _key('notification_moment_sound'), settings.momentSound);
    await prefs.setBool(_key('notification_inapp_sound'), settings.inAppSound);
    await prefs.setBool(
        _key('notification_inapp_vibrate'), settings.inAppVibrate);
    await prefs.setInt(
        _key('notification_sound_type'), settings.selectedSound.index);
    await AndroidMessageNotificationService.instance
        .setMasterEnabled(settings.masterEnabled);

    // 本地设置负责应用内行为，原生镜像负责 Flutter 停止时的拦截；
    // 预览和总开关变化还需同步后端，三处状态职责不同。
    if (oldShowPreview != settings.showPreview ||
        oldMasterEnabled != settings.masterEnabled) {
      _syncPushSettingsToServer(
        showPreview: settings.showPreview,
        enabled: settings.masterEnabled,
      );
    }
  }

  /// 同步推送设置到后端
  Future<void> _syncPushSettingsToServer({
    required bool showPreview,
    required bool enabled,
  }) async {
    if (!_canUseAccount) return;
    try {
      final api = _ref.read(apiClientProvider);
      await api.put('/user/push-settings', data: {
        'show_preview': showPreview,
        'enabled': enabled,
      });
      debugPrint(
          '[NotificationService] Push settings synced: enabled=$enabled showPreview=$showPreview');
    } catch (e) {
      debugPrint('[NotificationService] Failed to sync push settings: $e');
    }
  }

  /// 初始化时同步设置到后端（确保后端状态一致）
  Future<void> syncSettingsToServer() async {
    await _syncPushSettingsToServer(
      showPreview: state.showPreview,
      enabled: state.masterEnabled,
    );
  }

  /// 播放通知音效
  Future<void> playNotificationSound(NotificationType type,
      {bool isInApp = true}) async {
    // 检查是否应该播放声音
    if (!_shouldPlaySound(type, isInApp)) return;

    // 获取要播放的音效
    final sound = state.selectedSound;
    if (sound.assetPath == null) return;

    // 防止重复播放
    if (_isPlaying) return;

    try {
      _isPlaying = true;
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(sound.assetPath!));

      // 播放完成后重置状态
      _audioPlayer.onPlayerComplete.first.then((_) {
        _isPlaying = false;
      });
    } catch (e) {
      _isPlaying = false;
    }
  }

  /// 播放振动
  Future<void> playVibration(NotificationType type,
      {bool isInApp = true}) async {
    if (!_shouldVibrate(type, isInApp)) return;

    HapticFeedback.mediumImpact();
  }

  /// 播放通知（声音 + 振动）
  Future<void> playNotification(NotificationType type,
      {bool isInApp = true}) async {
    await Future.wait([
      playNotificationSound(type, isInApp: isInApp),
      playVibration(type, isInApp: isInApp),
    ]);
  }

  /// 检查是否应该播放声音
  bool _shouldPlaySound(NotificationType type, bool isInApp) {
    if (!state.masterEnabled) return false;
    // 应用内检查
    if (isInApp && !state.inAppSound) return false;
    // 应用外检查
    if (!isInApp && !state.soundEnabled) return false;

    // 根据通知类型检查
    switch (type) {
      case NotificationType.privateMessage:
        return state.messageNotification;
      case NotificationType.groupMessage:
        return state.groupNotification;
      case NotificationType.channelMessage:
        return state.channelNotification;
      case NotificationType.momentLike:
      case NotificationType.momentComment:
      case NotificationType.momentReply:
        return state.momentNotification && state.momentSound;
    }
  }

  /// 检查是否应该振动
  bool _shouldVibrate(NotificationType type, bool isInApp) {
    if (!state.masterEnabled) return false;
    // 应用内检查
    if (isInApp && !state.inAppVibrate) return false;
    // 应用外检查
    if (!isInApp && !state.vibrateEnabled) return false;

    // 根据通知类型检查
    switch (type) {
      case NotificationType.privateMessage:
        return state.messageNotification;
      case NotificationType.groupMessage:
        return state.groupNotification;
      case NotificationType.channelMessage:
        return state.channelNotification;
      case NotificationType.momentLike:
      case NotificationType.momentComment:
      case NotificationType.momentReply:
        return state.momentNotification;
    }
  }

  /// 预览播放音效
  Future<void> previewSound(SoundOption sound) async {
    if (sound.assetPath == null) return;

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(sound.assetPath!));
    } catch (e) {
      // 忽略错误
    }
  }

  /// 检查是否应该显示通知（用于推送通知内容）
  bool shouldShowNotification(NotificationType type) {
    // 这里只判定应用业务开关；系统通知权限由各平台通知服务单独处理。
    if (!state.masterEnabled) return false;
    switch (type) {
      case NotificationType.privateMessage:
        return state.messageNotification;
      case NotificationType.groupMessage:
        return state.groupNotification;
      case NotificationType.channelMessage:
        return state.channelNotification;
      case NotificationType.momentLike:
      case NotificationType.momentComment:
      case NotificationType.momentReply:
        return state.momentNotification;
    }
  }

  /// 检查是否应该显示消息预览内容
  bool shouldShowPreview() {
    return state.showPreview;
  }

  /// 获取当前设置状态（用于调试）
  Map<String, dynamic> getSettingsDebugInfo() {
    return {
      'messageNotification': state.messageNotification,
      'masterEnabled': state.masterEnabled,
      'groupNotification': state.groupNotification,
      'channelNotification': state.channelNotification,
      'momentNotification': state.momentNotification,
      'showPreview': state.showPreview,
      'soundEnabled': state.soundEnabled,
      'vibrateEnabled': state.vibrateEnabled,
      'momentSound': state.momentSound,
      'inAppSound': state.inAppSound,
      'inAppVibrate': state.inAppVibrate,
      'selectedSound': state.selectedSound.localizedLabel,
    };
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _audioPlayer.dispose();
    super.dispose();
  }
}

/// Provider
final notificationSoundServiceProvider =
    StateNotifierProvider<NotificationSoundService, NotificationSoundSettings>(
        (ref) {
  final accountId = ref.watch(currentAccountIdProvider);
  return NotificationSoundService(ref, accountId);
});
