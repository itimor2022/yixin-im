// 文件用途：封装 FavoriteMessageEntry 相关业务流程与外部能力调用，属于聊天与消息。
// 核心逻辑：封装 FavoriteMessageEntry 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../providers/message_provider.dart';
import '../utils/system_message_text.dart';

String _favoriteMessageText({
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

// 关键声明：favorite message service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class FavoriteMessageEntry {
  final String messageId;
  final int? messageSeq;
  final String chatId;
  final String chatName;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String messageType;
  final String content;
  final String? mediaUrl;
  final String? fileName;
  final int? mediaDuration;
  final double? locationLatitude;
  final double? locationLongitude;
  final String? locationTitle;
  final String? locationAddress;
  final DateTime createdAt;
  final DateTime collectedAt;

  const FavoriteMessageEntry({
    required this.messageId,
    this.messageSeq,
    required this.chatId,
    required this.chatName,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.messageType,
    required this.content,
    this.mediaUrl,
    this.fileName,
    this.mediaDuration,
    this.locationLatitude,
    this.locationLongitude,
    this.locationTitle,
    this.locationAddress,
    required this.createdAt,
    required this.collectedAt,
  });

  MessageItemType get type {
    return MessageItemType.values.firstWhere(
      (value) => value.name == messageType,
      orElse: () => MessageItemType.text,
    );
  }

  String get previewText {
    switch (type) {
      case MessageItemType.text:
        return content.trim().isNotEmpty
            ? content.trim()
            : _favoriteMessageText(
                zhCN: '[文本消息]',
                zhTW: '[文字訊息]',
                en: '[Text message]',
              );
      case MessageItemType.image:
        return content.trim().isNotEmpty
            ? content.trim()
            : _favoriteMessageText(
                zhCN: '[图片]',
                zhTW: '[圖片]',
                en: '[Photo]',
              );
      case MessageItemType.video:
        return _favoriteMessageText(
          zhCN: '[视频]',
          zhTW: '[影片]',
          en: '[Video]',
        );
      case MessageItemType.voice:
        return content.trim().isNotEmpty
            ? content.trim()
            : _favoriteMessageText(
                zhCN: '[语音]',
                zhTW: '[語音]',
                en: '[Voice message]',
              );
      case MessageItemType.file:
        return fileName?.trim().isNotEmpty == true
            ? '${_favoriteMessageText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]')} ${fileName!.trim()}'
            : _favoriteMessageText(
                zhCN: '[文件]',
                zhTW: '[檔案]',
                en: '[File]',
              );
      case MessageItemType.location:
        return locationTitle?.trim().isNotEmpty == true
            ? locationTitle!.trim()
            : (locationAddress?.trim().isNotEmpty == true
                ? locationAddress!.trim()
                : _favoriteMessageText(
                    zhCN: '[位置]',
                    zhTW: '[位置]',
                    en: '[Location]',
                  ));
      case MessageItemType.contact:
        return content.trim().isNotEmpty
            ? content.trim()
            : _favoriteMessageText(
                zhCN: '[名片]',
                zhTW: '[名片]',
                en: '[Contact card]',
              );
      case MessageItemType.redPacket:
        return _favoriteMessageText(
          zhCN: '[红包]',
          zhTW: '[紅包]',
          en: '[Red packet]',
        );
      case MessageItemType.transfer:
        return _favoriteMessageText(
          zhCN: '[转账]',
          zhTW: '[轉帳]',
          en: '[Transfer]',
        );
      case MessageItemType.forwardBundle:
        return _favoriteMessageText(
          zhCN: '[聊天记录]',
          zhTW: '[聊天記錄]',
          en: '[Chat history]',
        );
      case MessageItemType.call:
        return _favoriteMessageText(
          zhCN: '[通话]',
          zhTW: '[通話]',
          en: '[Call]',
        );
      case MessageItemType.system:
        return content.trim().isNotEmpty
            ? resolveSystemMessageText(content.trim())
            : _favoriteMessageText(
                zhCN: '[系统消息]',
                zhTW: '[系統訊息]',
                en: '[System message]',
              );
      case MessageItemType.audio:
        return _favoriteMessageText(
          zhCN: '[音频]',
          zhTW: '[音訊]',
          en: '[Audio]',
        );
      case MessageItemType.sticker:
        return _favoriteMessageText(
          zhCN: '[表情]',
          zhTW: '[貼圖]',
          en: '[Sticker]',
        );
      case MessageItemType.gif:
        return '[GIF]';
      case MessageItemType.poll:
        return _favoriteMessageText(
          zhCN: '[投票]',
          zhTW: '[投票]',
          en: '[Poll]',
        );
    }
  }

  bool get canOpenLocation =>
      type == MessageItemType.location &&
      locationLatitude != null &&
      locationLongitude != null;

  String get storageId {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isNotEmpty) {
      return 'msg:$normalizedMessageId';
    }
    if (messageSeq != null && messageSeq! > 0) {
      return 'seq:$messageSeq';
    }
    final createdAtMillis = createdAt.millisecondsSinceEpoch;
    if (createdAtMillis > 0) {
      return 'time:$createdAtMillis';
    }
    final preview = previewText.trim();
    if (preview.isNotEmpty) {
      return 'preview:${preview.hashCode}';
    }
    return 'fallback:${senderId.trim()}_${collectedAt.millisecondsSinceEpoch}';
  }

  String get dedupeKey {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return storageId;
    }
    return '$normalizedChatId::$storageId';
  }

  // 流程逻辑：`fromMessage` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  factory FavoriteMessageEntry.fromMessage(
    MessageItem message, {
    required String chatName,
  }) {
    return FavoriteMessageEntry(
      messageId: message.id,
      messageSeq: message.seq > 0 ? message.seq : null,
      chatId: message.chatId,
      chatName: chatName,
      senderId: message.senderId,
      senderName: message.senderName,
      senderAvatar: message.senderAvatar,
      messageType: message.type.name,
      content: message.content,
      mediaUrl: message.mediaUrl,
      fileName: message.fileName,
      mediaDuration: message.mediaDuration,
      locationLatitude: message.locationLatitude,
      locationLongitude: message.locationLongitude,
      locationTitle: message.locationTitle,
      locationAddress: message.locationAddress,
      createdAt: message.createdAt,
      collectedAt: DateTime.now(),
    );
  }

  factory FavoriteMessageEntry.fromJson(Map<String, dynamic> json) {
    return FavoriteMessageEntry(
      messageId: json['message_id']?.toString() ?? '',
      messageSeq: json['message_seq'] is num
          ? (json['message_seq'] as num).toInt()
          : int.tryParse(json['message_seq']?.toString() ?? ''),
      chatId: json['chat_id']?.toString() ?? '',
      chatName: json['chat_name']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      senderAvatar: json['sender_avatar']?.toString(),
      messageType:
          json['message_type']?.toString() ?? MessageItemType.text.name,
      content: json['content']?.toString() ?? '',
      mediaUrl: json['media_url']?.toString(),
      fileName: json['file_name']?.toString(),
      mediaDuration: json['media_duration'] is num
          ? (json['media_duration'] as num).toInt()
          : int.tryParse(json['media_duration']?.toString() ?? ''),
      locationLatitude: _readDouble(json['location_latitude']),
      locationLongitude: _readDouble(json['location_longitude']),
      locationTitle: json['location_title']?.toString(),
      locationAddress: json['location_address']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      collectedAt: DateTime.tryParse(json['collected_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      if (messageSeq != null) 'message_seq': messageSeq,
      'chat_id': chatId,
      'chat_name': chatName,
      'sender_id': senderId,
      'sender_name': senderName,
      if (senderAvatar != null) 'sender_avatar': senderAvatar,
      'message_type': messageType,
      'content': content,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (fileName != null) 'file_name': fileName,
      if (mediaDuration != null) 'media_duration': mediaDuration,
      if (locationLatitude != null) 'location_latitude': locationLatitude,
      if (locationLongitude != null) 'location_longitude': locationLongitude,
      if (locationTitle != null) 'location_title': locationTitle,
      if (locationAddress != null) 'location_address': locationAddress,
      'created_at': createdAt.toIso8601String(),
      'collected_at': collectedAt.toIso8601String(),
    };
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class FavoriteMessageService {
  static const String _storageKey = 'favorite_messages_v1';

  FavoriteMessageService({ApiClient? apiClient}) : _apiClient = apiClient;

  final ApiClient? _apiClient;

  String _storageKeyFor(String accountKey) {
    final normalized = accountKey.trim();
    if (normalized.isEmpty) return '';
    final accountHash = sha256.convert(utf8.encode(normalized));
    return 'acct_v1_${accountHash}_$_storageKey';
  }

  String _legacyScopedStorageKeyFor(String accountKey) {
    return '${_storageKey}_${accountKey.trim()}';
  }

  Future<String> _resolveAccountKey(String accountKey) async {
    return accountKey.trim();
  }

  Future<List<String>> _candidateStorageKeys(String accountKey) async {
    final normalized = accountKey.trim();
    if (normalized.isEmpty) return const [];
    return [_storageKeyFor(normalized)];
  }

  List<FavoriteMessageEntry> _mergeFavorites(
    Iterable<FavoriteMessageEntry> items,
  ) {
    final merged = <FavoriteMessageEntry>[];
    final seen = <String>{};
    for (final item in items) {
      if (seen.add(item.dedupeKey)) {
        merged.add(item);
      }
    }
    merged.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    return merged;
  }

  Future<List<FavoriteMessageEntry>> loadFavorites(String accountKey) async {
    final resolvedAccountKey = await _resolveAccountKey(accountKey);
    if (resolvedAccountKey.isEmpty) return const [];
    final remoteFavorites = await _loadRemoteFavorites();
    if (remoteFavorites != null) {
      final mergedRemote = _mergeFavorites(remoteFavorites);
      await _saveFavorites(resolvedAccountKey, mergedRemote);
      return mergedRemote;
    }
    final primaryKeys = await _candidateStorageKeys(resolvedAccountKey);

    var merged = _mergeFavorites(
      await _loadFavoritesFromKeys(primaryKeys),
    );
    if (merged.isEmpty) {
      final legacyKey = _legacyScopedStorageKeyFor(resolvedAccountKey);
      merged = _mergeFavorites(await _loadFavoritesFromKeys([legacyKey]));
      if (merged.isNotEmpty) {
        await _saveFavorites(resolvedAccountKey, merged);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(legacyKey);
      }
    }
    return merged;
  }

  Future<bool> contains(String accountKey, String messageId) async {
    final favorites = await loadFavorites(accountKey);
    final normalizedMessageId = messageId.trim();
    return favorites.any(
      (item) =>
          item.messageId == normalizedMessageId ||
          item.storageId == normalizedMessageId,
    );
  }

  Future<bool> toggleFavorite(
    String accountKey,
    MessageItem message, {
    required String chatName,
  }) async {
    final resolvedAccountKey = await _resolveAccountKey(accountKey);
    if (resolvedAccountKey.isEmpty) return false;
    final favorites = await loadFavorites(resolvedAccountKey);
    final targetKey = _messageKey(message);
    final normalizedMessageId = message.id.trim();
    final index = favorites.indexWhere(
      (item) =>
          item.dedupeKey == targetKey ||
          (normalizedMessageId.isNotEmpty &&
              item.messageId == normalizedMessageId),
    );
    if (index >= 0) {
      await _deleteRemoteFavorite(favorites[index]);
      favorites.removeAt(index);
      await _saveFavorites(resolvedAccountKey, favorites);
      return false;
    }

    final localEntry =
        FavoriteMessageEntry.fromMessage(message, chatName: chatName);
    final remoteEntry = await _addRemoteFavorite(localEntry);
    favorites.insert(0, remoteEntry ?? localEntry);
    await _saveFavorites(resolvedAccountKey, favorites);
    return true;
  }

  Future<void> removeFavorite(
    String accountKey,
    FavoriteMessageEntry target,
  ) async {
    final resolvedAccountKey = await _resolveAccountKey(accountKey);
    if (resolvedAccountKey.isEmpty) return;
    final favorites = await loadFavorites(resolvedAccountKey);
    await _deleteRemoteFavorite(target);
    favorites.removeWhere((item) => item.dedupeKey == target.dedupeKey);
    await _saveFavorites(resolvedAccountKey, favorites);
  }

  String _messageKey(MessageItem message) {
    final chatId = message.chatId.trim();
    final messageId = message.id.trim();
    if (messageId.isNotEmpty) {
      return '$chatId::msg:$messageId';
    }
    if (message.seq > 0) {
      return '$chatId::seq:${message.seq}';
    }
    final createdAtMillis = message.createdAt.millisecondsSinceEpoch;
    if (createdAtMillis > 0) {
      return '$chatId::time:$createdAtMillis';
    }
    final preview = message.content.trim();
    if (preview.isNotEmpty) {
      return '$chatId::preview:${preview.hashCode}';
    }
    return '$chatId::fallback:${message.senderId.trim()}';
  }

  Future<void> _saveFavorites(
    String accountKey,
    List<FavoriteMessageEntry> favorites,
  ) async {
    if (accountKey.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(favorites.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKeyFor(accountKey), encoded);
  }

  Future<List<FavoriteMessageEntry>> _loadFavoritesFromKeys(
    Iterable<String> storageKeys,
  ) async {
    final merged = <FavoriteMessageEntry>[];
    final seenKeys = <String>{};
    for (final key in storageKeys) {
      if (!seenKeys.add(key)) {
        continue;
      }
      merged.addAll(await _loadFavoritesByKey(key));
    }
    return merged;
  }

  Future<List<FavoriteMessageEntry>> _loadFavoritesByKey(
    String storageKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map(
            (item) =>
                FavoriteMessageEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.dedupeKey.isNotEmpty)
          .toList();
      items.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<List<FavoriteMessageEntry>?> _loadRemoteFavorites() async {
    final api = _apiClient;
    if (api == null) return null;
    final response = await api.get<Map<String, dynamic>>(
      '/message/favorites',
      queryParameters: const {'page': 1, 'page_size': 100},
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
    if (!response.isSuccess || response.data == null) return null;
    final rawList = response.data!['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map(
          (item) =>
              FavoriteMessageEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.dedupeKey.isNotEmpty)
        .toList(growable: false);
  }

  Future<FavoriteMessageEntry?> _addRemoteFavorite(
    FavoriteMessageEntry entry,
  ) async {
    final api = _apiClient;
    if (api == null) return null;
    final response = await api.post<Map<String, dynamic>>(
      '/message/favorite',
      data: {'chat_id': entry.chatId, 'message_id': entry.messageId},
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
    if (!response.isSuccess || response.data == null) {
      throw StateError(
          response.message.isEmpty ? 'favorite_failed' : response.message);
    }
    return FavoriteMessageEntry.fromJson(response.data!);
  }

  Future<void> _deleteRemoteFavorite(FavoriteMessageEntry entry) async {
    final api = _apiClient;
    if (api == null) return;
    final chatId = Uri.encodeComponent(entry.chatId);
    final messageId = Uri.encodeComponent(entry.messageId);
    final response = await api.delete<void>(
      '/message/favorite/$chatId/$messageId',
    );
    if (!response.isSuccess) {
      throw StateError(
        response.message.isEmpty ? 'remove_favorite_failed' : response.message,
      );
    }
  }
}
