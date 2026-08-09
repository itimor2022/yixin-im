// 文件用途：实现 MomentsPage 页面及其交互流程，属于朋友圈动态。
// 核心逻辑：维护 MomentsPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:lottie/lottie.dart';
import '../../../shared/widgets/web_safe_lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/upload_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../../../shared/widgets/animated_emoji_text.dart';
import '../../chat/widgets/emoji_picker.dart';
import '../providers/moment_provider.dart';

String _momentsText(
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

String _momentsServerMessage(
  String? raw, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  return localizeServerMessage(
    raw,
    fallbackZhCN: zhCN,
    fallbackZhTW: zhTW,
    fallbackEn: en,
  );
}

List<String> _momentReportReasons(BuildContext context) {
  return [
    _momentsText(
      context,
      zhCN: '垃圾广告',
      zhTW: '垃圾廣告',
      en: 'Spam or Ads',
    ),
    _momentsText(
      context,
      zhCN: '色情低俗',
      zhTW: '色情低俗',
      en: 'Explicit or Inappropriate',
    ),
    _momentsText(
      context,
      zhCN: '政治敏感',
      zhTW: '政治敏感',
      en: 'Sensitive Political Content',
    ),
    _momentsText(
      context,
      zhCN: '违法信息',
      zhTW: '違法資訊',
      en: 'Illegal Content',
    ),
    _momentsText(
      context,
      zhCN: '人身攻击',
      zhTW: '人身攻擊',
      en: 'Harassment or Abuse',
    ),
    _momentsText(
      context,
      zhCN: '其他',
      zhTW: '其他',
      en: 'Other',
    ),
  ];
}

String _momentRelativeTime(BuildContext context, String dateStr) {
  if (dateStr.isEmpty) return '';
  try {
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return _momentsText(context, zhCN: '刚刚', zhTW: '剛剛', en: 'Just now');
    }
    if (diff.inMinutes < 60) {
      return _momentsText(
        context,
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inHours < 24) {
      return _momentsText(
        context,
        zhCN: '${diff.inHours}小时前',
        zhTW: '${diff.inHours}小時前',
        en: '${diff.inHours}h ago',
      );
    }
    if (diff.inDays < 7) {
      return _momentsText(
        context,
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays}d ago',
      );
    }
    return '${date.month}-${date.day}';
  } catch (_) {
    return dateStr;
  }
}

List<String> _defaultMomentSearchKeywords(BuildContext context) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return ['Tech', 'Life', 'Music', 'Travel', 'Food', 'Photo'];
    case AppLanguage.zhTW:
      return ['科技', '生活', '音樂', '旅行', '美食', '攝影'];
    case AppLanguage.zhCN:
      return ['科技', '生活', '音乐', '旅行', '美食', '摄影'];
  }
}

// 关键声明：moments page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 动态广场 - 公共社交动态
class MomentsPage extends ConsumerStatefulWidget {
  /// 是否作为桌面端侧边栏使用
  final bool isDesktopSidebar;
  final bool isSecondaryPage;

  const MomentsPage({
    super.key,
    this.isDesktopSidebar = false,
    this.isSecondaryPage = false,
  });

  @override
  ConsumerState<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends ConsumerState<MomentsPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  int _notificationCount = 0;
  DateTime? _lastReadTime;
  bool _isLoadingMore = false; // 防止重复加载

  @override
  bool get wantKeepAlive => true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    // 添加滚动监听实现分页加载
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated) {
        ref.read(momentProvider.notifier).initialize();
        _loadLastReadTime().then((_) => _loadNotificationCount());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听 - 触发加载更多（带防抖）
  void _onScroll() {
    // NestedScrollView 使用 outerController
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 500) {
      // 距离底部 500px 时触发加载更多
      // 页面标记防止滚动监听重复派发；Provider 仍负责分页状态和接口级防重入。
      if (_isLoadingMore) return;
      final momentState = ref.read(momentProvider);
      if (momentState.isLoadingMore || !momentState.hasMore) return;

      _isLoadingMore = true;
      ref.read(momentProvider.notifier).loadMoreMoments().then((_) {
        _isLoadingMore = false;
      });
    }
  }

  /// 加载上次查看通知的时间
  Future<void> _loadLastReadTime() async {
    try {
      final accountId = ref.read(currentAccountIdProvider);
      if (accountId.isEmpty) return;
      // 账号 ID 先哈希再进入本地键名，既隔离多账号已读时间，也避免明文落盘。
      final key =
          'acct_v1_${sha256.convert(utf8.encode(accountId))}_moment_notification_last_read';
      final prefs = await SharedPreferences.getInstance();
      // 获取 SharedPreferences 期间可能已经切号，旧账号结果不能写入当前页面状态。
      if (ref.read(currentAccountIdProvider) != accountId) return;
      final timestamp = prefs.getInt(key);
      if (timestamp != null) {
        _lastReadTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      debugPrint('加载上次查看时间失败: $e');
    }
  }

  /// 保存当前时间为上次查看时间
  Future<void> _markNotificationsAsRead() async {
    try {
      final accountId = ref.read(currentAccountIdProvider);
      if (accountId.isEmpty) return;
      final key =
          'acct_v1_${sha256.convert(utf8.encode(accountId))}_moment_notification_last_read';
      final prefs = await SharedPreferences.getInstance();
      // 异步返回后再次核对账号，防止切号竞态污染另一个账号的已读游标。
      if (ref.read(currentAccountIdProvider) != accountId) return;
      await prefs.setInt(
        key,
        DateTime.now().millisecondsSinceEpoch,
      );
      _lastReadTime = DateTime.now();
    } catch (e) {
      debugPrint('保存查看时间失败: $e');
    }
  }

  Future<bool> _canPublishMoment() async {
    try {
      final settings = await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true);
      return settings.enableMomentPost;
    } catch (e) {
      debugPrint('[Moments] Load settings failed: $e');
      return true;
    }
  }

  Future<void> _loadNotificationCount() async {
    try {
      final api = ref.read(apiClientProvider);
      // 获取收到的评论数量
      final commentsRes = await api.get(
        '/moment/my/comments',
        queryParameters: {'type': 'all'},
      );
      final comments = commentsRes.isSuccess
          ? (commentsRes.data?['list'] as List? ?? [])
          : [];
      // 获取收到的点赞数量
      final likesRes = await api.get('/moment/my/received-likes');
      final likes =
          likesRes.isSuccess ? (likesRes.data?['list'] as List? ?? []) : [];

      // 计算未读数量（新于上次查看时间的通知）
      int unreadCount = 0;
      if (_lastReadTime != null) {
        for (final item in comments) {
          final createdAt = DateTime.tryParse(item['created_at'] ?? '');
          if (createdAt != null && createdAt.isAfter(_lastReadTime!)) {
            unreadCount++;
          }
        }
        for (final item in likes) {
          final createdAt = DateTime.tryParse(item['created_at'] ?? '');
          if (createdAt != null && createdAt.isAfter(_lastReadTime!)) {
            unreadCount++;
          }
        }
      } else {
        // 如果从未查看过，所有通知都是未读
        unreadCount = comments.length + likes.length;
      }

      if (mounted) {
        setState(() {
          _notificationCount = unreadCount;
        });
      }
    } catch (e) {
      debugPrint('加载通知数量失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 使用 select 只监听需要的字段，避免不必要的重建
    final moments = ref.watch(momentProvider.select((s) => s.moments));
    final isLoading = ref.watch(momentProvider.select((s) => s.isLoading));

    final topPadding = MediaQuery.of(context).padding.top;
    final floatingBottomSpace = FloatingNavLayout.isEnabledForContext(context)
        ? FloatingNavLayout.reservedSpace(context, extra: 8)
        : 100.0;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: Stack(
        children: [
          // 主内容区 - 带顶部偏移
          RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              await ref.read(momentProvider.notifier).refresh();
            },
            edgeOffset: topPadding + 70, // 头部高度
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 顶部占位（头部高度）
                SliverToBoxAdapter(child: SizedBox(height: topPadding + 70)),

                // 无动态时显示「暂无动态」
                if (moments.isEmpty && !isLoading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 64,
                            color: AppColors.textTertiaryFor(context),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _momentsText(
                              context,
                              zhCN: '暂无动态',
                              zhTW: '暫無動態',
                              en: 'No moments yet',
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // 动态列表 - 瀑布流布局（小红书风格）
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    sliver: SliverMasonryGrid.count(
                      // 桌面端侧边栏较窄，保持2列
                      crossAxisCount: widget.isDesktopSidebar ? 2 : 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childCount: moments.length,
                      itemBuilder: (context, index) {
                        final moment = moments[index];
                        // 使用 RepaintBoundary + key 优化滚动性能
                        return RepaintBoundary(
                          key: ValueKey(moment.id),
                          child: _WaterfallMomentCard(
                            moment: moment,
                            isDark: isDark,
                            onLike: () => ref
                                .read(momentProvider.notifier)
                                .toggleLike(moment.id),
                            onTap: () => _openMomentDetail(moment),
                            onLongPress: (details, ctx) => _showCardPopupMenu(
                              ctx,
                              details.globalPosition,
                              moment,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // 加载更多指示器 - 使用 Consumer 独立监听状态，避免整个列表重建
                SliverToBoxAdapter(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final isLoadingMore = ref.watch(
                        momentProvider.select((s) => s.isLoadingMore),
                      );
                      final hasMore = ref.watch(
                        momentProvider.select((s) => s.hasMore),
                      );
                      final hasMoments = ref.watch(
                        momentProvider.select((s) => s.moments.isNotEmpty),
                      );
                      return _buildLoadMoreIndicator(
                        isLoadingMore,
                        hasMore,
                        hasMoments,
                        isDark,
                      );
                    },
                  ),
                ),

                // 底部安全区域
                SliverToBoxAdapter(
                  child: SizedBox(height: floatingBottomSpace),
                ),
              ],
            ),
          ),

          // 固定头部栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color:
                  isDark ? AppColors.darkBackground : AppColors.lightBackground,
              child: _buildTopBar(isDark, l10n),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建加载更多指示器
  Widget _buildLoadMoreIndicator(
    bool isLoadingMore,
    bool hasMore,
    bool hasMoments,
    bool isDark,
  ) {
    if (isLoadingMore) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.textSecondaryFor(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _momentsText(
                  context,
                  zhCN: '加载中...',
                  zhTW: '載入中...',
                  en: 'Loading...',
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!hasMore && hasMoments) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            _momentsText(
              context,
              zhCN: '— 已加载全部动态 —',
              zhTW: '— 已載入全部動態 —',
              en: '— All moments loaded —',
            ),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTopBar(bool isDark, AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: widget.isSecondaryPage ? 8 : 20,
        right: 20,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.isSecondaryPage) ...[
            IconButton(
              onPressed: () => context.pop(),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(width: 4),
          ],
          // 大标题
          Text(
            l10n.tabSquare,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const Spacer(),
          // 发布按钮
          GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              final canPublish = await _canPublishMoment();
              if (!mounted) return;
              if (!canPublish) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _momentsText(
                        context,
                        zhCN: '广场发布功能已关闭，仅支持浏览',
                        zhTW: '廣場發佈功能已關閉，僅支援瀏覽',
                        en: 'Posting is disabled. Browse only.',
                      ),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (widget.isDesktopSidebar) {
                // 桌面端：在右侧面板显示发布页
                ref.read(desktopProfileProvider.notifier).state =
                    const DesktopProfileInfo(
                  type: DesktopPanelType.momentPublish,
                  id: 'publish',
                );
              } else {
                _showPublishSheet(context, isDark);
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryFor(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 24,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 通知按钮（我的动态、点赞、评论）
          GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              // 标记通知为已读
              await _markNotificationsAsRead();
              setState(() => _notificationCount = 0);

              if (!mounted) return;

              if (widget.isDesktopSidebar) {
                // 桌面端：在右侧面板显示通知页
                ref.read(desktopProfileProvider.notifier).state =
                    const DesktopProfileInfo(
                  type: DesktopPanelType.momentNotifications,
                  id: 'notifications',
                );
              } else {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        MomentNotificationsPage(isDark: isDark),
                  ),
                );
                // 返回后重新加载未读数量
                _loadNotificationCount();
              }
            },
            child: Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkControlBackgroundStrong
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    size: 22,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                // 小红点
                if (_notificationCount > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBackground
                              : AppColors.lightBackground,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 搜索按钮
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              if (widget.isDesktopSidebar) {
                // 桌面端：在右侧面板显示搜索页
                ref.read(desktopProfileProvider.notifier).state =
                    const DesktopProfileInfo(
                  type: DesktopPanelType.momentSearch,
                  id: 'search',
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => MomentSearchPage(isDark: isDark),
                  ),
                );
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkControlBackgroundStrong
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.search_rounded,
                size: 22,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotTopics(List<Topic> topics, bool isDark) {
    if (topics.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        border: Border(
          bottom: BorderSide(
            color: AppColors.dividerFor(context),
            width: 0.5,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: topics.length,
        itemBuilder: (context, index) {
          final topic = topics[index];

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _showTopicDetail(topic);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${topic.name}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  if (topic.isHot) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _momentsText(
                          context,
                          zhCN: '热',
                          zhTW: '熱',
                          en: 'Hot',
                        ),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showTopicDetail(Topic topic) {
    // 按话题名筛选动态列表
    ref.read(momentProvider.notifier).loadMomentsByTopic(topic.name);

    // 滚动到顶部
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _momentsText(
            context,
            zhCN: '已筛选话题 #${topic.name}，下拉刷新可恢复全部',
            zhTW: '已篩選話題 #${topic.name}，下拉重新整理可恢復全部',
            en: 'Filtered by #${topic.name}. Pull to refresh to restore all.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: _momentsText(
            context,
            zhCN: '清除筛选',
            zhTW: '清除篩選',
            en: 'Clear',
          ),
          onPressed: () => ref.read(momentProvider.notifier).clearTopicFilter(),
        ),
      ),
    );
  }

  void _openMomentDetail(Moment moment) {
    HapticFeedback.selectionClick();

    // 桌面端：在右侧面板显示
    if (widget.isDesktopSidebar) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
        type: DesktopPanelType.momentDetail,
        id: moment.id,
        momentData: moment,
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      // 使用 iOS 风格路由，支持左滑返回
      createPageRoute(builder: (context) => MomentDetailPage(moment: moment)),
    );
  }

  /// 在卡片上方显示毛玻璃悬浮菜单
  void _showCardPopupMenu(
    BuildContext cardContext,
    Offset globalPosition,
    Moment moment,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = ref.read(authServiceProvider).user?.id?.toString();
    final isMyMoment = currentUserId != null && currentUserId == moment.userId;
    final screenSize = MediaQuery.of(context).size;

    // 计算菜单位置，确保不超出屏幕
    double left = globalPosition.dx - 80; // 居中偏移
    double top = globalPosition.dy;

    // 边界检查
    if (left < 16) left = 16;
    if (left + 180 > screenSize.width - 16) left = screenSize.width - 196;
    if (top + 200 > screenSize.height - 100) top = globalPosition.dy - 160;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            // 点击空白关闭
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.transparent),
              ),
            ),
            // 毛玻璃菜单
            Positioned(
              left: left,
              top: top,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: animation,
                  child: _GlassPopupMenu(
                    isDark: isDark,
                    isMyMoment: isMyMoment,
                    onAction: (action) {
                      Navigator.pop(context);
                      _handleMenuAction(action, moment);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleMenuAction(String action, Moment moment) async {
    switch (action) {
      case 'private':
        final success =
            await ref.read(momentProvider.notifier).setPrivate(moment.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? _momentsText(
                        context,
                        zhCN: '已设为私密',
                        zhTW: '已設為私密',
                        en: 'Set to private',
                      )
                    : _momentsText(
                        context,
                        zhCN: '操作失败',
                        zhTW: '操作失敗',
                        en: 'Operation failed',
                      ),
              ),
            ),
          );
        }
        break;
      case 'delete':
        _confirmDeleteMoment(moment);
        break;
      case 'hide':
        final success =
            await ref.read(momentProvider.notifier).blockMoment(moment.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? _momentsText(
                        context,
                        zhCN: '已屏蔽该动态',
                        zhTW: '已封鎖此動態',
                        en: 'Blocked this moment',
                      )
                    : _momentsText(
                        context,
                        zhCN: '操作失败',
                        zhTW: '操作失敗',
                        en: 'Operation failed',
                      ),
              ),
            ),
          );
        }
        break;
      case 'block':
        final success =
            await ref.read(momentProvider.notifier).blockUser(moment.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? _momentsText(
                        context,
                        zhCN: '已屏蔽 ${moment.userName} 的动态',
                        zhTW: '已封鎖 ${moment.userName} 的動態',
                        en: 'Blocked ${moment.userName}\'s moments',
                      )
                    : _momentsText(
                        context,
                        zhCN: '操作失败',
                        zhTW: '操作失敗',
                        en: 'Operation failed',
                      ),
              ),
            ),
          );
        }
        break;
      case 'report':
        _showReportDialog(moment);
        break;
    }
  }

  void _showReportDialog(Moment moment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardFor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _momentsText(
            context,
            zhCN: '举报动态',
            zhTW: '檢舉動態',
            en: 'Report Moment',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReportOption(
              title: _momentsText(
                context,
                zhCN: '色情低俗',
                zhTW: '色情低俗',
                en: 'Explicit or Inappropriate',
              ),
              isDark: isDark,
              onTap: () => _submitReport(
                moment,
                _momentsText(
                  context,
                  zhCN: '色情低俗',
                  zhTW: '色情低俗',
                  en: 'Explicit or Inappropriate',
                ),
              ),
            ),
            _ReportOption(
              title: _momentsText(
                context,
                zhCN: '违法违规',
                zhTW: '違法違規',
                en: 'Illegal or Violating Rules',
              ),
              isDark: isDark,
              onTap: () => _submitReport(
                moment,
                _momentsText(
                  context,
                  zhCN: '违法违规',
                  zhTW: '違法違規',
                  en: 'Illegal or Violating Rules',
                ),
              ),
            ),
            _ReportOption(
              title: _momentsText(
                context,
                zhCN: '诈骗信息',
                zhTW: '詐騙資訊',
                en: 'Scam or Fraud',
              ),
              isDark: isDark,
              onTap: () => _submitReport(
                moment,
                _momentsText(
                  context,
                  zhCN: '诈骗信息',
                  zhTW: '詐騙資訊',
                  en: 'Scam or Fraud',
                ),
              ),
            ),
            _ReportOption(
              title: _momentsText(
                context,
                zhCN: '人身攻击',
                zhTW: '人身攻擊',
                en: 'Harassment or Abuse',
              ),
              isDark: isDark,
              onTap: () => _submitReport(
                moment,
                _momentsText(
                  context,
                  zhCN: '人身攻击',
                  zhTW: '人身攻擊',
                  en: 'Harassment or Abuse',
                ),
              ),
            ),
            _ReportOption(
              title: _momentsText(
                context,
                zhCN: '其他',
                zhTW: '其他',
                en: 'Other',
              ),
              isDark: isDark,
              onTap: () => _submitReport(
                moment,
                _momentsText(
                  context,
                  zhCN: '其他',
                  zhTW: '其他',
                  en: 'Other',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
        ],
      ),
    );
  }

  void _submitReport(Moment moment, String reason) {
    Navigator.pop(context);
    // 举报后屏蔽该动态
    ref.read(momentProvider.notifier).blockMoment(moment.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _momentsText(
            context,
            zhCN: '举报已提交，感谢您的反馈',
            zhTW: '檢舉已提交，感謝您的回饋',
            en: 'Report submitted. Thanks for your feedback.',
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMoment(Moment moment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardFor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _momentsText(
            context,
            zhCN: '确认删除',
            zhTW: '確認刪除',
            en: 'Delete Moment',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Text(
          _momentsText(
            context,
            zhCN: '删除后将无法恢复，确定要删除这条动态吗？',
            zhTW: '刪除後將無法恢復，確定要刪除此動態嗎？',
            en: 'This cannot be undone. Delete this moment?',
          ),
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(momentProvider.notifier).deleteMoment(moment.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _momentsText(
                      context,
                      zhCN: '动态已删除',
                      zhTW: '動態已刪除',
                      en: 'Moment deleted',
                    ),
                  ),
                ),
              );
            },
            child: Text(
              _momentsText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showMomentOptions(Moment moment) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = ref.read(authServiceProvider).user?.id?.toString();
    final isMyMoment = currentUserId != null && currentUserId == moment.userId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
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
              const SizedBox(height: 16),
              if (isMyMoment) ...[
                _OptionTile(
                  icon: Icons.lock_outline,
                  title: _momentsText(
                    context,
                    zhCN: '设为私密',
                    zhTW: '設為私密',
                    en: 'Set Private',
                  ),
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(momentProvider.notifier).setPrivate(moment.id);
                  },
                ),
                _OptionTile(
                  icon: Icons.delete_outline,
                  title: _momentsText(
                    context,
                    zhCN: '删除',
                    zhTW: '刪除',
                    en: 'Delete',
                  ),
                  isDark: isDark,
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(moment);
                  },
                ),
              ] else ...[
                _OptionTile(
                  icon: Icons.visibility_off_outlined,
                  title: _momentsText(
                    context,
                    zhCN: '屏蔽此动态',
                    zhTW: '封鎖此動態',
                    en: 'Block This Moment',
                  ),
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(context);
                    _blockMoment(moment);
                  },
                ),
                _OptionTile(
                  icon: Icons.person_off_outlined,
                  title: _momentsText(
                    context,
                    zhCN: '屏蔽此人动态',
                    zhTW: '封鎖此人的動態',
                    en: 'Block This User\'s Moments',
                  ),
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(context);
                    _blockUserMoments(moment);
                  },
                ),
                _OptionTile(
                  icon: Icons.report_outlined,
                  title: _momentsText(
                    context,
                    zhCN: '举报',
                    zhTW: '檢舉',
                    en: 'Report',
                  ),
                  isDark: isDark,
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _reportMoment(moment);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Moment moment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _momentsText(
            context,
            zhCN: '删除动态',
            zhTW: '刪除動態',
            en: 'Delete Moment',
          ),
        ),
        content: Text(
          _momentsText(
            context,
            zhCN: '确定要删除这条动态吗？删除后无法恢复。',
            zhTW: '確定要刪除此動態嗎？刪除後無法恢復。',
            en: 'Delete this moment? This action cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(momentProvider.notifier).deleteMoment(moment.id);
            },
            child: Text(
              _momentsText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _blockMoment(Moment moment) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _momentsText(
            context,
            zhCN: '屏蔽动态',
            zhTW: '封鎖動態',
            en: 'Block Moment',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Text(
          _momentsText(
            context,
            zhCN: '屏蔽后将不再看到此动态，确定要屏蔽吗？',
            zhTW: '封鎖後將不再看到此動態，確定要封鎖嗎？',
            en: 'You will no longer see this moment. Block it?',
          ),
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final api = ref.read(apiClientProvider);
                final response = await api.post('/moment/${moment.id}/block');
                if (response.isSuccess) {
                  ref
                      .read(momentProvider.notifier)
                      .removeMomentLocally(moment.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _momentsText(
                            context,
                            zhCN: '已屏蔽此动态',
                            zhTW: '已封鎖此動態',
                            en: 'Blocked this moment',
                          ),
                        ),
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _momentsServerMessage(
                            response.message,
                            zhCN: '屏蔽失败',
                            zhTW: '封鎖失敗',
                            en: 'Failed to block',
                          ),
                        ),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_momentsText(
                          context,
                          zhCN: '屏蔽失败',
                          zhTW: '封鎖失敗',
                          en: 'Failed to block',
                        )}: $e',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(
              _momentsText(
                context,
                zhCN: '屏蔽',
                zhTW: '封鎖',
                en: 'Block',
              ),
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _blockUserMoments(Moment moment) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _momentsText(
            context,
            zhCN: '屏蔽此人动态',
            zhTW: '封鎖此人的動態',
            en: 'Block This User\'s Moments',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Text(
          _momentsText(
            context,
            zhCN: '屏蔽后将不再看到 ${moment.userName} 的所有动态，确定要屏蔽吗？',
            zhTW: '封鎖後將不再看到 ${moment.userName} 的所有動態，確定要封鎖嗎？',
            en: 'You will no longer see any moments from ${moment.userName}. Block this user?',
          ),
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final api = ref.read(apiClientProvider);
                final response = await api.post(
                  '/moment/block-user/${moment.userId}',
                );
                if (response.isSuccess) {
                  ref
                      .read(momentProvider.notifier)
                      .removeUserMomentsLocally(moment.userId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _momentsText(
                            context,
                            zhCN: '已屏蔽 ${moment.userName} 的动态',
                            zhTW: '已封鎖 ${moment.userName} 的動態',
                            en: 'Blocked ${moment.userName}\'s moments',
                          ),
                        ),
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _momentsServerMessage(
                            response.message,
                            zhCN: '屏蔽失败',
                            zhTW: '封鎖失敗',
                            en: 'Failed to block',
                          ),
                        ),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_momentsText(
                          context,
                          zhCN: '屏蔽失败',
                          zhTW: '封鎖失敗',
                          en: 'Failed to block',
                        )}: $e',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(
              _momentsText(
                context,
                zhCN: '屏蔽',
                zhTW: '封鎖',
                en: 'Block',
              ),
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reportMoment(Moment moment) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reasons = _momentReportReasons(context);
    String? selectedReason;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  _momentsText(
                    context,
                    zhCN: '举报动态',
                    zhTW: '檢舉動態',
                    en: 'Report Moment',
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...reasons.map(
                (reason) => ListTile(
                  title: Text(
                    reason,
                    style: TextStyle(
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    selectedReason = reason;
                    try {
                      final api = ref.read(apiClientProvider);
                      final response = await api.post(
                        '/report',
                        data: {
                          'target_type': 'moment',
                          'target_id': moment.id,
                          'reason': selectedReason,
                        },
                      );
                      if (response.isSuccess && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _momentsText(
                                context,
                                zhCN: '举报成功，我们会尽快处理',
                                zhTW: '檢舉成功，我們會盡快處理',
                                en: 'Report submitted. We will review it soon.',
                              ),
                            ),
                          ),
                        );
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _momentsServerMessage(
                                response.message,
                                zhCN: '举报失败',
                                zhTW: '檢舉失敗',
                                en: 'Failed to report',
                              ),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${_momentsText(
                                context,
                                zhCN: '举报失败',
                                zhTW: '檢舉失敗',
                                en: 'Failed to report',
                              )}: $e',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Center(
                  child: Text(
                    _momentsText(
                      context,
                      zhCN: '取消',
                      zhTW: '取消',
                      en: 'Cancel',
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showPublishSheet(BuildContext context, bool isDark) {
    // 使用全屏页面代替底部弹窗，这样可以隐藏底部 tab 菜单
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return MomentPublishPage(isDark: isDark);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          );
        },
      ),
    );
  }
}

/// 瀑布流动态卡片（小红书风格）
class _WaterfallMomentCard extends StatefulWidget {
  final Moment moment;
  final bool isDark;
  final VoidCallback onLike;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails details, BuildContext context)
      onLongPress;

  const _WaterfallMomentCard({
    required this.moment,
    required this.isDark,
    required this.onLike,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_WaterfallMomentCard> createState() => _WaterfallMomentCardState();
}

class _WaterfallMomentCardState extends State<_WaterfallMomentCard>
    with SingleTickerProviderStateMixin {
  bool _showLikeAnimation = false;

  void _handleLike() {
    HapticFeedback.selectionClick();
    // 如果之前未点赞，显示动画
    if (!widget.moment.isLiked) {
      setState(() => _showLikeAnimation = true);
      // 动画播放完后隐藏
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _showLikeAnimation = false);
        }
      });
    }
    widget.onLike();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        widget.onLongPress(details, context);
      },
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardFor(context),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图片（自适应高度）
                if (widget.moment.mediaUrls.isNotEmpty) _buildCoverImage(),

                // 内容区域（限制行数 + 裁剪溢出，统一标准）
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 文字内容：最多 2 行 + 省略号，避免瀑布流溢出
                      if (widget.moment.content.isNotEmpty)
                        ClipRect(
                          child: AnimatedEmojiText(
                            text: widget.moment.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            emojiSize: 18,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: AppColors.textPrimaryFor(context),
                            ),
                          ),
                        ),

                      if (widget.moment.content.isNotEmpty)
                        const SizedBox(height: 8),

                      // 用户信息和点赞
                      Row(
                        children: [
                          // 头像
                          AvatarWidget(
                            name: widget.moment.userName,
                            avatar: widget.moment.userAvatar,
                            userId: widget.moment.userId,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          // 用户名
                          Expanded(
                            child: Text(
                              widget.moment.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryFor(context),
                              ),
                            ),
                          ),
                          // 点赞按钮
                          GestureDetector(
                            onTap: _handleLike,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.moment.isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 16,
                                  color: widget.moment.isLiked
                                      ? Colors.redAccent
                                      : AppColors.textTertiaryFor(context),
                                ),
                                if (widget.moment.likeCount > 0) ...[
                                  const SizedBox(width: 2),
                                  Text(
                                    _formatCount(widget.moment.likeCount),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiaryFor(context),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 点赞动画
          if (_showLikeAnimation)
            Positioned.fill(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    // 限制 opacity 在 0.0-1.0 范围内
                    final opacity =
                        (value > 0.8 ? 2 - value * 1.25 : 1.0).clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: value.clamp(0.0, 1.2),
                      child: Opacity(
                        opacity: opacity,
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: WebSafeLottie.asset(
                            'assets/emoji/lottie/heart_eyes.json',
                            repeat: false,
                            animate: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoverImage() {
    final isVideo = widget.moment.contentType == MomentContentType.video;
    final imageUrl = isVideo && widget.moment.videoThumbnail != null
        ? ApiConfig.getMediaUrl(widget.moment.videoThumbnail!)
        : ApiConfig.getMediaUrl(widget.moment.mediaUrls.first);

    // 通用占位符（带加载指示，减少“空白”感）
    final placeholder = Container(
      color: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F5),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

    // 视频类型
    if (isVideo) {
      return AspectRatio(
        aspectRatio: 0.8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => placeholder,
              errorWidget: (context, url, error) => Container(
                color: widget.isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF5F5F5),
                child: const Center(
                  child: Icon(Icons.videocam, size: 40, color: Colors.grey),
                ),
              ),
              memCacheWidth: 320,
              memCacheHeight: 400,
              fadeInDuration: const Duration(milliseconds: 150),
            ),
            // 播放图标
            Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 根据图片数量决定显示样式
    if (widget.moment.mediaUrls.length == 1) {
      return AspectRatio(
        aspectRatio: 1.0, // 正方形
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => Container(
            color: widget.isDark
                ? const Color(0xFF2C2C2E)
                : const Color(0xFFF5F5F5),
            child: const Center(
              child: Icon(Icons.broken_image_outlined, size: 32),
            ),
          ),
          memCacheWidth: 320,
          memCacheHeight: 320,
          fadeInDuration: const Duration(milliseconds: 150),
        ),
      );
    } else {
      // 多图时显示第一张，右下角显示数量
      return AspectRatio(
        aspectRatio: 0.85, // 略高的比例
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => placeholder,
              errorWidget: (context, url, error) => Container(
                color: widget.isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF5F5F5),
              ),
              memCacheWidth: 320,
              memCacheHeight: 360,
              fadeInDuration: const Duration(milliseconds: 150),
            ),
            // 图片数量标识
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.photo_library,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${widget.moment.mediaUrls.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}w';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

String _momentShareContentTypeText(BuildContext context, Moment moment) {
  switch (moment.contentType) {
    case MomentContentType.image:
      return _momentsText(
        context,
        zhCN: '分享了一组图片动态',
        zhTW: '分享了一組圖片動態',
        en: 'shared a photo moment',
      );
    case MomentContentType.video:
      return _momentsText(
        context,
        zhCN: '分享了一条视频动态',
        zhTW: '分享了一則影片動態',
        en: 'shared a video moment',
      );
    case MomentContentType.text:
      return _momentsText(
        context,
        zhCN: '分享了一条动态',
        zhTW: '分享了一則動態',
        en: 'shared a moment',
      );
  }
}

String _buildMomentShareText(BuildContext context, Moment moment) {
  final lines = <String>[
    _momentsText(
      context,
      zhCN: '${moment.userName}${_momentShareContentTypeText(context, moment)}',
      zhTW: '${moment.userName}${_momentShareContentTypeText(context, moment)}',
      en: '${moment.userName} ${_momentShareContentTypeText(context, moment)}',
    ),
  ];

  final content = moment.content.trim();
  if (content.isNotEmpty) {
    lines.add(content);
  }
  if (moment.topics.isNotEmpty) {
    lines.add(moment.topics.map((topic) => '#$topic').join(' '));
  }
  lines.add(
    _momentsText(
      context,
      zhCN: '动态ID：${moment.id}',
      zhTW: '動態ID：${moment.id}',
      en: 'Moment ID: ${moment.id}',
    ),
  );

  return lines.join('\n');
}

Future<void> _shareMoment(BuildContext context, Moment moment) async {
  final renderObject = context.findRenderObject();
  final shareOrigin = renderObject is RenderBox
      ? renderObject.localToGlobal(Offset.zero) & renderObject.size
      : null;

  try {
    await Share.share(
      _buildMomentShareText(context, moment),
      subject: _momentsText(
        context,
        zhCN: '分享动态',
        zhTW: '分享動態',
        en: 'Share Moment',
      ),
      sharePositionOrigin: shareOrigin,
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _momentsText(
            context,
            zhCN: '分享失败，请稍后重试',
            zhTW: '分享失敗，請稍後重試',
            en: 'Unable to share. Please try again later.',
          ),
        ),
      ),
    );
  }
}

/// 动态卡片
class _MomentCard extends StatelessWidget {
  final Moment moment;
  final bool isDark;
  final VoidCallback onLike;
  final VoidCallback onMore;
  final Widget? footer;
  final bool showModerationBadge;

  const _MomentCard({
    required this.moment,
    required this.isDark,
    required this.onLike,
    required this.onMore,
    this.footer,
    this.showModerationBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openMomentDetail(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dividerFor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _openUserProfile(context),
                    child: AvatarWidget(
                      name: moment.userName,
                      avatar: moment.userAvatar,
                      userId: moment.userId,
                      size: 42,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openUserProfile(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  moment.userName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryFor(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                moment.visibility.icon,
                                size: 14,
                                color: AppColors.textTertiaryFor(context),
                              ),
                              if (showModerationBadge &&
                                  (moment.isPendingReview ||
                                      moment.isHidden)) ...[
                                const SizedBox(width: 8),
                                _MomentStatusBadge(
                                    moment: moment, isDark: isDark),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            moment.timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiaryFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.more_horiz,
                      color: AppColors.textTertiaryFor(context),
                    ),
                    onPressed: onMore,
                  ),
                ],
              ),
            ),

            // 内容
            if (moment.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: _buildContent(),
              ),

            // 内容和图片之间的间距
            if (moment.content.isNotEmpty && moment.mediaUrls.isNotEmpty)
              const SizedBox(height: 6),

            // 媒体（图片/视频）
            if (moment.mediaUrls.isNotEmpty) _buildMedia(context),

            // 话题标签
            if (moment.topics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: moment.topics.map((topic) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryWithOpacity(context, 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '#$topic',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.linkFor(context),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 互动按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
              child: Row(
                children: [
                  _ActionButton(
                    icon:
                        moment.isLiked ? Icons.favorite : Icons.favorite_border,
                    label: moment.likeCount > 0
                        ? _formatCount(moment.likeCount)
                        : null,
                    isActive: moment.isLiked,
                    isDark: isDark,
                    onTap: onLike,
                  ),
                  _ActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: moment.commentCount > 0
                        ? _formatCount(moment.commentCount)
                        : null,
                    isDark: isDark,
                    onTap: () => _openMomentDetail(context, showComments: true),
                  ),
                  _ActionButton(
                    icon: Icons.share_outlined,
                    label: moment.shareCount > 0
                        ? _formatCount(moment.shareCount)
                        : null,
                    isDark: isDark,
                    onTap: () {
                      _shareMoment(context, moment);
                    },
                  ),
                ],
              ),
            ),

            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }

  void _openMomentDetail(BuildContext context, {bool showComments = false}) {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(
      // 使用 iOS 风格路由，支持左滑返回
      createPageRoute(
        builder: (context) =>
            MomentDetailPage(moment: moment, showComments: showComments),
      ),
    );
  }

  void _openUserProfile(BuildContext context) {
    HapticFeedback.selectionClick();
    // 使用 GoRouter 导航到用户主页
    GoRouter.of(context).push(
      '/user/${moment.userId}?name=${Uri.encodeComponent(moment.userName)}${moment.userAvatar != null ? "&avatar=${Uri.encodeComponent(moment.userAvatar!)}" : ""}',
    );
  }

  Widget _buildContent() {
    return AnimatedEmojiText(
      text: moment.content,
      emojiSize: 20,
      style: TextStyle(
        fontSize: 15,
        height: 1.35,
        color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
      ),
    );
  }

  Widget _buildMedia(BuildContext context) {
    if (moment.mediaUrls.length == 1) {
      return GestureDetector(
        onTap: () => _openImageViewer(context, 0),
        child: Hero(
          tag: 'media_${moment.id}_0',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(0),
            child: CachedNetworkImage(
              imageUrl: ApiConfig.getMediaUrl(moment.mediaUrls.first),
              fit: BoxFit.cover,
              width: double.infinity,
              height: 220,
              memCacheWidth: 440,
              memCacheHeight: 440,
              placeholder: (_, __) => Container(
                height: 220,
                color:
                    isDark ? const Color(0xFF30363D) : const Color(0xFFF6F8FA),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                height: 220,
                color:
                    isDark ? const Color(0xFF30363D) : const Color(0xFFF6F8FA),
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40),
                ),
              ),
              fadeInDuration: const Duration(milliseconds: 150),
            ),
          ),
        ),
      );
    }

    // 多图网格
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero, // 移除默认 padding
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: moment.mediaUrls.length == 2 ? 2 : 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: moment.mediaUrls.length > 9 ? 9 : moment.mediaUrls.length,
        itemBuilder: (context, index) {
          final isLast = index == 8 && moment.mediaUrls.length > 9;
          return GestureDetector(
            onTap: () => _openImageViewer(context, index),
            child: Hero(
              tag: 'media_${moment.id}_$index',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: ApiConfig.getMediaUrl(moment.mediaUrls[index]),
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      memCacheHeight: 300,
                      placeholder: (_, __) => Container(
                        color: isDark
                            ? const Color(0xFF30363D)
                            : const Color(0xFFF6F8FA),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: isDark
                            ? const Color(0xFF30363D)
                            : const Color(0xFFF6F8FA),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 28,
                        ),
                      ),
                      fadeInDuration: const Duration(milliseconds: 150),
                    ),
                    if (isLast)
                      Container(
                        color: Colors.black45,
                        child: Center(
                          child: Text(
                            '+${moment.mediaUrls.length - 9}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openImageViewer(BuildContext context, int initialIndex) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImageViewerPage(
            images: moment.mediaUrls,
            initialIndex: initialIndex,
            momentId: moment.id,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}w';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}

/// 图片查看器页面
class _ImageViewerPage extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String momentId;

  const _ImageViewerPage({
    required this.images,
    required this.initialIndex,
    required this.momentId,
  });

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 图片轮播
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: Hero(
                        tag: 'media_${widget.momentId}_$index',
                        child: CachedNetworkImage(
                          imageUrl: ApiConfig.getMediaUrl(widget.images[index]),
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 48,
                              color: Colors.white54,
                            ),
                          ),
                          fadeInDuration: const Duration(milliseconds: 200),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // 顶部栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  right: 8,
                  bottom: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (widget.images.length > 1)
                      Text(
                        '${_currentIndex + 1} / ${widget.images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () {
                        // TODO: 更多操作（保存、分享等）
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 底部指示器
            if (widget.images.length > 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.images.length,
                    (index) => Container(
                      width: index == _currentIndex ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == _currentIndex
                            ? Colors.white
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 动态详情页
class MomentDetailPage extends ConsumerStatefulWidget {
  final Moment moment;
  final bool showComments;
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示

  const MomentDetailPage({
    super.key,
    required this.moment,
    this.showComments = false,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<MomentDetailPage> createState() => _MomentDetailPageState();
}

class _MomentDetailPageState extends ConsumerState<MomentDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  List<Comment> _comments = [];
  bool _isLoadingComments = true;
  bool _isSendingComment = false;
  bool _showEmojiPicker = false;

  // 详情可脱离主列表打开，因此保留一份展示状态；若主列表中存在同一动态，
  // 构建时始终以 Provider 中的最新状态为准。
  late bool _isLiked;
  late int _likeCount;
  bool _isLiking = false;
  bool _showLikeAnimation = false; // 点赞动画状态

  @override
  void initState() {
    super.initState();
    _isLiked = widget.moment.isLiked;
    _likeCount = widget.moment.likeCount;
    _loadComments();
    if (widget.showComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _commentFocusNode.requestFocus();
      });
    }
  }

  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() => _isLoadingComments = true);

    try {
      final comments =
          await ref.read(momentProvider.notifier).getComments(widget.moment.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingComments = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  /// 关闭详情页（兼容桌面面板模式）
  void _closePage() {
    if (widget.isDesktopPanel) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
    } else {
      Navigator.pop(context);
    }
  }

  /// 显示毛玻璃弹出菜单
  void _showDetailPopupMenu(Offset globalPosition) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = ref.read(authServiceProvider).user?.id?.toString();
    final isMyMoment =
        currentUserId != null && currentUserId == widget.moment.userId;
    final screenSize = MediaQuery.of(context).size;

    double left = globalPosition.dx - 80;
    double top = globalPosition.dy;

    if (left < 16) left = 16;
    if (left + 180 > screenSize.width - 16) left = screenSize.width - 196;
    if (top + 200 > screenSize.height - 100) top = globalPosition.dy - 160;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: animation,
                  child: _GlassPopupMenu(
                    isDark: isDark,
                    isMyMoment: isMyMoment,
                    onAction: (action) {
                      Navigator.pop(context);
                      _handleDetailMenuAction(action);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleDetailMenuAction(String action) async {
    switch (action) {
      case 'private':
        final success = await ref
            .read(momentProvider.notifier)
            .setPrivate(widget.moment.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? _momentsText(
                        context,
                        zhCN: '已设为私密',
                        zhTW: '已設為私密',
                        en: 'Set to private',
                      )
                    : _momentsText(
                        context,
                        zhCN: '操作失败',
                        zhTW: '操作失敗',
                        en: 'Action failed',
                      ),
              ),
            ),
          );
          if (success) _closePage();
        }
        break;
      case 'delete':
        _confirmDeleteMoment();
        break;
      case 'hide':
        final success = await ref
            .read(momentProvider.notifier)
            .blockMoment(widget.moment.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? _momentsText(
                        context,
                        zhCN: '已屏蔽该动态',
                        zhTW: '已封鎖此動態',
                        en: 'Blocked this moment',
                      )
                    : _momentsText(
                        context,
                        zhCN: '操作失败',
                        zhTW: '操作失敗',
                        en: 'Action failed',
                      ),
              ),
            ),
          );
          if (success) _closePage();
        }
        break;
      case 'block':
        final success = await ref
            .read(momentProvider.notifier)
            .blockUser(widget.moment.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? _momentsText(
                        context,
                        zhCN: '已屏蔽 ${widget.moment.userName} 的动态',
                        zhTW: '已封鎖 ${widget.moment.userName} 的動態',
                        en: 'Blocked ${widget.moment.userName}\'s moments',
                      )
                    : _momentsText(
                        context,
                        zhCN: '操作失败',
                        zhTW: '操作失敗',
                        en: 'Action failed',
                      ),
              ),
            ),
          );
          if (success) _closePage();
        }
        break;
      case 'report':
        _showDetailReportDialog();
        break;
    }
  }

  void _confirmDeleteMoment() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _momentsText(
            context,
            zhCN: '确认删除',
            zhTW: '確認刪除',
            en: 'Confirm Delete',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Text(
          _momentsText(
            context,
            zhCN: '删除后将无法恢复，确定要删除这条动态吗？',
            zhTW: '刪除後將無法恢復，確定要刪除這條動態嗎？',
            en: 'This moment cannot be restored after deletion. Delete it?',
          ),
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref
                  .read(momentProvider.notifier)
                  .deleteMoment(widget.moment.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? _momentsText(
                              context,
                              zhCN: '动态已删除',
                              zhTW: '動態已刪除',
                              en: 'Moment deleted',
                            )
                          : _momentsText(
                              context,
                              zhCN: '删除失败',
                              zhTW: '刪除失敗',
                              en: 'Delete failed',
                            ),
                    ),
                  ),
                );
                if (success) _closePage();
              }
            },
            child: Text(
              _momentsText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailReportDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reasons = _momentReportReasons(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _momentsText(
            context,
            zhCN: '举报动态',
            zhTW: '檢舉動態',
            en: 'Report Moment',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: reasons
              .map(
                (reason) => _ReportOption(
                  title: reason,
                  isDark: isDark,
                  onTap: () => _submitDetailReport(ctx, reason),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
        ],
      ),
    );
  }

  void _submitDetailReport(BuildContext ctx, String reason) async {
    Navigator.pop(ctx);
    await ref.read(momentProvider.notifier).blockMoment(widget.moment.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _momentsText(
              context,
              zhCN: '举报已提交，感谢您的反馈',
              zhTW: '檢舉已提交，感謝您的回饋',
              en: 'Report submitted. Thanks for your feedback.',
            ),
          ),
        ),
      );
      _closePage();
    }
  }

  /// 图片预览
  void _openImagePreview(int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImagePreviewPage(
            images: widget.moment.mediaUrls,
            initialIndex: initialIndex,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 桌面面板模式：不显示 Scaffold，只返回内容
    if (widget.isDesktopPanel) {
      return _buildBody(isDark);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.backgroundFor(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _momentsText(
            context,
            zhCN: '动态详情',
            zhTW: '動態詳情',
            en: 'Moment Details',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // 点击空白区域收起表情选择器和键盘
            if (_showEmojiPicker) {
              setState(() => _showEmojiPicker = false);
            }
            _commentFocusNode.unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 动态内容
                      _buildMomentContent(isDark),

                      // 评论列表
                      _buildCommentSection(isDark),
                    ],
                  ),
                ),
              ),

              // 底部评论输入框
              _buildCommentInput(isDark),
            ],
          ),
        ),
        // 点赞动画
        if (_showLikeAnimation)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    // 限制 opacity 在 0.0-1.0 范围内
                    final opacity =
                        (value > 0.8 ? (1.0 - (value - 0.8) * 5) : 1.0).clamp(
                      0.0,
                      1.0,
                    );
                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: value.clamp(0.0, 1.2),
                        child: WebSafeLottie.asset(
                          'assets/emoji/lottie/heart_eyes.json',
                          width: 120,
                          height: 120,
                          repeat: false,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMomentContent(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户信息
          Row(
            children: [
              GestureDetector(
                onTap: () => _openUserProfile(widget.moment.userId),
                child: AvatarWidget(
                  name: widget.moment.userName,
                  avatar: widget.moment.userAvatar,
                  userId: widget.moment.userId,
                  size: 48,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openUserProfile(widget.moment.userId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.moment.userName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.moment.timeAgo,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTapDown: (details) {
                  HapticFeedback.mediumImpact();
                  _showDetailPopupMenu(details.globalPosition);
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.more_horiz,
                    color: AppColors.textTertiaryFor(context),
                  ),
                ),
              ),
            ],
          ),

          // 内容（支持动态表情）
          if (widget.moment.content.isNotEmpty) ...[
            const SizedBox(height: 16),
            AnimatedEmojiText(
              text: widget.moment.content,
              emojiSize: 22,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
          ],

          // 媒体
          if (widget.moment.mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildMediaGrid(isDark),
          ],

          // 话题
          if (widget.moment.topics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.moment.topics.map((topic) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWithOpacity(context, 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#$topic',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryFor(context),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // 互动数据
          const SizedBox(height: 20),
          Consumer(
            builder: (context, ref, _) {
              final momentState = ref.watch(momentProvider);
              // 主列表是共享状态源；本地字段只是在通知直达等无列表场景下兜底。
              final listMoment = momentState.moments.cast<Moment?>().firstWhere(
                    (m) => m?.id == widget.moment.id,
                    orElse: () => null,
                  );

              // 列表副本存在时跟随其乐观更新/回滚，否则使用详情页展示副本。
              final isLiked = listMoment?.isLiked ?? _isLiked;
              final likeCount = listMoment?.likeCount ?? _likeCount;
              final commentCount =
                  listMoment?.commentCount ?? widget.moment.commentCount;
              final shareCount =
                  listMoment?.shareCount ?? widget.moment.shareCount;

              return Row(
                children: [
                  GestureDetector(
                    onTap: _isLiking
                        ? null
                        : () async {
                            if (_isLiking) return;
                            HapticFeedback.selectionClick();

                            final wasLiked = isLiked;
                            setState(() => _isLiking = true);

                            if (listMoment != null) {
                              // 动态在主列表中，使用普通方法
                              ref
                                  .read(momentProvider.notifier)
                                  .toggleLike(widget.moment.id);
                              // 如果之前未点赞，显示动画
                              if (!wasLiked) {
                                setState(() => _showLikeAnimation = true);
                                Future.delayed(
                                  const Duration(milliseconds: 800),
                                  () {
                                    if (mounted)
                                      setState(
                                        () => _showLikeAnimation = false,
                                      );
                                  },
                                );
                              }
                            } else {
                              // 通知或外链可直达详情，此时点赞状态由详情页本地副本维护。
                              final newIsLiked = await ref
                                  .read(momentProvider.notifier)
                                  .toggleLikeWithState(
                                    widget.moment.id,
                                    _isLiked,
                                  );
                              if (mounted) {
                                setState(() {
                                  _isLiked = newIsLiked;
                                  _likeCount = newIsLiked
                                      ? _likeCount + 1
                                      : _likeCount - 1;
                                });
                                // 如果之前未点赞，显示动画
                                if (!wasLiked && newIsLiked) {
                                  setState(() => _showLikeAnimation = true);
                                  Future.delayed(
                                    const Duration(milliseconds: 800),
                                    () {
                                      if (mounted)
                                        setState(
                                          () => _showLikeAnimation = false,
                                        );
                                    },
                                  );
                                }
                              }
                            }

                            if (mounted) setState(() => _isLiking = false);
                          },
                    child: _buildStatItem(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      likeCount,
                      _momentsText(
                        context,
                        zhCN: '赞',
                        zhTW: '讚',
                        en: 'Likes',
                      ),
                      isActive: isLiked,
                    ),
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    Icons.chat_bubble_outline,
                    commentCount,
                    _momentsText(
                      context,
                      zhCN: '评论',
                      zhTW: '評論',
                      en: 'Comments',
                    ),
                  ),
                  const SizedBox(width: 24),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      _shareMoment(context, widget.moment);
                    },
                    child: _buildStatItem(
                      Icons.share_outlined,
                      shareCount,
                      _momentsText(
                        context,
                        zhCN: '分享',
                        zhTW: '分享',
                        en: 'Shares',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(bool isDark) {
    // 检查是否为视频
    if (widget.moment.contentType == MomentContentType.video &&
        widget.moment.mediaUrls.isNotEmpty) {
      return _VideoPlayerWidget(
        videoUrl: ApiConfig.getMediaUrl(widget.moment.mediaUrls.first),
        thumbnailUrl: widget.moment.videoThumbnail != null
            ? ApiConfig.getMediaUrl(widget.moment.videoThumbnail!)
            : null,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F5);
    if (widget.moment.mediaUrls.length == 1) {
      return GestureDetector(
        onTap: () => _openImagePreview(0),
        child: Hero(
          tag: 'moment_image_${widget.moment.id}_0',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: ApiConfig.getMediaUrl(widget.moment.mediaUrls.first),
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(
                color: placeColor,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: placeColor,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
              fadeInDuration: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: widget.moment.mediaUrls.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _openImagePreview(index),
          child: Hero(
            tag: 'moment_image_${widget.moment.id}_$index',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: ApiConfig.getMediaUrl(widget.moment.mediaUrls[index]),
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: placeColor,
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: placeColor,
                  child: const Icon(Icons.broken_image_outlined, size: 32),
                ),
                fadeInDuration: const Duration(milliseconds: 200),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
    IconData icon,
    int count,
    String label, {
    bool isActive = false,
  }) {
    final color =
        isActive ? AppColors.error : AppColors.textSecondaryFor(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          count > 0 ? '$count' : label,
          style: TextStyle(fontSize: 13, color: color),
        ),
      ],
    );
  }

  Widget _buildCommentSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: AppColors.textSecondaryFor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  _momentsText(
                    context,
                    zhCN: '评论',
                    zhTW: '評論',
                    en: 'Comments',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primaryWithOpacity(context, 0.2)
                        : AppColors.primaryWithOpacity(context, 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_comments.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryFor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
          if (_isLoadingComments)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 40,
                      color: AppColors.textTertiaryFor(context),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _momentsText(
                        context,
                        zhCN: '暂无评论',
                        zhTW: '暫無評論',
                        en: 'No comments yet',
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _momentsText(
                        context,
                        zhCN: '快来抢沙发~',
                        zhTW: '快來搶沙發~',
                        en: 'Be the first to comment',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_comments.length, (index) {
              final comment = _comments[index];
              return _CommentTile(
                comment: comment,
                isDark: isDark,
                onUserTap: () => _openUserProfile(comment.userId),
              );
            }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _openUserProfile(String userId) {
    GoRouter.of(context).push('/user/$userId');
  }

  Widget _buildCommentInput(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: _showEmojiPicker
                ? 12
                : MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 表情按钮
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (!_showEmojiPicker) {
                    _commentFocusNode.unfocus();
                  }
                  setState(() => _showEmojiPicker = !_showEmojiPicker);
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _showEmojiPicker
                        ? AppColors.primaryWithOpacity(context, 0.15)
                        : (isDark
                            ? AppColors.darkInputBackground
                            : AppColors.lightInputBackground),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _showEmojiPicker
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                    size: 22,
                    color: _showEmojiPicker
                        ? AppColors.primaryFor(context)
                        : (AppColors.textSecondaryFor(context)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkInputBackground
                        : AppColors.lightInputBackground,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkDivider
                          : AppColors.lightDivider,
                      width: 0.5,
                    ),
                  ),
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimaryFor(context),
                    ),
                    onTap: () {
                      if (_showEmojiPicker) {
                        setState(() => _showEmojiPicker = false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _momentsText(
                        context,
                        zhCN: '写评论...',
                        zhTW: '寫評論...',
                        en: 'Write a comment...',
                      ),
                      hintStyle: TextStyle(
                        color: AppColors.textTertiaryFor(context),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _sendComment,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: _isSendingComment
                        ? null
                        : LinearGradient(
                            colors: [
                              AppColors.primaryFor(context),
                              AppColors.primaryFor(context).withBlue(220),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: _isSendingComment
                        ? AppColors.primaryWithOpacity(context, 0.5)
                        : null,
                    shape: BoxShape.circle,
                    boxShadow: _isSendingComment
                        ? null
                        : [
                            BoxShadow(
                              color: AppColors.primaryWithOpacity(context, 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Center(
                    child: _isSendingComment
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 表情选择器
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _showEmojiPicker
              ? TGEmojiPicker(
                  height: 260,
                  onEmojiSelected: (emoji, {bool isAnimated = false}) {
                    if (emoji == 'BACKSPACE') {
                      final text = _commentController.text;
                      final selection = _commentController.selection;
                      if (text.isNotEmpty && selection.baseOffset > 0) {
                        final beforeCursor = text.substring(
                          0,
                          selection.baseOffset,
                        );
                        final afterCursor = text.substring(
                          selection.baseOffset,
                        );
                        int deleteCount = 1;
                        if (beforeCursor.isNotEmpty) {
                          final lastChar = beforeCursor.characters.last;
                          deleteCount = lastChar.length;
                        }
                        final newText = beforeCursor.substring(
                              0,
                              beforeCursor.length - deleteCount,
                            ) +
                            afterCursor;
                        _commentController.text = newText;
                        _commentController.selection = TextSelection.collapsed(
                          offset: selection.baseOffset - deleteCount,
                        );
                      }
                    } else {
                      final text = _commentController.text;
                      final selection = _commentController.selection;
                      final start = (selection.isValid && selection.start >= 0)
                          ? selection.start
                          : text.length;
                      final end = (selection.isValid && selection.end >= 0)
                          ? selection.end
                          : text.length;
                      final newText = text.replaceRange(start, end, emoji);
                      _commentController.text = newText;
                      _commentController.selection = TextSelection.collapsed(
                        offset: start + emoji.length,
                      );
                    }
                  },
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _sendComment() async {
    if (_commentController.text.isEmpty || _isSendingComment) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSendingComment = true);

    final content = _commentController.text;
    _commentController.clear();

    try {
      final comment = await ref
          .read(momentProvider.notifier)
          .addComment(widget.moment.id, content);

      if (!mounted) return;
      setState(() => _isSendingComment = false);

      if (comment != null) {
        // 仅插入服务端确认并返回的评论，避免失败请求留下无法追踪的本地假数据。
        setState(() {
          _comments.insert(0, comment);
        });
        _commentFocusNode.unfocus();
      } else {
        // 恢复文本
        _commentController.text = content;
        final errMsg = ref.read(momentProvider).error ??
            _momentsText(
              context,
              zhCN: '评论失败，请重试',
              zhTW: '評論失敗，請重試',
              en: 'Failed to comment. Please try again.',
            );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSendingComment = false);
        _commentController.text = content;
      }
    }
  }
}

// Comment 类已移至 moment_provider.dart

/// 评论列表项
class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isDark;
  final VoidCallback? onUserTap;

  const _CommentTile({
    required this.comment,
    required this.isDark,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onUserTap,
            child: AvatarWidget(
              name: comment.userName,
              avatar: comment.userAvatar,
              userId: comment.userId,
              size: 36,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onUserTap,
                      child: Text(
                        comment.userName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      comment.timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiaryFor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AnimatedEmojiText(
                  text: comment.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: AppColors.textPrimaryFor(context),
                  ),
                  emojiSize: 20,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: 16,
                            color: AppColors.textTertiaryFor(context),
                          ),
                          if (comment.likeCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${comment.likeCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiaryFor(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: () {},
                      child: Text(
                        _momentsText(
                          context,
                          zhCN: '回复',
                          zhTW: '回覆',
                          en: 'Reply',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 互动按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.label,
    this.isActive = false,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isActive ? AppColors.error : AppColors.textSecondaryFor(context);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: TextStyle(fontSize: 13, color: color)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 毛玻璃弹出菜单
class _GlassPopupMenu extends StatelessWidget {
  final bool isDark;
  final bool isMyMoment;
  final void Function(String action) onAction;

  const _GlassPopupMenu({
    required this.isDark,
    required this.isMyMoment,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          width: 180,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.6)
                : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: isMyMoment
                ? [
                    _buildMenuItem(
                      context,
                      Icons.lock_outline,
                      _momentsText(
                        context,
                        zhCN: '设为私密',
                        zhTW: '設為私密',
                        en: 'Set Private',
                      ),
                      'private',
                    ),
                    _buildDivider(context),
                    _buildMenuItem(
                      context,
                      Icons.delete_outline,
                      _momentsText(
                        context,
                        zhCN: '删除',
                        zhTW: '刪除',
                        en: 'Delete',
                      ),
                      'delete',
                      isDestructive: true,
                    ),
                  ]
                : [
                    _buildMenuItem(
                      context,
                      Icons.visibility_off_outlined,
                      _momentsText(
                        context,
                        zhCN: '屏蔽此动态',
                        zhTW: '封鎖此動態',
                        en: 'Block This Moment',
                      ),
                      'hide',
                    ),
                    _buildDivider(context),
                    _buildMenuItem(
                      context,
                      Icons.block,
                      _momentsText(
                        context,
                        zhCN: '屏蔽此人动态',
                        zhTW: '封鎖此人的動態',
                        en: 'Block This User\'s Moments',
                      ),
                      'block',
                    ),
                    _buildDivider(context),
                    _buildMenuItem(
                      context,
                      Icons.flag_outlined,
                      _momentsText(
                        context,
                        zhCN: '举报',
                        zhTW: '檢舉',
                        en: 'Report',
                      ),
                      'report',
                      isDestructive: true,
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String text,
    String action, {
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onAction(action);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isDestructive
                    ? Colors.red
                    : AppColors.textSecondaryFor(context),
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDestructive
                      ? Colors.red
                      : AppColors.textPrimaryFor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.dividerFor(context),
    );
  }
}

/// 选中的媒体数据
class _SelectedMedia {
  final String filePath;
  final String? livePhotoVideoPath;
  final bool isVideo;
  final bool isLivePhoto;

  _SelectedMedia({
    required this.filePath,
    this.livePhotoVideoPath,
    this.isVideo = false,
    this.isLivePhoto = false,
  });
}

/// 媒体选择器页面
class _MediaPickerPage extends StatefulWidget {
  final bool isDark;
  final int maxCount;
  final bool allowVideo;
  final bool videoOnly;

  const _MediaPickerPage({
    required this.isDark,
    required this.maxCount,
    this.allowVideo = false,
    this.videoOnly = false,
  });

  @override
  State<_MediaPickerPage> createState() => _MediaPickerPageState();
}

class _MediaPickerPageState extends State<_MediaPickerPage> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  final Set<String> _selectedIds = {}; // 用ID而非对象引用
  final List<AssetEntity> _selectedAssets = []; // 保持顺序
  bool _isLoading = true;
  bool _isConfirming = false;

  // 缩略图缓存 - 避免重复加载
  final Map<String, Uint8List> _thumbnailCache = {};

  // Live Photo 检测缓存
  final Map<String, bool> _livePhotoCache = {};

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    RequestType type;
    if (widget.videoOnly) {
      type = RequestType.video;
    } else if (widget.allowVideo) {
      type = RequestType.common;
    } else {
      type = RequestType.image;
    }

    final albums = await PhotoManager.getAssetPathList(type: type);
    if (albums.isNotEmpty) {
      _currentAlbum = albums.first;
      await _loadAssets();
    }
    if (mounted) {
      setState(() {
        _albums = albums;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAssets() async {
    if (_currentAlbum == null) return;
    final assets = await _currentAlbum!.getAssetListRange(start: 0, end: 2000);
    if (mounted) {
      setState(() => _assets = assets);
    }

    // 预加载 Live Photo 检测（异步）
    if (Platform.isIOS && !widget.videoOnly) {
      _preloadLivePhotoInfo(assets.take(100).toList());
    }
  }

  /// 预加载 Live Photo 信息
  Future<void> _preloadLivePhotoInfo(List<AssetEntity> assets) async {
    for (final asset in assets) {
      if (asset.type == AssetType.image &&
          !_livePhotoCache.containsKey(asset.id)) {
        _checkLivePhoto(asset);
      }
    }
  }

  /// 检测是否为 Live Photo
  Future<bool> _checkLivePhoto(AssetEntity asset) async {
    if (_livePhotoCache.containsKey(asset.id)) {
      return _livePhotoCache[asset.id]!;
    }

    if (!Platform.isIOS || asset.type != AssetType.image) {
      _livePhotoCache[asset.id] = false;
      return false;
    }

    try {
      // 通过 mimeType 或文件名检测
      final title = asset.title ?? '';
      final isLive = title.toLowerCase().contains('live') ||
          asset.mimeType?.contains('heic') == true;
      _livePhotoCache[asset.id] = isLive;
      return isLive;
    } catch (e) {
      _livePhotoCache[asset.id] = false;
      return false;
    }
  }

  /// 获取缓存的缩略图
  Future<Uint8List?> _getCachedThumbnail(AssetEntity asset) async {
    if (_thumbnailCache.containsKey(asset.id)) {
      return _thumbnailCache[asset.id];
    }

    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(300, 300),
      quality: 85,
    );

    if (data != null) {
      _thumbnailCache[asset.id] = data;
    }
    return data;
  }

  void _toggleSelect(AssetEntity asset) {
    HapticFeedback.selectionClick();

    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
        _selectedAssets.removeWhere((a) => a.id == asset.id);
      } else if (_selectedAssets.length < widget.maxCount) {
        _selectedIds.add(asset.id);
        _selectedAssets.add(asset);
      } else {
        // 达到最大数量，显示提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _momentsText(
                context,
                zhCN: '最多选择 ${widget.maxCount} 个',
                zhTW: '最多選擇 ${widget.maxCount} 個',
                en: 'You can select up to ${widget.maxCount}',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    });
  }

  Future<void> _confirm() async {
    if (_selectedAssets.isEmpty || _isConfirming) return;

    setState(() => _isConfirming = true);
    HapticFeedback.mediumImpact();

    final results = <_SelectedMedia>[];

    for (final asset in _selectedAssets) {
      String? filePath;
      String? liveVideoPath;

      try {
        // 对于 iOS 的 Live Photo，先检测视频路径
        if (Platform.isIOS && asset.type == AssetType.image) {
          // 获取原始文件路径用于检测 Live Photo 视频
          final originFile = await asset.originFile;
          if (originFile != null && await originFile.exists()) {
            final originPath = originFile.path;

            // 检测 Live Photo 视频
            final possibleVideoPaths = [
              originPath.replaceAll(
                RegExp(r'\.(heic|HEIC|jpg|JPG|jpeg|JPEG|png|PNG)$'),
                '.MOV',
              ),
              originPath.replaceAll(
                RegExp(r'\.(heic|HEIC|jpg|JPG|jpeg|JPEG|png|PNG)$'),
                '.mov',
              ),
            ];

            for (final videoPath in possibleVideoPaths) {
              final videoFile = File(videoPath);
              if (await videoFile.exists()) {
                liveVideoPath = videoPath;
                debugPrint('[MediaPicker] Live Photo video found: $videoPath');
                break;
              }
            }
          }
        }

        // 使用 asset.file 获取图片（会自动将 HEIC 转换为 JPEG）
        final file = await asset.file;
        if (file != null && await file.exists()) {
          filePath = file.path;
          debugPrint('[MediaPicker] File path: $filePath');
        }

        // 如果仍然没有文件路径，尝试获取原始数据并保存
        if (filePath == null) {
          debugPrint(
            '[MediaPicker] Warning: Could not get file for asset ${asset.id}, trying originBytes...',
          );
          final bytes = await asset.originBytes;
          if (bytes != null) {
            // 保存到临时目录
            final tempDir = await Directory.systemTemp.createTemp('media_');
            final tempFile = File('${tempDir.path}/${asset.id}.jpg');
            await tempFile.writeAsBytes(bytes);
            filePath = tempFile.path;
            debugPrint('[MediaPicker] Saved to temp file: $filePath');
          }
        }

        if (filePath == null) {
          debugPrint(
            '[MediaPicker] Error: Failed to get file for asset ${asset.id}',
          );
          continue;
        }

        results.add(
          _SelectedMedia(
            filePath: filePath,
            livePhotoVideoPath: liveVideoPath,
            isVideo: asset.type == AssetType.video,
            isLivePhoto: liveVideoPath != null,
          ),
        );
      } catch (e) {
        debugPrint('[MediaPicker] Error processing asset ${asset.id}: $e');
      }
    }

    debugPrint(
      '[MediaPicker] Confirm completed: ${results.length} files selected',
    );

    if (mounted) {
      Navigator.pop(context, results);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark ? const Color(0xFF17212B) : Colors.white,
      appBar: AppBar(
        backgroundColor: widget.isDark ? const Color(0xFF17212B) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: widget.isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _showAlbumPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white10
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentAlbum?.name ??
                      _momentsText(
                        context,
                        zhCN: '相册',
                        zhTW: '相簿',
                        en: 'Album',
                      ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.textSecondaryFor(context),
                ),
              ],
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _selectedAssets.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: _isConfirming ? null : _confirm,
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.primaryFor(context),
                        foregroundColor: AppColors.onPrimaryFor(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isConfirming
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _momentsText(
                                context,
                                zhCN: '完成 (${_selectedAssets.length})',
                                zhTW: '完成 (${_selectedAssets.length})',
                                en: 'Done (${_selectedAssets.length})',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _momentsText(
                      context,
                      zhCN: '加载中...',
                      zhTW: '載入中...',
                      en: 'Loading...',
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ],
              ),
            )
          : _assets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.videoOnly
                            ? Icons.videocam_off_outlined
                            : Icons.photo_library_outlined,
                        size: 64,
                        color: AppColors.textTertiaryFor(context),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.videoOnly
                            ? _momentsText(
                                context,
                                zhCN: '暂无视频',
                                zhTW: '暫無影片',
                                en: 'No videos',
                              )
                            : _momentsText(
                                context,
                                zhCN: '暂无照片',
                                zhTW: '暫無照片',
                                en: 'No photos',
                              ),
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(1),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                  ),
                  // 使用 cacheExtent 提前加载
                  cacheExtent: 500,
                  itemCount: _assets.length,
                  itemBuilder: (context, index) {
                    final asset = _assets[index];
                    return _MediaThumbnailTile(
                      key: ValueKey(asset.id),
                      asset: asset,
                      isDark: widget.isDark,
                      isSelected: _selectedIds.contains(asset.id),
                      selectIndex: _selectedAssets.indexWhere(
                        (a) => a.id == asset.id,
                      ),
                      onTap: () => _toggleSelect(asset),
                      getCachedThumbnail: _getCachedThumbnail,
                      isLivePhoto: _livePhotoCache[asset.id] ?? false,
                    );
                  },
                ),
    );
  }

  void _showAlbumPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _momentsText(
                  context,
                  zhCN: '选择相册',
                  zhTW: '選擇相簿',
                  en: 'Choose Album',
                ),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _albums.length,
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  final isSelected = _currentAlbum?.id == album.id;
                  return ListTile(
                    leading: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color:
                            widget.isDark ? Colors.white10 : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FutureBuilder<List<AssetEntity>>(
                        future: album.getAssetListRange(start: 0, end: 1),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                            return FutureBuilder<Uint8List?>(
                              future:
                                  snapshot.data!.first.thumbnailDataWithSize(
                                const ThumbnailSize(120, 120),
                              ),
                              builder: (context, thumbSnap) {
                                if (thumbSnap.hasData &&
                                    thumbSnap.data != null) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      thumbSnap.data!,
                                      fit: BoxFit.cover,
                                      width: 56,
                                      height: 56,
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            );
                          }
                          return Icon(
                            Icons.photo_library_outlined,
                            color: AppColors.textTertiaryFor(context),
                          );
                        },
                      ),
                    ),
                    title: Text(
                      album.name,
                      style: TextStyle(
                        color: AppColors.textPrimaryFor(context),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: FutureBuilder<int>(
                      future: album.assetCountAsync,
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return Text(
                          _momentsText(
                            context,
                            zhCN: '$count 项',
                            zhTW: '$count 項',
                            en: '$count items',
                          ),
                          style: TextStyle(
                            color: AppColors.textSecondaryFor(context),
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: AppColors.primaryFor(context),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (_currentAlbum?.id != album.id) {
                        setState(() {
                          _currentAlbum = album;
                          _isLoading = true;
                        });
                        _loadAssets().then((_) {
                          if (mounted) setState(() => _isLoading = false);
                        });
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 高性能缩略图卡片 - 独立组件避免重建
class _MediaThumbnailTile extends StatefulWidget {
  final AssetEntity asset;
  final bool isDark;
  final bool isSelected;
  final int selectIndex;
  final VoidCallback onTap;
  final Future<Uint8List?> Function(AssetEntity) getCachedThumbnail;
  final bool isLivePhoto;

  const _MediaThumbnailTile({
    super.key,
    required this.asset,
    required this.isDark,
    required this.isSelected,
    required this.selectIndex,
    required this.onTap,
    required this.getCachedThumbnail,
    required this.isLivePhoto,
  });

  @override
  State<_MediaThumbnailTile> createState() => _MediaThumbnailTileState();
}

class _MediaThumbnailTileState extends State<_MediaThumbnailTile> {
  Uint8List? _thumbnail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final data = await widget.getCachedThumbnail(widget.asset);
    if (mounted) {
      setState(() {
        _thumbnail = data;
        _isLoading = false;
      });
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图
          if (_thumbnail != null)
            Image.memory(
              _thumbnail!,
              fit: BoxFit.cover,
              gaplessPlayback: true, // 避免闪烁
            )
          else
            Container(
              color: widget.isDark
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFF5F5F5),
              child: _isLoading
                  ? null
                  : Icon(
                      Icons.broken_image_outlined,
                      color: widget.isDark ? Colors.white24 : Colors.black12,
                    ),
            ),

          // Live Photo 标识
          if (widget.isLivePhoto && widget.asset.type == AssetType.image)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.motion_photos_on,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _momentsText(
                        context,
                        zhCN: '实况',
                        zhTW: '實況',
                        en: 'Live',
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),

          // 视频时长
          if (widget.asset.type == AssetType.video)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(widget.asset.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // 选中状态圆圈
          Positioned(
            right: 6,
            top: 6,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isSelected
                    ? AppColors.primaryFor(context)
                    : Colors.black.withOpacity(0.3),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primaryWithOpacity(context, 0.4),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: widget.isSelected
                  ? Center(
                      child: Text(
                        '${widget.selectIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
            ),
          ),

          // 选中遮罩
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: widget.isSelected
                ? Colors.white.withOpacity(0.2)
                : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

/// 图片预览页面
class _ImagePreviewPage extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImagePreviewPage({required this.images, required this.initialIndex});

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 图片滑动
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: ApiConfig.getMediaUrl(widget.images[index]),
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: Colors.white54,
                          ),
                        ),
                        fadeInDuration: const Duration(milliseconds: 200),
                      ),
                    ),
                  ),
                );
              },
            ),

            // 关闭按钮
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            // 页码指示器
            if (widget.images.length > 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Live Photo 预览组件 - 长按播放动态效果
class _LivePhotoPreview extends StatefulWidget {
  final String imagePath;
  final String videoPath;
  final double width;
  final double height;

  const _LivePhotoPreview({
    required this.imagePath,
    required this.videoPath,
    required this.width,
    required this.height,
  });

  @override
  State<_LivePhotoPreview> createState() => _LivePhotoPreviewState();
}

class _LivePhotoPreviewState extends State<_LivePhotoPreview> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller = VideoPlayerController.file(File(widget.videoPath));
      await _controller!.initialize();
      _controller!.setLooping(true);
      _controller!.setVolume(0); // 静音播放
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[LivePhoto] Video init error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _startPlaying() {
    if (_isInitialized && !_isPlaying) {
      HapticFeedback.lightImpact();
      setState(() => _isPlaying = true);
      _controller?.seekTo(Duration.zero);
      _controller?.play();
    }
  }

  void _stopPlaying() {
    if (_isPlaying) {
      setState(() => _isPlaying = false);
      _controller?.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startPlaying(),
      onLongPressEnd: (_) => _stopPlaying(),
      onLongPressCancel: _stopPlaying,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 静态图片
            Image.file(
              File(widget.imagePath),
              fit: BoxFit.cover,
              width: widget.width,
              height: widget.height,
            ),

            // 视频层 - 仅在播放时显示
            if (_isPlaying && _isInitialized)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),

            // 长按提示
            if (!_isPlaying)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.5),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _momentsText(
                        context,
                        zhCN: '长按查看',
                        zhTW: '長按查看',
                        en: 'Press and hold to preview',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 视频播放器组件
class _MomentVideoPlaybackCoordinator {
  static _VideoPlayerWidgetState? _activePlayer;

  static void activate(_VideoPlayerWidgetState player) {
    if (identical(_activePlayer, player)) return;
    final previous = _activePlayer;
    _activePlayer = player;
    previous?._releaseFromCoordinator();
  }

  static void release(_VideoPlayerWidgetState player) {
    if (identical(_activePlayer, player)) {
      _activePlayer = null;
    }
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  const _VideoPlayerWidget({required this.videoUrl, this.thumbnailUrl});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  final Key _visibilityKey = UniqueKey();
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _hasError = false;
  bool _listenerAttached = false;
  int _controllerGeneration = 0;

  @override
  void didUpdateWidget(covariant _VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _releaseController(notify: false);
    }
  }

  Future<void> _initializeAndPlay() async {
    if (_isInitializing) return;
    final current = _controller;
    if (_isInitialized && current != null) {
      await _togglePlay();
      return;
    }

    _MomentVideoPlaybackCoordinator.activate(this);
    final generation = ++_controllerGeneration;
    setState(() {
      _isInitializing = true;
      _hasError = false;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted ||
          _controller != controller ||
          generation != _controllerGeneration) {
        return;
      }
      controller.addListener(_onPlayerStateChanged);
      _listenerAttached = true;
      setState(() {
        _isInitialized = true;
        _isInitializing = false;
      });
      await controller.play();
    } catch (e) {
      debugPrint('[Video] Initialize error: $e');
      if (_controller == controller) {
        _controller = null;
        unawaited(controller.dispose());
        _MomentVideoPlaybackCoordinator.release(this);
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isInitialized = false;
            _hasError = true;
          });
        }
      }
    }
  }

  void _onPlayerStateChanged() {
    final controller = _controller;
    if (mounted && controller != null) {
      setState(() {
        _isPlaying = controller.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _MomentVideoPlaybackCoordinator.release(this);
    _releaseController(notify: false);
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    HapticFeedback.selectionClick();
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      _MomentVideoPlaybackCoordinator.activate(this);
      await controller.play();
    }
  }

  void _releaseFromCoordinator() {
    _releaseController();
  }

  void _releaseController({bool notify = true}) {
    _controllerGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (_listenerAttached) {
        controller.removeListener(_onPlayerStateChanged);
      }
      unawaited(_pauseAndDispose(controller));
    }
    _listenerAttached = false;
    _isInitialized = false;
    _isInitializing = false;
    _isPlaying = false;
    _showControls = true;
    if (notify && mounted) {
      setState(() {});
    }
  }

  Future<void> _pauseAndDispose(VideoPlayerController controller) async {
    try {
      await controller.pause();
    } catch (_) {
      // The controller may still be initializing when it leaves the viewport.
    }
    await controller.dispose();
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    if (info.visibleFraction <= 0.01 &&
        (_controller != null || _isInitializing)) {
      _MomentVideoPlaybackCoordinator.release(this);
      _releaseController();
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final Widget content;
    if (!_isInitialized || controller == null) {
      content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _initializeAndPlay,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.thumbnailUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: widget.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 200,
                      memCacheWidth: 400,
                      memCacheHeight: 400,
                      placeholder: (_, __) => Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.black26,
                        child: const Icon(
                          Icons.videocam_off,
                          color: Colors.white54,
                          size: 40,
                        ),
                      ),
                      fadeInDuration: const Duration(milliseconds: 200),
                    ),
                  ),
                if (_isInitializing)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _hasError
                          ? Icons.refresh_rounded
                          : Icons.play_arrow_rounded,
                      size: 38,
                      color: Colors.white,
                    ),
                  ),
                if (_hasError)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      _momentsText(
                        context,
                        zhCN: '视频加载失败，点击重试',
                        zhTW: '影片載入失敗，點擊重試',
                        en: 'Failed to load. Tap to retry.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ));
    } else {
      content = GestureDetector(
        onTap: _toggleControls,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 视频画面
                VideoPlayer(controller),

                // 播放/暂停按钮
                if (_showControls || !_isPlaying)
                  GestureDetector(
                    onTap: () => _togglePlay(),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),

                // 进度条
                if (_showControls)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black54, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _formatDuration(controller.value.position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: controller.value.position.inMilliseconds
                                  .toDouble(),
                              max: controller.value.duration.inMilliseconds
                                  .toDouble(),
                              activeColor: AppColors.primaryFor(context),
                              inactiveColor: Colors.white38,
                              onChanged: (value) {
                                controller.seekTo(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                          Text(
                            _formatDuration(controller.value.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
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

    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _handleVisibilityChanged,
      child: content,
    );
  }

  String _formatDuration(Duration duration) {
    final min = duration.inMinutes;
    final sec = duration.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

/// 举报选项
class _ReportOption extends StatelessWidget {
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  const _ReportOption({
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppColors.dividerFor(context),
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
      ),
    );
  }
}

/// 选项列表项
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final bool isDestructive;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.isDark,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? AppColors.error : AppColors.textPrimaryFor(context);

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

/// 发布动态页面 -  （全屏页面）
class MomentPublishPage extends ConsumerStatefulWidget {
  final bool isDark;
  final bool isDesktopPanel;

  const MomentPublishPage({
    super.key,
    required this.isDark,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<MomentPublishPage> createState() => _MomentPublishPageState();
}

class _MomentPublishPageState extends ConsumerState<MomentPublishPage> {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  MomentVisibility _visibility = MomentVisibility.public;
  final List<String> _selectedTopics = [];

  // 本地文件列表
  final List<XFile> _localImages = [];
  XFile? _localVideo;
  Uint8List? _videoThumbnail; // 视频缩略图

  // Live Photo 数据 (key: 图片路径, value: 视频路径)
  final Map<String, String> _livePhotoVideos = {};

  // 已上传的URL列表
  final List<String> _uploadedUrls = [];

  bool _isPublishing = false;
  bool _isUploading = false;
  String? _uploadingStatus;
  bool _showEmojiPicker = false;
  bool? _publishReviewEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadPublishSettings();
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      _contentController.text.isNotEmpty ||
      _localImages.isNotEmpty ||
      _localVideo != null;
  bool get _hasMedia => _localImages.isNotEmpty || _localVideo != null;

  Future<void> _loadPublishSettings() async {
    try {
      final settings = await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _publishReviewEnabled = settings.momentPostReviewEnabled;
      });
    } catch (e) {
      debugPrint('[Publish] Load publish settings failed: $e');
    }
  }

  Future<bool> _canPublishMoment() async {
    final settings = await ref
        .read(systemSettingsServiceProvider)
        .getSettings(forceRefresh: true);
    return settings.enableMomentPost;
  }

  // 选择图片（支持多选，包含照片和实况照片）
  Future<void> _pickImages() async {
    if (_localVideo != null) {
      _showMediaTypeTip();
      return;
    }

    // 请求权限
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _momentsText(
                context,
                zhCN: '需要相册权限才能选择图片',
                zhTW: '需要相簿權限才能選擇圖片',
                en: 'Photo library permission is required to select images',
              ),
            ),
          ),
        );
      }
      return;
    }

    // 打开自定义媒体选择器
    final result = await Navigator.of(context).push<List<_SelectedMedia>>(
      MaterialPageRoute(
        builder: (context) => _MediaPickerPage(
          isDark: widget.isDark,
          maxCount: 9 - _localImages.length,
          allowVideo: false,
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      for (final media in result) {
        _localImages.add(XFile(media.filePath));
        if (media.livePhotoVideoPath != null) {
          _livePhotoVideos[media.filePath] = media.livePhotoVideoPath!;
        }
      }
      setState(() {});
      HapticFeedback.mediumImpact();
    }
  }

  // 拍照（直接打开相机）
  Future<void> _takePhoto() async {
    if (_localVideo != null) {
      _showMediaTypeTip();
      return;
    }

    if (_localImages.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _momentsText(
              context,
              zhCN: '最多只能添加9张图片',
              zhTW: '最多只能新增 9 張圖片',
              en: 'You can add up to 9 images',
            ),
          ),
        ),
      );
      return;
    }

    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        setState(() {
          _localImages.add(image);
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('[Publish] Take photo error: $e');
    }
  }

  // 选择视频（直接从相册选择）
  Future<void> _pickVideo() async {
    final settings = ref.read(systemSettingsProvider).valueOrNull;
    final videoAllowed =
        !Platform.isIOS || (settings?.iosCompliance.allowsMomentVideo ?? false);
    if (!videoAllowed) {
      return;
    }

    if (_localImages.isNotEmpty) {
      _showMediaTypeTip();
      return;
    }

    // 请求权限
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _momentsText(
                context,
                zhCN: '需要相册权限才能选择视频',
                zhTW: '需要相簿權限才能選擇影片',
                en: 'Photo library permission is required to select videos',
              ),
            ),
          ),
        );
      }
      return;
    }

    // 打开视频选择器
    final result = await Navigator.of(context).push<List<_SelectedMedia>>(
      MaterialPageRoute(
        builder: (context) => _MediaPickerPage(
          isDark: widget.isDark,
          maxCount: 1,
          allowVideo: true,
          videoOnly: true,
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      final videoPath = result.first.filePath;
      setState(() {
        _localVideo = XFile(videoPath);
      });
      HapticFeedback.mediumImpact();

      // 自动生成缩略图
      _generateVideoThumbnail(videoPath);
    }
  }

  /// 生成视频缩略图
  Future<void> _generateVideoThumbnail(String videoPath) async {
    try {
      final thumbnail = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 512,
        quality: 75,
      );

      if (mounted && thumbnail != null) {
        setState(() {
          _videoThumbnail = thumbnail;
        });
      }
    } catch (e) {
      debugPrint('[Publish] Generate thumbnail error: $e');
    }
  }

  void _showMediaTypeTip() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localVideo != null
              ? _momentsText(
                  context,
                  zhCN: '已选择视频，不能添加图片',
                  zhTW: '已選擇影片，不能新增圖片',
                  en: 'A video is already selected. You cannot add images',
                )
              : _momentsText(
                  context,
                  zhCN: '已选择图片，不能添加视频',
                  zhTW: '已選擇圖片，不能新增影片',
                  en: 'Images are already selected. You cannot add a video',
                ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 移除图片
  void _removeImage(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _localImages.removeAt(index);
    });
  }

  // 移除视频
  void _removeVideo() {
    HapticFeedback.selectionClick();
    setState(() {
      _localVideo = null;
      _videoThumbnail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;
    final displayName = user?.nickname ??
        user?.username ??
        l10n.get('me') ??
        _momentsText(context, zhCN: '我', zhTW: '我', en: 'Me');
    final avatar = user?.avatar;

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      body: Column(
        children: [
          // 顶部栏（含安全区）
          _buildTelegramHeader(displayName, avatar),

          // 主编辑区
          Expanded(
            child: GestureDetector(
              onTap: () {
                // 点击空白区域收起表情选择器和键盘
                if (_showEmojiPicker) {
                  setState(() => _showEmojiPicker = false);
                } else if (_focusNode.hasFocus) {
                  _focusNode.unfocus();
                } else {
                  _focusNode.requestFocus();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 编辑区域
                    _buildEditArea(),

                    // 媒体预览（图片九宫格或视频）
                    if (_hasMedia) _buildMediaPreview(),

                    // 上传状态
                    if (_isUploading) _buildUploadingStatus(),

                    // 已选话题
                    if (_selectedTopics.isNotEmpty) _buildSelectedTopics(),
                  ],
                ),
              ),
            ),
          ),

          // 底部工具栏
          _buildTelegramToolbar(bottomInset),

          // 表情选择器
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _showEmojiPicker
                ? TGEmojiPicker(
                    height: 260,
                    onEmojiSelected: (emoji, {bool isAnimated = false}) {
                      if (emoji == 'BACKSPACE') {
                        final text = _contentController.text;
                        final selection = _contentController.selection;
                        if (text.isNotEmpty && selection.baseOffset > 0) {
                          final beforeCursor = text.substring(
                            0,
                            selection.baseOffset,
                          );
                          final afterCursor = text.substring(
                            selection.baseOffset,
                          );
                          int deleteCount = 1;
                          if (beforeCursor.isNotEmpty) {
                            final lastChar = beforeCursor.characters.last;
                            deleteCount = lastChar.length;
                          }
                          final newText = beforeCursor.substring(
                                0,
                                beforeCursor.length - deleteCount,
                              ) +
                              afterCursor;
                          _contentController.text = newText;
                          _contentController.selection =
                              TextSelection.collapsed(
                            offset: selection.baseOffset - deleteCount,
                          );
                        }
                      } else {
                        final text = _contentController.text;
                        final selection = _contentController.selection;
                        final start =
                            (selection.isValid && selection.start >= 0)
                                ? selection.start
                                : text.length;
                        final end = (selection.isValid && selection.end >= 0)
                            ? selection.end
                            : text.length;
                        final newText = text.replaceRange(start, end, emoji);
                        _contentController.text = newText;
                        _contentController.selection = TextSelection.collapsed(
                          offset: start + emoji.length,
                        );
                      }
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTelegramHeader(String displayName, String? avatar) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundFor(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Row(
                children: [
                  // 返回按钮
                  IconButton(
                    onPressed: () {
                      if (widget.isDesktopPanel) {
                        ref.read(desktopProfileProvider.notifier).state =
                            DesktopProfileInfo.none;
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textSecondaryFor(context),
                      size: 22,
                    ),
                  ),

                  // 标题
                  Expanded(
                    child: Text(
                      _momentsText(
                        context,
                        zhCN: '发布动态',
                        zhTW: '發佈動態',
                        en: 'Post Moment',
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                  ),

                  // 发布按钮 - TG 风格
                  GestureDetector(
                    onTap: _canPublish && !_isPublishing ? _publish : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _canPublish
                            ? AppColors.primaryFor(context)
                            : (widget.isDark
                                ? AppColors.darkControlBackground
                                : Colors.black.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _isPublishing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _momentsText(
                                context,
                                zhCN: '发布',
                                zhTW: '發佈',
                                en: 'Post',
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _canPublish
                                    ? AppColors.onPrimaryFor(context)
                                    : (widget.isDark
                                        ? AppColors.textTertiaryFor(context)
                                        : Colors.black26),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // 用户信息栏
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  // 头像 - 使用 AvatarWidget
                  AvatarWidget(name: displayName, avatar: avatar, size: 46),
                  const SizedBox(width: 14),

                  // 用户名和可见性
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: _showVisibilityPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryWithOpacity(context, 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _visibility.icon,
                                  size: 14,
                                  color: AppColors.linkFor(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _visibility.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.linkFor(context),
                                  ),
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: AppColors.linkFor(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_publishReviewEnabled != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: (_publishReviewEnabled == true
                                      ? Colors.orange
                                      : Colors.green)
                                  .withOpacity(widget.isDark ? 0.16 : 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (_publishReviewEnabled == true
                                        ? Colors.orange
                                        : Colors.green)
                                    .withOpacity(0.22),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _publishReviewEnabled == true
                                      ? Icons.schedule_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 14,
                                  color: _publishReviewEnabled == true
                                      ? Colors.orangeAccent
                                      : Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _publishReviewEnabled == true
                                      ? _momentsText(
                                          context,
                                          zhCN: '当前发布后需要审核',
                                          zhTW: '目前發佈後需要審核',
                                          en: 'Posts currently require review',
                                        )
                                      : _momentsText(
                                          context,
                                          zhCN: '当前发布后将直接显示',
                                          zhTW: '目前發佈後將直接顯示',
                                          en: 'Posts will appear immediately',
                                        ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _publishReviewEnabled == true
                                        ? (widget.isDark
                                            ? Colors.orange[200]
                                            : Colors.orange[800])
                                        : (widget.isDark
                                            ? Colors.green[200]
                                            : Colors.green[800]),
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildEditArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: TextField(
        controller: _contentController,
        focusNode: _focusNode,
        maxLines: null,
        minLines: 5,
        onChanged: (_) => setState(() {}),
        onTap: () {
          if (_showEmojiPicker) {
            setState(() => _showEmojiPicker = false);
          }
        },
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: _momentsText(
            context,
            zhCN: '分享你的想法...',
            zhTW: '分享你的想法...',
            en: 'Share your thoughts...',
          ),
          hintStyle: TextStyle(
            fontSize: 16,
            color: AppColors.textTertiaryFor(context),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  /// 媒体预览（图片九宫格或视频）
  Widget _buildMediaPreview() {
    if (_localVideo != null) {
      return _buildVideoPreview();
    }
    return _buildImagesGrid();
  }

  /// 图片九宫格预览
  Widget _buildImagesGrid() {
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = screenWidth - 32; // padding
    final count = _localImages.length;

    // 根据数量确定布局
    int crossAxisCount;
    double itemSize;

    if (count == 1) {
      crossAxisCount = 1;
      itemSize = gridWidth * 0.7;
    } else if (count == 2) {
      crossAxisCount = 2;
      itemSize = (gridWidth - 4) / 2;
    } else if (count == 4) {
      crossAxisCount = 2;
      itemSize = (gridWidth - 4) / 2;
    } else {
      crossAxisCount = 3;
      itemSize = (gridWidth - 8) / 3;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: _localImages.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          final isLivePhoto = _livePhotoVideos.containsKey(file.path);
          final imgWidth = count == 1 ? itemSize : itemSize.clamp(80.0, 150.0);
          final imgHeight =
              count == 1 ? itemSize * 0.75 : itemSize.clamp(80.0, 150.0);

          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isLivePhoto
                    ? _LivePhotoPreview(
                        imagePath: file.path,
                        videoPath: _livePhotoVideos[file.path]!,
                        width: imgWidth,
                        height: imgHeight,
                      )
                    : Image.file(
                        File(file.path),
                        width: imgWidth,
                        height: imgHeight,
                        fit: BoxFit.cover,
                      ),
              ),

              // Live Photo 标识
              if (isLivePhoto)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.motion_photos_on,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _momentsText(
                            context,
                            zhCN: '实况',
                            zhTW: '實況',
                            en: 'Live',
                          ),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 删除按钮
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _removeImage(index),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // 图片序号（多图时显示）
              if (count > 1)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 视频预览
  Widget _buildVideoPreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: 200,
              color: Colors.black,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 视频缩略图
                  if (_videoThumbnail != null)
                    Image.memory(
                      _videoThumbnail!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 200,
                    )
                  else
                    Container(
                      color: widget.isDark ? Colors.white10 : Colors.black87,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white38,
                        ),
                      ),
                    ),

                  // 播放图标
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 40,
                      color: Colors.black87,
                    ),
                  ),

                  // 视频标签
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFor(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _momentsText(
                              context,
                              zhCN: '视频',
                              zhTW: '影片',
                              en: 'Video',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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

          // 删除按钮
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _removeVideo,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 20, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 上传状态指示器
  Widget _buildUploadingStatus() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryWithOpacity(context, 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  AppColors.primaryFor(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _uploadingStatus ??
                    _momentsText(
                      context,
                      zhCN: '正在上传...',
                      zhTW: '上傳中...',
                      en: 'Uploading...',
                    ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.linkFor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTopics() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _selectedTopics.map((topic) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryWithOpacity(context, 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#$topic',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.linkFor(context),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTopics.remove(topic));
                  },
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.linkFor(context),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTelegramToolbar(double bottomInset) {
    final hasImages = _localImages.isNotEmpty;
    final hasVideo = _localVideo != null;
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final videoAllowed =
        !Platform.isIOS || (settings?.iosCompliance.allowsMomentVideo ?? false);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundFor(context),
        border: Border(
          top: BorderSide(color: AppColors.dividerFor(context)),
        ),
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: _showEmojiPicker
            ? 8
            : (bottomInset > 0 ? 8 : MediaQuery.of(context).padding.bottom + 8),
      ),
      child: Row(
        children: [
          // 表情按钮
          _TelegramToolButton(
            icon: _showEmojiPicker
                ? Icons.keyboard_rounded
                : Icons.emoji_emotions_outlined,
            label: _momentsText(
              context,
              zhCN: '表情',
              zhTW: '表情',
              en: 'Emoji',
            ),
            isDark: widget.isDark,
            isSelected: _showEmojiPicker,
            onTap: () {
              HapticFeedback.selectionClick();
              if (!_showEmojiPicker) {
                _focusNode.unfocus();
              }
              setState(() => _showEmojiPicker = !_showEmojiPicker);
            },
          ),

          // 相册（选图片）
          _TelegramToolButton(
            icon: Icons.photo_library_rounded,
            label: hasImages
                ? '${_localImages.length}/9'
                : _momentsText(
                    context,
                    zhCN: '相册',
                    zhTW: '相簿',
                    en: 'Album',
                  ),
            isDark: widget.isDark,
            disabled: hasVideo,
            onTap: _pickImages,
          ),

          // 相机
          _TelegramToolButton(
            icon: Icons.camera_alt_rounded,
            label: _momentsText(
              context,
              zhCN: '拍照',
              zhTW: '拍照',
              en: 'Camera',
            ),
            isDark: widget.isDark,
            disabled: hasVideo || _localImages.length >= 9,
            onTap: _takePhoto,
          ),

          // 视频
          if (videoAllowed)
            _TelegramToolButton(
              icon: Icons.videocam_rounded,
              label: hasVideo
                  ? _momentsText(
                      context,
                      zhCN: '已选',
                      zhTW: '已選',
                      en: 'Selected',
                    )
                  : _momentsText(
                      context,
                      zhCN: '视频',
                      zhTW: '影片',
                      en: 'Video',
                    ),
              isDark: widget.isDark,
              disabled: hasImages,
              onTap: _pickVideo,
            ),

          // 话题
          _TelegramToolButton(
            icon: Icons.tag_rounded,
            label: _momentsText(
              context,
              zhCN: '话题',
              zhTW: '話題',
              en: 'Topic',
            ),
            isDark: widget.isDark,
            onTap: _showTopicPicker,
          ),

          // @
          _TelegramToolButton(
            icon: Icons.alternate_email_rounded,
            label: '@',
            isDark: widget.isDark,
            onTap: () {
              HapticFeedback.selectionClick();
              final text = _contentController.text;
              final selection = _contentController.selection;
              final start = (selection.isValid && selection.start >= 0)
                  ? selection.start
                  : text.length;
              final end = (selection.isValid && selection.end >= 0)
                  ? selection.end
                  : text.length;
              final newText = text.replaceRange(start, end, '@');
              _contentController.text = newText;
              _contentController.selection = TextSelection.collapsed(
                offset: start + 1,
              );
            },
          ),

          const Spacer(),

          // 媒体数量统计
          if (_hasMedia)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryWithOpacity(context, 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasVideo ? Icons.videocam : Icons.photo,
                    size: 16,
                    color: AppColors.primaryFor(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasVideo ? '1' : '${_localImages.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryFor(context),
                    ),
                  ),
                ],
              ),
            ),

          // 字数统计
          if (_contentController.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_contentController.text.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _publish() async {
    if (!_canPublish || _isPublishing) return;

    final canPublishMoment = await _canPublishMoment();
    if (!mounted) return;
    if (!canPublishMoment) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _momentsText(
              context,
              zhCN: '广场发布功能已关闭，仅支持浏览',
              zhTW: '廣場發佈功能已關閉，僅支援瀏覽',
              en: 'Posting is disabled. Browse only.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isPublishing = true;
      _isUploading = _hasMedia;
    });
    HapticFeedback.mediumImpact();

    List<String> uploadedUrls = [];
    MomentContentType contentType = MomentContentType.text;
    String? videoThumbnailUrl;

    debugPrint(
      '[Publish] Starting publish: images=${_localImages.length}, video=${_localVideo != null}',
    );

    try {
      final api = ref.read(apiClientProvider);
      final uploadService = UploadService(api);

      // 上传图片
      if (_localImages.isNotEmpty) {
        setState(
          () => _uploadingStatus = _momentsText(
            context,
            zhCN: '正在上传图片 (0/${_localImages.length})...',
            zhTW: '正在上傳圖片 (0/${_localImages.length})...',
            en: 'Uploading images (0/${_localImages.length})...',
          ),
        );
        debugPrint('[Publish] Uploading ${_localImages.length} images...');

        for (int i = 0; i < _localImages.length; i++) {
          if (!mounted) return;
          setState(
            () => _uploadingStatus = _momentsText(
              context,
              zhCN: '正在上传图片 (${i + 1}/${_localImages.length})...',
              zhTW: '正在上傳圖片 (${i + 1}/${_localImages.length})...',
              en: 'Uploading images (${i + 1}/${_localImages.length})...',
            ),
          );

          final url = await uploadService.uploadImage(_localImages[i]);
          debugPrint('[Publish] Image ${i + 1} upload result: $url');
          if (url != null) {
            uploadedUrls.add(url);
          } else {
            debugPrint(
              '[Publish] Warning: Image ${i + 1} upload returned null',
            );
          }
        }
        contentType = MomentContentType.image;
        debugPrint(
          '[Publish] All images uploaded: ${uploadedUrls.length} successful',
        );
      }

      // 上传视频
      if (_localVideo != null) {
        // 先上传缩略图
        if (_videoThumbnail != null) {
          setState(
            () => _uploadingStatus = _momentsText(
              context,
              zhCN: '正在上传缩略图...',
              zhTW: '正在上傳縮圖...',
              en: 'Uploading thumbnail...',
            ),
          );
          videoThumbnailUrl = await uploadService.uploadImageData(
            _videoThumbnail!,
            'video_thumb.jpg',
          );
        }

        setState(
          () => _uploadingStatus = _momentsText(
            context,
            zhCN: '正在上传视频...',
            zhTW: '正在上傳影片...',
            en: 'Uploading video...',
          ),
        );

        final url = await uploadService.uploadVideo(_localVideo!);
        if (url != null) {
          uploadedUrls.add(url);
        }
        contentType = MomentContentType.video;
      }

      setState(() {
        _isUploading = false;
        _uploadingStatus = null;
      });
    } catch (e) {
      debugPrint('[Publish] Upload error: $e');
      setState(() {
        _isPublishing = false;
        _isUploading = false;
        _uploadingStatus = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _momentsText(
                context,
                zhCN: '上传失败，请重试',
                zhTW: '上傳失敗，請重試',
                en: 'Upload failed. Please try again.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    // 从内容中提取话题
    final topicRegex = RegExp(r'#(\S+)');
    final topics = topicRegex
        .allMatches(_contentController.text)
        .map((m) => m.group(1)!)
        .toList();

    debugPrint(
      '[Publish] Calling publishMoment: contentType=$contentType, urlCount=${uploadedUrls.length}',
    );

    final success = await ref.read(momentProvider.notifier).publishMoment(
          content: _contentController.text,
          contentType: contentType,
          mediaUrls: uploadedUrls,
          videoThumbnail: videoThumbnailUrl,
          topics: [..._selectedTopics, ...topics],
          visibility: _visibility,
        );

    if (mounted) {
      setState(() => _isPublishing = false);

      if (success) {
        final momentState = ref.read(momentProvider);
        final successMessage = momentState.successMessage;
        final overlay = Overlay.of(context, rootOverlay: true);
        if (successMessage == null) {
          if (widget.isDesktopPanel) {
            // 桌面面板模式：发布成功后展示刚发布的动态详情，而非空白页
            final moments = momentState.moments;
            if (moments.isNotEmpty) {
              ref.read(desktopProfileProvider.notifier).state =
                  DesktopProfileInfo(
                type: DesktopPanelType.momentDetail,
                id: moments.first.id,
                momentData: moments.first,
              );
            } else {
              ref.read(desktopProfileProvider.notifier).state =
                  DesktopProfileInfo.none;
            }
          } else {
            Navigator.pop(context);
          }
          _showSuccessOverlay(overlay);
        } else {
          if (widget.isDesktopPanel) {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          } else {
            Navigator.pop(context);
          }
          ref.read(momentProvider.notifier).clearPublishFeedback();
          final isReviewMessage = successMessage.contains('审核');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              behavior: SnackBarBehavior.floating,
              backgroundColor:
                  isReviewMessage ? Colors.orangeAccent : Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        final errMsg = ref.read(momentProvider).error ??
            _momentsText(
              context,
              zhCN: '发布失败，请重试',
              zhTW: '發布失敗，請重試',
              en: 'Failed to publish. Please try again.',
            );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  /// 显示发布成功的动态提示
  void _showSuccessOverlay(OverlayState overlay) {
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _SuccessOverlay(onDismiss: () => entry.remove()),
    );

    overlay.insert(entry);
  }

  void _showVisibilityPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _momentsText(
                    context,
                    zhCN: '谁可以看',
                    zhTW: '誰可以看',
                    en: 'Who can view this',
                  ),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),

              ...MomentVisibility.values.map(
                (v) => _TelegramVisibilityOption(
                  visibility: v,
                  isSelected: _visibility == v,
                  isDark: widget.isDark,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _visibility = v);
                    Navigator.pop(context);
                  },
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showTopicPicker() {
    HapticFeedback.selectionClick();
    final hotTopics = ref.read(momentProvider).hotTopics;
    final customTopicController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.6,
            decoration: BoxDecoration(
              color: AppColors.cardFor(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // 拖动指示器
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.dividerFor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // 标题栏
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        _momentsText(
                          context,
                          zhCN: '添加话题',
                          zhTW: '新增話題',
                          en: 'Add Topic',
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? AppColors.darkControlBackgroundStrong
                                : Colors.black.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 自定义话题输入
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? AppColors.darkControlBackground
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: TextField(
                            controller: customTopicController,
                            style: TextStyle(
                              fontSize: 15,
                              color: AppColors.textPrimaryFor(context),
                            ),
                            decoration: InputDecoration(
                              hintText: _momentsText(
                                context,
                                zhCN: '输入自定义话题',
                                zhTW: '輸入自訂話題',
                                en: 'Enter a custom topic',
                              ),
                              hintStyle: TextStyle(
                                fontSize: 15,
                                color: AppColors.textTertiaryFor(context),
                              ),
                              prefixIcon: Icon(
                                Icons.tag,
                                size: 20,
                                color: AppColors.textTertiaryFor(context),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                final topicName = value.trim().replaceAll(
                                      '#',
                                      '',
                                    );
                                if (!_selectedTopics.contains(topicName)) {
                                  setState(
                                    () => _selectedTopics.add(topicName),
                                  );
                                }
                                Navigator.pop(ctx);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          final value = customTopicController.text.trim();
                          if (value.isNotEmpty) {
                            final topicName = value.replaceAll('#', '');
                            if (!_selectedTopics.contains(topicName)) {
                              setState(() => _selectedTopics.add(topicName));
                            }
                            Navigator.pop(ctx);
                          }
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.primaryFor(context),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Center(
                            child: Text(
                              _momentsText(
                                context,
                                zhCN: '添加',
                                zhTW: '新增',
                                en: 'Add',
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onPrimaryFor(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Divider(
                  height: 1,
                  color: AppColors.dividerFor(context),
                ),

                // 热门话题
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 18,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _momentsText(
                              context,
                              zhCN: '热门话题',
                              zhTW: '熱門話題',
                              en: 'Trending Topics',
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (hotTopics.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              _momentsText(
                                context,
                                zhCN: '暂无热门话题，快来创建吧！',
                                zhTW: '暫無熱門話題，快來建立吧！',
                                en: 'No trending topics yet. Create one now.',
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textTertiaryFor(context),
                              ),
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 12,
                          children: hotTopics.map((topic) {
                            final isSelected = _selectedTopics.contains(
                              topic.name,
                            );
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                if (!isSelected) {
                                  setState(
                                    () => _selectedTopics.add(topic.name),
                                  );
                                }
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryWithOpacity(
                                          context,
                                          0.15,
                                        )
                                      : (widget.isDark
                                          ? AppColors.darkControlBackground
                                          : Colors.black.withOpacity(0.04)),
                                  borderRadius: BorderRadius.circular(20),
                                  border: isSelected
                                      ? Border.all(
                                          color: AppColors.primaryWithOpacity(
                                            context,
                                            0.5,
                                          ),
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '#${topic.name}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: isSelected
                                            ? AppColors.linkFor(context)
                                            : AppColors.textPrimaryFor(
                                                context,
                                              ),
                                      ),
                                    ),
                                    if (topic.isHot) ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        '🔥',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                    if (topic.postCount > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '${topic.postCount}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textTertiaryFor(
                                              context),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 发布成功动态提示
class _SuccessOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const _SuccessOverlay({required this.onDismiss});

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<_SuccessOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // 自动消失
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lottie 动画表情 ✨ - 无背景
              SizedBox(
                width: 120,
                height: 120,
                child: WebSafeLottie.asset(
                  'assets/emoji/lottie/sparkles.json',
                  repeat: true,
                  animate: true,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _momentsText(
                    context,
                    zhCN: '发布成功',
                    zhTW: '發佈成功',
                    en: 'Posted successfully',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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
}

/// 工具按钮
class _TelegramToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final bool disabled;
  final bool isSelected;

  const _TelegramToolButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.disabled = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? AppColors.textTertiaryFor(context)
        : isSelected
            ? AppColors.linkFor(context)
            : AppColors.textSecondaryFor(context);
    final labelColor = disabled
        ? AppColors.textTertiaryFor(context)
        : isSelected
            ? AppColors.linkFor(context)
            : AppColors.textTertiaryFor(context);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 可见性选项
class _TelegramVisibilityOption extends StatelessWidget {
  final MomentVisibility visibility;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _TelegramVisibilityOption({
    required this.visibility,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  String _description(BuildContext context) {
    switch (visibility) {
      case MomentVisibility.public:
        return _momentsText(
          context,
          zhCN: '所有人都能看到',
          zhTW: '所有人都能看到',
          en: 'Visible to everyone',
        );
      case MomentVisibility.contacts:
        return _momentsText(
          context,
          zhCN: '仅你的联系人可见',
          zhTW: '僅你的聯絡人可見',
          en: 'Visible to your contacts only',
        );
      case MomentVisibility.selected:
        return _momentsText(
          context,
          zhCN: '选择可见的人',
          zhTW: '選擇可見的人',
          en: 'Choose who can view this',
        );
      case MomentVisibility.private:
        return _momentsText(
          context,
          zhCN: '仅自己可见',
          zhTW: '僅自己可見',
          en: 'Visible to yourself only',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryWithOpacity(context, 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryWithOpacity(context, 0.15)
                    : (isDark
                        ? AppColors.darkControlBackground
                        : Colors.black.withOpacity(0.04)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                visibility.icon,
                size: 22,
                color: isSelected
                    ? AppColors.linkFor(context)
                    : AppColors.textTertiaryFor(context),
              ),
            ),
            const SizedBox(width: 14),

            // 文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visibility.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? AppColors.linkFor(context)
                          : AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _description(context),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ],
              ),
            ),

            // 选中标识
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primaryFor(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: AppColors.onPrimaryFor(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 我的回复列表项
class _MyReplyTile extends StatelessWidget {
  final Comment comment;
  final bool isDark;

  const _MyReplyTile({required this.comment, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 回复内容
          Text(
            comment.content,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppColors.textPrimaryFor(context),
            ),
          ),
          const SizedBox(height: 10),
          // 时间和来源
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 14,
                color: AppColors.textTertiaryFor(context),
              ),
              const SizedBox(width: 4),
              Text(
                comment.timeAgo,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiaryFor(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.primaryWithOpacity(context, 0.15)
                      : AppColors.primaryWithOpacity(context, 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite,
                        size: 12, color: AppColors.primaryFor(context)),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likeCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryFor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 我的动态Tab内容
class _MyMomentsTab extends ConsumerStatefulWidget {
  final String type;
  final bool isDark;

  const _MyMomentsTab({required this.type, required this.isDark});

  @override
  ConsumerState<_MyMomentsTab> createState() => _MyMomentsTabState();
}

class _MyMomentsTabState extends ConsumerState<_MyMomentsTab>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _items = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  IconData get _emptyIcon {
    switch (widget.type) {
      case 'moments':
        return Icons.article_outlined;
      case 'likes':
        return Icons.favorite_outline;
      case 'replies':
        return Icons.chat_bubble_outline;
      default:
        return Icons.inbox_outlined;
    }
  }

  String get _emptyText {
    switch (widget.type) {
      case 'moments':
        return _momentsText(
          context,
          zhCN: '还没有发布任何动态',
          zhTW: '還沒有發佈任何動態',
          en: 'No moments published yet',
        );
      case 'likes':
        return _momentsText(
          context,
          zhCN: '还没有点赞任何动态',
          zhTW: '還沒有按讚任何動態',
          en: 'No liked moments yet',
        );
      case 'replies':
        return _momentsText(
          context,
          zhCN: '还没有回复任何评论',
          zhTW: '還沒有回覆任何評論',
          en: 'No replies yet',
        );
      default:
        return _momentsText(
          context,
          zhCN: '暂无内容',
          zhTW: '暫無內容',
          en: 'No content yet',
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiClientProvider);
      // 'replies' 在后端对应 /my/comments 接口
      final apiType = widget.type == 'replies' ? 'comments' : widget.type;
      final response = await api.get('/moment/my/$apiType');

      if (response.isSuccess && response.data != null) {
        // 后端统一返回 { list: [...], total, page } 格式
        final rawData = response.data;
        List dataList;
        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map && rawData['list'] != null) {
          dataList = rawData['list'] as List;
        } else {
          dataList = [];
        }
        setState(() {
          if (widget.type == 'moments' || widget.type == 'likes') {
            _items = dataList
                .map((e) => Moment.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            _items = dataList
                .map((e) => Comment.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint('加载数据失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = widget.isDark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          if (item is Moment) {
            return _MomentCard(
              moment: item,
              isDark: isDark,
              onLike: () =>
                  ref.read(momentProvider.notifier).toggleLike(item.id),
              onMore: () {},
              showModerationBadge: widget.type == 'moments',
              footer: widget.type == 'moments'
                  ? _MomentModerationFooter(moment: item, isDark: isDark)
                  : null,
            );
          } else if (item is Comment) {
            return _MyReplyTile(comment: item, isDark: isDark);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _emptyIcon,
              size: 36,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _emptyText,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentStatusBadge extends StatelessWidget {
  final Moment moment;
  final bool isDark;

  const _MomentStatusBadge({required this.moment, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isPending = moment.isPendingReview;
    final bgColor =
        isPending ? const Color(0xFFFFA726) : const Color(0xFFE5484D);
    final icon = isPending ? Icons.schedule_rounded : Icons.block_rounded;
    final label = isPending
        ? _momentsText(
            context,
            zhCN: '审核中',
            zhTW: '審核中',
            en: 'Under Review',
          )
        : _momentsText(
            context,
            zhCN: '未通过',
            zhTW: '未通過',
            en: 'Rejected',
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bgColor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: bgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: bgColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentModerationFooter extends StatelessWidget {
  final Moment moment;
  final bool isDark;

  const _MomentModerationFooter({required this.moment, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (!moment.isPendingReview && !moment.isHidden) {
      return const SizedBox.shrink();
    }

    final isPending = moment.isPendingReview;
    final bgColor = isPending
        ? Colors.orange.withOpacity(isDark ? 0.18 : 0.12)
        : Colors.red.withOpacity(isDark ? 0.18 : 0.10);
    final borderColor = isPending
        ? Colors.orange.withOpacity(0.35)
        : Colors.red.withOpacity(0.28);
    final textColor = isPending
        ? (isDark ? const Color(0xFFFFD08A) : const Color(0xFF9A5A00))
        : (isDark ? const Color(0xFFFFB4B4) : const Color(0xFFB42318));
    final icon =
        isPending ? Icons.schedule_rounded : Icons.report_gmailerrorred;
    final title = isPending
        ? _momentsText(
            context,
            zhCN: '审核中',
            zhTW: '審核中',
            en: 'Under Review',
          )
        : _momentsText(
            context,
            zhCN: '未通过审核',
            zhTW: '未通過審核',
            en: 'Review Rejected',
          );
    final detail = isPending
        ? _momentsText(
            context,
            zhCN: '内容审核通过后才会展示到广场',
            zhTW: '內容審核通過後才會顯示到廣場',
            en: 'This post will appear after review approval',
          )
        : (moment.moderationHint ??
            _momentsText(
              context,
              zhCN: '请修改内容后重新发布',
              zhTW: '請修改內容後重新發佈',
              en: 'Please revise the content and publish again',
            ));

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: textColor.withOpacity(0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 动态搜索页面
class MomentSearchPage extends ConsumerStatefulWidget {
  final bool isDark;
  final bool isDesktopPanel;

  const MomentSearchPage({
    super.key,
    required this.isDark,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<MomentSearchPage> createState() => _MomentSearchPageState();
}

class _MomentSearchPageState extends ConsumerState<MomentSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Moment> _searchResults = [];
  List<String> get _hotKeywords => _defaultMomentSearchKeywords(context);
  bool _isSearching = false;
  bool _hasSearched = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    if (keyword.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get(
        '/moment/search',
        queryParameters: {'keyword': keyword},
      );

      if (response.isSuccess && response.data != null) {
        // 后端返回 { list: [...], total: ..., page: ... }
        final rawData = response.data;
        List dataList;
        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map && rawData['list'] != null) {
          dataList = rawData['list'] as List;
        } else {
          dataList = [];
        }
        setState(() {
          _searchResults = dataList
              .map((e) => Moment.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('搜索失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: AppColors.textPrimaryFor(context),
            size: 20,
          ),
          onPressed: () {
            if (widget.isDesktopPanel) {
              ref.read(desktopProfileProvider.notifier).state =
                  DesktopProfileInfo.none;
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        titleSpacing: 0,
        title: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: AppColors.inputBackgroundFor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textPrimaryFor(context),
            ),
            decoration: InputDecoration(
              hintText: _momentsText(
                context,
                zhCN: '搜索动态、话题...',
                zhTW: '搜尋動態、話題...',
                en: 'Search moments or topics...',
              ),
              hintStyle: TextStyle(
                color: AppColors.textTertiaryFor(context),
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: AppColors.textTertiaryFor(context),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 18,
                            color: AppColors.textTertiaryFor(context),
                          ),
                          onPressed: () {
                            _debounceTimer?.cancel();
                            _searchController.clear();
                            setState(() {
                              _searchResults.clear();
                              _hasSearched = false;
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.linkFor(context),
                          ),
                          onPressed: () => _search(_searchController.text),
                        ),
                      ],
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (value) {
              setState(() {});
              // 防抖：停止输入 500ms 后自动搜索
              _debounceTimer?.cancel();
              if (value.trim().isNotEmpty) {
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  _search(value);
                });
              }
            },
            onSubmitted: _search,
          ),
        ),
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasSearched) {
      return _buildHotKeywords(isDark);
    }

    if (_searchResults.isEmpty) {
      return _buildEmptyResult(isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final moment = _searchResults[index];
        return _MomentCard(
          moment: moment,
          isDark: isDark,
          onLike: () => ref.read(momentProvider.notifier).toggleLike(moment.id),
          onMore: () {},
        );
      },
    );
  }

  Widget _buildHotKeywords(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 20,
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                _momentsText(
                  context,
                  zhCN: '热门搜索',
                  zhTW: '熱門搜尋',
                  en: 'Trending Searches',
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _hotKeywords.map((keyword) {
              return GestureDetector(
                onTap: () {
                  _searchController.text = keyword;
                  _search(keyword);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceFor(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.dividerFor(context)),
                  ),
                  child: Text(
                    '#$keyword',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 20,
                color: AppColors.textTertiaryFor(context),
              ),
              const SizedBox(width: 8),
              Text(
                _momentsText(
                  context,
                  zhCN: '搜索历史',
                  zhTW: '搜尋歷史',
                  en: 'Search History',
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _momentsText(
                context,
                zhCN: '暂无搜索历史',
                zhTW: '暫無搜尋歷史',
                en: 'No search history',
              ),
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResult(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 36,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _momentsText(
              context,
              zhCN: '未找到相关动态',
              zhTW: '未找到相關動態',
              en: 'No matching moments found',
            ),
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _momentsText(
              context,
              zhCN: '换个关键词试试吧',
              zhTW: '換個關鍵詞試試吧',
              en: 'Try a different keyword',
            ),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 动态通知页面（我的动态、点赞、评论）
class MomentNotificationsPage extends ConsumerStatefulWidget {
  final bool isDark;
  final bool isDesktopPanel;

  const MomentNotificationsPage({
    super.key,
    required this.isDark,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<MomentNotificationsPage> createState() =>
      _MomentNotificationsPageState();
}

class _MomentNotificationsPageState
    extends ConsumerState<MomentNotificationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _myMoments = [];
  List<dynamic> _myLikes = [];
  List<dynamic> _receivedNotifications = []; // 合并的通知（评论+点赞）
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    // 进入页面时清除未读计数
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(momentProvider.notifier).clearUnreadCount();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);

      final momentsRes = await api.get('/moment/my/moments');
      if (momentsRes.isSuccess) _myMoments = momentsRes.data?['list'] ?? [];

      final likesRes = await api.get('/moment/my/likes');
      if (likesRes.isSuccess) _myLikes = likesRes.data?['list'] ?? [];

      // 获取收到的评论
      final commentsRes = await api.get(
        '/moment/my/comments',
        queryParameters: {'type': 'all'},
      );
      final comments =
          commentsRes.isSuccess ? (commentsRes.data?['list'] ?? []) : [];

      // 获取收到的点赞
      final receivedLikesRes = await api.get('/moment/my/received-likes');
      final receivedLikes = receivedLikesRes.isSuccess
          ? (receivedLikesRes.data?['list'] ?? [])
          : [];

      // 合并并按时间排序
      final allNotifications = <dynamic>[...comments, ...receivedLikes];
      allNotifications.sort((a, b) {
        final aTime = a['created_at'] ?? '';
        final bTime = b['created_at'] ?? '';
        return bTime.compareTo(aTime); // 降序
      });
      _receivedNotifications = allNotifications;
    } catch (e) {
      debugPrint('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showClearConfirmDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: _momentsText(
        context,
        zhCN: '清除通知',
        zhTW: '清除通知',
        en: 'Clear notifications',
      ),
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withOpacity(0.6)
                        : Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.15)
                          : Colors.black.withOpacity(0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 图标
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.cleaning_services_rounded,
                            color: AppColors.error,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 标题
                        Text(
                          _momentsText(
                            context,
                            zhCN: '清除全部通知',
                            zhTW: '清除全部通知',
                            en: 'Clear All Notifications',
                          ),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 内容
                        Text(
                          _momentsText(
                            context,
                            zhCN: '确定要清除所有收到的通知吗？\n此操作不可撤销。',
                            zhTW: '確定要清除所有收到的通知嗎？\n此操作不可撤銷。',
                            en: 'Clear all received notifications?\nThis action cannot be undone.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 按钮
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.2)
                                          : Colors.black.withOpacity(0.1),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _momentsText(
                                    context,
                                    zhCN: '取消',
                                    zhTW: '取消',
                                    en: 'Cancel',
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondaryFor(context),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _clearAllNotifications();
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  backgroundColor: AppColors.error,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _momentsText(
                                    context,
                                    zhCN: '清除',
                                    zhTW: '清除',
                                    en: 'Clear',
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _clearAllNotifications() {
    setState(() {
      _receivedNotifications.clear();
    });
    // TODO: 可以调用后端 API 标记所有通知为已读
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () {
            if (widget.isDesktopPanel) {
              ref.read(desktopProfileProvider.notifier).state =
                  DesktopProfileInfo.none;
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _momentsText(
            context,
            zhCN: '动态通知',
            zhTW: '動態通知',
            en: 'Moment Notifications',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          // 一键清除按钮
          if (_receivedNotifications.isNotEmpty)
            IconButton(
              onPressed: _showClearConfirmDialog,
              tooltip: _momentsText(
                context,
                zhCN: '清除全部',
                zhTW: '清除全部',
                en: 'Clear all',
              ),
              icon: Icon(
                Icons.cleaning_services_outlined,
                size: 22,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    return Column(
      children: [
        // Tab 切换（毛玻璃效果）
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceFor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.dividerFor(context)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: isDark
                        ? AppColors.darkControlBackgroundStrong
                        : Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: AppColors.textPrimaryFor(context),
                  unselectedLabelColor: AppColors.textTertiaryFor(context),
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                  ),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  tabs: [
                    Tab(
                      text: _momentsText(
                        context,
                        zhCN: '我的动态',
                        zhTW: '我的動態',
                        en: 'My Moments',
                      ),
                    ),
                    Tab(
                      text: _momentsText(
                        context,
                        zhCN: '我的点赞',
                        zhTW: '我的按讚',
                        en: 'My Likes',
                      ),
                    ),
                    Tab(
                      text: _momentsText(
                        context,
                        zhCN: '收到的',
                        zhTW: '收到的',
                        en: 'Received',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 内容
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMomentList(
                      _myMoments,
                      isDark,
                      _momentsText(
                        context,
                        zhCN: '暂无动态',
                        zhTW: '暫無動態',
                        en: 'No moments yet',
                      ),
                      isMyMoments: true,
                    ),
                    _buildMomentList(
                      _myLikes,
                      isDark,
                      _momentsText(
                        context,
                        zhCN: '暂无点赞',
                        zhTW: '暫無按讚',
                        en: 'No likes yet',
                      ),
                    ),
                    _buildNotificationList(
                      _receivedNotifications,
                      isDark,
                      _momentsText(
                        context,
                        zhCN: '暂无通知',
                        zhTW: '暫無通知',
                        en: 'No notifications yet',
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMomentList(
    List<dynamic> moments,
    bool isDark,
    String emptyText, {
    bool isMyMoments = false,
  }) {
    if (moments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: AppColors.textTertiaryFor(context),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: moments.length,
        itemBuilder: (context, index) => _NotificationMomentTile(
          moment: moments[index],
          isDark: isDark,
          showMoreButton: isMyMoments,
          onMore: isMyMoments
              ? () => _showMomentActions(moments[index], isDark)
              : null,
          onTap: () async {
            await _openMomentDetail(moments[index]);
            // 返回时刷新数据以获取最新点赞状态
            _loadData();
          },
        ),
      ),
    );
  }

  void _showMomentActions(dynamic moment, bool isDark) {
    final momentId = moment['id']?.toString() ?? moment['uuid'] ?? '';
    final visibility = moment['visibility'] ?? 1;
    final isPrivate = visibility == 4; // 4 = 仅自己可见

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 设为私密/公开
              ListTile(
                leading: Icon(
                  isPrivate ? Icons.public : Icons.lock_outline,
                  color: AppColors.linkFor(context),
                ),
                title: Text(
                  isPrivate
                      ? _momentsText(
                          context,
                          zhCN: '设为公开',
                          zhTW: '設為公開',
                          en: 'Set Public',
                        )
                      : _momentsText(
                          context,
                          zhCN: '设为私密',
                          zhTW: '設為私密',
                          en: 'Set Private',
                        ),
                  style: TextStyle(
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleMomentVisibility(momentId, isPrivate);
                },
              ),
              // 删除
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  _momentsText(
                    context,
                    zhCN: '删除动态',
                    zhTW: '刪除動態',
                    en: 'Delete Moment',
                  ),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMoment(momentId, isDark);
                },
              ),
              const SizedBox(height: 8),
              // 取消
              ListTile(
                title: Center(
                  child: Text(
                    _momentsText(
                      context,
                      zhCN: '取消',
                      zhTW: '取消',
                      en: 'Cancel',
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
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

  Future<void> _toggleMomentVisibility(
    String momentId,
    bool isCurrentlyPrivate,
  ) async {
    try {
      final api = ref.read(apiClientProvider);
      final newVisibility = isCurrentlyPrivate ? 1 : 4; // 1=公开, 4=私密
      final response = await api.put(
        '/moment/$momentId',
        data: {'visibility': newVisibility},
      );

      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCurrentlyPrivate
                  ? _momentsText(
                      context,
                      zhCN: '已设为公开',
                      zhTW: '已設為公開',
                      en: 'Set to public',
                    )
                  : _momentsText(
                      context,
                      zhCN: '已设为私密',
                      zhTW: '已設為私密',
                      en: 'Set to private',
                    ),
            ),
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _momentsServerMessage(
                response.message,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: 'Action failed',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '${_momentsText(
              context,
              zhCN: '操作失败',
              zhTW: '操作失敗',
              en: 'Action failed',
            )}: $e',
          ),
        ),
      );
    }
  }

  void _confirmDeleteMoment(String momentId, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _momentsText(
            context,
            zhCN: '确认删除',
            zhTW: '確認刪除',
            en: 'Confirm Delete',
          ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: Text(
          _momentsText(
            context,
            zhCN: '删除后无法恢复，确定要删除吗？',
            zhTW: '刪除後無法恢復，確定要刪除嗎？',
            en: 'This item cannot be restored after deletion. Delete it?',
          ),
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _momentsText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMoment(momentId);
            },
            child: Text(
              _momentsText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMoment(String momentId) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.delete('/moment/$momentId');

      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _momentsText(
                context,
                zhCN: '删除成功',
                zhTW: '刪除成功',
                en: 'Deleted successfully',
              ),
            ),
          ),
        );
        _loadData();
        // 同时刷新广场列表
        ref.read(momentProvider.notifier).refresh();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _momentsServerMessage(
                response.message,
                zhCN: '删除失败',
                zhTW: '刪除失敗',
                en: 'Delete failed',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '${_momentsText(
              context,
              zhCN: '删除失败',
              zhTW: '刪除失敗',
              en: 'Delete failed',
            )}: $e',
          ),
        ),
      );
    }
  }

  Widget _buildCommentList(
    List<dynamic> comments,
    bool isDark,
    String emptyText,
  ) {
    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: AppColors.textTertiaryFor(context),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: comments.length,
        itemBuilder: (context, index) => _NotificationCommentTile(
          comment: comments[index],
          isDark: isDark,
          onTap: () async {
            await _openCommentDetail(comments[index]);
            // 返回时刷新数据
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildNotificationList(
    List<dynamic> notifications,
    bool isDark,
    String emptyText,
  ) {
    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: AppColors.textTertiaryFor(context),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final item = notifications[index];
          final type = item['type'] ?? '';

          if (type == 'like') {
            // 点赞通知
            return _NotificationLikeTile(
              like: item,
              isDark: isDark,
              onTap: () async {
                await _openCommentDetail(item);
                _loadData();
              },
            );
          } else {
            // 评论通知
            return _NotificationCommentTile(
              comment: item,
              isDark: isDark,
              onTap: () async {
                await _openCommentDetail(item);
                _loadData();
              },
            );
          }
        },
      ),
    );
  }

  Future<void> _openMomentDetail(dynamic momentData) async {
    HapticFeedback.selectionClick();
    final moment = Moment.fromJson(Map<String, dynamic>.from(momentData));
    await Navigator.of(context).push(
      createPageRoute(builder: (context) => MomentDetailPage(moment: moment)),
    );
  }

  Future<void> _openCommentDetail(dynamic comment) async {
    HapticFeedback.selectionClick();
    final momentId = comment['moment_id'];
    if (momentId == null) return;

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/moment/$momentId/detail');

      if (response.isSuccess && response.data != null && mounted) {
        final moment = Moment.fromJson(
          Map<String, dynamic>.from(response.data),
        );
        await Navigator.of(context).push(
          createPageRoute(
            builder: (context) =>
                MomentDetailPage(moment: moment, showComments: true),
          ),
        );
      }
    } catch (e) {
      debugPrint('打开动态失败: $e');
    }
  }
}

/// 通知页动态卡片
class _NotificationMomentTile extends StatelessWidget {
  final dynamic moment;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onMore; // 三点菜单
  final bool showMoreButton; // 是否显示更多按钮

  const _NotificationMomentTile({
    required this.moment,
    required this.isDark,
    required this.onTap,
    this.onMore,
    this.showMoreButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = moment['content'] ?? '';
    final userName = moment['user_name'] ??
        _momentsText(context, zhCN: '用户', zhTW: '使用者', en: 'User');
    final rawAvatar = moment['user_avatar'] ?? '';
    // 转换头像 URL
    final userAvatar = rawAvatar.isNotEmpty
        ? (ApiConfig.getMediaUrl(rawAvatar) ?? rawAvatar)
        : '';
    final userId = moment['user_id']?.toString() ?? '';
    final likeCount = moment['like_count'] ?? 0;
    final commentCount = moment['comment_count'] ?? 0;
    final createdAt = moment['created_at'] ?? '';
    final visibility = moment['visibility'] ?? 1;
    final isPrivate = visibility == 4; // 4 = 仅自己可见

    // 处理 media_urls，可能是 List 也可能是 null，并转换 URL
    List<String> mediaUrls = [];
    final rawMedia = moment['media_urls'];
    if (rawMedia is List) {
      mediaUrls = rawMedia
          .map((url) => ApiConfig.getMediaUrl(url.toString()) ?? url.toString())
          .toList();
    }

    // 检测是否为视频
    final contentType = moment['content_type'] ?? 1;
    final isVideo = contentType == 3;
    final videoThumbnail = moment['video_thumbnail'];
    final thumbnailUrl =
        videoThumbnail != null && videoThumbnail.toString().isNotEmpty
            ? ApiConfig.getMediaUrl(videoThumbnail.toString())
            : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.15 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息
            Row(
              children: [
                AvatarWidget(
                  name: userName,
                  avatar: userAvatar,
                  userId: userId,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _formatTime(context, createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiaryFor(context),
                            ),
                          ),
                          // 私密标签
                          if (isPrivate) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock,
                                    size: 10,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _momentsText(
                                      context,
                                      zhCN: '私密',
                                      zhTW: '私密',
                                      en: 'Private',
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 三点菜单按钮
                if (showMoreButton && onMore != null)
                  GestureDetector(
                    onTap: onMore,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: AppColors.textTertiaryFor(context),
                      ),
                    ),
                  ),
              ],
            ),

            // 内容
            if (content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // 媒体预览
            if (isVideo && (thumbnailUrl != null || mediaUrls.isNotEmpty)) ...[
              // 视频缩略图
              const SizedBox(height: 10),
              Container(
                width: 120,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 缩略图
                      if (thumbnailUrl != null)
                        CachedNetworkImage(
                          imageUrl: thumbnailUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          memCacheHeight: 160,
                          placeholder: (_, __) => Container(
                            color: isDark ? Colors.white10 : Colors.black87,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: isDark ? Colors.white10 : Colors.black87,
                          ),
                          fadeInDuration: const Duration(milliseconds: 150),
                        )
                      else
                        Container(
                          color: isDark ? Colors.white10 : Colors.black87,
                        ),
                      // 播放图标
                      Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 24,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      // 视频标签
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryFor(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.videocam,
                                size: 10,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _momentsText(
                                  context,
                                  zhCN: '视频',
                                  zhTW: '影片',
                                  en: 'Video',
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
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
            ] else if (_getValidUrls(mediaUrls).isNotEmpty) ...[
              // 图片预览（过滤空URL）
              const SizedBox(height: 10),
              SizedBox(
                height: 60,
                child: Row(
                  children: _getValidUrls(mediaUrls).take(3).map((url) {
                    return Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(right: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          memCacheHeight: 120,
                          placeholder: (_, __) => Container(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withOpacity(0.05),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withOpacity(0.05),
                            child: Icon(
                              Icons.image,
                              size: 20,
                              color: AppColors.textTertiaryFor(context),
                            ),
                          ),
                          fadeInDuration: const Duration(milliseconds: 150),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // 互动数据
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.favorite,
                  size: 14,
                  color: Colors.red.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  '$likeCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.chat_bubble_outline,
                  size: 13,
                  color: AppColors.textTertiaryFor(context),
                ),
                const SizedBox(width: 4),
                Text(
                  '$commentCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    String name,
    String avatar,
    double size,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarColor =
        isDark ? AppColors.primaryDarkMode : AppColors.primaryLight;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withOpacity(0.1),
      ),
      child: avatar.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatar,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                memCacheHeight: 96,
                placeholder: (_, __) => _avatarText(name, avatarColor),
                errorWidget: (_, __, ___) => _avatarText(name, avatarColor),
                fadeInDuration: const Duration(milliseconds: 150),
              ),
            )
          : _avatarText(name, avatarColor),
    );
  }

  Widget _avatarText(String name, Color color) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// 过滤有效的图片URL，并补全相对路径
  List<String> _getValidUrls(List<dynamic> urls) {
    final serverUrl = ApiConfig.serverUrl;
    return urls
        .map((u) {
          var url = u.toString();
          if (url.isEmpty || url.length < 5) return '';
          // 如果是相对路径，补全服务器地址
          if (url.startsWith('/uploads/') || url.startsWith('uploads/')) {
            url = '$serverUrl$url';
          }
          // 替换本地开发地址为实际服务器地址
          final localDevUrl = String.fromCharCodes(const [
            104,
            116,
            116,
            112,
            58,
            47,
            47,
            108,
            111,
            99,
            97,
            108,
            104,
            111,
            115,
            116,
            58,
            56,
            48,
            56,
            48,
          ]);
          if (url.contains(localDevUrl)) {
            url = url.replaceAll(localDevUrl, serverUrl);
          }
          return url;
        })
        .where((url) => url.isNotEmpty)
        .toList();
  }

  String _formatTime(BuildContext context, String dateStr) {
    return _momentRelativeTime(context, dateStr);
  }
}

/// 通知页点赞卡片 - 简洁风格
class _NotificationLikeTile extends StatelessWidget {
  final dynamic like;
  final bool isDark;
  final VoidCallback onTap;

  const _NotificationLikeTile({
    required this.like,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final userName = like['user_name'] ?? '';
    final rawAvatar = like['user_avatar'] ?? '';
    // 转换头像 URL
    final userAvatar = rawAvatar.isNotEmpty
        ? (ApiConfig.getMediaUrl(rawAvatar) ?? rawAvatar)
        : '';
    final userId = like['user_id']?.toString() ?? '';
    final momentBrief = like['moment_brief'] ?? '';
    final createdAt = like['created_at'] ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 头像 + 爱心角标
            Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarWidget(
                  name: userName,
                  avatar: userAvatar,
                  userId: userId,
                  size: 44,
                ),
                // 爱心角标
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: userName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        TextSpan(
                          text: _momentsText(
                            context,
                            zhCN: ' 赞了你的动态',
                            zhTW: ' 讚了你的動態',
                            en: ' liked your moment',
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (momentBrief.isNotEmpty)
                    Text(
                      momentBrief,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // 时间
            Text(
              _formatTime(context, createdAt),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, String dateStr) {
    return _momentRelativeTime(context, dateStr);
  }
}

/// 通知页评论卡片
class _NotificationCommentTile extends StatelessWidget {
  final dynamic comment;
  final bool isDark;
  final VoidCallback onTap;

  const _NotificationCommentTile({
    required this.comment,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = comment['content'] ?? '';
    final userName = comment['user_name'] ?? '';
    final rawAvatar = comment['user_avatar'] ?? '';
    // 转换头像 URL
    final userAvatar = rawAvatar.isNotEmpty
        ? (ApiConfig.getMediaUrl(rawAvatar) ?? rawAvatar)
        : '';
    final userId = comment['user_id']?.toString() ?? '';
    final momentBrief = comment['moment_brief'] ?? '';
    final createdAt = comment['created_at'] ?? '';
    final type = comment['type'] ?? '';

    String typeLabel = '';
    Color typeColor = AppColors.primaryFor(context);
    if (type == 'received_comment') {
      typeLabel = _momentsText(
        context,
        zhCN: '评论了你的动态',
        zhTW: '評論了你的動態',
        en: 'commented on your moment',
      );
      typeColor = const Color(0xFF34C759);
    } else if (type == 'received_reply') {
      typeLabel = _momentsText(
        context,
        zhCN: '回复了你',
        zhTW: '回覆了你',
        en: 'replied to you',
      );
      typeColor = const Color(0xFF5856D6);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.15 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息
            Row(
              children: [
                AvatarWidget(
                  name: userName,
                  avatar: userAvatar,
                  userId: userId,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              userName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: typeColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatTime(context, createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 评论内容
            const SizedBox(height: 10),
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),

            // 原动态
            if (momentBrief.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: AppColors.primaryWithOpacity(context, 0.5),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  momentBrief,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, String dateStr) {
    return _momentRelativeTime(context, dateStr);
  }
}
