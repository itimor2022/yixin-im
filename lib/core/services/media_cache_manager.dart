// 文件用途：封装 ChatMediaCacheManager 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：按稳定媒体键管理下载缓存，协调并发请求和失效时间，避免同一媒体重复下载或串用账号缓存。
import 'dart:async';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';

import 'api/api_client.dart';

// 关键声明：media cache manager 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 统一管理可重新下载的公共缓存和账号私有媒体目录。
///
/// 私有目录按账号摘要隔离；清理可下载缓存时不能误删草稿、待上传文件等不可恢复数据。
class ChatMediaCacheManager {
  static const key = 'chatMediaCache';

  static CacheManager instance = _ChatImageCacheManager();

  static String accountDigest(String accountId) {
    final normalized = accountId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  static Future<Directory> accountPrivateDirectory(
    String accountId,
    String category, {
    bool create = true,
  }) async {
    // 浏览器存储不暴露文件系统目录，Web 调用方必须使用自身缓存实现。
    if (kIsWeb) {
      throw UnsupportedError(
          'Account media directories are unavailable on web');
    }
    // 分类名进入磁盘路径前收敛字符集，账号标识则只以摘要出现，避免路径穿越和明文泄露。
    final safeCategory = category.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}account_media'
      '${Platform.pathSeparator}${accountDigest(accountId)}'
      '${Platform.pathSeparator}$safeCategory',
    );
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Copies an outgoing media file out of picker/cache temporary directories.
  ///
  /// The returned path lives in Application Support and is deliberately not
  /// included in [clearRedownloadableCache]. It remains available for message
  /// rendering and resend after the app is killed or iOS purges tmp/cache.
  static Future<String> persistOutgoingMedia({
    required String accountId,
    required String sourcePath,
    required String messageId,
    required String category,
  }) async {
    if (kIsWeb) return sourcePath;
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
          'Outgoing media source does not exist', sourcePath);
    }
    final directory = await accountPrivateDirectory(
      accountId,
      'outgoing_$category',
    );
    final file = await copyMediaIntoDirectory(
      source: source,
      directory: directory,
      stableName: messageId,
    );
    return file.path;
  }

  @visibleForTesting
  static Future<File> copyMediaIntoDirectory({
    required File source,
    required Directory directory,
    required String stableName,
  }) async {
    if (!await source.exists()) {
      throw FileSystemException(
        'Outgoing media source does not exist',
        source.path,
      );
    }
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final safeName =
        stableName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (safeName.isEmpty) {
      throw ArgumentError.value(stableName, 'stableName', 'must not be empty');
    }
    final sourceName =
        source.uri.pathSegments.isEmpty ? '' : source.uri.pathSegments.last;
    final dot = sourceName.lastIndexOf('.');
    final rawExtension = dot >= 0 ? sourceName.substring(dot + 1) : '';
    final safeExtension =
        rawExtension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    final suffix = safeExtension.isEmpty ? '' : '.$safeExtension';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$safeName$suffix',
    );
    if (source.absolute.path == destination.absolute.path) {
      return destination;
    }

    if (await destination.exists() &&
        await destination.length() == await source.length()) {
      return destination;
    }

    final temporary = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await source.copy(temporary.path);
      if (await destination.exists()) {
        await destination.delete();
      }
      return await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static Future<Directory> _accountPrivateRoot(
    String accountId, {
    bool create = false,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}account_media'
      '${Platform.pathSeparator}${accountDigest(accountId)}',
    );
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<int> directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;
    var bytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          bytes += await entity.length();
        } catch (_) {}
      }
    }
    return bytes;
  }

  static Future<({int files, int bytes})> inspectAccountPrivateData(
    String accountId,
  ) async {
    if (kIsWeb || accountId.trim().isEmpty) return (files: 0, bytes: 0);
    final root = await _accountPrivateRoot(accountId);
    if (!await root.exists()) return (files: 0, bytes: 0);
    var files = 0;
    var bytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files++;
        try {
          bytes += await entity.length();
        } catch (_) {}
      }
    }
    return (files: files, bytes: bytes);
  }

  static Future<int> clearRedownloadableCache(String accountId) async {
    // 只清理明确标记为可重新下载的目录；账号私有根目录由删除账号流程单独处理。
    var bytes = 0;
    try {
      await instance.emptyCache();
    } catch (_) {}
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}

    if (!kIsWeb) {
      for (final category in const ['downloads', 'desktop_downloads']) {
        final directory = await accountPrivateDirectory(
          accountId,
          category,
          create: false,
        );
        bytes += await directorySize(directory);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }

      // Files created by older desktop builds were all downloaded copies.
      final support = await getApplicationSupportDirectory();
      final legacyDesktop = Directory(
        '${support.path}${Platform.pathSeparator}media_cache',
      );
      bytes += await directorySize(legacyDesktop);
      if (await legacyDesktop.exists()) {
        await legacyDesktop.delete(recursive: true);
      }
    }

    imageCache.clear();
    imageCache.clearLiveImages();
    return bytes;
  }

  static Future<int> inspectRedownloadableCacheBytes(String accountId) async {
    if (kIsWeb || accountId.trim().isEmpty) return 0;
    var bytes = 0;
    for (final category in const ['downloads', 'desktop_downloads']) {
      final directory = await accountPrivateDirectory(
        accountId,
        category,
        create: false,
      );
      bytes += await directorySize(directory);
    }
    final support = await getApplicationSupportDirectory();
    bytes += await directorySize(
      Directory('${support.path}${Platform.pathSeparator}media_cache'),
    );
    return bytes;
  }

  static Future<int> deleteAccountPrivateData(String accountId) async {
    if (kIsWeb || accountId.trim().isEmpty) return 0;
    final root = await _accountPrivateRoot(accountId);
    final bytes = await directorySize(root);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    return bytes;
  }

  static bool isLocalPath(String? value) {
    if (value == null || value.isEmpty) return false;
    if (value.startsWith('http')) return false;
    if (value.startsWith('data:')) return false;
    return value.startsWith('/') && !value.startsWith('/uploads');
  }

  static String normalizeUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return '';
    if (isLocalPath(raw) || raw.startsWith('data:')) return raw;
    return ApiConfig.getMediaUrl(raw);
  }

  static void prefetchImage(String? value) {
    if (kIsWeb) return;
    final url = normalizeUrl(value);
    if (url.isEmpty || isLocalPath(url) || !url.startsWith('http')) return;
    try {
      CachedNetworkImageProvider(
        url,
        cacheManager: instance,
      ).resolve(const ImageConfiguration());
    } catch (_) {}
  }

  static void prefetchFile(String? value) {
    if (kIsWeb) return;
    final url = normalizeUrl(value);
    if (url.isEmpty || isLocalPath(url) || !url.startsWith('http')) return;
    unawaited(instance.downloadFile(url).then<void>((_) {}, onError: (_) {}));
  }
}

class _ChatImageCacheManager extends CacheManager with ImageCacheManager {
  _ChatImageCacheManager()
      : super(
          Config(
            ChatMediaCacheManager.key,
            stalePeriod: const Duration(days: 60),
            maxNrOfCacheObjects: 1200,
          ),
        );
}
