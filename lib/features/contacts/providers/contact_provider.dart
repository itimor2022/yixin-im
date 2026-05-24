import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../core/services/storage/isar_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/storage/models/user_model.dart';
import '../../../shared/widgets/avatar_widget.dart';

/// 联系人数据模型
class ContactItem {
  final String id; // 数字ID，用于头像颜色一致性
  final String? uuid; // UUID，用于API调用
  final String name;
  final String? remark;
  final String? username;
  final String? avatar;
  final String? phone;
  final String? bio;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? emojiAvatar; // 表情状态
  final String? nicknameColor; // 昵称颜色
  final String? premiumType; // 会员类型

  ContactItem({
    required this.id,
    this.uuid,
    required this.name,
    this.remark,
    this.username,
    this.avatar,
    this.phone,
    this.bio,
    this.isOnline = false,
    this.lastSeen,
    this.emojiAvatar,
    this.nicknameColor,
    this.premiumType,
  });

  static String _buildSearchText({
    required String name,
    String? remark,
    String? username,
    String? phone,
    String? bio,
  }) {
    return <String>[name, remark ?? '', username ?? '', phone ?? '', bio ?? '']
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  String get searchText => _buildSearchText(
    name: name,
    remark: remark,
    username: username,
    phone: phone,
    bio: bio,
  );

  String get stableKey {
    final normalizedUuid = uuid?.trim() ?? '';
    return normalizedUuid.isNotEmpty ? normalizedUuid : id;
  }

  bool matchesQuery(String keyword) {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return searchText.contains(normalized);
  }

  ContactItem copyWith({
    String? name,
    String? remark,
    String? username,
    String? avatar,
    String? phone,
    String? bio,
    bool? isOnline,
    DateTime? lastSeen,
    String? emojiAvatar,
    String? nicknameColor,
    String? premiumType,
  }) {
    return ContactItem(
      id: id,
      uuid: uuid,
      name: name ?? this.name,
      remark: remark ?? this.remark,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      phone: phone ?? this.phone,
      bio: bio ?? this.bio,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      emojiAvatar: emojiAvatar ?? this.emojiAvatar,
      nicknameColor: nicknameColor ?? this.nicknameColor,
      premiumType: premiumType ?? this.premiumType,
    );
  }

  factory ContactItem.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return ContactItem(
      id: json['id']?.toString() ?? '',
      uuid: json['uuid']?.toString(),
      name: json['name'] ?? json['nickname'] ?? '',
      remark: json['remark']?.toString(),
      username: json['username'],
      avatar: avatarUrl,
      phone: json['phone'],
      bio: json['bio'],
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen']).toLocal()
          : null,
      emojiAvatar: json['emoji_avatar'],
      nicknameColor: json['nickname_color'],
      premiumType: json['premium_type'],
    );
  }
}

/// 联系人列表状态
class ContactListState {
  final List<ContactItem> contacts;
  final bool isLoading;
  final String? error;
  final bool isInitialized;

  const ContactListState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
  });

  ContactListState copyWith({
    List<ContactItem>? contacts,
    bool? isLoading,
    String? error,
    bool? isInitialized,
  }) {
    return ContactListState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// 联系人列表 Provider
final contactListProvider =
    StateNotifierProvider<ContactListNotifier, List<ContactItem>>((ref) {
      final api = ref.watch(apiClientProvider);
      final ws = ref.read(webSocketServiceProvider.notifier);
      return ContactListNotifier(api, ws);
    });

class ContactListNotifier extends StateNotifier<List<ContactItem>> {
  final ApiClient _api;
  final WebSocketService _ws;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // 保存 WebSocket handler ID，用于清理
  String? _userStatusHandlerId;
  String? _userProfileHandlerId;

  ContactListNotifier(this._api, this._ws) : super([]) {
    _setupWebSocketHandlers();
  }

  /// 设置 WebSocket 消息处理器
  void _setupWebSocketHandlers() {
    // 监听 WebSocket 用户在线状态，实时更新联系人列表
    _userStatusHandlerId = _ws.registerHandler('user_status', (data) {
      if (_isDisposed) return;
      final userId = data['user_id']?.toString();
      final isOnline = data['is_online'] as bool? ?? false;
      if (userId == null) return;
      state = state.map((c) {
        if (c.uuid == userId || c.id == userId) {
          return c.copyWith(
            isOnline: isOnline,
            lastSeen: isOnline ? null : DateTime.now(),
          );
        }
        return c;
      }).toList();
    });

    // 监听 WebSocket 用户资料变更（昵称、头像、颜色、动态表情）实时更新联系人
    _userProfileHandlerId = _ws.registerHandler('user_profile', (data) {
      if (_isDisposed) return;
      final userId = data['user_id']?.toString();
      if (userId == null) return;
      String? avatarUrl = data['avatar'] as String?;
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
      }
      state = state.map((c) {
        if (c.uuid != userId && c.id != userId) return c;
        final name = (data['nickname'] ?? data['name'])?.toString();
        return c.copyWith(
          name: c.remark != null && c.remark!.isNotEmpty
              ? c.name
              : (name != null && name.isNotEmpty ? name : c.name),
          username: data['username']?.toString() ?? c.username,
          avatar: avatarUrl ?? c.avatar,
          bio: data['bio']?.toString() ?? c.bio,
          nicknameColor: data['nickname_color']?.toString() ?? c.nicknameColor,
          emojiAvatar: data['emoji_avatar']?.toString() ?? c.emojiAvatar,
          premiumType: data['premium_type']?.toString() ?? c.premiumType,
        );
      }).toList();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 清理 WebSocket handlers
    if (_userStatusHandlerId != null) {
      _ws.unregisterHandler(_userStatusHandlerId!);
      _userStatusHandlerId = null;
    }
    if (_userProfileHandlerId != null) {
      _ws.unregisterHandler(_userProfileHandlerId!);
      _userProfileHandlerId = null;
    }
    super.dispose();
  }

  /// 初始化
  Future<void> initialize() async {
    if (_isInitialized) return;
    await loadFromServer(force: true);
  }

  /// 从本地 Isar 读取联系人列表缓存，先展示再请求服务器
  Future<void> _loadContactListFromCache() async {
    if (PlatformUtils.isWeb) return;
    if (!IsarService.instance.isAvailable) return;

    try {
      final list = await IsarService.instance.isar.userModels
          .filter()
          .isContactEqualTo(true)
          .findAll();
      if (list.isEmpty) return;
      final items = list
          .map(
            (m) => ContactItem(
              id: m.id,
              uuid: m.id,
              name: m.nickname ?? m.username,
              username: m.username,
              avatar: m.avatar,
              phone: m.phone,
              bio: m.bio,
              isOnline: m.isOnline,
              lastSeen: m.lastSeen,
              emojiAvatar: m.emojiAvatar,
              nicknameColor: m.nicknameColor,
              premiumType: m.premiumType,
            ),
          )
          .toList();
      state = items;
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Contact] Failed to load from cache: $e');
    }
  }

  /// 拉取全部联系人（自动分页，避免后端分页导致只返回部分数据）
  Future<List<ContactItem>> _fetchAllContacts() async {
    final allContacts = <ContactItem>[];
    final seenKeys = <String>{};
    int page = 1;
    const pageSize = 500;

    while (true) {
      final response = await _api.get(
        '/contact/list',
        queryParameters: {'page': page, 'page_size': pageSize},
      );

      if (!response.isSuccess || response.data == null) {
        // 如果第一页就失败且后端不支持分页参数，尝试无参数请求
        if (page == 1) {
          final fallback = await _api.get('/contact/list');
          if (fallback.isSuccess && fallback.data != null) {
            final list =
                (fallback.data['list'] as List?)
                    ?.map((e) => ContactItem.fromJson(e))
                    .toList() ??
                [];
            return list;
          }
        }
        break;
      }

      final batch =
          (response.data['list'] as List?)
              ?.map((e) => ContactItem.fromJson(e))
              .toList() ??
          [];
      var addedCount = 0;
      for (final contact in batch) {
        if (seenKeys.add(contact.stableKey)) {
          allContacts.add(contact);
          addedCount++;
        }
      }

      final total = response.data['total'] is num
          ? (response.data['total'] as num).toInt()
          : null;
      if (batch.isEmpty || addedCount == 0) break;
      if (total != null && allContacts.length >= total) break;
      if (batch.length < pageSize) break;
      page++;
    }

    return allContacts;
  }

  // 防抖：记录上次请求时间
  DateTime? _lastLoadTime;
  static const _minLoadInterval = Duration(milliseconds: 500);
  static const _refreshInterval = Duration(seconds: 30);

  /// 是否应该刷新（数据过期超过30秒）
  bool get shouldRefresh {
    if (_lastLoadTime == null) return true;
    return DateTime.now().difference(_lastLoadTime!) > _refreshInterval;
  }

  /// 从服务器加载联系人列表
  Future<void> loadFromServer({bool force = false}) async {
    // 防抖：500ms 内不重复请求
    final now = DateTime.now();
    final lastLoadTime = _lastLoadTime;
    final hasFreshState =
        _isInitialized &&
        state.isNotEmpty &&
        lastLoadTime != null &&
        now.difference(lastLoadTime) <= _refreshInterval;
    if (!force) {
      if (lastLoadTime != null &&
          now.difference(lastLoadTime) < _minLoadInterval) {
        return;
      }
      if (hasFreshState) {
        return;
      }
    }
    _lastLoadTime = now;

    // 先读本地缓存，联系人页进软件即可秒显列表
    if (state.isEmpty) {
      await _loadContactListFromCache();
    }

    try {
      final list = await _fetchAllContacts();
      if (_isDisposed) return;

      if (list.isNotEmpty) {
        state = list;
        _isInitialized = true;
        if (PlatformUtils.isWeb) {
          return;
        }
        if (!IsarService.instance.isAvailable) return;

        // 写入 Isar，下次进软件先读缓存秒显联系人
        try {
          final now = DateTime.now();
          final models = list.map((c) {
            final m = UserModel();
            m.id = c.id;
            m.username = c.username ?? '';
            m.nickname = c.name;
            m.avatar = c.avatar;
            m.phone = c.phone;
            m.bio = c.bio;
            m.nicknameColor = c.nicknameColor;
            m.emojiAvatar = c.emojiAvatar;
            m.premiumType = c.premiumType;
            m.isOnline = c.isOnline ?? false;
            m.lastSeen = c.lastSeen;
            m.isContact = true;
            m.isBlocked = false;
            m.createdAt = now;
            m.updatedAt = now;
            return m;
          }).toList();
          await IsarService.instance.isar.writeTxn(() async {
            await IsarService.instance.isar.userModels
                .filter()
                .isContactEqualTo(true)
                .deleteAll();
            if (models.isNotEmpty)
              await IsarService.instance.isar.userModels.putAll(models);
          });
        } catch (e) {
          if (kDebugMode) debugPrint('[Contact] Failed to cache contacts: $e');
        }

        // 联系人列表头像预取到本地，列表/聊天等处加载即秒开
        final avatarUrls = list
            .map((c) => c.avatar)
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList();
        AvatarCacheManager.prefetchUrls(avatarUrls);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Contact] Load from server failed: $e');
    }
  }

  /// 刷新联系人列表
  Future<void> refresh() async {
    await loadFromServer(force: true);
  }

  /// 静默刷新联系人列表（从后台恢复时使用，不触发UI加载状态）
  Future<void> silentRefresh() async {
    // 防抖：500ms 内不重复请求
    final now = DateTime.now();
    if (_lastLoadTime != null &&
        now.difference(_lastLoadTime!) < _minLoadInterval) {
      return;
    }
    _lastLoadTime = now;

    // 如果还没有初始化，则正常加载
    if (!_isInitialized) {
      await loadFromServer(force: true);
      return;
    }

    // 静默刷新
    try {
      final list = await _fetchAllContacts();
      if (_isDisposed) return;

      if (list.isNotEmpty) {
        // 检查是否有变化
        if (_hasListChanges(list)) {
          state = list;
        }
        if (PlatformUtils.isWeb) return;
        if (!IsarService.instance.isAvailable) return;

        // 写入 Isar 缓存
        try {
          final now = DateTime.now();
          final models = list.map((c) {
            final m = UserModel();
            m.id = c.id;
            m.username = c.username ?? '';
            m.nickname = c.name;
            m.avatar = c.avatar;
            m.phone = c.phone;
            m.bio = c.bio;
            m.nicknameColor = c.nicknameColor;
            m.emojiAvatar = c.emojiAvatar;
            m.premiumType = c.premiumType;
            m.isOnline = c.isOnline ?? false;
            m.lastSeen = c.lastSeen;
            m.isContact = true;
            m.isBlocked = false;
            m.createdAt = now;
            m.updatedAt = now;
            return m;
          }).toList();
          await IsarService.instance.isar.writeTxn(() async {
            await IsarService.instance.isar.userModels
                .filter()
                .isContactEqualTo(true)
                .deleteAll();
            if (models.isNotEmpty)
              await IsarService.instance.isar.userModels.putAll(models);
          });
        } catch (e) {
          if (kDebugMode) debugPrint(
            '[Contact] Failed to cache contacts in silent refresh: $e',
          );
        }
      }
    } catch (e) {
      // 静默刷新失败记录日志
      if (kDebugMode) debugPrint('[Contact] Silent refresh failed: $e');
    }
  }

  /// 检查联系人列表是否有变化
  bool _hasListChanges(List<ContactItem> newList) {
    if (state.length != newList.length) return true;

    for (var i = 0; i < newList.length; i++) {
      if (state[i].id != newList[i].id ||
          state[i].name != newList[i].name ||
          state[i].remark != newList[i].remark ||
          state[i].avatar != newList[i].avatar ||
          state[i].isOnline != newList[i].isOnline ||
          state[i].nicknameColor != newList[i].nicknameColor ||
          state[i].emojiAvatar != newList[i].emojiAvatar ||
          state[i].premiumType != newList[i].premiumType) {
        return true;
      }
    }
    return false;
  }

  /// 重置状态（登出时调用）
  void reset() {
    state = [];
    _isInitialized = false;
  }

  /// 搜索用户
  Future<List<ContactItem>> searchUsers(String keyword) async {
    // 去掉开头的 @ 符号（支持 @username 格式搜索）
    String searchKeyword = keyword.trim();
    if (searchKeyword.startsWith('@')) {
      searchKeyword = searchKeyword.substring(1);
    }

    final response = await _api.get(
      '/user/search',
      queryParameters: {'keyword': searchKeyword},
    );

    if (response.isSuccess && response.data != null) {
      return (response.data['list'] as List?)
              ?.map((e) => ContactItem.fromJson(e))
              .toList() ??
          [];
    }

    return [];
  }

  /// 添加联系人（调用API）
  Future<bool> addContact(String userId, {String? remark}) async {
    final response = await _api.post(
      '/contact/add',
      data: {'user_id': userId, if (remark != null) 'remark': remark},
    );

    if (response.isSuccess) {
      await loadFromServer(force: true);
      return true;
    }

    return false;
  }

  /// 删除联系人（调用API）
  Future<bool> removeContact(String contactId) async {
    final response = await _api.delete('/contact/$contactId');

    if (response.isSuccess) {
      // 同时检查 id 和 uuid，因为 contactId 可能是任意一种格式
      state = state
          .where((c) => c.id != contactId && c.uuid != contactId)
          .toList();
      return true;
    }

    return false;
  }

  /// 更新备注（调用API）
  Future<bool> updateRemark(String contactId, String remark) async {
    final nextRemark = remark.trim();
    final response = await _api.put(
      '/contact/$contactId/remark',
      data: {'remark': nextRemark},
    );

    if (response.isSuccess) {
      state = state.map((c) {
        if (c.id != contactId && c.uuid != contactId) return c;
        final fallbackName = c.remark?.isNotEmpty == true
            ? (c.username?.isNotEmpty == true ? c.username! : c.name)
            : c.name;
        return c.copyWith(
          remark: nextRemark,
          name: nextRemark.isNotEmpty ? nextRemark : fallbackName,
        );
      }).toList();
      _lastLoadTime = null;
      await loadFromServer(force: true);
    }

    return response.isSuccess;
  }

  void updateContact(ContactItem updatedContact) {
    state = state.map((c) {
      if (c.id == updatedContact.id) {
        return updatedContact;
      }
      return c;
    }).toList();
  }
}
