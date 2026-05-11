import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'chat_provider.dart';

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
      includeChatIds: (json['includeChatIds'] as List<dynamic>?)?.cast<String>(),
      excludeChatIds: (json['excludeChatIds'] as List<dynamic>?)?.cast<String>(),
      showUnreadOnly: json['showUnreadOnly'] ?? false,
      isDefault: json['isDefault'] ?? false,
      order: json['order'] ?? 0,
    );
  }

  /// 默认分组列表
  static List<ChatFolder> get defaults => [
    const ChatFolder(
      id: 'all',
      name: '全部',
      isDefault: true,
      order: 0,
    ),
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
final folderProvider = StateNotifierProvider<FolderNotifier, FolderState>((ref) {
  return FolderNotifier();
});

class FolderNotifier extends StateNotifier<FolderState> {
  FolderNotifier() : super(const FolderState()) {
    _loadFolders();
  }

  static const String _key = 'chat_folders';

  Future<void> _loadFolders() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);
      
      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        final folders = jsonList.map((e) => ChatFolder.fromJson(e)).toList();
        state = state.copyWith(folders: folders, isLoading: false);
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
    final defaultFolders = [
      const ChatFolder(
        id: 'all',
        name: '全部',
        isDefault: true,
        order: 0,
      ),
      ChatFolder(
        id: 'contacts',
        name: '联系人',
        includeTypes: [ChatItemType.private],
        order: 1,
      ),
      ChatFolder(
        id: 'groups',
        name: '群组',
        includeTypes: [ChatItemType.group],
        order: 2,
      ),
      ChatFolder(
        id: 'channels',
        name: '频道',
        includeTypes: [ChatItemType.channel],
        order: 3,
      ),
    ];
    
    state = state.copyWith(folders: defaultFolders, isLoading: false);
    await _saveFolders();
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(state.folders.map((e) => e.toJson()).toList());
    await prefs.setString(_key, jsonString);
  }

  void selectFolder(int index) {
    if (index >= 0 && index < state.folders.length) {
      state = state.copyWith(selectedIndex: index);
    }
  }

  Future<void> addFolder(ChatFolder folder) async {
    final newFolders = [...state.folders, folder.copyWith(order: state.folders.length)];
    state = state.copyWith(folders: newFolders);
    await _saveFolders();
  }

  Future<void> updateFolder(ChatFolder folder) async {
    final newFolders = state.folders.map((f) {
      return f.id == folder.id ? folder : f;
    }).toList();
    state = state.copyWith(folders: newFolders);
    await _saveFolders();
  }

  Future<void> deleteFolder(String folderId) async {
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
    for (final chat in [...filteredChats.pinnedChats, ...filteredChats.regularChats]) {
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
}
