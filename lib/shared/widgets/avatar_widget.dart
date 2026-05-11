import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/premium_theme_tokens.dart';
import '../../core/services/api/api_client.dart';

/// 自定义缓存管理器 - 持久化缓存头像到本地，本地加载可秒开
class AvatarCacheManager {
  static const key = 'avatarCache';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30), // 缓存30天
      maxNrOfCacheObjects: 500,
    ),
  );

  /// 预取单个头像到本地，下次 AvatarWidget 加载即秒开
  static Future<void> prefetch(String url) async {
    final full = ApiConfig.getMediaUrl(url);
    if (full.isEmpty) return;
    try {
      await instance.getSingleFile(full);
    } catch (_) {}
  }

  /// 预取一批头像（如联系人列表），后台静默缓存，列表展示时秒加载
  static void prefetchUrls(List<String> urls) {
    final valid = urls
        .map(ApiConfig.getMediaUrl)
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    for (final url in valid) {
      prefetch(url);
    }
  }

  /// 清除所有头像缓存
  static Future<void> clearAll() async {
    await instance.emptyCache();
  }

  /// 清除指定URL的缓存
  static Future<void> removeFile(String url) async {
    await instance.removeFile(url);
  }
}

class AvatarWidget extends StatefulWidget {
  final String name;
  final String? avatar;
  final String? userId;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final double? borderRadius;
  final String? cacheKey;
  final String? premiumType;

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
    this.premiumType,
  });

  @override
  State<AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<AvatarWidget>
    with SingleTickerProviderStateMixin {
  File? _cachedFile;
  bool _cacheChecked = false;
  late final AnimationController _premiumController;

  String? _normalizePremiumType() {
    final type = widget.premiumType?.trim();
    if (type == null || type.isEmpty) return null;
    if (PremiumThemeTokens.isPremium(type)) return type;

    final normalized = type.toLowerCase();
    if (normalized.contains('year') || normalized.contains('annual')) {
      return 'yearly';
    }
    if (normalized.contains('quarter') || normalized.contains('season')) {
      return 'quarterly';
    }
    return null;
  }

  String get _resolvedAvatar => ApiConfig.getMediaUrl(widget.avatar);

  @override
  void initState() {
    super.initState();
    final normalizedPremiumType = _normalizePremiumType();
    _premiumController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            PremiumThemeTokens.isYearly(normalizedPremiumType) ? 2600 : 1700,
      ),
    );
    if (PremiumThemeTokens.isPremium(normalizedPremiumType)) {
      _premiumController.repeat(reverse: true);
    }
    if (widget.avatar != null && widget.avatar!.isNotEmpty) {
      _loadFromCache();
    }
  }

  @override
  void didUpdateWidget(AvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatar != widget.avatar ||
        oldWidget.cacheKey != widget.cacheKey) {
      setState(() {
        _cachedFile = null;
        _cacheChecked = false;
      });
      if (widget.avatar != null && widget.avatar!.isNotEmpty) {
        _loadFromCache();
      }
    }
    if (oldWidget.premiumType != widget.premiumType) {
      final normalizedPremiumType = _normalizePremiumType();
      _premiumController.duration = Duration(
        milliseconds:
            PremiumThemeTokens.isYearly(normalizedPremiumType) ? 2600 : 1700,
      );
      if (PremiumThemeTokens.isPremium(normalizedPremiumType)) {
        _premiumController
          ..reset()
          ..repeat(reverse: true);
      } else {
        _premiumController.stop();
      }
    }
  }

  Future<void> _loadFromCache() async {
    if (kIsWeb) {
      if (!mounted) return;
      // On web, we don't use file caching, but we still need to mark cache as checked
      // so that the widget proceeds to use CachedNetworkImage
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cacheChecked = true);
      });
      return;
    }

    try {
      final url = _resolvedAvatar;
      final key = widget.cacheKey ?? url;
      final file = await AvatarCacheManager.instance.getFileFromCache(key);
      if (!mounted) return;
      setState(() {
        _cachedFile = file?.file;
        _cacheChecked = true;
      });
    } catch (e) {
      debugPrint('[Avatar] cache lookup failed, fallback to network: $e');
      if (!mounted) return;
      setState(() {
        _cachedFile = null;
        _cacheChecked = true;
      });
    }
  }

  @override
  void dispose() {
    _premiumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedPremiumType = _normalizePremiumType();
    final avatarColor = (widget.avatar == null || widget.avatar!.isEmpty)
        ? AppColors.defaultAvatarColor
        : AppColors.getAvatarColor(widget.userId ?? widget.name);
    final initial = widget.name.isNotEmpty ? widget.name.characters.first : '?';
    final isRounded = widget.borderRadius != null;
    final size = widget.size;
    final isPremium = PremiumThemeTokens.isPremium(normalizedPremiumType);

    Widget child;

    if (widget.avatar == null || widget.avatar!.isEmpty) {
      child = _buildPlaceholder(avatarColor, initial);
    } else if (kIsWeb) {
      child = CachedNetworkImage(
        imageUrl: _resolvedAvatar,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholderFadeInDuration: Duration.zero,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        useOldImageOnUrlChange: false,
        imageBuilder: (context, imageProvider) => Container(
          decoration: BoxDecoration(
            shape: isRounded ? BoxShape.rectangle : BoxShape.circle,
            borderRadius:
                isRounded ? BorderRadius.circular(widget.borderRadius!) : null,
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
        ),
        placeholder: (context, url) => _buildLoadingPlaceholder(),
        errorWidget: (context, url, error) =>
            _buildPlaceholder(avatarColor, initial),
      );
    } else if (_cachedFile != null) {
      // 本地缓存命中：直接读文件，秒加载，不闪烁
      child = Image.file(
        _cachedFile!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        cacheWidth: (size * 2).toInt(),
        cacheHeight: (size * 2).toInt(),
      );
    } else if (_cacheChecked) {
      // 缓存未命中：走网络并写入本地缓存
      child = CachedNetworkImage(
        imageUrl: _resolvedAvatar,
        cacheManager: AvatarCacheManager.instance,
        cacheKey: widget.cacheKey ?? _resolvedAvatar,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholderFadeInDuration: Duration.zero,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        useOldImageOnUrlChange: false,
        imageBuilder: (context, imageProvider) => Container(
          decoration: BoxDecoration(
            shape: isRounded ? BoxShape.rectangle : BoxShape.circle,
            borderRadius:
                isRounded ? BorderRadius.circular(widget.borderRadius!) : null,
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
        ),
        placeholder: (context, url) => _buildLoadingPlaceholder(),
        errorWidget: (context, url, error) =>
            _buildPlaceholder(avatarColor, initial),
      );
    } else {
      child = _buildLoadingPlaceholder();
    }

    return AnimatedBuilder(
      animation: _premiumController,
      builder: (context, _) {
        final pulse = isPremium ? _premiumController.value : 0.0;
        final glowOpacity = PremiumThemeTokens.isYearly(normalizedPremiumType)
            ? 0.24 + (pulse * 0.18)
            : 0.18 + (pulse * 0.12);
        final glowBlur = PremiumThemeTokens.isYearly(normalizedPremiumType)
            ? 18 + (pulse * 10)
            : 14 + (pulse * 8);
        final badgeOffset = PremiumThemeTokens.isYearly(normalizedPremiumType)
            ? -(pulse * 1.2)
            : -(pulse * 1.8);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.all(isPremium ? 3 : 0),
          decoration: isPremium
              ? BoxDecoration(
                  shape: isRounded ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isRounded
                      ? BorderRadius.circular((widget.borderRadius ?? 0) + 4)
                      : null,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: PremiumThemeTokens.avatarRingGradient(
                      normalizedPremiumType,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: PremiumThemeTokens.glow(
                        normalizedPremiumType,
                      ).withValues(alpha: glowOpacity),
                      blurRadius: glowBlur,
                      spreadRadius:
                          PremiumThemeTokens.isYearly(normalizedPremiumType)
                              ? 1.2
                              : 0.4,
                    ),
                  ],
                )
              : widget.showBorder
                  ? BoxDecoration(
                      shape: isRounded ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isRounded
                          ? BorderRadius.circular(widget.borderRadius!)
                          : null,
                      border: Border.all(
                        color: widget.borderColor ?? AppColors.primary,
                        width: 2,
                      ),
                    )
                  : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: isRounded
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius!,
                        ),
                        child: child,
                      )
                    : ClipOval(child: child),
              ),
              if (isPremium)
                Positioned(
                  right: -2,
                  bottom: -2 + badgeOffset,
                  child: Transform.scale(
                    scale: PremiumThemeTokens.isYearly(normalizedPremiumType)
                        ? 1 + (pulse * 0.06)
                        : 1 + (pulse * 0.04),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: PremiumThemeTokens.accent(
                              normalizedPremiumType,
                            ).withValues(alpha: 0.28 + (pulse * 0.12)),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingPlaceholder() {
    final size = widget.size;
    final isRounded = widget.borderRadius != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isRounded ? BoxShape.rectangle : BoxShape.circle,
        borderRadius:
            isRounded ? BorderRadius.circular(widget.borderRadius!) : null,
        color: const Color(0xFFE0E0E0),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.4,
          height: size * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(Color color, String initial) {
    final size = widget.size;
    final isRounded = widget.borderRadius != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isRounded ? BoxShape.rectangle : BoxShape.circle,
        borderRadius:
            isRounded ? BorderRadius.circular(widget.borderRadius!) : null,
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
