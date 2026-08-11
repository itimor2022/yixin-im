// 文件用途：实现 NotificationSettingsPage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 NotificationSettingsPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

import '../../../core/services/android_notification_settings_service.dart';
import '../../../core/services/background_keep_alive_policy.dart';
import '../../../core/services/background_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/adaptive_settings_tile.dart';
import '../../../shared/widgets/themed_app_bar.dart';

String _notificationText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：notification settings page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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
  String _androidManufacturer = '';
  String _androidBrandLabel = 'Android';
  AndroidBackgroundRestrictionStatus? _backgroundRestrictionStatus;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationPermissionStatus();
    _loadAndroidBrand();
    _loadBackgroundRestrictionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 用户可能刚从系统设置返回，系统权限和厂商后台限制都需要重新读取。
      _refreshNotificationPermissionStatus();
      _loadAndroidBrand();
      _loadBackgroundRestrictionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(notificationSoundServiceProvider);
    final keepAliveMode = ref.watch(backgroundKeepAlivePolicyProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 桌面面板模式：只返回内容
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, settings, keepAliveMode, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: ThemedAppBar(
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
      body: _buildBody(isDark, settings, keepAliveMode, l10n),
    );
  }

  Widget _buildBody(
    bool isDark,
    NotificationSoundSettings settings,
    BackgroundKeepAliveMode keepAliveMode,
    AppLocalizations l10n,
  ) {
    return ListView(
      children: [
        const SizedBox(height: 24),

        if (Platform.isAndroid) ...[
          _SectionTitle(
            title: _notificationText(
              context,
              zhCN: '系统通知权限',
              zhTW: '系統通知權限',
              en: 'System Notification Permission',
            ),
            isDark: isDark,
          ),
          _SettingsCard(
            isDark: isDark,
            children: [
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '允许系统通知',
                  zhTW: '允許系統通知',
                  en: 'Allow System Notifications',
                ),
                subtitle: _notificationPermissionLabel(),
                isDark: isDark,
                onTap: _openNotificationSettings,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: _notificationText(
              context,
              zhCN: '安卓后台保护',
              zhTW: 'Android 背景保護',
              en: 'Android Background Protection',
            ),
            isDark: isDark,
          ),
          _SettingsCard(
            isDark: isDark,
            children: [
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '后台接收设置引导',
                  zhTW: '背景接收設定引導',
                  en: 'Background Delivery Guide',
                ),
                subtitle: _androidBrandLabel,
                isDark: isDark,
                onTap: _openAndroidProtectionGuide,
              ),
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '打开电池设置',
                  zhTW: '開啟電池設定',
                  en: 'Open Battery Settings',
                ),
                subtitle: _notificationText(
                  context,
                  zhCN: _backgroundRestrictionStatus?.needsAttention == true
                      ? '检测到后台限制，请处理'
                      : '未检测到系统限制',
                  zhTW: _backgroundRestrictionStatus?.needsAttention == true
                      ? '已偵測到背景/電池限制，點擊處理'
                      : '未偵測到系統限制',
                  en: _backgroundRestrictionStatus?.needsAttention == true
                      ? 'Background or battery restriction detected'
                      : 'No system restriction detected',
                ),
                isDark: isDark,
                onTap: _openBatterySettings,
              ),
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '打开自启动设置',
                  zhTW: '開啟自啟動設定',
                  en: 'Open Auto-Start Settings',
                ),
                subtitle: _notificationText(
                  context,
                  zhCN: '允许后台活动',
                  zhTW: '允許背景活動',
                  en: 'Allow background activity',
                ),
                isDark: isDark,
                onTap: _openAutoStartSettings,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: _notificationText(
              context,
              zhCN: '消息保活模式',
              zhTW: '訊息保活模式',
              en: 'Message Keep-Alive Mode',
            ),
            isDark: isDark,
          ),
          _SettingsCard(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: _notificationText(
                  context,
                  zhCN: '增强保活',
                  zhTW: '增強保活',
                  en: 'Enhanced Keep-Alive',
                ),
                subtitle: keepAliveMode == BackgroundKeepAliveMode.enhanced
                    ? _notificationText(
                        context,
                        zhCN: '后台连接更积极，可能增加耗电和发热',
                        zhTW: '背景連線更積極，可能增加耗電和發熱',
                        en: 'Keeps background connection more aggressively and may use more battery',
                      )
                    : _notificationText(
                        context,
                        zhCN: '默认省电模式：短后台尽量实时，长锁屏走系统推送',
                        zhTW: '預設省電模式：短背景盡量即時，長鎖屏走系統推送',
                        en: 'Balanced mode: short background is near real-time, long lock uses push',
                      ),
                value: keepAliveMode == BackgroundKeepAliveMode.enhanced,
                isDark: isDark,
                onChanged: _updateKeepAliveMode,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        // 消息通知
        _SectionTitle(
          title: _notificationText(
            context,
            zhCN: '通知总开关',
            zhTW: '通知總開關',
            en: 'All Notifications',
          ),
          isDark: isDark,
        ),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: _notificationText(
                context,
                zhCN: '允许应用通知',
                zhTW: '允許應用通知',
                en: 'Allow App Notifications',
              ),
              subtitle: _notificationText(
                context,
                zhCN: '关闭后保留下方分类选择，重新开启时自动恢复',
                zhTW: '關閉後保留下方分類選擇，重新開啟時自動恢復',
                en: 'Category choices are preserved and restored when enabled again',
              ),
              value: settings.masterEnabled,
              isDark: isDark,
              onChanged: (v) =>
                  _updateSettings(settings.copyWith(masterEnabled: v)),
            ),
          ],
        ),

        const SizedBox(height: 24),

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
              subtitle: settings.selectedSound.localizedLabel,
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

  Future<void> _updateKeepAliveMode(bool enhanced) async {
    final mode = enhanced
        ? BackgroundKeepAliveMode.enhanced
        : BackgroundKeepAliveMode.balanced;
    await ref.read(backgroundKeepAlivePolicyProvider.notifier).setMode(mode);
    BackgroundService.instance.applyPolicy(mode);
  }

  Future<void> _refreshNotificationPermissionStatus() async {
    if (!Platform.isAndroid) return;
    // 统一服务会合并运行时权限与系统通知总开关，这里只负责展示最新结果。
    final status = await AndroidNotificationSettingsService.status();
    if (!mounted) return;
    setState(() {
      _notificationPermissionStatus = status;
    });
  }

  Future<void> _loadAndroidBrand() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final manufacturer = info.manufacturer.trim();
      final brand = info.brand.trim();
      final label = [manufacturer, brand]
          .where((part) => part.isNotEmpty)
          .toSet()
          .join(' ')
          .trim();
      if (!mounted) return;
      setState(() {
        _androidManufacturer = manufacturer.toLowerCase();
        _androidBrandLabel = label.isEmpty ? 'Android' : label;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _androidManufacturer = '';
        _androidBrandLabel = 'Android';
      });
    }
  }

  Future<void> _loadBackgroundRestrictionStatus() async {
    final status =
        await AndroidNotificationSettingsService.backgroundRestrictionStatus();
    if (!mounted) return;
    setState(() => _backgroundRestrictionStatus = status);
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

  Future<void> _openBatterySettings() async {
    HapticFeedback.selectionClick();
    await AndroidNotificationSettingsService.openBatterySettings();
  }

  Future<void> _openAutoStartSettings() async {
    HapticFeedback.selectionClick();
    await AndroidNotificationSettingsService.openAutoStartSettings();
  }

  void _openAndroidProtectionGuide() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AndroidBackgroundProtectionPage(
          manufacturer: _androidManufacturer,
          brandLabel: _androidBrandLabel,
        ),
      ),
    );
  }

  String _notificationPermissionLabel() {
    final status = _notificationPermissionStatus;
    if (status == null) {
      return _notificationText(
        context,
        zhCN: '正在检查',
        zhTW: '正在檢查',
        en: 'Checking',
      );
    }
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.provisional:
      case PermissionStatus.limited:
        return _notificationText(
          context,
          zhCN: '已允许',
          zhTW: '已允許',
          en: 'Allowed',
        );
      case PermissionStatus.denied:
        return _notificationText(
          context,
          zhCN: '未允许，点击去开启',
          zhTW: '未允許，點擊去開啟',
          en: 'Not allowed, tap to enable',
        );
      case PermissionStatus.permanentlyDenied:
      case PermissionStatus.restricted:
        return _notificationText(
          context,
          zhCN: '已关闭，点击去系统设置开启',
          zhTW: '已關閉，點擊到系統設定開啟',
          en: 'Disabled, tap to open system settings',
        );
    }
  }

  void _showSoundPicker(
      NotificationSoundSettings settings, AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final soundService = ref.read(notificationSoundServiceProvider.notifier);

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示条
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
                  color: AppColors.textTertiaryFor(context),
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
                color: AppColors.textSecondaryFor(context),
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

class _AndroidBackgroundProtectionPage extends StatelessWidget {
  final String manufacturer;
  final String brandLabel;

  const _AndroidBackgroundProtectionPage({
    required this.manufacturer,
    required this.brandLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _notificationText(
      context,
      zhCN: '安卓后台保护',
      zhTW: 'Android 背景保護',
      en: 'Android Background Protection',
    );
    final steps = _stepsForManufacturer(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          _GuideInfoCard(
            isDark: isDark,
            icon: Icons.shield_outlined,
            title: _notificationText(
              context,
              zhCN: '$brandLabel 后台接收建议',
              zhTW: '$brandLabel 背景接收建議',
              en: '$brandLabel delivery checklist',
            ),
            body: _notificationText(
              context,
              zhCN: '安卓系统会按厂商策略限制后台运行。请完成下面设置，减少手动划掉、锁屏或省电模式导致的消息延迟。',
              zhTW: 'Android 會依廠商策略限制背景執行。請完成以下設定，減少手動關閉、鎖屏或省電模式造成的訊息延遲。',
              en: 'Android vendors can restrict background work. Complete these settings to reduce delays after recents cleanup, lock screen, or battery saver.',
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: _notificationText(
              context,
              zhCN: '设置步骤',
              zhTW: '設定步驟',
              en: 'Setup Steps',
            ),
            isDark: isDark,
          ),
          _SettingsCard(
            isDark: isDark,
            children: [
              for (var i = 0; i < steps.length; i++)
                _GuideStepTile(
                  index: i + 1,
                  title: steps[i].title,
                  body: steps[i].body,
                  isDark: isDark,
                ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: _notificationText(
              context,
              zhCN: '快捷入口',
              zhTW: '快速入口',
              en: 'Shortcuts',
            ),
            isDark: isDark,
          ),
          _SettingsCard(
            isDark: isDark,
            children: [
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '系统通知设置',
                  zhTW: '系統通知設定',
                  en: 'System Notification Settings',
                ),
                subtitle: _notificationText(
                  context,
                  zhCN: '允许通知',
                  zhTW: '允許通知',
                  en: 'Allow notifications',
                ),
                isDark: isDark,
                onTap: AndroidNotificationSettingsService.open,
              ),
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '电池设置',
                  zhTW: '電池設定',
                  en: 'Battery Settings',
                ),
                subtitle: _notificationText(
                  context,
                  zhCN: '不限制后台',
                  zhTW: '不限制背景',
                  en: 'Unrestricted',
                ),
                isDark: isDark,
                onTap: AndroidNotificationSettingsService.openBatterySettings,
              ),
              _TapTile(
                title: _notificationText(
                  context,
                  zhCN: '自启动设置',
                  zhTW: '自啟動設定',
                  en: 'Auto-Start Settings',
                ),
                subtitle: _notificationText(
                  context,
                  zhCN: '允许自启动和后台活动',
                  zhTW: '允許自啟動和背景活動',
                  en: 'Allow auto-start and background activity',
                ),
                isDark: isDark,
                onTap: AndroidNotificationSettingsService.openAutoStartSettings,
              ),
            ],
          ),
          const SizedBox(height: 32),
          _GuideInfoCard(
            isDark: isDark,
            icon: Icons.info_outline_rounded,
            title: _notificationText(
              context,
              zhCN: '手动强停后的限制',
              zhTW: '手動強停後的限制',
              en: 'Manual Force-Stop Limitation',
            ),
            body: _notificationText(
              context,
              zhCN: '如果系统把应用标记为已强行停止，任何推送都不能保证立即显示。重新打开一次应用后会恢复接收。',
              zhTW: '如果系統把應用標記為已強制停止，任何推播都不能保證立即顯示。重新開啟一次應用後會恢復接收。',
              en: 'If the system marks the app as force-stopped, no push channel can guarantee immediate delivery. Open the app once to restore receiving.',
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  List<_GuideStepData> _stepsForManufacturer(BuildContext context) {
    final common = [
      _GuideStepData(
        title: _notificationText(
          context,
          zhCN: '允许系统通知',
          zhTW: '允許系統通知',
          en: 'Allow system notifications',
        ),
        body: _notificationText(
          context,
          zhCN: '确保通知权限、锁屏通知和声音/振动没有被关闭。',
          zhTW: '確認通知權限、鎖屏通知和聲音/震動沒有被關閉。',
          en: 'Make sure notifications, lock-screen alerts, sound, and vibration are enabled.',
        ),
      ),
      _GuideStepData(
        title: _notificationText(
          context,
          zhCN: '电池策略设为不限制',
          zhTW: '電池策略設為不限制',
          en: 'Set battery usage to unrestricted',
        ),
        body: _notificationText(
          context,
          zhCN: '在应用电池设置中选择不限制、允许后台运行或关闭深度省电。',
          zhTW: '在應用電池設定中選擇不限制、允許背景執行或關閉深度省電。',
          en: 'In app battery settings, choose unrestricted, allow background activity, or disable deep battery saving.',
        ),
      ),
    ];

    final vendor = manufacturer.toLowerCase();
    if (vendor.contains('huawei') || vendor.contains('honor')) {
      return [
        ...common,
        _GuideStepData(
          title: '华为/荣耀：允许自启动、关联启动、后台活动',
          body: '进入应用启动管理，关闭自动管理，然后打开自启动、关联启动、后台活动。',
        ),
        _GuideStepData(
          title: '华为/荣耀：不要从最近任务强行划掉',
          body: '部分机型划掉最近任务会触发 iAware 强停。强停后需要重新打开 App 才能恢复推送。',
        ),
      ];
    }
    if (vendor.contains('xiaomi') || vendor.contains('redmi')) {
      return [
        ...common,
        _GuideStepData(
          title: '小米/Redmi：开启自启动',
          body: '进入手机管家或安全中心，允许应用自启动，并在省电策略中选择无限制。',
        ),
        _GuideStepData(
          title: '小米/Redmi：锁定最近任务',
          body: '在最近任务中长按应用卡片并锁定，避免被一键清理。',
        ),
      ];
    }
    if (vendor.contains('oppo') ||
        vendor.contains('oneplus') ||
        vendor.contains('realme')) {
      return [
        ...common,
        _GuideStepData(
          title: 'OPPO/realme/一加：允许自启动',
          body: '在应用管理或手机管家中允许自启动，并允许后台耗电。',
        ),
        _GuideStepData(
          title: 'OPPO/realme/一加：关闭后台冻结',
          body: '在电池设置中关闭睡眠待机优化或后台冻结限制。',
        ),
      ];
    }
    if (vendor.contains('vivo') || vendor.contains('iqoo')) {
      return [
        ...common,
        _GuideStepData(
          title: 'vivo/iQOO：允许后台高耗电',
          body: '进入电池或 i管家，允许后台高耗电和自启动。',
        ),
        _GuideStepData(
          title: 'vivo/iQOO：加入白名单',
          body: '在后台管理中把应用加入白名单，避免被一键加速清理。',
        ),
      ];
    }
    if (vendor.contains('samsung')) {
      return [
        ...common,
        _GuideStepData(
          title: '三星：取消休眠限制',
          body: '在电池和设备维护中，将应用从睡眠/深度睡眠列表移除。',
        ),
        _GuideStepData(
          title: '三星：允许后台活动',
          body: '在应用电池设置中允许后台活动，并关闭未使用应用自动休眠。',
        ),
      ];
    }
    return [
      ...common,
      _GuideStepData(
        title: _notificationText(
          context,
          zhCN: '允许自启动和后台活动',
          zhTW: '允許自啟動和背景活動',
          en: 'Allow auto-start and background activity',
        ),
        body: _notificationText(
          context,
          zhCN: '在系统应用管理、电池或安全中心里，允许应用自启动和后台运行。',
          zhTW: '在系統應用管理、電池或安全中心裡，允許應用自啟動和背景執行。',
          en: 'In app management, battery, or security settings, allow auto-start and background activity.',
        ),
      ),
      _GuideStepData(
        title: _notificationText(
          context,
          zhCN: '避免一键清理或强行停止',
          zhTW: '避免一鍵清理或強制停止',
          en: 'Avoid one-tap cleanup or force stop',
        ),
        body: _notificationText(
          context,
          zhCN: '如果系统把应用强行停止，必须重新打开一次应用后才能恢复推送。',
          zhTW: '如果系統把應用強制停止，必須重新開啟一次應用後才能恢復推播。',
          en: 'If the system force-stops the app, open it once to restore push delivery.',
        ),
      ),
    ];
  }
}

class _GuideStepData {
  final String title;
  final String body;

  const _GuideStepData({required this.title, required this.body});
}

class _GuideInfoCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String body;

  const _GuideInfoCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.linkFor(context), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStepTile extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final bool isDark;

  const _GuideStepTile({
    required this.index,
    required this.title,
    required this.body,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.emphasisSoftFor(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.linkFor(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
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
                    color: AppColors.emphasisSoftFor(context),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.linkFor(context),
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
                  color: AppColors.textTertiaryFor(context),
                  size: 20,
                ),
              ),
            const SizedBox(width: 14),
            // 标题
            Expanded(
              child: Text(
                sound.localizedLabel,
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
                color: AppColors.controlActiveFor(context),
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
          color: AppColors.textTertiaryFor(context),
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
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.controlActiveFor(context),
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
    return AdaptiveSettingsTapTile(
      title: title,
      subtitle: subtitle,
      titleStyle: TextStyle(
        fontSize: 16,
        color: titleColor ?? (isDark ? Colors.white : Colors.black),
      ),
      subtitleStyle: TextStyle(
        fontSize: 14,
        height: 1.3,
        color: AppColors.textTertiaryFor(context),
      ),
      chevronColor: isDark ? Colors.white24 : Colors.black26,
      onTap: onTap,
      showChevron: subtitle != null,
    );
  }
}
