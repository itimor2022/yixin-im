// 文件用途：实现 OfficialAnnouncementPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 OfficialAnnouncementPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/message_provider.dart';

String _channelText(
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

// 关键声明：channel page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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
  ConsumerState<OfficialAnnouncementPage> createState() =>
      _OfficialAnnouncementPageState();
}

class _OfficialAnnouncementPageState
    extends ConsumerState<OfficialAnnouncementPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
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
                                !_isSameDay(message.createdAt,
                                    previousMessage.createdAt);

                            return Column(
                              children: [
                                if (showDateDivider)
                                  _buildDateDivider(message.createdAt, isDark),
                                _AnnouncementCard(
                                  message: message,
                                  isDark: isDark,
                                  onLongPress: () =>
                                      _showMessageOptions(message),
                                )
                                    .animate()
                                    .fadeIn(
                                        duration: 300.ms,
                                        delay: (index * 30).ms)
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
          color: AppColors.textPrimaryFor(context),
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
              color: AppColors.textPrimaryFor(context),
            ),
          ),
          const SizedBox(width: 4),
          // 官方认证标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryWithOpacity(context, 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _channelText(
                context,
                zhCN: '官方',
                zhTW: '官方',
                en: 'Official',
              ),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryFor(context),
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.info_outline_rounded,
            color: AppColors.textSecondaryFor(context),
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
                  AppColors.primaryFor(context),
                  AppColors.primaryWithOpacity(context, 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryWithOpacity(context, 0.3),
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
              color: AppColors.textPrimaryFor(context),
            ),
          ),
          const SizedBox(height: 8),

          // 描述
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _channelText(
                context,
                zhCN: '重要通知、版本更新、活动公告都会在这里发布，请注意查看',
                zhTW: '重要通知、版本更新、活動公告都會在這裡發布，請注意查看',
                en: 'Important notices, version updates, and event announcements will be posted here.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 提示标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: AppColors.textTertiaryFor(context),
                ),
                const SizedBox(width: 6),
                Text(
                  _channelText(
                    context,
                    zhCN: '系统消息 · 仅官方可发布',
                    zhTW: '系統消息 · 僅官方可發布',
                    en: 'System messages · Only official posts can be published',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiaryFor(context),
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
            color: AppColors.textTertiaryFor(context),
          ),
          const SizedBox(height: 16),
          Text(
            _channelText(
              context,
              zhCN: '暂无公告',
              zhTW: '暫無公告',
              en: 'No announcements yet',
            ),
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textTertiaryFor(context),
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
          Expanded(child: Divider(color: AppColors.dividerFor(context))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatDateDivider(context, date),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.dividerFor(context))),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateDivider(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (_isSameDay(messageDate, today)) {
      return _channelText(
        context,
        zhCN: '今天',
        zhTW: '今天',
        en: 'Today',
      );
    }
    if (_isSameDay(messageDate, yesterday)) {
      return _channelText(
        context,
        zhCN: '昨天',
        zhTW: '昨天',
        en: 'Yesterday',
      );
    }
    if (date.year == now.year) return '${date.month}/${date.day}';
    if (AppLocalizations.of(context).language == AppLanguage.en) {
      return DateFormat('yyyy/MM/dd').format(date);
    }
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
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppColors.dividerFor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Logo
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryFor(context),
                        AppColors.primaryWithOpacity(context, 0.7)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      size: 32, color: Colors.white),
                ),
                const SizedBox(height: 16),

                Text(
                  _channelText(
                    context,
                    zhCN: '关于官方公告',
                    zhTW: '關於官方公告',
                    en: 'About Official Announcements',
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  _channelText(
                    context,
                    zhCN:
                        '官方公告是系统级消息通道，用于发布重要通知、版本更新、活动信息等。\n\n此消息会自动出现在所有用户的聊天列表中，无法删除或退出。',
                    zhTW:
                        '官方公告是系統級消息通道，用於發布重要通知、版本更新、活動資訊等。\n\n此消息會自動出現在所有使用者的聊天列表中，無法刪除或退出。',
                    en: 'Official announcements are system-level messages used for important notices, version updates, and event information.\n\nThese messages automatically appear in every user chat list and cannot be deleted or left.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      backgroundColor: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.04),
                    ),
                    child: Text(
                      _channelText(
                        context,
                        zhCN: '我知道了',
                        zhTW: '我知道了',
                        en: 'OK',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.copy_rounded,
                    color: AppColors.textSecondaryFor(context)),
                title: Text(
                  _channelText(
                    context,
                    zhCN: '复制',
                    zhTW: '複製',
                    en: 'Copy',
                  ),
                  style: TextStyle(color: AppColors.textPrimaryFor(context)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _channelText(
                          context,
                          zhCN: '已复制',
                          zhTW: '已複製',
                          en: 'Copied',
                        ),
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.forward_rounded,
                    color: AppColors.textSecondaryFor(context)),
                title: Text(
                  _channelText(
                    context,
                    zhCN: '转发',
                    zhTW: '轉發',
                    en: 'Forward',
                  ),
                  style: TextStyle(color: AppColors.textPrimaryFor(context)),
                ),
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
                    color: isDark
                        ? const Color(0xFFE6EDF3)
                        : const Color(0xFF1F2328),
                  ),
                ),
              ),

            // 图片
            if (message.type == MessageItemType.image &&
                message.mediaUrl != null)
              ClipRRect(
                borderRadius: message.content.isEmpty
                    ? const BorderRadius.vertical(top: Radius.circular(13))
                    : BorderRadius.zero,
                child: CachedNetworkImage(
                  imageUrl: ChatMediaCacheManager.normalizeUrl(
                    message.mediaUrl,
                  ),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: 800,
                  maxWidthDiskCache: 800,
                  placeholder: (context, url) => Container(
                    height: 160,
                    color: isDark
                        ? const Color(0xFF30363D)
                        : const Color(0xFFF6F8FA),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 160,
                    color: isDark
                        ? const Color(0xFF30363D)
                        : const Color(0xFFF6F8FA),
                    child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey)),
                  ),
                ),
              ),

            // 底部
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.02)
                    : Colors.black.withOpacity(0.02),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(13)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: isDark
                        ? const Color(0xFF7D8590)
                        : const Color(0xFF656D76),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(context, message.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF7D8590)
                          : const Color(0xFF656D76),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: isDark
                        ? const Color(0xFF7D8590)
                        : const Color(0xFF656D76),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatViews(
                        context, (message.id.hashCode.abs() % 8000) + 2000),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF7D8590)
                          : const Color(0xFF656D76),
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

  String _formatTime(BuildContext context, DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return _channelText(
        context,
        zhCN: '刚刚',
        zhTW: '剛剛',
        en: 'Just now',
      );
    }
    if (diff.inMinutes < 60) {
      return _channelText(
        context,
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inHours < 24) {
      return _channelText(
        context,
        zhCN: '${diff.inHours}小时前',
        zhTW: '${diff.inHours}小時前',
        en: '${diff.inHours}h ago',
      );
    }
    if (diff.inDays < 7) {
      return _channelText(
        context,
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays}d ago',
      );
    }
    return DateFormat('MM/dd HH:mm').format(time);
  }

  String _formatViews(BuildContext context, int views) {
    final isEnglish = AppLocalizations.of(context).language == AppLanguage.en;
    if (views >= 10000) {
      return isEnglish
          ? '${(views / 1000).toStringAsFixed(1)}k'
          : '${(views / 10000).toStringAsFixed(1)}万';
    }
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
        width: 44,
        height: 44,
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
