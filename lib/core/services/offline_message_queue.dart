// 文件用途：封装 OfflineMessageType 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：在网络不可用时持久化待发送消息，恢复连接后按顺序重放，并根据幂等 ID 防止重复发送。
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 关键声明：offline message queue 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 离线消息类型
enum OfflineMessageType {
  text,
  image,
  video,
  file,
  voice,
}

enum OfflineMessageSendResult {
  success,
  retry,
  permanentFailure,
}

/// 离线消息数据
class OfflineMessage {
  final String accountId;
  final String id;
  final String chatId;
  final OfflineMessageType type;
  final String? content;
  final String? localPath;
  final int? width;
  final int? height;
  final int? duration;
  final String? fileName;
  final DateTime createdAt;
  int retryCount;

  OfflineMessage({
    required this.accountId,
    required this.id,
    required this.chatId,
    required this.type,
    this.content,
    this.localPath,
    this.width,
    this.height,
    this.duration,
    this.fileName,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'id': id,
        'chatId': chatId,
        'type': type.index,
        'content': content,
        'localPath': localPath,
        'width': width,
        'height': height,
        'duration': duration,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory OfflineMessage.fromJson(Map<String, dynamic> json) {
    final typeIndex = (json['type'] as num?)?.toInt() ?? 0;
    final type =
        (typeIndex >= 0 && typeIndex < OfflineMessageType.values.length)
            ? OfflineMessageType.values[typeIndex]
            : OfflineMessageType.text; // 未知类型回退到 text
    return OfflineMessage(
      accountId: json['accountId']?.toString() ?? '',
      id: json['id'],
      chatId: json['chatId'],
      type: type,
      content: json['content'],
      localPath: json['localPath'],
      width: json['width'],
      height: json['height'],
      duration: json['duration'],
      fileName: json['fileName'],
      createdAt: DateTime.parse(json['createdAt']),
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

/// 离线消息队列服务
///
/// 功能：
/// - 监听网络状态变化
/// - 断网时缓存待发送消息
/// - 恢复网络后自动重发
class OfflineMessageQueue {
  static final OfflineMessageQueue _instance = OfflineMessageQueue._internal();
  factory OfflineMessageQueue() => _instance;
  OfflineMessageQueue._internal();

  static const String _legacyStorageKey = 'offline_message_queue';
  static const String _legacyCleanupKey =
      'offline_message_queue_account_migration_v1';
  static const int _markFailedAfterRetryCount = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  final List<OfflineMessage> _queue = [];
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool _isProcessing = false;
  bool _isDisposed = false;
  bool _isInitialized = false;
  String _activeAccountId = '';
  int _accountGeneration = 0;

  /// 发送回调（由外部注入）
  Future<OfflineMessageSendResult> Function(OfflineMessage message)?
      onSendMessage;

  /// 消息重试耗尽回调（由外部注入）
  Future<void> Function(OfflineMessage message)? onMessageFailed;

  /// 状态变化回调
  void Function(bool isOnline)? onNetworkStatusChanged;

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 旧版队列没有账号归属，无法安全迁移；直接清除可避免用新账号 Token
    // 发送上一账号遗留的消息。
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyCleanupKey) != true) {
      await prefs.remove(_legacyStorageKey);
      await prefs.setBool(_legacyCleanupKey, true);
    }

    // Connectivity 只表示存在网络接口，不保证服务端可达；实际发送结果仍由回调判定。
    final results = await _connectivity.checkConnectivity();
    _isOnline = !results.contains(ConnectivityResult.none);
    debugPrint(
        '[OfflineQueue] Initial network status: ${_isOnline ? "online" : "offline"}');

    // 监听网络变化
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);

      debugPrint(
          '[OfflineQueue] Network changed: ${_isOnline ? "online" : "offline"}');

      onNetworkStatusChanged?.call(_isOnline);

      // 从离线恢复到在线，尝试发送队列
      if (!wasOnline && _isOnline) {
        _processQueue();
      }
    });

    // 如果在线且有待发送消息，立即处理
    if (_isOnline && _queue.isNotEmpty && _activeAccountId.isNotEmpty) {
      _processQueue();
    }
  }

  String _storageKeyFor(String accountId) {
    final digest = crypto.sha256.convert(utf8.encode(accountId.trim()));
    return 'acct_v1_${digest}_offline_message_queue';
  }

  Future<void> activateAccount(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return;
    if (!_isInitialized) await initialize();
    if (_activeAccountId == normalized) return;

    // 代次用于废弃切号前尚未完成的加载和发送结果。
    final generation = ++_accountGeneration;
    _activeAccountId = normalized;
    _queue.clear();
    await _loadQueue(normalized, generation);
    if (_activeAccountId != normalized || _accountGeneration != generation) {
      return;
    }
    if (_isOnline && _queue.isNotEmpty) {
      unawaited(_processQueue());
    }
  }

  Future<void> freezeAccount(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty || _activeAccountId != normalized) return;
    _accountGeneration++;
    // 先复制并隔离内存队列，再按原账号键持久化，退出期间不会继续发送。
    final frozenMessages = List<OfflineMessage>.from(_queue);
    _queue.clear();
    _activeAccountId = '';
    await _saveQueue(accountId: normalized, messages: frozenMessages);
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  /// 释放资源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    onSendMessage = null;
    onMessageFailed = null;
    onNetworkStatusChanged = null;
    debugPrint('[OfflineQueue] Disposed');
  }

  /// 当前是否在线
  bool get isOnline => _isOnline;

  /// 队列中的消息数量
  int get queueLength => _queue.length;

  /// 发送回调绑定后或恢复前台时，主动触发一次待发送队列处理。
  Future<void> processPending() => _processQueue();

  /// 添加消息到队列
  Future<void> enqueue(OfflineMessage message) async {
    if (message.accountId.trim().isEmpty ||
        message.accountId != _activeAccountId) {
      debugPrint(
        '[OfflineQueue] Refused cross-account enqueue: ${message.id}',
      );
      return;
    }
    // 消息 ID 是队列幂等键，重复入队更新同一待发送项而不是重复发送。
    _queue.removeWhere((m) => m.id == message.id);
    _queue.add(message);
    await _saveQueue();
    debugPrint(
        '[OfflineQueue] Enqueued message: ${message.id} (queue: ${_queue.length})');

    // 如果在线，立即尝试发送
    if (_isOnline) {
      _processQueue();
    }
  }

  /// 从队列移除消息
  Future<void> dequeue(String messageId) async {
    _queue.removeWhere((m) => m.id == messageId);
    await _saveQueue();
  }

  /// 处理队列中的消息
  Future<void> _processQueue() async {
    if (_isProcessing ||
        _queue.isEmpty ||
        onSendMessage == null ||
        _activeAccountId.isEmpty) {
      return;
    }

    _isProcessing = true;
    // 整轮处理绑定账号和代次；任一变化都立即停止消费旧快照。
    final processingAccountId = _activeAccountId;
    final processingGeneration = _accountGeneration;
    var retryBlocked = false;
    debugPrint('[OfflineQueue] Processing ${_queue.length} queued messages');

    try {
      // 复制队列避免并发修改
      final messages = List<OfflineMessage>.from(_queue);

      for (final message in messages) {
        if (_activeAccountId != processingAccountId ||
            _accountGeneration != processingGeneration ||
            message.accountId != processingAccountId) {
          break;
        }
        if (!_isOnline) {
          debugPrint('[OfflineQueue] Network lost, stopping');
          break;
        }

        try {
          final result = await onSendMessage!(message);

          if (_activeAccountId != processingAccountId ||
              _accountGeneration != processingGeneration) {
            break;
          }

          if (result == OfflineMessageSendResult.success) {
            await dequeue(message.id);
            debugPrint('[OfflineQueue] Sent successfully: ${message.id}');
          } else if (result == OfflineMessageSendResult.permanentFailure) {
            debugPrint(
                '[OfflineQueue] Permanent failure, marking failed: ${message.id}');
            await onMessageFailed?.call(message);
            await dequeue(message.id);
          } else {
            // 临时失败耗尽本轮重试后仍保留在持久化队列，等待下次显式触发；
            // onMessageFailed 只负责更新 UI 失败态，不代表丢弃消息。
            message.retryCount++;
            if (message.retryCount >= _markFailedAfterRetryCount) {
              debugPrint(
                  '[OfflineQueue] Transient retries exhausted, keeping queued: ${message.id}');
              await onMessageFailed?.call(message);
              await _saveQueue();
              retryBlocked = true;
              break;
            } else {
              debugPrint(
                  '[OfflineQueue] Retry ${message.retryCount}/$_markFailedAfterRetryCount: ${message.id}');
              await _saveQueue();
              await Future.delayed(_retryDelay);
            }
          }
        } catch (e) {
          debugPrint('[OfflineQueue] Send error: $e');
          message.retryCount++;
          if (message.retryCount >= _markFailedAfterRetryCount) {
            debugPrint(
                '[OfflineQueue] Transient error retries exhausted, keeping queued: ${message.id}');
            await onMessageFailed?.call(message);
            await _saveQueue();
            retryBlocked = true;
            break;
          } else {
            await _saveQueue();
          }
        }
      }
    } finally {
      _isProcessing = false;
      if (!retryBlocked &&
          _activeAccountId.isNotEmpty &&
          _queue.isNotEmpty &&
          _isOnline) {
        unawaited(_processQueue());
      }
    }
  }

  /// 持久化队列到本地存储
  Future<void> _saveQueue({
    String? accountId,
    List<OfflineMessage>? messages,
  }) async {
    try {
      final owner = (accountId ?? _activeAccountId).trim();
      if (owner.isEmpty) return;
      // 写入不可变快照，避免 await 获取存储实例期间队列变化导致跨账号串写。
      final snapshot = List<OfflineMessage>.from(messages ?? _queue);
      final jsonList = snapshot.map((m) => jsonEncode(m.toJson())).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKeyFor(owner), jsonList);
    } catch (e) {
      debugPrint('[OfflineQueue] Save error: $e');
    }
  }

  /// 从本地存储加载队列
  Future<void> _loadQueue(String accountId, int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_storageKeyFor(accountId)) ?? [];

      // 存储读取期间可能已经切号，旧账号结果不得重新注入当前内存队列。
      if (_activeAccountId != accountId || _accountGeneration != generation) {
        return;
      }

      _queue.clear();
      for (final jsonStr in jsonList) {
        try {
          final json = jsonDecode(jsonStr);
          final message = OfflineMessage.fromJson(json);
          if (message.accountId == accountId) {
            _queue.add(message);
          }
        } catch (_) {}
      }

      debugPrint(
          '[OfflineQueue] Loaded ${_queue.length} messages from storage');
    } catch (e) {
      debugPrint('[OfflineQueue] Load error: $e');
    }
  }

  /// 清空队列
  Future<void> clear() async {
    final owner = _activeAccountId;
    _queue.clear();
    if (owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKeyFor(owner));
  }

  Future<void> clearAccount(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return;
    if (_activeAccountId == normalized) {
      _accountGeneration++;
      _queue.clear();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKeyFor(normalized));
  }
}
