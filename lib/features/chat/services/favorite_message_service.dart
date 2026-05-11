import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api/api_client.dart';
import '../providers/message_provider.dart';

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
        return content.trim().isNotEmpty ? content.trim() : '[文本消息]';
      case MessageItemType.image:
        return content.trim().isNotEmpty ? content.trim() : '[图片]';
      case MessageItemType.video:
        return '[视频]';
      case MessageItemType.voice:
        return content.trim().isNotEmpty ? content.trim() : '[语音]';
      case MessageItemType.file:
        return fileName?.trim().isNotEmpty == true
            ? '[文件] ${fileName!.trim()}'
            : '[文件]';
      case MessageItemType.location:
        return locationTitle?.trim().isNotEmpty == true
            ? locationTitle!.trim()
            : (locationAddress?.trim().isNotEmpty == true
                ? locationAddress!.trim()
                : '[位置]');
      case MessageItemType.contact:
        return content.trim().isNotEmpty ? content.trim() : '[名片]';
      case MessageItemType.redPacket:
        return '[红包]';
      case MessageItemType.transfer:
        return '[转账]';
      case MessageItemType.call:
        return '[通话]';
      case MessageItemType.system:
        return content.trim().isNotEmpty ? content.trim() : '[系统消息]';
      case MessageItemType.audio:
        return '[音频]';
      case MessageItemType.sticker:
        return '[表情]';
      case MessageItemType.gif:
        return '[GIF]';
      case MessageItemType.poll:
        return '[投票]';
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

  String _storageKeyFor(String accountKey) {
    final normalized = accountKey.trim();
    if (normalized.isEmpty) return _storageKey;
    return '${_storageKey}_$normalized';
  }

  Future<String> _resolveAccountKey(String accountKey) async {
    final normalized = accountKey.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    final storedUserId = (await TokenStorage.getUserId())?.trim() ?? '';
    return storedUserId;
  }

  Future<List<String>> _candidateStorageKeys(String accountKey) async {
    final keys = <String>{_storageKey};
    final normalized = accountKey.trim();
    if (normalized.isNotEmpty) {
      keys.add(_storageKeyFor(normalized));
    }
    final storedUserId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (storedUserId.isNotEmpty) {
      keys.add(_storageKeyFor(storedUserId));
    }
    return keys.toList(growable: false);
  }

  Future<List<String>> _fallbackScopedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((key) => key.startsWith('${_storageKey}_'))
        .toList(growable: false);
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
    final primaryKeys = await _candidateStorageKeys(resolvedAccountKey);

    final merged = _mergeFavorites(
      await _loadFavoritesFromKeys(primaryKeys),
    );
    if (merged.isNotEmpty) {
      if (resolvedAccountKey.isNotEmpty) {
        await _saveFavorites(resolvedAccountKey, merged);
      }
      return merged;
    }

    final fallbackKeys = await _fallbackScopedKeys();
    final fallbackMerged = _mergeFavorites(
      await _loadFavoritesFromKeys(fallbackKeys),
    );
    if (fallbackMerged.isNotEmpty && resolvedAccountKey.isNotEmpty) {
      await _saveFavorites(resolvedAccountKey, fallbackMerged);
    }
    return fallbackMerged;
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
      favorites.removeAt(index);
      await _saveFavorites(resolvedAccountKey, favorites);
      return false;
    }

    favorites.insert(
      0,
      FavoriteMessageEntry.fromMessage(message, chatName: chatName),
    );
    await _saveFavorites(resolvedAccountKey, favorites);
    return true;
  }

  Future<void> removeFavorite(
    String accountKey,
    FavoriteMessageEntry target,
  ) async {
    final resolvedAccountKey = await _resolveAccountKey(accountKey);
    final favorites = await loadFavorites(resolvedAccountKey);
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
}
