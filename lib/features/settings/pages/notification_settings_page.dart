import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/web_notification_permission.dart';

import '../../../core/services/android_notification_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/settings_ui.dart';

const Color _kNotifPrimary = Color(0xFFFF6B6B);

/// 通知和声音设置页面
class NotificationSettingsPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const NotificationSettingsPage({
    super.key,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage>
    with WidgetsBindingObserver {
  PermissionStatus? _notificationPermissionStatus;
  String _webNotificationPermission = 'default'; // 'default' | 'granted' | 'denied'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationPermissionStatus();
    if (kIsWeb) {
      _checkWebNotificationPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPermissionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(notificationSoundServiceProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    return SettingsScaffold(
      title: l10n.notificationsAndSounds,
      isDesktopPanel: widget.isDesktopPanel,
      children: _buildIslands(settings, l10n),
    );
  }

  List<Widget> _buildIslands(
      NotificationSoundSettings settings, AppLocalizations l10n) {
    return [
      if (kIsWeb) ...[
        const SettingsSection('浏览器推送通知'),
        SettingsChoiceIsland(
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFFF9500),
          label: '后台消息推送',
          subtitle: _webNotificationPermission == 'granted'
              ? '已开启，切换到其他标签页时可收到推送'
              : _webNotificationPermission == 'denied'
                  ? '已拒绝，请在浏览器地址栏手动开启'
                  : '点击开启，切换其他标签页仍可收到消息推送',
          trailing: _webNotificationPermission == 'granted'
              ? const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF34C759), size: 20)
              : null,
          onTap: _webNotificationPermission == 'granted'
              ? null
              : () {
                  _requestWebNotificationPermission();
                },
        ),
      ],
      if (!kIsWeb && Platform.isAndroid) ...[
        const SettingsSection('系统通知权限'),
        SettingsChoiceIsland(
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFFF9500),
          label: '允许系统通知',
          value: _notificationPermissionLabel(),
          onTap: _openNotificationSettings,
        ),
      ],

      // 消息通知
      SettingsSection(l10n.messageNotifications),
      SettingsSwitchIsland(
        icon: Icons.chat_bubble_outline_rounded,
        iconColor: _kNotifPrimary,
        label: l10n.privateMessages,
        value: settings.messageNotification,
        onChanged: (v) =>
            _updateSettings(settings.copyWith(messageNotification: v)),
      ),
      SettingsSwitchIsland(
        icon: Icons.groups_2_outlined,
        iconColor: const Color(0xFF34C759),
        label: l10n.groupMessages,
        value: settings.groupNotification,
        onChanged: (v) =>
            _updateSettings(settings.copyWith(groupNotification: v)),
      ),
      SettingsSwitchIsland(
        icon: Icons.campaign_outlined,
        iconColor: const Color(0xFFAF52DE),
        label: l10n.channelMessages,
        value: settings.channelNotification,
        onChanged: (v) =>
            _updateSettings(settings.copyWith(channelNotification: v)),
      ),
      SettingsSwitchIsland(
        icon: Icons.favorite_outline_rounded,
        iconColor: const Color(0xFFFF2D55),
        label: l10n.momentNotifications,
        subtitle: l10n.likesCommentsReplies,
        value: settings.momentNotification,
        onChanged: (v) =>
            _updateSettings(settings.copyWith(momentNotification: v)),
      ),

      // 通知预览
      SettingsSection(l10n.notificationContent),
      SettingsSwitchIsland(
        icon: Icons.preview_rounded,
        iconColor: const Color(0xFF5AC8FA),
        label: l10n.showMessagePreview,
        subtitle: l10n.showMessageInNotification,
        value: settings.showPreview,
        onChanged: (v) => _updateSettings(settings.copyWith(showPreview: v)),
      ),

      // 声音和振动
      SettingsSection(l10n.soundAndVibration),
      SettingsSwitchIsland(
        icon: Icons.volume_up_outlined,
        iconColor: _kNotifPrimary,
        label: l10n.notificationSound,
        value: settings.soundEnabled,
        onChanged: (v) => _updateSettings(settings.copyWith(soundEnabled: v)),
      ),
      SettingsChoiceIsland(
        icon: Icons.music_note_rounded,
        iconColor: const Color(0xFFAF52DE),
        label: l10n.alertTone,
        value: settings.selectedSound.label,
        onTap: () => _showSoundPicker(settings, l10n),
      ),
      SettingsSwitchIsland(
        icon: Icons.notifications_none_rounded,
        iconColor: const Color(0xFFFF2D55),
        label: l10n.momentSound,
        subtitle: l10n.get('likes_comments_play_sound'),
        value: settings.momentSound,
        onChanged: (v) => _updateSettings(settings.copyWith(momentSound: v)),
      ),
      SettingsSwitchIsland(
        icon: Icons.vibration_rounded,
        iconColor: const Color(0xFF34C759),
        label: l10n.vibration,
        value: settings.vibrateEnabled,
        onChanged: (v) =>
            _updateSettings(settings.copyWith(vibrateEnabled: v)),
      ),

      // 应用内通知
      SettingsSection(l10n.inAppNotifications),
      SettingsSwitchIsland(
        icon: Icons.speaker_notes_outlined,
        iconColor: _kNotifPrimary,
        label: l10n.inAppSound,
        value: settings.inAppSound,
        onChanged: (v) => _updateSettings(settings.copyWith(inAppSound: v)),
      ),
      SettingsSwitchIsland(
        icon: Icons.phonelink_ring_outlined,
        iconColor: const Color(0xFF34C759),
        label: l10n.inAppVibration,
        value: settings.inAppVibrate,
        onChanged: (v) => _updateSettings(settings.copyWith(inAppVibrate: v)),
      ),

      // 重置
      const SizedBox(height: 16),
      SettingsChoiceIsland(
        icon: Icons.restart_alt_rounded,
        iconColor: AppColors.error,
        label: l10n.resetAllNotificationSettings,
        labelColor: AppColors.error,
        onTap: () => _showResetConfirm(l10n),
      ),
    ];
  }

  void _updateSettings(NotificationSoundSettings settings) {
    ref.read(notificationSoundServiceProvider.notifier).saveSettings(settings);
  }

  void _checkWebNotificationPermission() {
    if (!kIsWeb) return;
    final permission = getBrowserNotificationPermission();
    setState(() {
      _webNotificationPermission = permission;
    });
  }

  Future<void> _requestWebNotificationPermission() async {
    if (!kIsWeb) return;
    final result = await requestBrowserNotificationPermission();
    if (!mounted) return;
    setState(() { _webNotificationPermission = result; });
    if (result == 'granted') {
      await ref.read(pushNotificationServiceProvider).register();
    }
  }

  Future<void> _refreshNotificationPermissionStatus() async {
    if (!Platform.isAndroid) return;
    final status = await AndroidNotificationSettingsService.status();
    if (!mounted) return;
    setState(() {
      _notificationPermissionStatus = status;
    });
  }

  Future<void> _openNotificationSettings() async {
    HapticFeedback.selectionClick();
    await AndroidNotificationSettingsService.open();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _refreshNotificationPermissionStatus();
      }
    });
  }

  String _notificationPermissionLabel() {
    final status = _notificationPermissionStatus;
    if (status == null) return '正在检查';
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.provisional:
      case PermissionStatus.limited:
        return '已允许';
      case PermissionStatus.denied:
        return '未允许，点击去开启';
      case PermissionStatus.permanentlyDenied:
      case PermissionStatus.restricted:
        return '已关闭，点击去系统设置开启';
    }
  }

  void _showSoundPicker(
      NotificationSoundSettings settings, AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final soundService = ref.read(notificationSoundServiceProvider.notifier);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示条
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.selectAlertTone,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tapToPreview,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 16),
              ...SoundOption.values.map((sound) => _SoundOptionTile(
                    sound: sound,
                    isSelected: settings.selectedSound == sound,
                    isDark: isDark,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      // 播放预览
                      if (sound.assetPath != null) {
                        soundService.previewSound(sound);
                      }
                    },
                    onSelect: () {
                      HapticFeedback.selectionClick();
                      _updateSettings(settings.copyWith(selectedSound: sound));
                      Navigator.pop(context);
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetConfirm(AppLocalizations l10n) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          l10n.resetAllNotificationSettings,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          l10n.confirmResetNotifications,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // 重置为默认设置
              ref.read(notificationSoundServiceProvider.notifier).saveSettings(
                    const NotificationSoundSettings(),
                  );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.resetToDefault),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            child: Text(l10n.reset, style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SoundOptionTile extends StatelessWidget {
  final SoundOption sound;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onSelect;

  const _SoundOptionTile({
    required this.sound,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // 播放按钮（如果有音效）
            if (sound.assetPath != null)
              GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              )
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.volume_off_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                  size: 20,
                ),
              ),
            const SizedBox(width: 14),
            // 标题
            Expanded(
              child: Text(
                sound.label,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            // 选中标记
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

