// 文件用途：实现 HotkeyCallback 相关逻辑，服务于业务服务。
// 核心逻辑：围绕 HotkeyCallback 组织，完成输入校验、核心处理和结果回传。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/platform_utils.dart';

String _hotkeyText({
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

// 关键声明：hotkey service 把桌面系统能力封装成应用接口，处理窗口、托盘或快捷键生命周期并避免泄漏监听器。
/// 快捷键回调
typedef HotkeyCallback = void Function();

/// 桌面系统级全局快捷键服务，仅在 macOS、Windows 和 Linux 上注册。
///
/// 此服务负责应用失焦时仍可触发的系统快捷键；文件末尾的 [desktopShortcuts]
/// 则属于 Flutter 应用内焦点体系，两者需要保持按键语义一致。
class HotkeyService {
  static final HotkeyService _instance = HotkeyService._();
  static HotkeyService get instance => _instance;
  HotkeyService._();

  bool _initialized = false;
  bool _isDisposed = false;
  final Map<String, HotKey> _registeredHotkeys = {};
  // 注册失败通常表示被操作系统或其他应用占用，不应阻断其余快捷键注册。
  final Set<String> _failedHotkeys = {}; // 跟踪注册失败的快捷键

  /// 获取注册失败的快捷键列表
  Set<String> get failedHotkeys => Set.unmodifiable(_failedHotkeys);

  /// 是否有快捷键注册失败
  bool get hasFailedHotkeys => _failedHotkeys.isNotEmpty;

  // 回调
  HotkeyCallback? onNewChat;
  HotkeyCallback? onSearch;
  HotkeyCallback? onSettings;
  HotkeyCallback? onNextChat;
  HotkeyCallback? onPrevChat;
  HotkeyCallback? onCloseChat;

  /// 初始化快捷键
  Future<void> initialize() async {
    if (!PlatformUtils.isPhysicalDesktop || _initialized) return;

    // 先清理系统中可能由上一次进程状态遗留的注册，再逐项重建本服务的记录。
    await hotKeyManager.unregisterAll();

    // Cmd/Ctrl + N: 新建聊天
    await _registerHotkey(
      'new_chat',
      HotKey(
        key: LogicalKeyboardKey.keyN,
        modifiers: [_cmdOrCtrl],
      ),
      () => onNewChat?.call(),
    );

    // Cmd/Ctrl + K 或 Cmd/Ctrl + F: 搜索
    await _registerHotkey(
      'search',
      HotKey(
        key: LogicalKeyboardKey.keyK,
        modifiers: [_cmdOrCtrl],
      ),
      () => onSearch?.call(),
    );

    // Cmd/Ctrl + ,: 设置
    await _registerHotkey(
      'settings',
      HotKey(
        key: LogicalKeyboardKey.comma,
        modifiers: [_cmdOrCtrl],
      ),
      () => onSettings?.call(),
    );

    // Cmd/Ctrl + ↓ 或 Tab: 下一个聊天
    await _registerHotkey(
      'next_chat',
      HotKey(
        key: LogicalKeyboardKey.arrowDown,
        modifiers: [_cmdOrCtrl],
      ),
      () => onNextChat?.call(),
    );

    // Cmd/Ctrl + ↑: 上一个聊天
    await _registerHotkey(
      'prev_chat',
      HotKey(
        key: LogicalKeyboardKey.arrowUp,
        modifiers: [_cmdOrCtrl],
      ),
      () => onPrevChat?.call(),
    );

    // Cmd/Ctrl + W: 关闭当前聊天
    await _registerHotkey(
      'close_chat',
      HotKey(
        key: LogicalKeyboardKey.keyW,
        modifiers: [_cmdOrCtrl],
      ),
      () => onCloseChat?.call(),
    );

    _initialized = true;
    debugPrint('[Hotkey] Registered ${_registeredHotkeys.length} hotkeys');
  }

  /// 获取 Cmd（macOS）或 Ctrl（Windows/Linux）
  HotKeyModifier get _cmdOrCtrl =>
      PlatformUtils.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control;

  /// 注册快捷键
  Future<void> _registerHotkey(
      String id, HotKey hotKey, VoidCallback callback) async {
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hotKey) {
          debugPrint('[Hotkey] Triggered: $id');
          callback();
        },
      );
      _registeredHotkeys[id] = hotKey;
      _failedHotkeys.remove(id); // 成功则移除失败记录
    } catch (e) {
      debugPrint('[Hotkey] Failed to register $id: $e');
      _failedHotkeys.add(id); // 记录失败的快捷键
    }
  }

  /// 获取失败快捷键的描述信息
  String getFailedHotkeysDescription() {
    if (_failedHotkeys.isEmpty) return '';

    final descriptions = _failedHotkeys.map((id) {
      final text = getHotkeyText(id);
      return '$text (${_getHotkeyLabel(id)})';
    }).join(', ');

    return _hotkeyText(
      zhCN: '以下快捷键注册失败，可能与系统快捷键冲突：$descriptions',
      zhTW: '以下快捷鍵註冊失敗，可能與系統快捷鍵衝突：$descriptions',
      en: 'These shortcuts could not be registered and may conflict with system shortcuts: $descriptions',
    );
  }

  /// 获取快捷键标签
  String _getHotkeyLabel(String id) {
    switch (id) {
      case 'new_chat':
        return _hotkeyText(zhCN: '新建聊天', zhTW: '新增聊天', en: 'New chat');
      case 'search':
        return _hotkeyText(zhCN: '搜索', zhTW: '搜尋', en: 'Search');
      case 'settings':
        return _hotkeyText(zhCN: '设置', zhTW: '設定', en: 'Settings');
      case 'next_chat':
        return _hotkeyText(
          zhCN: '下一个聊天',
          zhTW: '下一個聊天',
          en: 'Next chat',
        );
      case 'prev_chat':
        return _hotkeyText(
          zhCN: '上一个聊天',
          zhTW: '上一個聊天',
          en: 'Previous chat',
        );
      case 'close_chat':
        return _hotkeyText(
          zhCN: '关闭聊天',
          zhTW: '關閉聊天',
          en: 'Close chat',
        );
      default:
        return id;
    }
  }

  /// 取消注册所有快捷键
  Future<void> unregisterAll() async {
    if (!PlatformUtils.isPhysicalDesktop) return;
    // 插件 API 是进程级清理，调用方应避免在其他模块独立注册热键。
    await hotKeyManager.unregisterAll();
    _registeredHotkeys.clear();
  }

  /// 获取快捷键显示文本（用于 UI 提示）
  String getHotkeyText(String id) {
    final modifier = PlatformUtils.isMacOS ? '⌘' : 'Ctrl';

    switch (id) {
      case 'new_chat':
        return '$modifier+N';
      case 'search':
        return '$modifier+K';
      case 'settings':
        return '$modifier+,';
      case 'next_chat':
        return '$modifier+↓';
      case 'prev_chat':
        return '$modifier+↑';
      case 'close_chat':
        return '$modifier+W';
      default:
        return '';
    }
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  /// 销毁
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await unregisterAll();
    // 清理回调
    onNewChat = null;
    onSearch = null;
    onSettings = null;
    onNextChat = null;
    onPrevChat = null;
    onCloseChat = null;
    _initialized = false;
    debugPrint('[Hotkey] Disposed');
  }
}

/// 应用内键盘快捷键 Intent
class NewChatIntent extends Intent {
  const NewChatIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class SettingsIntent extends Intent {
  const SettingsIntent();
}

class NextChatIntent extends Intent {
  const NextChatIntent();
}

class PrevChatIntent extends Intent {
  const PrevChatIntent();
}

class CloseChatIntent extends Intent {
  const CloseChatIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

/// Flutter 应用内快捷键绑定，仅在对应 Focus/Shortcuts 树激活时生效。
final Map<ShortcutActivator, Intent> desktopShortcuts = {
  // 新建聊天
  LogicalKeySet(
    PlatformUtils.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyN,
  ): const NewChatIntent(),

  // 搜索
  LogicalKeySet(
    PlatformUtils.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyK,
  ): const SearchIntent(),

  // 设置
  LogicalKeySet(
    PlatformUtils.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control,
    LogicalKeyboardKey.comma,
  ): const SettingsIntent(),

  // 下一个聊天
  LogicalKeySet(
    PlatformUtils.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control,
    LogicalKeyboardKey.arrowDown,
  ): const NextChatIntent(),

  // 上一个聊天
  LogicalKeySet(
    PlatformUtils.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control,
    LogicalKeyboardKey.arrowUp,
  ): const PrevChatIntent(),

  // 关闭聊天
  LogicalKeySet(
    PlatformUtils.isMacOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyW,
  ): const CloseChatIntent(),

  // ESC
  const SingleActivator(LogicalKeyboardKey.escape): const EscapeIntent(),
};
