import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/message_provider.dart';

/// 官方公告页面 - 系统级只读消息
/// 强制出现在所有用户的聊天列表中，无法删除
class OfficialAnnouncementPage extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;
  final String? avatar;

  const OfficialAnnouncementPage({
    super.key,
    required this.channelId,
    required this.channelName,
    this.avatar,
  });

  @override
  ConsumerState<OfficialAnnouncementPage> createState() => _OfficialAnnouncementPageState();
}

class _OfficialAnnouncementPageState extends ConsumerState<OfficialAnnouncementPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(messageListProvider(widget.channelId).notifier).initialize();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final showButton = _scrollController.offset > 300;
    if (showButton != _showScrollToTop) {
      setState(() => _showScrollToTop = showButton);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      authServiceProvider.select((s) => s.user?.uuid ?? ''),
      (previous, next) {
        final p = previous ?? '';
        final n = next ?? '';
        if (p.isNotEmpty && n.isNotEmpty && p != n) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(messageListProvider(widget.channelId).notifier)
                .initialize();
          });
        }
      },
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messages = ref.watch(messageListProvider(widget.channelId));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 简洁顶部栏
              _buildAppBar(isDark),
              
              // 官方公告头部
              SliverToBoxAdapter(child: _buildHeader(isDark)),
              
              // 公告列表
              messages.isEmpty
                  ? SliverFillRemaining(child: _buildEmptyState(isDark))
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final reversedIndex = messages.length - 1 - index;
                            final message = messages[reversedIndex];
                            final previousMessage = reversedIndex > 0 
                                ? messages[reversedIndex - 1] 
                                : null;
                            
                            final showDateDivider = previousMessage == null ||
                                !_isSameDay(message.createdAt, previousMessage.createdAt);

                            return Column(
                              children: [
                                if (showDateDivider) _buildDateDivider(message.createdAt, isDark),
                                _AnnouncementCard(
                                  message: message,
                                  isDark: isDark,
                                  onLongPress: () => _showMessageOptions(message),
                                ).animate()
                                  .fadeIn(duration: 300.ms, delay: (index * 30).ms)
                                  .slideY(begin: 0.05, end: 0),
                              ],
                            );
                          },
                          childCount: messages.length,
                        ),
                      ),
                    ),
            ],
          ),
          
          // 回到顶部按钮
          if (_showScrollToTop)
            Positioned(
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: _ScrollToTopButton(onTap: _scrollToTop),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDark) {
    return SliverAppBar(
      floating: true,
      snap: true,
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded, 
          size: 20,
          color: isDark ? Colors.white : Colors.black87,
        ),
        onPressed: () => context.pop(),
      ),
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.channelName,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 4),
          // 官方认证标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '官方',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.info_outline_rounded,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          onPressed: () => _showAbout(context, isDark),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 官方 Logo
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.campaign_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          
          // 标题
          Text(
            widget.channelName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          
          // 描述
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '重要通知、版本更新、活动公告都会在这里发布，请注意查看',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 提示标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                const SizedBox(width: 6),
                Text(
                  '系统消息 · 仅官方可发布',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无公告',
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime date, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: isDark ? Colors.white10 : Colors.black12)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatDateDivider(date),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          Expanded(child: Divider(color: isDark ? Colors.white10 : Colors.black12)),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => 
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateDivider(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);
    
    if (messageDate == today) return '今天';
    if (messageDate == yesterday) return '昨天';
    if (date.year == now.year) return '${date.month}月${date.day}日';
    return '${date.year}年${date.month}月${date.day}日';
  }

  void _showAbout(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Logo
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.campaign_rounded, size: 32, color: Colors.white),
                ),
                const SizedBox(height: 16),
                
                Text(
                  '关于官方公告',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                
                Text(
                  '官方公告是系统级消息通道，用于发布重要通知、版本更新、活动信息等。\n\n此消息会自动出现在所有用户的聊天列表中，无法删除或退出。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                    ),
                    child: Text(
                      '我知道了',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(MessageItem message) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: isDark ? Colors.white70 : Colors.black54),
                title: Text('复制', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('已复制'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.forward_rounded, color: isDark ? Colors.white70 : Colors.black54),
                title: Text('转发', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 公告卡片
class _AnnouncementCard extends StatelessWidget {
  final MessageItem message;
  final bool isDark;
  final VoidCallback? onLongPress;

  const _AnnouncementCard({
    required this.message,
    required this.isDark,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF21262D) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8EAED),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 内容
            if (message.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
                  ),
                ),
              ),
            
            // 图片
            if (message.type == MessageItemType.image && message.mediaUrl != null)
              ClipRRect(
                borderRadius: message.content.isEmpty 
                    ? const BorderRadius.vertical(top: Radius.circular(13))
                    : BorderRadius.zero,
                child: CachedNetworkImage(
                  imageUrl: message.mediaUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: 800,
                  maxWidthDiskCache: 800,
                  placeholder: (context, url) => Container(
                    height: 160,
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFF6F8FA),
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 160,
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFF6F8FA),
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                  ),
                ),
              ),
            
            // 底部
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: isDark ? const Color(0xFF7D8590) : const Color(0xFF656D76),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF7D8590) : const Color(0xFF656D76),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: isDark ? const Color(0xFF7D8590) : const Color(0xFF656D76),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatViews((message.id.hashCode.abs() % 8000) + 2000),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF7D8590) : const Color(0xFF656D76),
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('MM/dd HH:mm').format(time);
  }

  String _formatViews(int views) {
    if (views >= 10000) return '${(views / 10000).toStringAsFixed(1)}万';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}k';
    return views.toString();
  }
}

/// 回到顶部按钮
class _ScrollToTopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollToTopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF21262D) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8EAED),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.keyboard_arrow_up_rounded,
          color: isDark ? const Color(0xFF7D8590) : const Color(0xFF656D76),
        ),
      ),
    ).animate().scale(duration: 200.ms);
  }
}

// 保留原有的 ChannelPage 别名以兼容路由
typedef ChannelPage = OfficialAnnouncementPage;
