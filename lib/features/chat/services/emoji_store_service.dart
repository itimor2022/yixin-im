import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/api/api_client.dart';

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

  static const String _installedPacksKey = 'installed_sticker_packs';
  static const String _favoriteCodesKey = 'favorite_emoji_codes';
  static const String _customEmojisKey = 'custom_emoji_items';
  static const String _recentEmojisKey = 'recent_emojis';
  static const String _cloudUpdatedAtKey = 'emoji_store_cloud_updated_at';

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
  static const int _maxCatalogFiles = 500;

  static List<StickerPack>? _catalogCache;

  static bool isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  static Future<ApiClient> _newAuthedApiClient() async {
    final api = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      api.setToken(token);
    }
    return api;
  }

  static Future<EmojiStoreData> _loadLocalOnly() async {
    final prefs = await SharedPreferences.getInstance();

    final installedRaw = prefs.getStringList(_installedPacksKey) ?? const [];
    final installed = _sanitizeInstalledPackIds(installedRaw);

    final favoriteCodesRaw =
        prefs.getStringList(_favoriteCodesKey) ?? const <String>[];
    final favoriteCodes = _sanitizeFavoriteCodes(favoriteCodesRaw);

    final customEmojis = await loadCustomEmojis();
    final recent = prefs.getStringList(_recentEmojisKey) ?? const [];
    final cloudUpdatedAt = _normalizeUpdatedAtString(
      prefs.getString(_cloudUpdatedAtKey),
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
    ApiClient? api;
    try {
      api = await _newAuthedApiClient();
      final resp = await api.get<Map<String, dynamic>>(
        '/user/emoji-store',
        fromJson: (data) => Map<String, dynamic>.from(data as Map),
      );
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
      final mergedCustom = _mergeCustomEmojis(local.customEmojis, custom);

      return EmojiStoreData(
        installedPackIds: _sanitizeInstalledPackIds(installed),
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
    final safeInstalled = _sanitizeInstalledPackIds(installedPackIds);
    final safeFavorites = _sanitizeFavoriteCodes(favoriteCodes);
    final safeCustom = _sanitizeCustomEmojis(customEmojis);
    ApiClient? api;
    try {
      api = await _newAuthedApiClient();
      await _syncRemoteWithRetry(
        api,
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
    required List<String> installedPackIds,
    required List<String> favoriteCodes,
    required List<CustomEmojiItem> customEmojis,
    int attempt = 0,
  }) async {
    final baseUpdatedAt = await _getCloudUpdatedAt();
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
    final local = await _loadLocalOnly();
    final remote = await _fetchRemoteData();
    if (remote == null) return local;

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
    final prefs = await SharedPreferences.getInstance();
    final valid = _sanitizeInstalledPackIds(ids);
    await prefs.setStringList(_installedPacksKey, valid);
    if (syncRemote) {
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
    final prefs = await SharedPreferences.getInstance();
    final next = _sanitizeFavoriteCodes(favoriteCodes);
    await prefs.setStringList(_favoriteCodesKey, next);
    if (syncRemote) {
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
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentEmojisKey) ?? [];
    recent.remove(emoji);
    recent.insert(0, emoji);
    if (recent.length > _maxRecent) {
      recent.removeRange(_maxRecent, recent.length);
    }
    await prefs.setStringList(_recentEmojisKey, recent);
  }

  static Future<List<CustomEmojiItem>> loadCustomEmojis() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customEmojisKey);
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
    final prefs = await SharedPreferences.getInstance();
    final safeItems = _sanitizeCustomEmojis(items);
    await prefs.setString(
      _customEmojisKey,
      jsonEncode(safeItems.map((e) => e.toJson()).toList()),
    );
    if (syncRemote) {
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
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final docs = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final customDir = Directory('${docs.path}${sep}custom_emojis');
    if (!await customDir.exists()) {
      await customDir.create(recursive: true);
    }

    final dotIndex = source.path.lastIndexOf('.');
    final ext = dotIndex > -1 ? source.path.substring(dotIndex) : '.png';
    final fileName =
        'emoji_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.png' : ext}';
    final targetPath = '${customDir.path}$sep$fileName';
    await source.copy(targetPath);

    final remoteUrl = await _uploadCustomEmojiAndGetUrl(targetPath);
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
    final prefs = await SharedPreferences.getInstance();
    return _normalizeUpdatedAtString(prefs.getString(_cloudUpdatedAtKey));
  }

  static Future<void> _setCloudUpdatedAt(String updatedAt) async {
    final normalized = _normalizeUpdatedAtString(updatedAt);
    if (normalized == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudUpdatedAtKey, normalized);
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
      _catalogCache = safe.isEmpty ? BuiltInStickerPacks.all : safe;
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
