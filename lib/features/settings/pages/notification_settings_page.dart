import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

import '../../../core/services/android_notification_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/notification_sound_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationPermissionStatus();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(notificationSoundServiceProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 桌面面板模式：只返回内容
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, settings, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.notificationsAndSounds,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark, settings, l10n),
    );
  }

  Widget _buildBody(
      bool isDark, NotificationSoundSettings settings, AppLocalizations l10n) {
    return ListView(
      children: [
        const SizedBox(height: 24),

        if (Platform.isAndroid) ...[
          _SectionTitle(title: '系统通知权限', isDark: isDark),
          _SettingsCard(
            isDark: isDark,
            children: [
              _TapTile(
                title: '允许系统通知',
                subtitle: _notificationPermissionLabel(),
                isDark: isDark,
                onTap: _openNotificationSettings,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // 消息通知
        _SectionTitle(title: l10n.messageNotifications, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.privateMessages,
              value: settings.messageNotification,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(messageNotification: v)),
            ),
            _SwitchTile(
              title: l10n.groupMessages,
              value: settings.groupNotification,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(groupNotification: v)),
            ),
            _SwitchTile(
              title: l10n.channelMessages,
              value: settings.channelNotification,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(channelNotification: v)),
            ),
            _SwitchTile(
              title: l10n.momentNotifications,
              subtitle: l10n.likesCommentsReplies,
              value: settings.momentNotification,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(momentNotification: v)),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 通知预览
        _SectionTitle(title: l10n.notificationContent, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.showMessagePreview,
              subtitle: l10n.showMessageInNotification,
              value: settings.showPreview,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(showPreview: v)),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 声音和振动
        _SectionTitle(title: l10n.soundAndVibration, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.notificationSound,
              value: settings.soundEnabled,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(soundEnabled: v)),
            ),
            _TapTile(
              title: l10n.alertTone,
              subtitle: settings.selectedSound.label,
              isDark: isDark,
              onTap: () => _showSoundPicker(settings, l10n),
            ),
            _SwitchTile(
              title: l10n.momentSound,
              subtitle: l10n.get('likes_comments_play_sound'),
              value: settings.momentSound,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(momentSound: v)),
            ),
            _SwitchTile(
              title: l10n.vibration,
              value: settings.vibrateEnabled,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(vibrateEnabled: v)),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 应用内通知
        _SectionTitle(title: l10n.inAppNotifications, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.inAppSound,
              value: settings.inAppSound,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(inAppSound: v)),
            ),
            _SwitchTile(
              title: l10n.inAppVibration,
              value: settings.inAppVibrate,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(inAppVibrate: v)),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 重置
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.resetAllNotificationSettings,
              titleColor: AppColors.error,
              isDark: isDark,
              onTap: () => _showResetConfirm(l10n),
            ),
          ],
        ),

        const SizedBox(height: 100),
      ],
    );
  }

  void _updateSettings(NotificationSoundSettings settings) {
    ref.read(notificationSoundServiceProvider.notifier).saveSettings(settings);
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 1,
              indent: 16,
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool isDark;
  final VoidCallback onTap;

  const _TapTile({
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: titleColor ?? (isDark ? Colors.white : Colors.black),
                ),
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            if (subtitle != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
