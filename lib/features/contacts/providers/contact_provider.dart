// 文件用途：管理 ContactItem 相关状态、异步加载与界面通知，属于联系人。
// 核心逻辑：以 Riverpod 暴露 ContactItem 状态，串联 API、本地缓存和生命周期事件，统一处理加载、刷新、失败与重试。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../core/services/storage/isar_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/storage/models/user_model.dart'
    if (dart.library.js_interop) '../../../core/services/storage/models/user_model_web.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../vip/models/vip_profile_summary.dart';

// 关键声明：contact provider 是状态边界，统一管理加载、成功、失败和刷新状态，避免页面直接维护异步请求结果。
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
  final VipProfileSummary vip;

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
    this.vip = VipProfileSummary.inactive,
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
    VipProfileSummary? vip,
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
      vip: vip ?? this.vip,
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
      vip: VipProfileSummary.fromJson(json['vip']),
    );
  }
}

class FriendRequestItem {
  final String id;
  final String direction;
  final String status;
  final String message;
  final DateTime expiresAt;
  final DateTime createdAt;
  final ContactItem user;

  const FriendRequestItem({
    required this.id,
    required this.direction,
    required this.status,
    required this.message,
    required this.expiresAt,
    required this.createdAt,
    required this.user,
  });

  bool get isPending => status == 'pending';

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) {
    return FriendRequestItem(
      id: json['id']?.toString() ?? '',
      direction: json['direction']?.toString() ?? 'incoming',
      status: json['status']?.toString() ?? 'pending',
      message: json['message']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(json['expires_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      user: ContactItem.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? const {}),
      ),
    );
  }
}

class FriendRequestSubmitResult {
  final FriendRequestItem request;
  final bool created;
  final bool autoAccepted;

  const FriendRequestSubmitResult({
    required this.request,
    required this.created,
    required this.autoAccepted,
  });
}

// 角标按账号创建独立实例；WebSocket 只提供变化信号，准确数量仍回源接口。
final pendingFriendRequestCountProvider =
    StateNotifierProvider<PendingFriendRequestCountNotifier, int>((ref) {
  final api = ref.watch(apiClientProvider);
  final ws = ref.read(webSocketServiceProvider.notifier);
  final accountId = ref.watch(currentAccountIdProvider);
  final notifier = PendingFriendRequestCountNotifier(api, ws, accountId);
  ref.listen<WSConnectionState>(webSocketServiceProvider, (previous, next) {
    if (next == WSConnectionState.connected &&
        previous != WSConnectionState.connected) {
      unawaited(notifier.refresh());
    }
  });
  return notifier;
});

class PendingFriendRequestCountNotifier extends StateNotifier<int> {
  PendingFriendRequestCountNotifier(
    this._api,
    this._ws,
    this._accountId,
  ) : super(0) {
    if (_accountId.isNotEmpty) {
      _friendRequestCreatedHandlerId = _ws.registerHandler(
        'friend_request_created',
        (_) => unawaited(refresh()),
      );
      _friendRequestChangedHandlerId = _ws.registerHandler(
        'friend_request_changed',
        (_) => unawaited(refresh()),
      );
      unawaited(refresh());
    }
  }

  final ApiClient _api;
  final WebSocketService _ws;
  final String _accountId;
  String? _friendRequestCreatedHandlerId;
  String? _friendRequestChangedHandlerId;
  bool _isDisposed = false;
  bool _isRefreshing = false;

  Future<void> refresh() async {
    if (_accountId.isEmpty || _isDisposed || _isRefreshing) return;
    _isRefreshing = true;
    try {
      final response = await _api.get(
        '/contact/requests',
        queryParameters: const {'box': 'incoming', 'status': 'pending'},
      );
      if (_isDisposed || !response.isSuccess || response.data is! Map) return;
      final data = Map<String, dynamic>.from(response.data as Map);
      final requests = data['list'] as List? ?? const [];
      state = requests.whereType<Map>().where((request) {
        return request['status']?.toString() == 'pending';
      }).length;
    } finally {
      _isRefreshing = false;
    }
  }

  void syncFromIncoming(List<FriendRequestItem> requests) {
    if (_isDisposed) return;
    state = requests.where((request) => request.isPending).length;
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    _isDisposed = true;
    if (_friendRequestCreatedHandlerId != null) {
      _ws.unregisterHandler(_friendRequestCreatedHandlerId!);
    }
    if (_friendRequestChangedHandlerId != null) {
      _ws.unregisterHandler(_friendRequestChangedHandlerId!);
    }
    super.dispose();
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

class _ContactFetchResult {
  const _ContactFetchResult({required this.contacts, required this.success});

  final List<ContactItem> contacts;
  final bool success;
}

/// 联系人列表 Provider
///
/// 依赖当前账号 ID，因此切换账号会销毁旧实例，避免联系人状态跨账号串用。
final contactListProvider =
    StateNotifierProvider<ContactListNotifier, List<ContactItem>>((ref) {
  final api = ref.watch(apiClientProvider);
  final ws = ref.read(webSocketServiceProvider.notifier);
  final accountId = ref.watch(currentAccountIdProvider);
  return ContactListNotifier(api, ws, accountId);
});

class ContactListNotifier extends StateNotifier<List<ContactItem>> {
  final ApiClient _api;
  final WebSocketService _ws;
  final String _accountId;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // 保存 WebSocket handler ID，用于清理
  String? _userStatusHandlerId;
  String? _userProfileHandlerId;
  String? _friendRequestHandlerId;

  ContactListNotifier(this._api, this._ws, this._accountId) : super([]) {
    if (_accountId.isNotEmpty) {
      _setupWebSocketHandlers();
    }
  }

  /// 设置 WebSocket 消息处理器
  void _setupWebSocketHandlers() {
    // 在线状态和资料事件只是联系人列表的实时投影，联系人关系本身仍以服务端列表为准。
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
          vip: data.containsKey('vip')
              ? VipProfileSummary.fromJson(data['vip'])
              : c.vip,
        );
      }).toList();
    });

    _friendRequestHandlerId = _ws.registerHandler(
      'friend_request_changed',
      (data) {
        final request = data['request'];
        if (request is Map && request['status'] == 'accepted') {
          // 接受申请会改变联系人关系，不能只根据事件载荷拼接本地列表。
          unawaited(loadFromServer(force: true));
        }
      },
    );
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
    if (_friendRequestHandlerId != null) {
      _ws.unregisterHandler(_friendRequestHandlerId!);
      _friendRequestHandlerId = null;
    }
    super.dispose();
  }

  /// 初始化
  Future<void> initialize() async {
    if (_accountId.isEmpty) return;
    if (_isInitialized) return;
    await loadFromServer(force: true);
  }

  /// 从本地 Isar 读取联系人列表缓存，先展示再请求服务器。
  ///
  /// Isar 只负责首屏快速展示，不是联系人关系的权威数据源。
  Future<void> _loadContactListFromCache() async {
    if (_accountId.isEmpty || _isDisposed) return;
    if (PlatformUtils.isWeb) return;
    if (!IsarService.instance.isAvailable) return;

    try {
      final list = await IsarService.instance.isar.userModels
          .filter()
          .accountIdEqualTo(_accountId)
          .isContactEqualTo(true)
          .findAll();
      if (_isDisposed) return;
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
            ),
          )
          .toList();
      state = items;
      _isInitialized = true;
    } catch (e) {
      debugPrint('[Contact] Failed to load from cache: $e');
    }
  }

  /// 拉取全部联系人（自动分页，避免后端分页导致只返回部分数据）
  Future<_ContactFetchResult> _fetchAllContacts() async {
    if (_accountId.isEmpty || _isDisposed) {
      return const _ContactFetchResult(contacts: [], success: false);
    }
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
            final list = (fallback.data['list'] as List?)
                    ?.map((e) => ContactItem.fromJson(e))
                    .toList() ??
                [];
            return _ContactFetchResult(contacts: list, success: true);
          }
        }
        return const _ContactFetchResult(contacts: [], success: false);
      }

      final batch = (response.data['list'] as List?)
              ?.map((e) => ContactItem.fromJson(e))
              .toList() ??
          [];
      var addedCount = 0;
      for (final contact in batch) {
        // uuid 优先、id 兜底，防止分页边界重复数据导致同一联系人出现两次。
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

    return _ContactFetchResult(contacts: allContacts, success: true);
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
    if (_accountId.isEmpty || _isDisposed) return;
    // 防抖：500ms 内不重复请求
    final now = DateTime.now();
    final lastLoadTime = _lastLoadTime;
    final hasFreshState = _isInitialized &&
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
      final result = await _fetchAllContacts();
      if (_isDisposed) return;
      if (!result.success) return;
      final list = result.contacts;

      // 请求成功后即使列表为空也要覆盖缓存态，确保已删除的关系不会残留。
      state = list;
      _isInitialized = true;
      if (PlatformUtils.isWeb) {
        return;
      }
      if (!IsarService.instance.isAvailable) return;

      // 写入 Isar；成功返回空列表时也必须清除该账号旧索引。
      try {
        final now = DateTime.now();
        final models = list.map((c) {
          final m = UserModel();
          m.accountId = _accountId;
          m.id = c.id;
          m.username = c.username ?? '';
          m.nickname = c.name;
          m.avatar = c.avatar;
          m.phone = c.phone;
          m.bio = c.bio;
          m.nicknameColor = c.nicknameColor;
          m.emojiAvatar = c.emojiAvatar;
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
              .accountIdEqualTo('')
              .deleteAll();
          await IsarService.instance.isar.userModels
              .filter()
              .accountIdEqualTo(_accountId)
              .isContactEqualTo(true)
              .deleteAll();
          if (models.isNotEmpty) {
            await IsarService.instance.isar.userModels.putAll(models);
          }
        });
      } catch (e) {
        debugPrint('[Contact] Failed to cache contacts: $e');
      }

      final avatarUrls = list
          .map((c) => c.avatar)
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList();
      AvatarCacheManager.prefetchUrls(avatarUrls);
    } catch (e) {
      debugPrint('[Contact] Load from server failed: $e');
    }
  }

  /// 刷新联系人列表
  Future<void> refresh() async {
    await loadFromServer(force: true);
  }

  /// 静默刷新联系人列表（从后台恢复时使用，不触发UI加载状态）
  Future<void> silentRefresh() async {
    if (_accountId.isEmpty || _isDisposed) return;
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
      final result = await _fetchAllContacts();
      if (_isDisposed) return;
      if (!result.success) return;
      final list = result.contacts;

      if (_hasListChanges(list)) {
        state = list;
      }
      if (PlatformUtils.isWeb) return;
      if (!IsarService.instance.isAvailable) return;

      try {
        final now = DateTime.now();
        final models = list.map((c) {
          final m = UserModel();
          m.accountId = _accountId;
          m.id = c.id;
          m.username = c.username ?? '';
          m.nickname = c.name;
          m.avatar = c.avatar;
          m.phone = c.phone;
          m.bio = c.bio;
          m.nicknameColor = c.nicknameColor;
          m.emojiAvatar = c.emojiAvatar;
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
              .accountIdEqualTo('')
              .deleteAll();
          await IsarService.instance.isar.userModels
              .filter()
              .accountIdEqualTo(_accountId)
              .isContactEqualTo(true)
              .deleteAll();
          if (models.isNotEmpty) {
            await IsarService.instance.isar.userModels.putAll(models);
          }
        });
      } catch (e) {
        debugPrint(
          '[Contact] Failed to cache contacts in silent refresh: $e',
        );
      }
    } catch (e) {
      // 静默刷新失败记录日志
      debugPrint('[Contact] Silent refresh failed: $e');
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
          state[i].vip != newList[i].vip) {
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
    // 搜索结果是用户目录匹配，不代表双方已经建立联系人关系。
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

  Future<FriendRequestSubmitResult?> sendFriendRequest(
    String userId, {
    String message = '',
  }) async {
    final response = await _api.post(
      '/contact/requests',
      data: {'user_id': userId, 'message': message.trim()},
    );
    if (!response.isSuccess || response.data is! Map) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final requestJson = data['request'];
    if (requestJson is! Map) return null;
    final result = FriendRequestSubmitResult(
      request: FriendRequestItem.fromJson(
        Map<String, dynamic>.from(requestJson),
      ),
      created: data['created'] == true,
      autoAccepted: data['auto_accepted'] == true,
    );
    if (result.autoAccepted || result.request.status == 'accepted') {
      await loadFromServer(force: true);
    }
    return result;
  }

  Future<List<FriendRequestItem>> loadFriendRequests({
    required String box,
  }) async {
    final response = await _api.get(
      '/contact/requests',
      queryParameters: {'box': box},
    );
    if (!response.isSuccess || response.data is! Map) return const [];
    final list = (response.data['list'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map(
          (item) => FriendRequestItem.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<bool> reviewFriendRequest(String requestId,
      {required bool accept}) async {
    final action = accept ? 'accept' : 'reject';
    // 申请可能已在另一端处理或过期，最终状态必须以本次服务端响应为准。
    final response = await _api.post('/contact/requests/$requestId/$action');
    if (response.isSuccess && accept) {
      await loadFromServer(force: true);
    }
    return response.isSuccess;
  }

  /// 删除联系人（调用API）
  Future<bool> removeContact(String contactId) async {
    final response = await _api.delete('/contact/$contactId');

    if (response.isSuccess) {
      // 同时检查 id 和 uuid，因为 contactId 可能是任意一种格式
      state =
          state.where((c) => c.id != contactId && c.uuid != contactId).toList();
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
