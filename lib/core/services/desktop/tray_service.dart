// 文件用途：实现 TrayService 相关逻辑，服务于业务服务。
// 核心逻辑：围绕 TrayService 组织，完成输入校验、核心处理和结果回传。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/platform_utils.dart';
import '../api/system_settings_service.dart';
import 'window_service.dart';

// 关键声明：tray service 把桌面系统能力封装成应用接口，处理窗口、托盘或快捷键生命周期并避免泄漏监听器。
/// 管理桌面系统托盘图标、菜单、未读提示和窗口显隐入口。
///
/// 托盘插件只在物理桌面初始化；初始化失败会保留应用主窗口功能，并允许日志
/// 记录失败原因。菜单文案来自本地缓存，网络设置刷新后需调用 [refreshLabels]。
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._();
  static TrayService get instance => _instance;
  TrayService._();

  bool _initialized = false;
  bool _isDisposed = false;
  int _unreadCount = 0;
  String _appDisplayName = defaultAppDisplayName();

  String _trayText({
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

  Menu _buildMenu() {
    return Menu(
      items: [
        MenuItem(
          key: 'show',
          label: _trayText(
            zhCN: '打开$_appDisplayName',
            zhTW: '打開$_appDisplayName',
            en: 'Open $_appDisplayName',
          ),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'mute',
          label: _trayText(
            zhCN: '免打扰模式',
            zhTW: '勿擾模式',
            en: 'Do Not Disturb',
          ),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'about',
          label: _trayText(
            zhCN: '关于$_appDisplayName',
            zhTW: '關於$_appDisplayName',
            en: 'About $_appDisplayName',
          ),
        ),
        MenuItem(
          key: 'exit',
          label: _trayText(
            zhCN: '退出',
            zhTW: '退出',
            en: 'Exit',
          ),
        ),
      ],
    );
  }

  String _buildTooltip() {
    if (_unreadCount <= 0) return _appDisplayName;
    return _trayText(
      zhCN: '$_appDisplayName ($_unreadCount 条未读)',
      zhTW: '$_appDisplayName ($_unreadCount 則未讀)',
      en: '$_appDisplayName ($_unreadCount unread)',
    );
  }

  Future<void> initialize() async {
    if (!PlatformUtils.isPhysicalDesktop || _initialized) return;

    await _loadDisplayName();

    try {
      String iconPath;
      if (PlatformUtils.isWindows) {
        iconPath = 'assets/logo.ico';
      } else {
        iconPath = 'assets/logo.png';
      }

      // 资源图标缺失时仅 macOS 可退回系统 AppIcon，其他平台继续尝试初始化菜单。
      try {
        await rootBundle.load(iconPath);
        await trayManager.setIcon(iconPath);
      } catch (e) {
        debugPrint('[Tray] Icon not found at $iconPath, using fallback');
        if (PlatformUtils.isMacOS) {
          await trayManager.setIcon('AppIcon');
        }
      }

      await trayManager.setToolTip(_buildTooltip());
      await trayManager.setContextMenu(_buildMenu());
      trayManager.addListener(this);

      _initialized = true;
      debugPrint('[Tray] Initialized');
    } catch (e) {
      debugPrint('[Tray] Failed to initialize: $e');
    }
  }

  Future<void> _loadDisplayName() async {
    try {
      // 启动阶段不发网络请求，避免托盘初始化依赖后端可用性。
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('system_settings_cache');
      if (cached != null && cached.isNotEmpty) {
        final settings = SystemSettings.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
        _appDisplayName = settings.displayName;
      }
    } catch (e) {
      debugPrint('[Tray] Failed to load app name: $e');
    }
  }

  Future<void> refreshLabels() async {
    if (!PlatformUtils.isPhysicalDesktop || !_initialized) return;
    await _loadDisplayName();
    try {
      await trayManager.setContextMenu(_buildMenu());
      await trayManager.setToolTip(_buildTooltip());
    } catch (e) {
      debugPrint('[Tray] Failed to refresh labels: $e');
    }
  }

  Future<void> updateUnreadCount(int count) async {
    if (!PlatformUtils.isPhysicalDesktop) return;

    // 始终先保存内存状态，托盘稍后初始化或刷新时仍能生成正确提示。
    _unreadCount = count;

    try {
      await trayManager.setToolTip(_buildTooltip());
    } catch (e) {
      debugPrint('[Tray] Failed to update tooltip: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    _toggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  VoidCallback? onAboutClicked;
  VoidCallback? onMuteToggled;

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _onOpenClicked();
        break;
      case 'mute':
        onMuteToggled?.call();
        break;
      case 'about':
        _onOpenClicked();
        onAboutClicked?.call();
        break;
      case 'exit':
        _onExitClicked();
        break;
    }
  }

  void _toggleWindow() {
    // 是否隐藏以 WindowService 为唯一权威，避免仅凭系统窗口可见性误判。
    final windowService = WindowService.instance;
    if (windowService.isMinimizedToTray) {
      windowService.restoreFromTray();
    } else {
      windowService.minimizeToTray();
    }
  }

  void _onOpenClicked() {
    WindowService.instance.restoreFromTray();
  }

  void _onExitClicked() {
    WindowService.instance.close();
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_initialized) {
      try {
        // 先移除回调再销毁原生托盘，防止释放过程中继续收到菜单事件。
        trayManager.removeListener(this);
        await trayManager.destroy();
      } catch (e) {
        debugPrint('[Tray] Dispose error: $e');
      }
    }
    _initialized = false;
    debugPrint('[Tray] Disposed');
  }
}
