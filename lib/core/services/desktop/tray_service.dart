import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../utils/platform_utils.dart';
import '../api/system_settings_service.dart';
import 'window_service.dart';

/// 系统托盘服务
/// 仅在 macOS/Windows/Linux 上使用
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._();
  static TrayService get instance => _instance;
  TrayService._();

  bool _initialized = false;
  bool _isDisposed = false;
  int _unreadCount = 0;
  String _appDisplayName = kDefaultAppDisplayName;

  /// 初始化系统托盘
  Future<void> initialize() async {
    if (!PlatformUtils.isPhysicalDesktop || _initialized) return;

    await _loadDisplayName();

    try {
      // 设置托盘图标（检查文件是否可用）
      String iconPath;
      if (PlatformUtils.isWindows) {
        iconPath = 'assets/logo.ico';
      } else {
        iconPath = 'assets/logo.png';
      }

      // 尝试加载图标资源验证其存在
      try {
        await rootBundle.load(iconPath);
        await trayManager.setIcon(iconPath);
      } catch (e) {
        debugPrint('[Tray] Icon not found at $iconPath, using fallback');
        // 使用默认应用图标作为后备
        if (PlatformUtils.isMacOS) {
          // macOS 可以使用应用图标
          await trayManager.setIcon('AppIcon');
        }
      }

      // 设置工具提示
      await trayManager.setToolTip(_appDisplayName);

      // 创建菜单（增加更多选项）
      final menu = Menu(
        items: [
          MenuItem(key: 'show', label: '打开$_appDisplayName'),
          MenuItem.separator(),
          MenuItem(key: 'mute', label: '免打扰模式'),
          MenuItem.separator(),
          MenuItem(key: 'about', label: '关于$_appDisplayName'),
          MenuItem(key: 'exit', label: '退出'),
        ],
      );

      await trayManager.setContextMenu(menu);

      // 添加监听器
      trayManager.addListener(this);

      _initialized = true;
      debugPrint('[Tray] Initialized');
    } catch (e) {
      debugPrint('[Tray] Failed to initialize: $e');
    }
  }

  Future<void> _loadDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('system_settings_cache');
      if (cached != null && cached.isNotEmpty) {
        final settings = SystemSettings.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        _appDisplayName = settings.displayName;
      }
    } catch (e) {
      debugPrint('[Tray] Failed to load app name: $e');
    }
  }

  /// 更新未读消息数
  Future<void> updateUnreadCount(int count) async {
    if (!PlatformUtils.isPhysicalDesktop) return;

    _unreadCount = count;

    // 更新提示文字
    String tooltip = _appDisplayName;
    if (count > 0) {
      tooltip = '$_appDisplayName ($count 条未读)';
    }

    try {
      await trayManager.setToolTip(tooltip);
    } catch (e) {
      debugPrint('[Tray] Failed to update tooltip: $e');
    }
  }

  // ===== TrayListener 回调 =====

  @override
  void onTrayIconMouseDown() {
    // 单击托盘图标：切换窗口显示
    _toggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键：显示菜单
    trayManager.popUpContextMenu();
  }

  // 回调
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

  /// 切换窗口显示/隐藏
  void _toggleWindow() {
    final windowService = WindowService.instance;
    if (windowService.isMinimizedToTray) {
      windowService.restoreFromTray();
    } else {
      windowService.minimizeToTray();
    }
  }

  /// 打开窗口
  void _onOpenClicked() {
    WindowService.instance.restoreFromTray();
  }

  /// 退出应用
  void _onExitClicked() {
    WindowService.instance.close();
  }

  /// 销毁托盘
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_initialized) {
      try {
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
