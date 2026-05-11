import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_colors.dart';
import 'in_app_browser.dart';

/// 链接预览卡片（Telegram 风格）
class LinkPreviewCard extends StatelessWidget {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final bool isOutgoing;
  final Color? bubbleColor;

  const LinkPreviewCard({
    super.key,
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.isOutgoing = false,
    this.bubbleColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final domain = _getDomain(url);
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final hasTitle = title != null && title!.isNotEmpty;
    final hasDescription = description != null && description!.isNotEmpty;
    
    // 颜色配置
    final cardColor = bubbleColor ?? (isOutgoing 
        ? (isDark ? AppColors.darkBubbleOutgoing : AppColors.lightBubbleOutgoing)
        : (isDark ? AppColors.darkBubbleIncoming : AppColors.lightBubbleIncoming));
    final accentColor = isOutgoing ? Colors.white.withOpacity(0.3) : AppColors.primary;
    final textColor = isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final subTextColor = isOutgoing ? Colors.white70 : (isDark ? Colors.white60 : Colors.black54);

    return GestureDetector(
      onTap: () => InAppBrowser.open(context, url),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图片预览
            if (hasImage)
              AspectRatio(
                aspectRatio: 1.91, // Open Graph 推荐比例
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 560,  // 280 * 2 考虑高 DPI
                  memCacheHeight: 294, // 147 * 2
                  placeholder: (_, __) => Container(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: isDark ? Colors.white38 : Colors.black26,
                      size: 40,
                    ),
                  ),
                ),
              ),
            // 内容区域
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧竖线
                  Container(
                    width: 3,
                    height: hasTitle || hasDescription ? 40 : 20,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 文字内容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 网站名称
                        Text(
                          siteName ?? domain,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // 标题
                        if (hasTitle) ...[
                          const SizedBox(height: 4),
                          Text(
                            title!,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // 描述
                        if (hasDescription) ...[
                          const SizedBox(height: 4),
                          Text(
                            description!,
                            style: TextStyle(
                              fontSize: 13,
                              color: subTextColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // 如果没有标题和描述，显示 URL
                        if (!hasTitle && !hasDescription) ...[
                          const SizedBox(height: 4),
                          Text(
                            url,
                            style: TextStyle(
                              fontSize: 13,
                              color: subTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return url;
    }
  }
}

/// 简单的链接预览卡片（不带图片，仅显示链接信息）
class SimpleLinkPreviewCard extends StatelessWidget {
  final String url;
  final bool isOutgoing;
  final Color? bubbleColor;

  const SimpleLinkPreviewCard({
    super.key,
    required this.url,
    this.isOutgoing = false,
    this.bubbleColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final domain = _getDomain(url);
    
    // 颜色配置
    final accentColor = isOutgoing ? Colors.white.withOpacity(0.5) : AppColors.primary;
    final textColor = isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final linkColor = isOutgoing ? Colors.white70 : Colors.blue;

    return GestureDetector(
      onTap: () => InAppBrowser.open(context, url),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 左侧竖线
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 10),
            // 内容
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 域名
                  Text(
                    domain,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 链接
                  Text(
                    url,
                    style: TextStyle(
                      fontSize: 14,
                      color: linkColor,
                      decoration: TextDecoration.underline,
                      decorationColor: linkColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return url;
    }
  }
}
