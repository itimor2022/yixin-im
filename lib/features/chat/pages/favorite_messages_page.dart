// 文件用途：实现 FavoriteMessagesPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 FavoriteMessagesPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../providers/message_provider.dart';
import '../services/favorite_message_service.dart';

String _favoriteText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：favorite messages page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class FavoriteMessagesPage extends StatefulWidget {
  const FavoriteMessagesPage({
    super.key,
    required this.accountKey,
    required this.favoriteService,
  });

  final String accountKey;
  final FavoriteMessageService favoriteService;

  @override
  State<FavoriteMessagesPage> createState() => _FavoriteMessagesPageState();
}

class _FavoriteMessagesPageState extends State<FavoriteMessagesPage> {
  bool _loading = true;
  List<FavoriteMessageEntry> _favorites = const [];

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final favorites =
        await widget.favoriteService.loadFavorites(widget.accountKey);
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _loading = false;
    });
  }

  Future<void> _removeFavorite(FavoriteMessageEntry item) async {
    try {
      await widget.favoriteService.removeFavorite(widget.accountKey, item);
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.warning(
        context,
        _favoriteText(
          context,
          zhCN: '取消收藏同步失败，请稍后重试',
          zhTW: '取消收藏同步失敗，請稍後重試',
          en: 'Failed to sync removal. Please retry.',
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _favorites = _favorites
          .where((entry) => entry.dedupeKey != item.dedupeKey)
          .toList();
    });
    AppSnackBar.success(
      context,
      _favoriteText(
        context,
        zhCN: '已移出收藏',
        zhTW: '已移出收藏',
        en: 'Removed from favorites',
      ),
    );
  }

  Future<void> _confirmRemoveFavorite(FavoriteMessageEntry item) async {
    final preview = item.previewText.trim();
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _favoriteText(
            dialogContext,
            zhCN: '删除收藏',
            zhTW: '刪除收藏',
            en: 'Delete Favorite',
          ),
        ),
        content: Text(
          preview.isNotEmpty
              ? '${_favoriteText(
                  dialogContext,
                  zhCN: '确定删除这条收藏吗？',
                  zhTW: '確定刪除這條收藏嗎？',
                  en: 'Delete this favorite?',
                )}\n\n$preview'
              : _favoriteText(
                  dialogContext,
                  zhCN: '确定删除这条收藏吗？',
                  zhTW: '確定刪除這條收藏嗎？',
                  en: 'Delete this favorite?',
                ),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _favoriteText(
                dialogContext,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _favoriteText(
                dialogContext,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldRemove == true) {
      await _removeFavorite(item);
    }
  }

  Future<void> _handleItemTap(FavoriteMessageEntry item) async {
    if (item.canOpenLocation) {
      final url = Uri.parse(
        'https://maps.google.com/?q=${item.locationLatitude!.toStringAsFixed(6)},${item.locationLongitude!.toStringAsFixed(6)}',
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }

    final text = item.previewText.trim();
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppSnackBar.success(
      context,
      _favoriteText(
        context,
        zhCN: '已复制收藏内容',
        zhTW: '已複製收藏內容',
        en: 'Favorite content copied',
      ),
    );
  }

  IconData _iconForType(MessageItemType type) {
    switch (type) {
      case MessageItemType.image:
        return Icons.image_outlined;
      case MessageItemType.video:
        return Icons.videocam_outlined;
      case MessageItemType.voice:
        return Icons.keyboard_voice_outlined;
      case MessageItemType.file:
        return Icons.insert_drive_file_outlined;
      case MessageItemType.location:
        return Icons.location_on_outlined;
      case MessageItemType.contact:
        return Icons.contact_page_outlined;
      case MessageItemType.redPacket:
        return Icons.redeem_outlined;
      case MessageItemType.transfer:
        return Icons.swap_horiz_rounded;
      case MessageItemType.forwardBundle:
        return Icons.library_books_outlined;
      case MessageItemType.call:
        return Icons.call_outlined;
      case MessageItemType.system:
        return Icons.info_outline_rounded;
      case MessageItemType.audio:
        return Icons.graphic_eq_outlined;
      case MessageItemType.sticker:
      case MessageItemType.gif:
        return Icons.emoji_emotions_outlined;
      case MessageItemType.poll:
        return Icons.poll_outlined;
      case MessageItemType.text:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  String _buildStaticMapUrl(double latitude, double longitude) {
    final lat = latitude.toStringAsFixed(6);
    final lng = longitude.toStringAsFixed(6);
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=15&size=800x360&maptype=mapnik&markers=$lat,$lng,red-pushpin';
  }

  Widget _buildLocationPreview(FavoriteMessageEntry item, bool isDark) {
    final latitude = item.locationLatitude;
    final longitude = item.locationLongitude;
    if (latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1.9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: _buildStaticMapUrl(latitude, longitude),
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: isDark
                      ? const Color(0xFF20242C)
                      : const Color(0xFFF3F5F8),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: isDark
                      ? const Color(0xFF20242C)
                      : const Color(0xFFF3F5F8),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 32,
                        color: AppColors.primaryFor(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryFor(context),
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
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 32,
                top: 13,
                child: Text(
                  _favoriteText(
                    context,
                    zhCN: '位置收藏',
                    zhTW: '位置收藏',
                    en: 'Saved Location',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_favoriteText(
            context,
            zhCN: '收藏',
            zhTW: '收藏',
            en: 'Favorites',
          )} (${_favorites.length})',
        ),
        actions: [
          IconButton(
            tooltip: _favoriteText(
              context,
              zhCN: '刷新',
              zhTW: '重新整理',
              en: 'Refresh',
            ),
            onPressed: _loadFavorites,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 52,
                        color: AppColors.textTertiaryFor(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _favoriteText(
                          context,
                          zhCN: '还没有收藏的消息',
                          zhTW: '還沒有收藏的訊息',
                          en: 'No saved messages yet',
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _favoriteText(
                          context,
                          zhCN: '长按消息后点击“收藏”即可保存',
                          zhTW: '長按訊息後點擊「收藏」即可保存',
                          en: 'Long press a message and tap "Favorite" to save it',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFavorites,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _favorites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _favorites[index];
                      return Dismissible(
                        key: ValueKey('${item.chatId}_${item.messageId}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) => _removeFavorite(item),
                        child: Material(
                          color: AppColors.cardFor(context),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _handleItemTap(item),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.canOpenLocation)
                                    _buildLocationPreview(item, isDark),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryWithOpacity(
                                            context,
                                            isDark ? 0.18 : 0.10,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _iconForType(item.type),
                                          color: AppColors.primaryFor(context),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item.chatName.isNotEmpty
                                                        ? item.chatName
                                                        : _favoriteText(
                                                            context,
                                                            zhCN: '未命名会话',
                                                            zhTW: '未命名會話',
                                                            en: 'Unnamed Chat',
                                                          ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isDark
                                                          ? AppColors
                                                              .darkTextPrimary
                                                          : Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  DateFormat(
                                                    'MM-dd HH:mm',
                                                  ).format(item.collectedAt),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? AppColors
                                                            .darkTextTertiary
                                                        : Colors.black38,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              item.senderName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? AppColors
                                                        .darkTextSecondary
                                                    : Colors.black54,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              item.previewText,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.4,
                                                color: isDark
                                                    ? AppColors.darkTextPrimary
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: _favoriteText(
                                          context,
                                          zhCN: '删除收藏',
                                          zhTW: '刪除收藏',
                                          en: 'Delete Favorite',
                                        ),
                                        onPressed: () =>
                                            _confirmRemoveFavorite(item),
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: isDark
                                              ? Colors.redAccent.shade100
                                              : AppColors.error,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: item.canOpenLocation
                                            ? _favoriteText(
                                                context,
                                                zhCN: '打开位置',
                                                zhTW: '打開位置',
                                                en: 'Open Location',
                                              )
                                            : _favoriteText(
                                                context,
                                                zhCN: '复制',
                                                zhTW: '複製',
                                                en: 'Copy',
                                              ),
                                        onPressed: () => _handleItemTap(item),
                                        icon: Icon(
                                          item.canOpenLocation
                                              ? Icons.map_outlined
                                              : Icons.copy_rounded,
                                          size: 20,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
