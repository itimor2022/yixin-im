// 文件用途：提供 _AvatarPrefetchTask 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 _AvatarPrefetchTask，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/services/api/api_client.dart';
import '../../core/services/performance_trace_service.dart';
import '../../core/theme/app_colors.dart';

// 关键声明：avatar widget 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class _AvatarPrefetchTask {
  _AvatarPrefetchTask(this.url, this.completer);

  final String url;
  final Completer<void> completer;
}

class AvatarCacheManager {
  static const key = 'avatarCache';
  static const int _maxConcurrentPrefetch = 4;
  static const int _maxBatchPrefetch = 40;
  static final Queue<_AvatarPrefetchTask> _prefetchQueue =
      Queue<_AvatarPrefetchTask>();
  static final Set<String> _queuedUrls = <String>{};
  static int _activePrefetches = 0;

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );

  static Future<void> prefetch(String url) async {
    final full = ApiConfig.getMediaUrl(url);
    if (full.isEmpty || _queuedUrls.contains(full)) return;

    final completer = Completer<void>();
    _queuedUrls.add(full);
    _prefetchQueue.add(_AvatarPrefetchTask(full, completer));
    _pumpPrefetchQueue();
    return completer.future;
  }

  static void prefetchUrls(List<String> urls) {
    final valid = urls
        .map(ApiConfig.getMediaUrl)
        .where((u) => u.isNotEmpty)
        .toSet()
        .take(_maxBatchPrefetch)
        .toList();
    PerformanceTraceService.mark(
        'avatar_prefetch_queued count=${valid.length}');
    for (final url in valid) {
      prefetch(url);
    }
  }

  static void _pumpPrefetchQueue() {
    while (_activePrefetches < _maxConcurrentPrefetch &&
        _prefetchQueue.isNotEmpty) {
      final task = _prefetchQueue.removeFirst();
      _activePrefetches++;
      unawaited(_runPrefetchTask(task));
    }
  }

  static Future<void> _runPrefetchTask(_AvatarPrefetchTask task) async {
    try {
      await instance.getSingleFile(task.url);
      task.completer.complete();
    } catch (_) {
      task.completer.complete();
    } finally {
      _queuedUrls.remove(task.url);
      _activePrefetches--;
      _pumpPrefetchQueue();
    }
  }

  static Future<void> clearAll() async {
    await instance.emptyCache();
  }

  static Future<void> removeFile(String url) async {
    await instance.removeFile(ApiConfig.getMediaUrl(url));
  }
}

class AvatarWidget extends StatelessWidget {
  final String name;
  final String? avatar;
  final String? userId;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final double? borderRadius;
  final String? cacheKey;
  final bool isCircle;

  const AvatarWidget({
    super.key,
    required this.name,
    this.avatar,
    this.userId,
    this.size = 48,
    this.showBorder = false,
    this.borderColor,
    this.borderRadius,
    this.cacheKey,
    this.isCircle = false,
  });

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final resolvedAvatar = ApiConfig.getMediaUrl(avatar);
    final avatarColor = (avatar == null || avatar!.isEmpty)
        ? AppColors.defaultAvatarColor
        : AppColors.getAvatarColor(userId ?? name);
    final initial = name.isNotEmpty ? name.characters.first : '?';
    final effectiveBorderRadius = isCircle
        ? size / 2
        : math.min(borderRadius ?? size * 0.22, size * 0.28);
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 512)
        .toInt();

    final child = resolvedAvatar.isEmpty
        ? _buildPlaceholder(
            avatarColor,
            initial,
            effectiveBorderRadius,
            isCircle,
          )
        : _buildNetworkAvatar(
            resolvedAvatar: resolvedAvatar,
            initial: initial,
            avatarColor: avatarColor,
            borderRadius: effectiveBorderRadius,
            isCircle: isCircle,
            decodeSize: decodeSize,
          );

    return DecoratedBox(
      decoration: showBorder
          ? BoxDecoration(
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCircle
                  ? null
                  : BorderRadius.circular(effectiveBorderRadius),
              border: Border.all(
                color: borderColor ?? AppColors.primaryFor(context),
                width: 2,
              ),
            )
          : const BoxDecoration(),
      child: SizedBox(
        width: size,
        height: size,
        child: isCircle
            ? ClipOval(child: child)
            : ClipRRect(
                borderRadius: BorderRadius.circular(effectiveBorderRadius),
                child: child,
              ),
      ),
    );
  }

  Widget _buildNetworkAvatar({
    required String resolvedAvatar,
    required String initial,
    required Color avatarColor,
    required double borderRadius,
    required bool isCircle,
    required int decodeSize,
  }) {
    return CachedNetworkImage(
      imageUrl: resolvedAvatar,
      cacheManager: kIsWeb ? null : AvatarCacheManager.instance,
      cacheKey: cacheKey ?? resolvedAvatar,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      memCacheWidth: decodeSize,
      memCacheHeight: decodeSize,
      useOldImageOnUrlChange: true,
      imageBuilder: (context, imageProvider) => Container(
        decoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
          image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
        ),
      ),
      placeholder: (context, url) =>
          _buildLoadingPlaceholder(borderRadius, isCircle),
      errorWidget: (context, url, error) =>
          _buildPlaceholder(avatarColor, initial, borderRadius, isCircle),
    );
  }

  Widget _buildLoadingPlaceholder(double borderRadius, bool isCircle) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        color: const Color(0xFFE0E0E0),
      ),
    );
  }

  Widget _buildPlaceholder(
    Color color,
    String initial,
    double borderRadius,
    bool isCircle,
  ) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.8)],
        ),
      ),
      child: Center(
        child: Text(
          initial.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
