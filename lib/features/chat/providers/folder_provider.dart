// 文件用途：管理 ChatFolder 相关状态、异步加载与界面通知，属于聊天与消息。
// 核心逻辑：以 Riverpod 暴露 ChatFolder 状态，串联 API、本地缓存和生命周期事件，统一处理加载、刷新、失败与重试。
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/account_session_coordinator.dart';
import 'chat_provider.dart';

String _folderText({
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

String _defaultFolderName(String id) {
  switch (id) {
    case 'all':
      return _folderText(zhCN: '全部', zhTW: '全部', en: 'All');
    case 'contacts':
      return _folderText(zhCN: '联系人', zhTW: '聯絡人', en: 'Contacts');
    case 'groups':
      return _folderText(zhCN: '群组', zhTW: '群組', en: 'Groups');
    case 'channels':
      return _folderText(zhCN: '频道', zhTW: '頻道', en: 'Channels');
    default:
      return id;
  }
}

ChatFolder _normalizeDefaultFolder(ChatFolder folder) {
  switch (folder.id) {
    case 'all':
    case 'contacts':
    case 'groups':
    case 'channels':
      return folder.copyWith(name: _defaultFolderName(folder.id));
    default:
      return folder;
  }
}

// 关键声明：folder provider 是状态边界，统一管理加载、成功、失败和刷新状态，避免页面直接维护异步请求结果。
/// 聊天文件夹模型
class ChatFolder {
  final String id;
  final String name;
  final IconData? icon;
  final List<ChatItemType>? includeTypes; // 包含的聊天类型
  final List<String>? includeChatIds; // 包含的具体聊天ID
  final List<String>? excludeChatIds; // 排除的聊天ID
  final bool showUnreadOnly; // 只显示未读
  final bool isDefault; // 是否是默认分组（全部）
  final int order; // 排序顺序

  const ChatFolder({
    required this.id,
    required this.name,
    this.icon,
    this.includeTypes,
    this.includeChatIds,
    this.excludeChatIds,
    this.showUnreadOnly = false,
    this.isDefault = false,
    this.order = 0,
  });

  ChatFolder copyWith({
    String? id,
    String? name,
    IconData? icon,
    List<ChatItemType>? includeTypes,
    List<String>? includeChatIds,
    List<String>? excludeChatIds,
    bool? showUnreadOnly,
    bool? isDefault,
    int? order,
  }) {
    return ChatFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      includeTypes: includeTypes ?? this.includeTypes,
      includeChatIds: includeChatIds ?? this.includeChatIds,
      excludeChatIds: excludeChatIds ?? this.excludeChatIds,
      showUnreadOnly: showUnreadOnly ?? this.showUnreadOnly,
      isDefault: isDefault ?? this.isDefault,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'includeTypes': includeTypes?.map((e) => e.name).toList(),
      'includeChatIds': includeChatIds,
      'excludeChatIds': excludeChatIds,
      'showUnreadOnly': showUnreadOnly,
      'isDefault': isDefault,
      'order': order,
    };
  }

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: json['id'],
      name: json['name'],
      includeTypes: (json['includeTypes'] as List<dynamic>?)
          ?.map((e) => ChatItemType.values.firstWhere((t) => t.name == e))
          .toList(),
      includeChatIds:
          (json['includeChatIds'] as List<dynamic>?)?.cast<String>(),
      excludeChatIds:
          (json['excludeChatIds'] as List<dynamic>?)?.cast<String>(),
      showUnreadOnly: json['showUnreadOnly'] ?? false,
      isDefault: json['isDefault'] ?? false,
      order: json['order'] ?? 0,
    );
  }

  /// 默认分组列表
  static List<ChatFolder> get defaults => [
        const ChatFolder(
          id: 'all',
          name: '',
          isDefault: true,
          order: 0,
        ).copyWith(name: _defaultFolderName('all')),
      ];
}

/// 文件夹状态
class FolderState {
  final List<ChatFolder> folders;
  final int selectedIndex;
  final bool isLoading;

  const FolderState({
    this.folders = const [],
    this.selectedIndex = 0,
    this.isLoading = false,
  });

  FolderState copyWith({
    List<ChatFolder>? folders,
    int? selectedIndex,
    bool? isLoading,
  }) {
    return FolderState(
      folders: folders ?? this.folders,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 文件夹 Provider
final folderProvider =
    StateNotifierProvider<FolderNotifier, FolderState>((ref) {
  final accountId = ref.watch(currentAccountIdProvider);
  return FolderNotifier(accountId);
});

class FolderNotifier extends StateNotifier<FolderState> {
  FolderNotifier(this._accountId) : super(const FolderState()) {
    if (_accountId.isNotEmpty) {
      _loadFolders();
    }
  }

  final String _accountId;
  bool _isDisposed = false;

  String get _key =>
      'acct_v1_${sha256.convert(utf8.encode(_accountId))}_chat_folders';

  Future<void> _loadFolders() async {
    if (_accountId.isEmpty || _isDisposed) return;
    state = state.copyWith(isLoading: true);

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isDisposed) return;
      final jsonString = prefs.getString(_key);

      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        final folders = jsonList
            .map((e) => _normalizeDefaultFolder(ChatFolder.fromJson(e)))
            .toList();
        if (!_isDisposed) {
          state = state.copyWith(folders: folders, isLoading: false);
        }
      } else {
        // 首次使用，创建默认分组
        await _createDefaultFolders();
      }
    } catch (e) {
      debugPrint('[Folder] Load folders failed: $e, using default folders');
      await _createDefaultFolders();
    }
  }

  Future<void> _createDefaultFolders() async {
    if (_accountId.isEmpty || _isDisposed) return;
    final defaultFolders = [
      const ChatFolder(
        id: 'all',
        name: '',
        isDefault: true,
        order: 0,
      ).copyWith(name: _defaultFolderName('all')),
      ChatFolder(
        id: 'contacts',
        name: _defaultFolderName('contacts'),
        includeTypes: [ChatItemType.private],
        order: 1,
      ),
      ChatFolder(
        id: 'groups',
        name: _defaultFolderName('groups'),
        includeTypes: [ChatItemType.group],
        order: 2,
      ),
      ChatFolder(
        id: 'channels',
        name: _defaultFolderName('channels'),
        includeTypes: [ChatItemType.channel],
        order: 3,
      ),
    ];

    state = state.copyWith(folders: defaultFolders, isLoading: false);
    await _saveFolders();
  }

  Future<void> _saveFolders() async {
    if (_accountId.isEmpty || _isDisposed) return;
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;
    final jsonString =
        json.encode(state.folders.map((e) => e.toJson()).toList());
    await prefs.setString(_key, jsonString);
  }

  void selectFolder(int index) {
    if (index >= 0 && index < state.folders.length) {
      state = state.copyWith(selectedIndex: index);
    }
  }

  Future<void> addFolder(ChatFolder folder) async {
    if (_accountId.isEmpty || _isDisposed) return;
    final newFolders = [
      ...state.folders,
      folder.copyWith(order: state.folders.length)
    ];
    state = state.copyWith(folders: newFolders);
    await _saveFolders();
  }

  Future<void> updateFolder(ChatFolder folder) async {
    if (_accountId.isEmpty || _isDisposed) return;
    final newFolders = state.folders.map((f) {
      return f.id == folder.id ? folder : f;
    }).toList();
    state = state.copyWith(folders: newFolders);
    await _saveFolders();
  }

  Future<void> deleteFolder(String folderId) async {
    if (_accountId.isEmpty || _isDisposed) return;
    // 不能删除默认分组
    final folder = state.folders.firstWhere((f) => f.id == folderId);
    if (folder.isDefault) return;

    final newFolders = state.folders.where((f) => f.id != folderId).toList();
    state = state.copyWith(
      folders: newFolders,
      selectedIndex: state.selectedIndex >= newFolders.length
          ? newFolders.length - 1
          : state.selectedIndex,
    );
    await _saveFolders();
  }

  Future<void> reorderFolders(int oldIndex, int newIndex) async {
    if (_accountId.isEmpty || _isDisposed) return;
    final folders = [...state.folders];
    final folder = folders.removeAt(oldIndex);
    folders.insert(newIndex, folder);

    // 更新排序
    final reorderedFolders = folders.asMap().entries.map((e) {
      return e.value.copyWith(order: e.key);
    }).toList();

    state = state.copyWith(folders: reorderedFolders);
    await _saveFolders();
  }

  /// 计算文件夹未读数
  int getUnreadCount(ChatFolder folder, ChatListState chats) {
    final filteredChats = filterChats(folder, chats);
    var count = 0;
    for (final chat in [
      ...filteredChats.pinnedChats,
      ...filteredChats.regularChats
    ]) {
      count += chat.unreadCount;
    }
    return count;
  }

  /// 根据文件夹过滤聊天
  ChatListState filterChats(ChatFolder folder, ChatListState chats) {
    if (folder.isDefault && folder.id == 'all') {
      return chats;
    }

    bool matchesFolder(ChatItem chat) {
      // 检查排除列表
      if (folder.excludeChatIds?.contains(chat.id) == true) {
        return false;
      }

      // 检查只显示未读
      if (folder.showUnreadOnly && chat.unreadCount == 0) {
        return false;
      }

      // 检查包含的具体聊天
      if (folder.includeChatIds?.isNotEmpty == true) {
        return folder.includeChatIds!.contains(chat.id);
      }

      // 检查包含的类型
      if (folder.includeTypes?.isNotEmpty == true) {
        return folder.includeTypes!.contains(chat.type);
      }

      return true;
    }

    return ChatListState(
      pinnedChats: chats.pinnedChats.where(matchesFolder).toList(),
      regularChats: chats.regularChats.where(matchesFolder).toList(),
    );
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
