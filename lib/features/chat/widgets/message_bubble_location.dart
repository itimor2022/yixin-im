// 文件用途：提供 _MessageBubbleLocation 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleLocation，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble location 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleLocation on MessageBubble {
  Widget _buildLocationBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    final l10n = AppLocalizations.of(context);
    final latitude = message.locationLatitude;
    final longitude = message.locationLongitude;
    final title = message.locationTitle?.trim().isNotEmpty == true
        ? message.locationTitle!.trim()
        : message.content;
    final address = message.locationAddress?.trim();
    final coordinates = (latitude != null && longitude != null)
        ? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
        : '';

    // 流程逻辑：`openMap` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
    Future<void> openMap() async {
      if (latitude == null || longitude == null) return;
      final url = Uri.parse(
        'https://maps.google.com/?q=${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }

    String buildStaticMapUrl(double lat, double lng) {
      final latText = lat.toStringAsFixed(6);
      final lngText = lng.toStringAsFixed(6);
      return 'https://staticmap.openstreetmap.de/staticmap.php?center=$latText,$lngText&zoom=15&size=800x360&maptype=mapnik&markers=$latText,$lngText,red-pushpin';
    }

    return GestureDetector(
      onTap: (latitude != null && longitude != null) ? openMap : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: _getBubbleRadius(isOutgoing),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (latitude != null && longitude != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1.9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: buildStaticMapUrl(latitude, longitude),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: Colors.black.withOpacity(0.05),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.black.withOpacity(0.05),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 30,
                                color: AppColors.primaryFor(context),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                coordinates,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: textColor.withOpacity(0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.46),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _localizedText(
                                  context,
                                  zhCN: '地图位置',
                                  zhTW: '地圖位置',
                                  en: 'Map location',
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title.isNotEmpty ? title : l10n.get('location'),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (address != null && address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                address,
                style: AppTextStyles.bodySmall.copyWith(
                  color: textColor.withOpacity(0.75),
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ] else if (coordinates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                coordinates,
                style: AppTextStyles.bodySmall.copyWith(
                  color: textColor.withOpacity(0.75),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm')
                      .format(toCurrentLocalTime(message.createdAt)),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 3),
                  _buildStatusIcon(timeColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
