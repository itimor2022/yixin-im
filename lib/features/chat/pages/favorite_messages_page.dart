import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../providers/message_provider.dart';
import '../services/favorite_message_service.dart';

class FavoriteMessagesPage extends StatefulWidget {
  const FavoriteMessagesPage({super.key, required this.accountKey});

  final String accountKey;

  @override
  State<FavoriteMessagesPage> createState() => _FavoriteMessagesPageState();
}

class _FavoriteMessagesPageState extends State<FavoriteMessagesPage> {
  final FavoriteMessageService _favoriteService = FavoriteMessageService();

  bool _loading = true;
  List<FavoriteMessageEntry> _favorites = const [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final favorites = await _favoriteService.loadFavorites(widget.accountKey);
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _loading = false;
    });
  }

  Future<void> _removeFavorite(FavoriteMessageEntry item) async {
    await _favoriteService.removeFavorite(widget.accountKey, item);
    if (!mounted) return;
    setState(() {
      _favorites = _favorites
          .where((entry) => entry.dedupeKey != item.dedupeKey)
          .toList();
    });
    AppSnackBar.success(context, '已移出收藏');
  }

  Future<void> _confirmRemoveFavorite(FavoriteMessageEntry item) async {
    final preview = item.previewText.trim();
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text(
          preview.isNotEmpty ? '确定删除这条收藏吗？\n\n$preview' : '确定删除这条收藏吗？',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
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
    AppSnackBar.success(context, '已复制收藏内容');
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
                      const Icon(
                        Icons.map_outlined,
                        size: 32,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
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
                      Text(
                        '位置收藏',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('收藏 (${_favorites.length})'),
        actions: [
          IconButton(
            tooltip: '刷新',
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
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '还没有收藏的消息',
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '长按消息后点击“收藏”即可保存',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
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
                          color:
                              isDark ? const Color(0xFF161A20) : Colors.white,
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
                                          color: AppColors.primary.withValues(
                                            alpha: isDark ? 0.18 : 0.10,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _iconForType(item.type),
                                          color: AppColors.primary,
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
                                                        : '未命名会话',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isDark
                                                          ? Colors.white
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
                                                        ? Colors.white38
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
                                                    ? Colors.white54
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
                                                    ? Colors.white70
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: '删除收藏',
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
                                            ? '打开位置'
                                            : '复制',
                                        onPressed: () => _handleItemTap(item),
                                        icon: Icon(
                                          item.canOpenLocation
                                              ? Icons.map_outlined
                                              : Icons.copy_rounded,
                                          size: 20,
                                          color: isDark
                                              ? Colors.white54
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
