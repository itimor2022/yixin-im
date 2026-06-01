import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const String _storageKey = 'offline_message_queue';
  static const int _maxRetryCount = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  final List<OfflineMessage> _queue = [];
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool _isProcessing = false;
  bool _isDisposed = false;

  /// 发送回调（由外部注入）
  Future<OfflineMessageSendResult> Function(OfflineMessage message)?
      onSendMessage;

  /// 消息重试耗尽回调（由外部注入）
  Future<void> Function(OfflineMessage message)? onMessageFailed;

  /// 状态变化回调
  void Function(bool isOnline)? onNetworkStatusChanged;

  /// 初始化服务
  Future<void> initialize() async {
    // 加载持久化的队列
    await _loadQueue();

    // 检查初始网络状态
    final results = await _connectivity.checkConnectivity();
    _isOnline = !results.contains(ConnectivityResult.none);
    if (kDebugMode) debugPrint(
        '[OfflineQueue] Initial network status: ${_isOnline ? "online" : "offline"}');

    // 监听网络变化
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);

      if (kDebugMode) debugPrint(
          '[OfflineQueue] Network changed: ${_isOnline ? "online" : "offline"}');

      onNetworkStatusChanged?.call(_isOnline);

      // 从离线恢复到在线，尝试发送队列
      if (!wasOnline && _isOnline) {
        _processQueue();
      }
    });

    // 如果在线且有待发送消息，立即处理
    if (_isOnline && _queue.isNotEmpty) {
      _processQueue();
    }
  }

  /// 释放资源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    onSendMessage = null;
    onMessageFailed = null;
    onNetworkStatusChanged = null;
    if (kDebugMode) debugPrint('[OfflineQueue] Disposed');
  }

  /// 当前是否在线
  bool get isOnline => _isOnline;

  /// 队列中的消息数量
  int get queueLength => _queue.length;

  /// 发送回调绑定后或恢复前台时，主动触发一次待发送队列处理。
  Future<void> processPending() => _processQueue();

  /// 添加消息到队列
  Future<void> enqueue(OfflineMessage message) async {
    _queue.add(message);
    await _saveQueue();
    if (kDebugMode) debugPrint(
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
    if (_isProcessing || _queue.isEmpty || onSendMessage == null) return;

    _isProcessing = true;
    if (kDebugMode) debugPrint('[OfflineQueue] Processing ${_queue.length} queued messages');

    try {
      // 复制队列避免并发修改
      final messages = List<OfflineMessage>.from(_queue);

      for (final message in messages) {
        if (!_isOnline) {
          if (kDebugMode) debugPrint('[OfflineQueue] Network lost, stopping');
          break;
        }

        try {
          final result = await onSendMessage!(message);

          if (result == OfflineMessageSendResult.success) {
            await dequeue(message.id);
            if (kDebugMode) debugPrint('[OfflineQueue] Sent successfully: ${message.id}');
          } else if (result == OfflineMessageSendResult.permanentFailure) {
            if (kDebugMode) debugPrint(
                '[OfflineQueue] Permanent failure, marking failed: ${message.id}');
            await onMessageFailed?.call(message);
            await dequeue(message.id);
          } else {
            message.retryCount++;
            if (message.retryCount >= _maxRetryCount) {
              if (kDebugMode) debugPrint(
                  '[OfflineQueue] Max retries reached, marking failed: ${message.id}');
              await onMessageFailed?.call(message);
              await dequeue(message.id);
            } else {
              if (kDebugMode) debugPrint(
                  '[OfflineQueue] Retry ${message.retryCount}/$_maxRetryCount: ${message.id}');
              await _saveQueue();
              await Future.delayed(_retryDelay);
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[OfflineQueue] Send error: $e');
          message.retryCount++;
          if (message.retryCount >= _maxRetryCount) {
            if (kDebugMode) debugPrint(
                '[OfflineQueue] Max retries reached after error, marking failed: ${message.id}');
            await onMessageFailed?.call(message);
            await dequeue(message.id);
          } else {
            await _saveQueue();
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// 持久化队列到本地存储
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _queue.map((m) => jsonEncode(m.toJson())).toList();
      await prefs.setStringList(_storageKey, jsonList);
    } catch (e) {
      if (kDebugMode) debugPrint('[OfflineQueue] Save error: $e');
    }
  }

  /// 从本地存储加载队列
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_storageKey) ?? [];

      _queue.clear();
      for (final jsonStr in jsonList) {
        try {
          final json = jsonDecode(jsonStr);
          _queue.add(OfflineMessage.fromJson(json));
        } catch (_) {}
      }

      if (kDebugMode) debugPrint(
          '[OfflineQueue] Loaded ${_queue.length} messages from storage');
    } catch (e) {
      if (kDebugMode) debugPrint('[OfflineQueue] Load error: $e');
    }
  }

  /// 清空队列
  Future<void> clear() async {
    _queue.clear();
    await _saveQueue();
  }
}
