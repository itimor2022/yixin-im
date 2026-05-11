import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../utils/platform_utils.dart';
import '../api/system_settings_service.dart';

/// 桌面端窗口管理服务
/// 仅在 macOS/Windows/Linux 上使用
class WindowService with WindowListener {
  static final WindowService _instance = WindowService._();
  static WindowService get instance => _instance;
  WindowService._();

  bool _initialized = false;
  bool _isDisposed = false;
  Timer? _saveStateTimer;

  // 窗口状态
  bool _isMaximized = false;
  bool _isFullScreen = false;
  bool _isMinimizedToTray = false;

  // 存储键
  static const String _keyWindowWidth = 'window_width';
  static const String _keyWindowHeight = 'window_height';
  static const String _keyWindowX = 'window_x';
  static const String _keyWindowY = 'window_y';
  static const String _keyWindowMaximized = 'window_maximized';
  static const String _keySidebarWidth = 'sidebar_width';

  Future<String> _loadDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('system_settings_cache');
      if (cached != null && cached.isNotEmpty) {
        final settings = SystemSettings.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        return settings.displayName;
      }
    } catch (e) {
      debugPrint('[Window] Failed to load app name: $e');
    }
    return kDefaultAppDisplayName;
  }

  /// 初始化窗口管理
  Future<void> initialize() async {
    if (!PlatformUtils.isPhysicalDesktop || _initialized) return;

    await windowManager.ensureInitialized();

    // 加载保存的窗口设置
    final prefs = await SharedPreferences.getInstance();
    final savedWidth =
        prefs.getDouble(_keyWindowWidth) ?? PlatformUtils.desktopDefaultWidth;
    final savedHeight =
        prefs.getDouble(_keyWindowHeight) ?? PlatformUtils.desktopDefaultHeight;
    final savedX = prefs.getDouble(_keyWindowX);
    final savedY = prefs.getDouble(_keyWindowY);
    final savedMaximized = prefs.getBool(_keyWindowMaximized) ?? false;
    final appDisplayName = await _loadDisplayName();

    final windowOptions = WindowOptions(
      size: Size(savedWidth, savedHeight),
      center: savedX == null || savedY == null,
      minimumSize: const Size(
        PlatformUtils.desktopMinWidth,
        PlatformUtils.desktopMinHeight,
      ),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: PlatformUtils.isMacOS
          ? TitleBarStyle
                .hidden // macOS 使用自定义标题栏
          : TitleBarStyle.normal,
      title: appDisplayName,
    );

    bool shown = false;

    // 兜底：如果 waitUntilReadyToShow 的回调 5 秒内没触发，强制显示窗口
    final fallbackTimer = Timer(const Duration(seconds: 5), () async {
      if (!shown) {
        shown = true;
        debugPrint('[Window] Fallback: force showing window after timeout');
        try {
          await windowManager.center();
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          debugPrint('[Window] Fallback show error: $e');
        }
      }
    });

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      shown = true;
      fallbackTimer.cancel();

      if (savedX != null && savedY != null) {
        final isOnScreen = await _isPositionOnScreen(savedX, savedY);
        if (isOnScreen) {
          await windowManager.setPosition(Offset(savedX, savedY));
        } else {
          debugPrint('[Window] Saved position off-screen ($savedX, $savedY), centering');
          await windowManager.center();
        }
      }

      if (savedMaximized) {
        await windowManager.maximize();
        _isMaximized = true;
      }

      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);

    _initialized = true;
    debugPrint('[Window] Initialized with size: ${savedWidth}x$savedHeight');
  }

  /// 检测坐标是否在任何一块屏幕的可见区域内
  Future<bool> _isPositionOnScreen(double x, double y) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      for (final display in displays) {
        final vx = display.visiblePosition?.dx ?? 0;
        final vy = display.visiblePosition?.dy ?? 0;
        final vw = display.visibleSize?.width ?? display.size.width;
        final vh = display.visibleSize?.height ?? display.size.height;
        // 窗口左上角在屏幕可见区域内（留 50px 容差）
        if (x >= vx - 50 && y >= vy - 50 && x < vx + vw && y < vy + vh) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('[Window] Screen retriever error: $e');
    }
    return false;
  }

  /// 保存窗口状态（带错误处理）
  Future<void> _saveWindowState() async {
    if (!PlatformUtils.isPhysicalDesktop || _isDisposed) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      final isMaximized = await windowManager.isMaximized();

      // 只有在非最大化时才保存大小和位置
      if (!isMaximized) {
        await prefs.setDouble(_keyWindowWidth, size.width);
        await prefs.setDouble(_keyWindowHeight, size.height);
        await prefs.setDouble(_keyWindowX, position.dx);
        await prefs.setDouble(_keyWindowY, position.dy);
      }
      await prefs.setBool(_keyWindowMaximized, isMaximized);
      debugPrint('[Window] State saved successfully');
    } catch (e) {
      debugPrint('[Window] Failed to save state: $e');
    }
  }

  /// 保存侧边栏宽度
  Future<void> saveSidebarWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySidebarWidth, width);
  }

  /// 获取保存的侧边栏宽度
  Future<double> getSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySidebarWidth) ??
        PlatformUtils.desktopSidebarWidth;
  }

  /// 最小化窗口
  Future<void> minimize() async {
    if (!PlatformUtils.isPhysicalDesktop) return;
    await windowManager.minimize();
  }

  /// 最大化/还原窗口
  Future<void> toggleMaximize() async {
    if (!PlatformUtils.isPhysicalDesktop) return;
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 关闭窗口
  Future<void> close() async {
    if (!PlatformUtils.isPhysicalDesktop) return;
    await _saveWindowState();
    await windowManager.close();
  }

  /// 最小化到托盘
  Future<void> minimizeToTray() async {
    if (!PlatformUtils.isPhysicalDesktop) return;
    await windowManager.hide();
    _isMinimizedToTray = true;
  }

  /// 从托盘恢复
  Future<void> restoreFromTray() async {
    if (!PlatformUtils.isPhysicalDesktop) return;
    await windowManager.show();
    await windowManager.focus();
    _isMinimizedToTray = false;
  }

  /// 是否在托盘中
  bool get isMinimizedToTray => _isMinimizedToTray;

  /// 是否最大化
  bool get isMaximized => _isMaximized;

  /// 是否全屏
  bool get isFullScreen => _isFullScreen;

  // ===== WindowListener 回调 =====

  @override
  void onWindowMaximize() {
    _isMaximized = true;
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
  }

  @override
  void onWindowEnterFullScreen() {
    _isFullScreen = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    _isFullScreen = false;
  }

  @override
  void onWindowClose() async {
    await _saveWindowState();
    // 注意：实际资源清理由 main.dart 或 app.dart 负责
    // 这里只保存状态，不调用 dispose，因为窗口关闭后应用会退出
  }

  @override
  void onWindowResized() {
    if (_isDisposed) return;
    // 延迟保存，避免频繁写入
    _saveStateTimer?.cancel();
    _saveStateTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_isDisposed) {
        _saveWindowState();
      }
    });
  }

  @override
  void onWindowMoved() {
    if (_isDisposed) return;
    // 延迟保存，避免频繁写入
    _saveStateTimer?.cancel();
    _saveStateTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_isDisposed) {
        _saveWindowState();
      }
    });
  }

  /// 销毁
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _saveStateTimer?.cancel();
    _saveStateTimer = null;
    if (PlatformUtils.isPhysicalDesktop && _initialized) {
      try {
        await _saveWindowState();
        windowManager.removeListener(this);
      } catch (e) {
        debugPrint('[Window] Dispose error: $e');
      }
    }
    _initialized = false;
    debugPrint('[Window] Disposed');
  }
}
