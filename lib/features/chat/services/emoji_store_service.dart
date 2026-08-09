// 文件用途：封装 CustomEmojiItem 相关业务流程与外部能力调用，属于聊天与消息。
// 核心逻辑：封装 CustomEmojiItem 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/media_cache_manager.dart';

// 关键声明：emoji store service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class CustomEmojiItem {
  final String id;
  final String path;
  final String? remoteUrl;
  final DateTime createdAt;

  const CustomEmojiItem({
    required this.id,
    required this.path,
    this.remoteUrl,
    required this.createdAt,
  });

  bool get hasLocalPath =>
      path.isNotEmpty &&
      !path.startsWith('http://') &&
      !path.startsWith('https://');

  String? get displayPath {
    if (path.isNotEmpty) return path;
    return remoteUrl;
  }

  // 流程逻辑：`toJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        if (remoteUrl != null && remoteUrl!.isNotEmpty) 'remote_url': remoteUrl,
        'created_at': createdAt.toIso8601String(),
      };

  factory CustomEmojiItem.fromJson(Map<String, dynamic> json) {
    final remote = (json['remote_url'] ?? '').toString();
    final pathRaw = (json['path'] ?? '').toString();
    final path = pathRaw.isNotEmpty ? pathRaw : remote;
    return CustomEmojiItem(
      id: (json['id'] ?? '').toString(),
      path: path,
      remoteUrl: remote.isEmpty ? null : remote,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class RemoteStickerPayload {
  final String packId;
  final String stickerId;
  final String url;
  final String? emoji;

  const RemoteStickerPayload({
    required this.packId,
    required this.stickerId,
    required this.url,
    this.emoji,
  });
}

class EmojiStoreData {
  final List<String> installedPackIds;
  final List<String> favoriteCodes;
  final List<CustomEmojiItem> customEmojis;
  final List<String> recentEmojis;
  final String? cloudUpdatedAt;

  const EmojiStoreData({
    required this.installedPackIds,
    required this.favoriteCodes,
    required this.customEmojis,
    required this.recentEmojis,
    this.cloudUpdatedAt,
  });
}

class EmojiStoreService {
  EmojiStoreService._();

  static const String customEmojiSendPrefix = '__custom_emoji__:';
  static const String customEmojiSendUrlPrefix = '__custom_emoji_url__:';
  static const String builtInStickerSendPrefix = '__builtin_sticker__:';
  static const String remoteStickerSendPrefix = '__remote_sticker__:';

  static const String _installedPacksKey = 'installed_sticker_packs';
  static const String _favoriteCodesKey = 'favorite_emoji_codes';
  static const String _customEmojisKey = 'custom_emoji_items';
  static const String _recentEmojisKey = 'recent_emojis';
  static const String _cloudUpdatedAtKey = 'emoji_store_cloud_updated_at';

  static String _accountId = '';
  static int _generation = 0;

  static void activateAccount(String accountId) {
    final normalized = accountId.trim();
    if (normalized.isEmpty || normalized == _accountId) return;
    _accountId = normalized;
    _generation++;
  }

  static void freezeAccount(String accountId) {
    if (accountId.trim().isNotEmpty && accountId.trim() != _accountId) return;
    _accountId = '';
    _generation++;
  }

  static String? _accountKey(String baseKey) {
    if (_accountId.isEmpty) return null;
    final accountHash = sha256.convert(utf8.encode(_accountId));
    return 'acct_v1_${accountHash}_$baseKey';
  }

  static bool _isCurrentAccount(int generation, String accountId) {
    return generation == _generation &&
        accountId.isNotEmpty &&
        accountId == _accountId;
  }

  static const List<String> _defaultInstalledPackIds = [
    'cubigator',
    'duck',
    'premium_gifts',
  ];
  static const Set<String> _bundledStickerPackIds = {
    'cubigator',
    'duck',
    'premium_gifts',
  };

  static const String _emojiCodePrefix = 'emoji:';
  static const String _customCodePrefix = 'custom:';
  static const int _maxRecent = 30;
  static const int _maxInstalledPacks = 200;
  static const int _maxFavoriteCodes = 500;
  static const int _maxCustomEmojis = 300;
  static const int _maxPackIdRunes = 64;
  static const int _maxFavoriteCodeRunes = 128;
  static const int _maxCustomIdRunes = 64;
  static const int _maxCustomPathRunes = 1024;
  static const int _maxCatalogNameRunes = 100;
  static const int _maxCatalogDescRunes = 255;
  static const int _maxCatalogFileRunes = 100;
  static const int _maxCatalogFiles = 1000;

  static List<StickerPack>? _catalogCache;

  static bool isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  static bool isUploadRelativeUrl(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    return normalized.startsWith('/uploads/') ||
        normalized.startsWith('uploads/');
  }

  static bool isRemoteStickerFile(String value) {
    final normalized = value.trim();
    return isHttpUrl(normalized) || isUploadRelativeUrl(normalized);
  }

  static bool isLottieStickerFile(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    final path = Uri.tryParse(normalized)?.path.toLowerCase() ??
        normalized.toLowerCase();
    return path.endsWith('.json');
  }

  static bool isGifStickerFile(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    final path = Uri.tryParse(normalized)?.path.toLowerCase() ??
        normalized.toLowerCase();
    return path.endsWith('.gif');
  }

  static String? resolveBundledStickerAssetPath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return null;

    final path =
        Uri.tryParse(normalized)?.path.replaceAll('\\', '/') ?? normalized;
    const uploadPrefix = '/uploads/stickers/';
    const relativeUploadPrefix = 'uploads/stickers/';
    const assetPrefix = '/assets/stickers/';
    const relativeAssetPrefix = 'assets/stickers/';
    final relative = path.startsWith(uploadPrefix)
        ? path.substring(uploadPrefix.length)
        : path.startsWith(relativeUploadPrefix)
            ? path.substring(relativeUploadPrefix.length)
            : path.startsWith(assetPrefix)
                ? path.substring(assetPrefix.length)
                : path.startsWith(relativeAssetPrefix)
                    ? path.substring(relativeAssetPrefix.length)
                    : null;
    if (relative == null || relative.isEmpty) return null;

    final parts = relative.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2 || !_bundledStickerPackIds.contains(parts.first)) {
      return null;
    }
    return 'assets/stickers/${parts.join('/')}';
  }

  static String resolveStickerDisplayPath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return normalized;
    final bundledAsset = resolveBundledStickerAssetPath(normalized);
    if (bundledAsset != null) return bundledAsset;
    return resolveStickerFilePath(normalized);
  }

  static String resolveStickerFilePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return normalized;
    if (isHttpUrl(normalized)) return normalized;
    if (isUploadRelativeUrl(normalized)) {
      return ApiConfig.getMediaUrl(normalized);
    }
    return EmojiAnimations.getPath(normalized);
  }

  static String canonicalRemoteStickerUrl(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('uploads/')) return '/$normalized';
    return normalized;
  }

  static String stickerIdFromFile(String value, int index) {
    final normalized = value.trim().replaceAll('\\', '/');
    final path = Uri.tryParse(normalized)?.path ?? normalized;
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    final name = parts.isEmpty ? null : parts.last;
    if (name != null && name.isNotEmpty) {
      final dot = name.lastIndexOf('.');
      return dot > 0 ? name.substring(0, dot) : name;
    }
    return (index + 1).toString().padLeft(3, '0');
  }

  static String encodeRemoteStickerSend({
    required String packId,
    required String stickerId,
    required String url,
    String? emoji,
  }) {
    return '$remoteStickerSendPrefix${jsonEncode({
          'pack_id': packId,
          'sticker_id': stickerId,
          'url': canonicalRemoteStickerUrl(url),
          if (emoji != null && emoji.isNotEmpty) 'emoji': emoji,
        })}';
  }

  static RemoteStickerPayload? decodeRemoteStickerSend(String value) {
    if (!value.startsWith(remoteStickerSendPrefix)) return null;
    final raw = value.substring(remoteStickerSendPrefix.length);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final packId = (decoded['pack_id'] ?? '').toString();
      final stickerId = (decoded['sticker_id'] ?? '').toString();
      final url = canonicalRemoteStickerUrl((decoded['url'] ?? '').toString());
      if (packId.isEmpty || stickerId.isEmpty || url.isEmpty) return null;
      return RemoteStickerPayload(
        packId: packId,
        stickerId: stickerId,
        url: url,
        emoji: decoded['emoji']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ApiClient> _newAuthedApiClient() async {
    final api = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      api.setToken(token);
    }
    return api;
  }

  static Future<EmojiStoreData> _loadLocalOnly() async {
    final installedKey = _accountKey(_installedPacksKey);
    final favoriteKey = _accountKey(_favoriteCodesKey);
    final recentKey = _accountKey(_recentEmojisKey);
    final cloudUpdatedAtKey = _accountKey(_cloudUpdatedAtKey);
    if (installedKey == null ||
        favoriteKey == null ||
        recentKey == null ||
        cloudUpdatedAtKey == null) {
      return EmojiStoreData(
        installedPackIds: _defaultInstalledPackIds,
        favoriteCodes: const [],
        customEmojis: const [],
        recentEmojis: const [],
      );
    }
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) {
      return EmojiStoreData(
        installedPackIds: _defaultInstalledPackIds,
        favoriteCodes: const [],
        customEmojis: const [],
        recentEmojis: const [],
      );
    }

    final installedRaw = prefs.getStringList(installedKey) ?? const [];
    final installed = _withDefaultInstalledPackIds(
      _sanitizeInstalledPackIds(installedRaw),
    );
    if (!_sameStringList(installedRaw, installed)) {
      await prefs.setStringList(installedKey, installed);
    }

    final favoriteCodesRaw =
        prefs.getStringList(favoriteKey) ?? const <String>[];
    final favoriteCodes = _sanitizeFavoriteCodes(favoriteCodesRaw);

    final customEmojis = await loadCustomEmojis();
    final recent = prefs.getStringList(recentKey) ?? const [];
    final cloudUpdatedAt = _normalizeUpdatedAtString(
      prefs.getString(cloudUpdatedAtKey),
    );

    return EmojiStoreData(
      installedPackIds: installed,
      favoriteCodes: favoriteCodes,
      customEmojis: customEmojis,
      recentEmojis: recent,
      cloudUpdatedAt: cloudUpdatedAt,
    );
  }

  static Future<EmojiStoreData?> _fetchRemoteData() async {
    final generation = _generation;
    final accountId = _accountId;
    if (!_isCurrentAccount(generation, accountId)) return null;
    ApiClient? api;
    try {
      api = await _newAuthedApiClient();
      if (!_isCurrentAccount(generation, accountId)) return null;
      final resp = await api.get<Map<String, dynamic>>(
        '/user/emoji-store',
        fromJson: (data) => Map<String, dynamic>.from(data as Map),
      );
      if (!_isCurrentAccount(generation, accountId)) return null;
      if (!resp.isSuccess || resp.data == null) return null;
      final data = resp.data!;

      final installed = ((data['installed_pack_ids'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();

      final favoriteCodes = ((data['favorite_codes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();

      final custom = ((data['custom_emojis'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CustomEmojiItem.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.displayPath != null && e.displayPath!.isNotEmpty)
          .toList();
      final cloudUpdatedAt = _normalizeUpdatedAtString(data['updated_at']);

      final local = await _loadLocalOnly();
      if (!_isCurrentAccount(generation, accountId)) return null;
      final mergedCustom = _mergeCustomEmojis(local.customEmojis, custom);

      return EmojiStoreData(
        installedPackIds: _withDefaultInstalledPackIds(
          _sanitizeInstalledPackIds(installed),
        ),
        favoriteCodes: _sanitizeFavoriteCodes(favoriteCodes),
        customEmojis: mergedCustom,
        recentEmojis: local.recentEmojis,
        cloudUpdatedAt: cloudUpdatedAt ?? local.cloudUpdatedAt,
      );
    } catch (_) {
      return null;
    } finally {
      api?.dispose();
    }
  }

  static List<CustomEmojiItem> _mergeCustomEmojis(
    List<CustomEmojiItem> local,
    List<CustomEmojiItem> remote,
  ) {
    final byId = <String, CustomEmojiItem>{};
    for (final item in remote) {
      byId[item.id] = item;
    }
    for (final item in local) {
      final existing = byId[item.id];
      if (existing == null) {
        byId[item.id] = item;
      } else {
        byId[item.id] = CustomEmojiItem(
          id: existing.id,
          path: item.path.isNotEmpty ? item.path : existing.path,
          remoteUrl: item.remoteUrl ?? existing.remoteUrl,
          createdAt: existing.createdAt,
        );
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _sanitizeCustomEmojis(list);
  }

  static Future<void> _syncRemote({
    required List<String> installedPackIds,
    required List<String> favoriteCodes,
    required List<CustomEmojiItem> customEmojis,
  }) async {
    final generation = _generation;
    final accountId = _accountId;
    if (!_isCurrentAccount(generation, accountId)) return;
    final safeInstalled = _sanitizeInstalledPackIds(installedPackIds);
    final safeFavorites = _sanitizeFavoriteCodes(favoriteCodes);
    final safeCustom = _sanitizeCustomEmojis(customEmojis);
    ApiClient? api;
    try {
      api = await _newAuthedApiClient();
      if (!_isCurrentAccount(generation, accountId)) return;
      await _syncRemoteWithRetry(
        api,
        generation: generation,
        accountId: accountId,
        installedPackIds: safeInstalled,
        favoriteCodes: safeFavorites,
        customEmojis: safeCustom,
      );
    } catch (_) {
      // keep local data even if cloud sync fails
    } finally {
      api?.dispose();
    }
  }

  static Future<void> _syncRemoteWithRetry(
    ApiClient api, {
    required int generation,
    required String accountId,
    required List<String> installedPackIds,
    required List<String> favoriteCodes,
    required List<CustomEmojiItem> customEmojis,
    int attempt = 0,
  }) async {
    if (!_isCurrentAccount(generation, accountId)) return;
    final baseUpdatedAt = await _getCloudUpdatedAt();
    if (!_isCurrentAccount(generation, accountId)) return;
    final resp = await api.put<Map<String, dynamic>>(
      '/user/emoji-store',
      data: {
        'installed_pack_ids': installedPackIds,
        'favorite_codes': favoriteCodes,
        'custom_emojis': customEmojis.map((e) => e.toJson()).toList(),
        if (baseUpdatedAt != null && baseUpdatedAt.isNotEmpty)
          'base_updated_at': baseUpdatedAt,
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
    if (!_isCurrentAccount(generation, accountId)) return;

    if (resp.isSuccess) {
      final updatedAt = _normalizeUpdatedAtString(resp.data?['updated_at']);
      if (updatedAt != null) {
        await _setCloudUpdatedAt(updatedAt);
      }
      return;
    }

    if (resp.code != 409 || attempt >= 1) {
      return;
    }

    final remoteData = resp.data;
    if (remoteData == null) return;

    final remoteInstalled = ((remoteData['installed_pack_ids'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final remoteFavorites = ((remoteData['favorite_codes'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final remoteCustom = ((remoteData['custom_emojis'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => CustomEmojiItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.displayPath != null && e.displayPath!.isNotEmpty)
        .toList();

    final mergedInstalled = _mergeAndSanitizeStringList(
        remoteInstalled, installedPackIds,
        maxItems: _maxInstalledPacks, maxRunes: _maxPackIdRunes);
    final mergedFavorites = _mergeAndSanitizeStringList(
        remoteFavorites, favoriteCodes,
        maxItems: _maxFavoriteCodes,
        maxRunes: _maxFavoriteCodeRunes,
        allow: (v) =>
            v.startsWith(_emojiCodePrefix) || v.startsWith(_customCodePrefix));
    final mergedCustom = _mergeCustomEmojis(customEmojis, remoteCustom);

    final remoteUpdatedAt = _normalizeUpdatedAtString(remoteData['updated_at']);
    if (remoteUpdatedAt != null) {
      await _setCloudUpdatedAt(remoteUpdatedAt);
    }

    await _syncRemoteWithRetry(
      api,
      generation: generation,
      accountId: accountId,
      installedPackIds: mergedInstalled,
      favoriteCodes: mergedFavorites,
      customEmojis: mergedCustom,
      attempt: attempt + 1,
    );
  }

  static Future<void> _syncRemoteWithCurrentLocal() async {
    final local = await _loadLocalOnly();
    await _syncRemote(
      installedPackIds: local.installedPackIds,
      favoriteCodes: local.favoriteCodes,
      customEmojis: local.customEmojis,
    );
  }

  static Future<EmojiStoreData> loadAll() async {
    final generation = _generation;
    final accountId = _accountId;
    final local = await _loadLocalOnly();
    if (!_isCurrentAccount(generation, accountId)) return local;
    final remote = await _fetchRemoteData();
    if (remote == null || !_isCurrentAccount(generation, accountId)) {
      return local;
    }

    await setInstalledPackIds(remote.installedPackIds, syncRemote: false);
    await setFavoriteCodes(remote.favoriteCodes, syncRemote: false);
    await saveCustomEmojis(remote.customEmojis, syncRemote: false);
    if (remote.cloudUpdatedAt != null) {
      await _setCloudUpdatedAt(remote.cloudUpdatedAt!);
    }

    return remote;
  }

  static String favoriteCodeForEmoji(String emoji) => '$_emojiCodePrefix$emoji';

  static String favoriteCodeForCustom(String customId) =>
      '$_customCodePrefix$customId';

  static bool isEmojiFavoriteCode(String code) =>
      code.startsWith(_emojiCodePrefix);

  static bool isCustomFavoriteCode(String code) =>
      code.startsWith(_customCodePrefix);

  static String emojiFromFavoriteCode(String code) =>
      code.replaceFirst(_emojiCodePrefix, '');

  static String customIdFromFavoriteCode(String code) =>
      code.replaceFirst(_customCodePrefix, '');

  static Future<void> setInstalledPackIds(
    List<String> ids, {
    bool syncRemote = true,
  }) async {
    final key = _accountKey(_installedPacksKey);
    if (key == null) return;
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return;
    final valid = _sanitizeInstalledPackIds(ids);
    await prefs.setStringList(key, valid);
    if (syncRemote && _isCurrentAccount(generation, _accountId)) {
      await _syncRemoteWithCurrentLocal();
    }
  }

  static Future<void> addPack(String packId) async {
    final data = await loadAll();
    final next = [...data.installedPackIds];
    if (!next.contains(packId)) {
      next.add(packId);
    }
    await setInstalledPackIds(next);
  }

  static Future<void> removePack(String packId) async {
    final data = await loadAll();
    final next = [...data.installedPackIds]..remove(packId);
    await setInstalledPackIds(next);
  }

  static Future<void> setFavoriteCodes(
    List<String> favoriteCodes, {
    bool syncRemote = true,
  }) async {
    final key = _accountKey(_favoriteCodesKey);
    if (key == null) return;
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return;
    final next = _sanitizeFavoriteCodes(favoriteCodes);
    await prefs.setStringList(key, next);
    if (syncRemote && _isCurrentAccount(generation, _accountId)) {
      await _syncRemoteWithCurrentLocal();
    }
  }

  static Future<void> toggleFavoriteEmoji(String emoji) async {
    final data = await loadAll();
    final code = favoriteCodeForEmoji(emoji);
    final next = [...data.favoriteCodes];
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    await setFavoriteCodes(next);
  }

  static Future<void> toggleFavoriteCustom(String customId) async {
    final data = await loadAll();
    final code = favoriteCodeForCustom(customId);
    final next = [...data.favoriteCodes];
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    await setFavoriteCodes(next);
  }

  static Future<void> addRecentEmoji(String emoji) async {
    final key = _accountKey(_recentEmojisKey);
    if (key == null) return;
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return;
    final recent = prefs.getStringList(key) ?? [];
    recent.remove(emoji);
    recent.insert(0, emoji);
    if (recent.length > _maxRecent) {
      recent.removeRange(_maxRecent, recent.length);
    }
    await prefs.setStringList(key, recent);
  }

  static Future<void> setRecentEmojis(List<String> emojis) async {
    final key = _accountKey(_recentEmojisKey);
    if (key == null) return;
    final generation = _generation;
    final next = <String>[];
    for (final emoji in emojis) {
      if (emoji.isNotEmpty && !next.contains(emoji)) next.add(emoji);
      if (next.length >= _maxRecent) break;
    }
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return;
    await prefs.setStringList(key, next);
  }

  static Future<List<CustomEmojiItem>> loadCustomEmojis() async {
    final key = _accountKey(_customEmojisKey);
    if (key == null) return const [];
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return const [];
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => CustomEmojiItem.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.displayPath != null && e.displayPath!.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveCustomEmojis(
    List<CustomEmojiItem> items, {
    bool syncRemote = true,
  }) async {
    final key = _accountKey(_customEmojisKey);
    if (key == null) return;
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return;
    final safeItems = _sanitizeCustomEmojis(items);
    await prefs.setString(
      key,
      jsonEncode(safeItems.map((e) => e.toJson()).toList()),
    );
    if (syncRemote && _isCurrentAccount(generation, _accountId)) {
      await _syncRemoteWithCurrentLocal();
    }
  }

  static Future<String?> _uploadCustomEmojiAndGetUrl(String localPath) async {
    ApiClient? api;
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;

      final ext = localPath.contains('.')
          ? localPath.split('.').last.toLowerCase()
          : 'png';
      final fileName =
          'custom_emoji_${DateTime.now().millisecondsSinceEpoch}.$ext';

      api = await _newAuthedApiClient();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(localPath, filename: fileName),
      });
      final resp = await api.upload<Map<String, dynamic>>(
        '/upload/image',
        formData,
      );
      if (!resp.isSuccess || resp.data == null) return null;
      final url = (resp.data!['url'] ?? '').toString();
      if (url.isEmpty) return null;
      return ApiConfig.getMediaUrl(url);
    } catch (_) {
      return null;
    } finally {
      api?.dispose();
    }
  }

  static Future<CustomEmojiItem?> addCustomEmojiFromPath(
      String sourcePath) async {
    final generation = _generation;
    final accountId = _accountId;
    if (!_isCurrentAccount(generation, accountId)) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final sep = Platform.pathSeparator;
    final customDir = await ChatMediaCacheManager.accountPrivateDirectory(
      accountId,
      'custom_emojis',
    );

    final dotIndex = source.path.lastIndexOf('.');
    final ext = dotIndex > -1 ? source.path.substring(dotIndex) : '.png';
    final fileName =
        'emoji_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.png' : ext}';
    final targetPath = '${customDir.path}$sep$fileName';
    await source.copy(targetPath);

    final remoteUrl = await _uploadCustomEmojiAndGetUrl(targetPath);
    if (!_isCurrentAccount(generation, accountId)) return null;
    final item = CustomEmojiItem(
      id: const Uuid().v4(),
      path: targetPath,
      remoteUrl: remoteUrl,
      createdAt: DateTime.now(),
    );

    final current = await loadCustomEmojis();
    final next = [item, ...current];
    await saveCustomEmojis(next);
    return item;
  }

  static String _trimAndClampRunes(String value, int maxRunes) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final runes = trimmed.runes.toList(growable: false);
    if (runes.length <= maxRunes) return trimmed;
    return String.fromCharCodes(runes.take(maxRunes));
  }

  static List<String> _sanitizeInstalledPackIds(List<String> ids) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in ids) {
      final id = _trimAndClampRunes(raw, _maxPackIdRunes);
      if (id.isEmpty) continue;
      if (seen.add(id)) {
        out.add(id);
      }
      if (out.length >= _maxInstalledPacks) break;
    }
    return out;
  }

  static List<String> _withDefaultInstalledPackIds(List<String> ids) {
    final out = [...ids];
    for (final id in _defaultInstalledPackIds) {
      if (!out.contains(id)) {
        out.add(id);
      }
    }
    return _sanitizeInstalledPackIds(out);
  }

  static bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<String> _sanitizeFavoriteCodes(List<String> codes) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in codes) {
      final code = _trimAndClampRunes(raw, _maxFavoriteCodeRunes);
      if (code.isEmpty) continue;
      final valid = code.startsWith(_emojiCodePrefix) ||
          code.startsWith(_customCodePrefix);
      if (!valid) continue;
      if (seen.add(code)) {
        out.add(code);
      }
      if (out.length >= _maxFavoriteCodes) break;
    }
    return out;
  }

  static List<CustomEmojiItem> _sanitizeCustomEmojis(
    List<CustomEmojiItem> items,
  ) {
    final out = <CustomEmojiItem>[];
    final seenIDs = <String>{};
    for (final item in items) {
      final id = _trimAndClampRunes(item.id, _maxCustomIdRunes);
      if (id.isEmpty || !seenIDs.add(id)) continue;

      final path = _trimAndClampRunes(item.path, _maxCustomPathRunes);
      var remote = _trimAndClampRunes(
        item.remoteUrl ?? '',
        _maxCustomPathRunes,
      );
      if (remote.isNotEmpty && !isHttpUrl(remote)) {
        remote = '';
      }
      if (path.isEmpty && remote.isEmpty) continue;

      out.add(
        CustomEmojiItem(
          id: id,
          path: path.isNotEmpty ? path : remote,
          remoteUrl: remote.isEmpty ? null : remote,
          createdAt: item.createdAt,
        ),
      );

      if (out.length >= _maxCustomEmojis) break;
    }
    return out;
  }

  static String? _normalizeUpdatedAtString(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return parsed.toUtc().toIso8601String();
  }

  static Future<String?> _getCloudUpdatedAt() async {
    final key = _accountKey(_cloudUpdatedAtKey);
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return _normalizeUpdatedAtString(prefs.getString(key));
  }

  static Future<void> _setCloudUpdatedAt(String updatedAt) async {
    final normalized = _normalizeUpdatedAtString(updatedAt);
    if (normalized == null) return;
    final key = _accountKey(_cloudUpdatedAtKey);
    if (key == null) return;
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || _accountId.isEmpty) return;
    await prefs.setString(key, normalized);
  }

  static List<String> _mergeAndSanitizeStringList(
    List<String> preferred,
    List<String> fallback, {
    required int maxItems,
    required int maxRunes,
    bool Function(String v)? allow,
  }) {
    final merged = <String>[];
    final seen = <String>{};
    for (final raw in [...preferred, ...fallback]) {
      final value = _trimAndClampRunes(raw, maxRunes);
      if (value.isEmpty) continue;
      if (allow != null && !allow(value)) continue;
      if (seen.add(value)) {
        merged.add(value);
      }
      if (merged.length >= maxItems) break;
    }
    return merged;
  }

  static Future<List<StickerPack>> loadPackCatalog({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _catalogCache != null && _catalogCache!.isNotEmpty) {
      return _catalogCache!;
    }

    ApiClient? api;
    try {
      api = await _newAuthedApiClient();
      final resp = await api.get<Map<String, dynamic>>(
        '/user/emoji-store/catalog',
        fromJson: (data) => Map<String, dynamic>.from(data as Map),
      );
      if (!resp.isSuccess || resp.data == null) {
        _catalogCache = BuiltInStickerPacks.all;
        return _catalogCache!;
      }

      final list = ((resp.data!['list'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => _catalogPackFromJson(Map<String, dynamic>.from(e)))
          .whereType<StickerPack>()
          .toList();

      final safe = _sanitizeCatalogPacks(list);
      _catalogCache = _mergeBuiltInCatalog(safe);
      return _catalogCache!;
    } catch (_) {
      _catalogCache = BuiltInStickerPacks.all;
      return _catalogCache!;
    } finally {
      api?.dispose();
    }
  }

  static StickerPack? _catalogPackFromJson(Map<String, dynamic> json) {
    final id =
        _trimAndClampRunes((json['id'] ?? '').toString(), _maxPackIdRunes);
    final name = _trimAndClampRunes(
        (json['name'] ?? '').toString(), _maxCatalogNameRunes);
    final description = _trimAndClampRunes(
      (json['description'] ?? '').toString(),
      _maxCatalogDescRunes,
    );
    final previewEmoji =
        _trimAndClampRunes((json['preview_emoji'] ?? '').toString(), 16);
    var previewFile = _trimAndClampRunes(
      (json['preview_file'] ?? '').toString(),
      _maxCatalogFileRunes,
    );
    final files = ((json['sticker_files'] as List?) ?? const [])
        .map((e) => _trimAndClampRunes(e.toString(), _maxCatalogFileRunes))
        .where((e) => e.isNotEmpty)
        .toList();
    if (id.isEmpty || name.isEmpty || files.isEmpty) {
      return null;
    }
    if (previewFile.isEmpty) {
      previewFile = files.first;
    }
    return StickerPack(
      id: id,
      name: name,
      description: description,
      previewEmoji: previewEmoji,
      previewFile: previewFile,
      stickerFiles: files.take(_maxCatalogFiles).toList(growable: false),
      isBuiltIn: (json['is_built_in'] ?? false) == true,
    );
  }

  static List<StickerPack> _sanitizeCatalogPacks(List<StickerPack> packs) {
    final out = <StickerPack>[];
    final seen = <String>{};
    for (final p in packs) {
      final id = _trimAndClampRunes(p.id, _maxPackIdRunes);
      final name = _trimAndClampRunes(p.name, _maxCatalogNameRunes);
      final description =
          _trimAndClampRunes(p.description, _maxCatalogDescRunes);
      final previewEmoji = _trimAndClampRunes(p.previewEmoji, 16);
      var previewFile = _trimAndClampRunes(p.previewFile, _maxCatalogFileRunes);
      if (id.isEmpty || name.isEmpty || !seen.add(id)) continue;

      final files = p.stickerFiles
          .map((e) => _trimAndClampRunes(e, _maxCatalogFileRunes))
          .where((e) => e.isNotEmpty)
          .take(_maxCatalogFiles)
          .toList(growable: false);
      if (files.isEmpty) continue;
      if (previewFile.isEmpty) {
        previewFile = files.first;
      }

      out.add(
        StickerPack(
          id: id,
          name: name,
          description: description,
          previewEmoji: previewEmoji,
          previewFile: previewFile,
          stickerFiles: files,
          isBuiltIn: p.isBuiltIn,
        ),
      );
    }
    return out;
  }

  static List<StickerPack> _mergeBuiltInCatalog(List<StickerPack> remote) {
    final merged = <StickerPack>[];
    final seen = <String>{};
    for (final pack in [...remote, ...BuiltInStickerPacks.all]) {
      if (seen.add(pack.id)) {
        merged.add(pack);
      }
    }
    return merged;
  }

  static Future<void> deleteCustomEmojis(Set<String> ids) async {
    if (ids.isEmpty) return;

    final current = await loadCustomEmojis();
    final deleting = current.where((e) => ids.contains(e.id)).toList();
    final next = current.where((e) => !ids.contains(e.id)).toList();
    await saveCustomEmojis(next, syncRemote: false);

    for (final item in deleting) {
      if (!item.hasLocalPath) continue;
      final f = File(item.path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    final data = await _loadLocalOnly();
    final favoriteNext = data.favoriteCodes
        .where((code) =>
            !isCustomFavoriteCode(code) ||
            !ids.contains(customIdFromFavoriteCode(code)))
        .toList();
    await setFavoriteCodes(favoriteNext, syncRemote: false);
    await _syncRemoteWithCurrentLocal();
  }
}
