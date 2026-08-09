// 文件用途：实现 ChannelProfilePage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 ChannelProfilePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/utils/platform_utils.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/voice_playback_audio_context.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../providers/chat_provider.dart';
import '../../vip/widgets/vip_badge.dart';
import 'group_profile_page.dart' show GroupAutoMessagesPage;
import 'message_search_page.dart';
import 'report_page.dart';

String _channelProfileText(
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

String _channelServerMessage(
  String? raw, {
  required String fallbackEn,
}) {
  return localizeServerMessage(raw, fallbackEn: fallbackEn);
}

String _channelRelativeTimeText(BuildContext context, DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return _channelProfileText(
      context,
      zhCN: '刚刚',
      zhTW: '剛剛',
      en: 'Just now',
    );
  }
  if (diff.inHours < 1) {
    return _channelProfileText(
      context,
      zhCN: '${diff.inMinutes}分钟前',
      zhTW: '${diff.inMinutes}分鐘前',
      en: '${diff.inMinutes} min ago',
    );
  }
  if (diff.inDays < 1) {
    return _channelProfileText(
      context,
      zhCN: '${diff.inHours}小时前',
      zhTW: '${diff.inHours}小時前',
      en: '${diff.inHours} hr ago',
    );
  }
  if (diff.inDays < 7) {
    return _channelProfileText(
      context,
      zhCN: '${diff.inDays}天前',
      zhTW: '${diff.inDays}天前',
      en: '${diff.inDays} days ago',
    );
  }
  return _channelProfileText(
    context,
    zhCN: '${time.month}月${time.day}日',
    zhTW: '${time.month}月${time.day}日',
    en: '${time.month}/${time.day}',
  );
}

// 关键声明：channel profile page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 频道资料页面
class ChannelProfilePage extends ConsumerStatefulWidget {
  final String channelId;
  final String? name;
  final String? avatar;
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示

  const ChannelProfilePage({
    super.key,
    required this.channelId,
    this.name,
    this.avatar,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<ChannelProfilePage> createState() => _ChannelProfilePageState();
}

class _ChannelProfilePageState extends ConsumerState<ChannelProfilePage> {
  api.ChatMediaCounts? _mediaCounts;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadMediaCounts();
  }

  Future<void> _loadMediaCounts() async {
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getChatMediaCounts(widget.channelId);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _mediaCounts = response.data;
        });
      }
    } catch (e) {
      // 忽略错误
    }
  }

  Future<int> _loadJoinRequestCount() async {
    try {
      final response = await ref
          .read(api.chatServiceProvider)
          .getJoinRequests(widget.channelId);
      return response.data?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    // 频道详情中的 myRole 是订阅/管理权限的展示依据，接口仍负责最终鉴权。
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.channelId));
    final bgColor = AppColors.backgroundFor(context);
    final cardColor = AppColors.cardFor(context);
    final separatorColor = AppColors.dividerFor(context);

    Widget content = Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // iOS 风格导航栏
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surfaceFor(context),
            elevation: 0,
            scrolledUnderElevation: 0.5,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                size: 20,
                color: AppColors.primaryFor(context),
              ),
              onPressed: () {
                if (widget.isDesktopPanel) {
                  // 桌面面板模式：关闭资料页，返回聊天
                  ref.read(desktopProfileProvider.notifier).state =
                      DesktopProfileInfo.none;
                } else {
                  context.pop();
                }
              },
            ),
            actions: [
              chatDetailAsync.when(
                data: (chat) {
                  if (chat == null || chat.myRole < 1) {
                    return const SizedBox.shrink();
                  }
                  return FutureBuilder<int>(
                    future: _loadJoinRequestCount(),
                    builder: (context, snapshot) {
                      final pendingCount =
                          (chat.myRole >= 2 && chat.joinApproval)
                              ? (snapshot.data ?? 0)
                              : 0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.more_horiz,
                              color: AppColors.primaryFor(context),
                            ),
                            onPressed: () => _showMoreMenu(context, chat),
                          ),
                          if (pendingCount > 0)
                            Positioned(
                              right: 10,
                              top: 10,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.surfaceFor(context),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),

          // 头像和基本信息
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.surfaceFor(context),
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  // 频道头像
                  AvatarWidget(
                    avatar: widget.avatar,
                    name: widget.name ??
                        _channelProfileText(
                          context,
                          zhCN: '频道',
                          zhTW: '頻道',
                          en: 'Channel',
                        ),
                    size: 100,
                    borderRadius: 25,
                  ),
                  const SizedBox(height: 12),
                  // 频道名称 + 官方标识
                  Consumer(
                    builder: (context, ref, _) {
                      final officialChatsAsync =
                          ref.watch(officialChatsProvider);
                      final officialChats =
                          officialChatsAsync.valueOrNull ?? {};
                      final isOfficial =
                          officialChats.contains(widget.channelId);

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.name ??
                                _channelProfileText(
                                  context,
                                  zhCN: '频道',
                                  zhTW: '頻道',
                                  en: 'Channel',
                                ),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryFor(context),
                            ),
                          ),
                          if (isOfficial) ...[
                            const SizedBox(width: 6),
                            const OfficialBadge(size: 22),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  // 订阅者数
                  chatDetailAsync.when(
                    data: (chat) => Text(
                      _formatSubscriberCount(chat?.memberCount ?? 0),
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                    loading: () => Text(l10n.loading,
                        style: TextStyle(fontSize: 15, color: Colors.grey)),
                    error: (_, __) => Text(
                        _channelProfileText(
                          context,
                          zhCN: '频道',
                          zhTW: '頻道',
                          en: 'Channel',
                        ),
                        style: TextStyle(fontSize: 15, color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ),

          // 操作按钮
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.surfaceFor(context),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Consumer(
                builder: (context, ref, _) {
                  // 获取当前频道的静音状态
                  final chatListState = ref.watch(chatListProvider);
                  final allChats = chatListState.allChats;
                  final currentChat = allChats
                      .where((c) => c.id == widget.channelId)
                      .firstOrNull;
                  final isMuted = currentChat?.isMuted ?? false;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TGActionButton(
                        icon: isMuted
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        label: isMuted ? l10n.unmute : l10n.mute,
                        isActive: isMuted,
                        onTap: () {
                          GlobalHaptics.medium();
                          ref
                              .read(chatListProvider.notifier)
                              .toggleMute(widget.channelId);
                        },
                      ),
                      _TGActionButton(
                        icon: Icons.search,
                        label: l10n.search,
                        onTap: () => _searchMessages(context),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // 间距
          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 频道信息卡片
          SliverToBoxAdapter(
            child: _TGSection(
              cardColor: cardColor,
              separatorColor: separatorColor,
              children: [
                // 频道简介
                chatDetailAsync.when(
                  data: (chat) => _TGInfoCell(
                    title: chat?.description?.isNotEmpty == true
                        ? chat!.description!
                        : _channelProfileText(
                            context,
                            zhCN: '暂无简介',
                            zhTW: '暫無簡介',
                            en: 'No description',
                          ),
                    subtitle: l10n.description,
                  ),
                  loading: () => _TGInfoCell(
                      title: l10n.loading, subtitle: l10n.description),
                  error: (_, __) => _TGInfoCell(
                    title: _channelProfileText(
                      context,
                      zhCN: '暂无简介',
                      zhTW: '暫無簡介',
                      en: 'No description',
                    ),
                    subtitle: l10n.description,
                  ),
                ),
                // 频道号
                chatDetailAsync.when(
                  data: (chat) {
                    final username = chat?.username;
                    if (username == null || username.isEmpty)
                      return const SizedBox.shrink();
                    return _TGInfoCell(
                      title: '@$username',
                      subtitle: _channelProfileText(
                        context,
                        zhCN: '频道号',
                        zhTW: '頻道號',
                        en: 'Channel ID',
                      ),
                      titleColor: AppColors.linkFor(context),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '@$username'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _channelProfileText(
                                context,
                                zhCN: '频道号已复制',
                                zhTW: '頻道號已複製',
                                en: 'Channel ID copied',
                              ),
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 共享媒体
          SliverToBoxAdapter(
            child: _TGSection(
              cardColor: cardColor,
              separatorColor: separatorColor,
              children: [
                _TGCell(
                  icon: Icons.photo_outlined,
                  iconColor: AppColors.primaryFor(context),
                  title: l10n.get('photos_and_videos'),
                  trailing: _buildCountTrailing('${_mediaCounts?.media ?? 0}'),
                  onTap: () => _showMediaList(
                    context,
                    l10n.get('photos_and_videos'),
                    'media',
                  ),
                ),
                _TGCell(
                  icon: Icons.insert_drive_file_outlined,
                  iconColor: AppColors.primaryFor(context),
                  title: l10n.file,
                  trailing: _buildCountTrailing('${_mediaCounts?.file ?? 0}'),
                  onTap: () => _showMediaList(context, l10n.file, 'file'),
                ),
                _TGCell(
                  icon: Icons.link,
                  iconColor: AppColors.primaryFor(context),
                  title: l10n.get('shared_links'),
                  trailing: _buildCountTrailing('${_mediaCounts?.link ?? 0}'),
                  onTap: () =>
                      _showMediaList(context, l10n.get('shared_links'), 'link'),
                ),
                _TGCell(
                  icon: Icons.mic_outlined,
                  iconColor: AppColors.primaryFor(context),
                  title: l10n.get('voice_messages'),
                  trailing: _buildCountTrailing('${_mediaCounts?.voice ?? 0}'),
                  onTap: () => _showMediaList(
                    context,
                    l10n.get('voice_messages'),
                    'voice',
                  ),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 订阅者（仅管理员和创建者可见，类似 Telegram）
          chatDetailAsync.when(
            data: (chat) {
              // 普通订阅者不显示订阅者列表入口
              if (chat == null || chat.myRole < 2) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return SliverToBoxAdapter(
                child: _TGSection(
                  cardColor: cardColor,
                  separatorColor: separatorColor,
                  children: [
                    Column(
                      children: [
                        _TGCell(
                          icon: Icons.people_outline,
                          iconColor: Colors.green,
                          title: _channelProfileText(
                            context,
                            zhCN: '订阅者',
                            zhTW: '訂閱者',
                            en: 'Subscribers',
                          ),
                          trailing: _buildCountTrailing(
                              _formatSubscriberCount(chat.memberCount)),
                          onTap: () => _showSubscriberList(context),
                        ),
                        // 订阅请求（管理员可见且开启审批）
                        if (chat.joinApproval) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 56),
                            child: Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: separatorColor),
                          ),
                          _TGCell(
                            icon: Icons.how_to_reg_outlined,
                            iconColor: Colors.orange,
                            title: _channelProfileText(
                              context,
                              zhCN: '订阅请求',
                              zhTW: '訂閱請求',
                              en: 'Subscription Requests',
                            ),
                            trailing: _JoinRequestCountBadge(
                                chatId: widget.channelId),
                            onTap: () => _showJoinRequests(context),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 分享和举报
          SliverToBoxAdapter(
            child: _TGSection(
              cardColor: cardColor,
              separatorColor: separatorColor,
              children: [
                _TGCell(
                  icon: Icons.share_outlined,
                  iconColor: AppColors.primaryFor(context),
                  title: l10n.get('share_channel'),
                  onTap: () => _shareChannel(context),
                ),
                _TGCell(
                  title: l10n.report,
                  titleColor: Colors.red,
                  onTap: () => _showReportDialog(context),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 未订阅时显示订阅按钮（已订阅用户通过三点菜单取消订阅）
          chatDetailAsync.when(
            data: (chat) {
              // 已订阅的用户不显示（可以通过三点菜单取消订阅）
              if (chat != null && chat.myRole >= 1) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              // 未订阅 - 显示订阅按钮
              return SliverToBoxAdapter(
                child: _TGSection(
                  cardColor: cardColor,
                  separatorColor: separatorColor,
                  children: [
                    _TGCell(
                      title: l10n.get('subscribe_channel'),
                      titleColor: AppColors.linkFor(context),
                      onTap: () => _subscribeChannel(context),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );

    // 桌面端面板模式：直接返回内容（不重复包裹）
    if (widget.isDesktopPanel) {
      return content;
    }

    // 桌面端全屏模式：限制最大宽度并居中
    if (PlatformUtils.useDesktopLayout(context)) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: content,
          ),
        ),
      );
    }

    return content;
  }

  Widget _buildCountTrailing(String count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(count, style: TextStyle(color: Colors.grey, fontSize: 17)),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22),
      ],
    );
  }

  String _formatSubscriberCount(int count) {
    if (count >= 10000) {
      return AppLocalizations.of(context).language == AppLanguage.en
          ? '${(count / 1000).toStringAsFixed(1)}k'
          : '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '$count';
  }

  void _showMediaList(BuildContext context, String title, String type) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _MediaListPage(
          chatId: widget.channelId,
          title: title,
          type: type,
        ),
      ),
    );
  }

  void _showSubscriberList(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _SubscriberListPage(
          channelId: widget.channelId,
          channelName: widget.name ??
              _channelProfileText(
                context,
                zhCN: '频道',
                zhTW: '頻道',
                en: 'Channel',
              ),
        ),
      ),
    );
  }

  void _showFeatureNotAvailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
            _channelProfileText(
              context,
              zhCN: '$feature 功能暂未开放',
              zhTW: '$feature 功能暫未開放',
              en: '$feature is not available yet',
            ),
          ),
          duration: const Duration(seconds: 1)),
    );
  }

  void _searchMessages(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => MessageSearchPage(
          chatId: widget.channelId,
          chatName: widget.name ??
              _channelProfileText(
                context,
                zhCN: '频道',
                zhTW: '頻道',
                en: 'Channel',
              ),
          chatType: 'channel',
        ),
      ),
    );
  }

  void _shareChannel(BuildContext context) {
    final chat = ref.read(chatDetailProvider(widget.channelId)).value;
    final link = chat?.username?.isNotEmpty == true
        ? 't.me/${chat!.username}'
        : (chat?.inviteLink ?? '');

    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _channelProfileText(
            context,
            zhCN: '链接已复制，可以分享给好友',
            zhTW: '連結已複製，可以分享給好友',
            en: 'Link copied. Share it with your contacts.',
          ),
        ),
      ),
    );
  }

  /// 显示更多菜单（三点按钮）
  void _openAutoMessages(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => GroupAutoMessagesPage(
          chatId: widget.channelId,
          chatName: widget.name ??
              _channelProfileText(
                context,
                zhCN: '频道',
                zhTW: '頻道',
                en: 'Channel',
              ),
          isChannel: true,
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context, api.Chat chat) {
    // 频道角色由低到高为订阅者、管理员、创建者，不同角色只暴露对应操作入口。
    final isOwner = chat.myRole == 3; // 创建者
    final isAdmin = chat.myRole >= 2; // 管理员
    final isSubscriber = chat.myRole >= 1; // 订阅者

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        actions: [
          if (isOwner)
            _TGActionSheetItem(
              title: _channelProfileText(
                context,
                zhCN: '定时频道消息',
                zhTW: '定時頻道訊息',
                en: 'Scheduled Channel Messages',
              ),
              onTap: () {
                Navigator.pop(context);
                _openAutoMessages(context);
              },
            ),
          if (isAdmin && chat.joinApproval)
            _TGActionSheetItem(
              title: _channelProfileText(
                context,
                zhCN: '订阅请求',
                zhTW: '訂閱請求',
                en: 'Subscription Requests',
              ),
              trailing: FutureBuilder<int>(
                future: _loadJoinRequestCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  if (count <= 0) return const SizedBox.shrink();
                  return Text(
                    '（${count > 99 ? '99+' : count}）',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _showJoinRequests(context);
              },
            ),
          // 订阅者可以取消订阅
          if (isSubscriber && !isOwner)
            _TGActionSheetItem(
              title: AppLocalizations.of(context).leaveChannel,
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _showLeaveDialog(context);
              },
            ),
          // 创建者可以解散频道
          if (isOwner)
            _TGActionSheetItem(
              title: AppLocalizations.of(context).deleteChannel,
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _showDisbandDialog(context);
              },
            ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
      ),
    );
  }

  /// 显示解散频道确认对话框
  void _showDisbandDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _channelProfileText(
          context,
          zhCN: '解散「${widget.name ?? '该频道'}」？',
          zhTW: '解散「${widget.name ?? '該頻道'}」？',
          en: 'Delete "${widget.name ?? 'this channel'}"?',
        ),
        message: _channelProfileText(
          context,
          zhCN: '解散后所有订阅者将被移除，频道内容将被删除，此操作不可恢复',
          zhTW: '解散後所有訂閱者將被移除，頻道內容將被刪除，此操作不可恢復',
          en: 'All subscribers will be removed and channel content will be deleted permanently.',
        ),
        actions: [
          _TGActionSheetItem(
            title: AppLocalizations.of(context).deleteChannel,
            isDestructive: true,
            onTap: () => _disbandChannel(context),
          ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
      ),
    );
  }

  /// 解散频道
  Future<void> _disbandChannel(BuildContext context) async {
    Navigator.pop(context);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.delete('/chat/${widget.channelId}');

      if (!mounted) return;

      if (response.isSuccess) {
        // 解散成功，返回首页
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _channelProfileText(
                context,
                zhCN: '频道已解散',
                zhTW: '頻道已解散',
                en: 'Channel deleted',
              ),
            ),
          ),
        );
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _channelServerMessage(
                response.message,
                fallbackEn: 'Failed to delete channel',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _channelProfileText(
              context,
              zhCN: '解散失败: $e',
              zhTW: '解散失敗: $e',
              en: 'Failed to delete channel: $e',
            ),
          ),
        ),
      );
    }
  }

  void _showReportDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportPage(
          targetId: widget.channelId,
          targetType: 'channel',
          targetName: widget.name ??
              _channelProfileText(
                context,
                zhCN: '频道',
                zhTW: '頻道',
                en: 'Channel',
              ),
        ),
      ),
    );
  }

  void _showLeaveDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _channelProfileText(
          context,
          zhCN: '取消订阅「${widget.name ?? '该频道'}」？',
          zhTW: '取消訂閱「${widget.name ?? '該頻道'}」？',
          en: 'Unsubscribe from "${widget.name ?? 'this channel'}"?',
        ),
        message: _channelProfileText(
          context,
          zhCN: '取消订阅后将不再接收此频道的消息',
          zhTW: '取消訂閱後將不再接收此頻道的訊息',
          en: 'You will stop receiving messages from this channel.',
        ),
        actions: [
          _TGActionSheetItem(
            title: AppLocalizations.of(context).leaveChannel,
            isDestructive: true,
            onTap: () => _leaveChannel(context),
          ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
      ),
    );
  }

  Future<void> _leaveChannel(BuildContext context) async {
    Navigator.pop(context); // 关闭底部弹窗

    final (success, _) = await ref
        .read(chatListProvider.notifier)
        .leaveChatFromServer(widget.channelId);

    if (!mounted) return;

    if (success) {
      // 取消订阅成功后返回聊天列表
      context.go('/home');
    }
  }

  Future<void> _subscribeChannel(BuildContext context) async {
    // 订阅成功可能只是进入待审批队列；只有直接通过时才能立即进入会话。
    final (success, _, requiresApproval, approvalMsg) = await ref
        .read(chatListProvider.notifier)
        .joinChatFromServer(widget.channelId);

    if (!mounted) return;

    if (success) {
      if (requiresApproval) {
        // 需要审批 - 这个提示还是需要的
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _channelServerMessage(
                approvalMsg,
                fallbackEn:
                    'Subscription request submitted. Please wait for approval.',
              ),
            ),
          ),
        );
      } else {
        // 直接订阅成功 - 进入聊天页
        ref.invalidate(chatDetailProvider(widget.channelId));
        context.push(
            '/chat/${widget.channelId}?name=${Uri.encodeComponent(widget.name ?? '')}&type=channel${widget.avatar != null ? '&avatar=${Uri.encodeComponent(widget.avatar!)}' : ''}');
      }
    }
  }

  Future<void> _showJoinRequests(BuildContext context) async {
    await Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _JoinRequestsPage(
          chatId: widget.channelId,
          chatName: widget.name ??
              _channelProfileText(
                context,
                zhCN: '频道',
                zhTW: '頻道',
                en: 'Channel',
              ),
          isChannel: true,
        ),
      ),
    );
    if (!mounted) return;
    ref.invalidate(chatDetailProvider(widget.channelId));
    setState(() {});
  }
}

// 订阅请求列表页面
class _JoinRequestsPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final bool isChannel;

  const _JoinRequestsPage({
    required this.chatId,
    required this.chatName,
    required this.isChannel,
  });

  @override
  ConsumerState<_JoinRequestsPage> createState() => _JoinRequestsPageState();
}

class _JoinRequestsPageState extends ConsumerState<_JoinRequestsPage> {
  List<api.JoinRequest> _requests = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getJoinRequests(widget.chatId);

      if (response.isSuccess && response.data != null) {
        setState(() {
          _requests = response.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = _channelServerMessage(
            response.message,
            fallbackEn: 'Loading failed',
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = _channelProfileText(
          context,
          zhCN: '加载失败',
          zhTW: '載入失敗',
          en: 'Loading failed',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _reviewRequest(api.JoinRequest request, bool approve) async {
    final chatService = ref.read(api.chatServiceProvider);
    final response = await chatService.reviewJoinRequest(
      widget.chatId,
      request.id,
      approve,
    );

    if (!mounted) return;

    if (response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? _channelProfileText(
                    context,
                    zhCN: '已通过申请',
                    zhTW: '已通過申請',
                    en: 'Request approved',
                  )
                : _channelProfileText(
                    context,
                    zhCN: '已拒绝申请',
                    zhTW: '已拒絕申請',
                    en: 'Request rejected',
                  ),
          ),
        ),
      );
      _loadRequests(); // 刷新列表
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
          _channelServerMessage(
            response.message,
            fallbackEn: AppLocalizations.of(context).failed,
          ),
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.isChannel
        ? _channelProfileText(
            context,
            zhCN: '订阅请求',
            zhTW: '訂閱請求',
            en: 'Subscription Requests',
          )
        : AppLocalizations.of(context).get('join_requests');

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: AppColors.primaryFor(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loadRequests,
                        child: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ),
                )
              : _requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            _channelProfileText(
                              context,
                              zhCN: '暂无待审批的请求',
                              zhTW: '暫無待審批的請求',
                              en: 'No pending requests',
                            ),
                            style: TextStyle(fontSize: 17, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadRequests,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          return _buildRequestCard(request, isDark);
                        },
                      ),
                    ),
    );
  }

  Widget _buildRequestCard(api.JoinRequest request, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 头像
            AvatarWidget(
              name: request.nickname,
              avatar: request.avatar,
              size: 50,
            ),
            const SizedBox(width: 12),
            // 用户信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.nickname,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  if (request.username != null && request.username!.isNotEmpty)
                    Text(
                      '@${request.username}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.linkFor(context),
                      ),
                    ),
                  Text(
                    _formatTime(request.createdAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ],
              ),
            ),
            // 操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拒绝按钮
                IconButton(
                  onPressed: () => _reviewRequest(request, false),
                  icon: Icon(Icons.close, color: Colors.red),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.1),
                  ),
                ),
                const SizedBox(width: 8),
                // 通过按钮
                IconButton(
                  onPressed: () => _reviewRequest(request, true),
                  icon: Icon(Icons.check, color: Colors.green),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return _channelRelativeTimeText(context, time);
  }
}

class _JoinRequestCountBadge extends ConsumerWidget {
  final String chatId;

  const _JoinRequestCountBadge({required this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<ApiResponse<List<api.JoinRequest>>>(
      future: ref.read(api.chatServiceProvider).getJoinRequests(chatId),
      builder: (context, snapshot) {
        final count = snapshot.data?.data?.length ?? 0;
        if (count <= 0) {
          return const Icon(Icons.chevron_right, color: Colors.grey, size: 20);
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        );
      },
    );
  }
}

// 卡片容器
class _TGSection extends StatelessWidget {
  final Color cardColor;
  final Color separatorColor;
  final List<Widget> children;

  const _TGSection({
    required this.cardColor,
    required this.separatorColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final validChildren = children
        .where((c) => c is! SizedBox || (c as SizedBox).height != 0)
        .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int i = 0; i < validChildren.length; i++) ...[
            validChildren[i],
            if (i < validChildren.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child:
                    Divider(height: 0.5, thickness: 0.5, color: separatorColor),
              ),
          ],
        ],
      ),
    );
  }
}

// 信息单元格
class _TGInfoCell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _TGInfoCell({
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      color: titleColor ?? AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
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
}

// 单元格
class _TGCell extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _TGCell({
    this.icon,
    this.iconColor,
    required this.title,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor ?? Colors.grey, size: 24),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  color: titleColor ?? AppColors.textPrimaryFor(context),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// 风格操作表
class _TGActionSheet extends StatelessWidget {
  final String? title;
  final String? message;
  final List<_TGActionSheetItem> actions;
  final String cancelText;

  const _TGActionSheet({
    this.title,
    this.message,
    required this.actions,
    required this.cancelText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppColors.cardFor(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  if (title != null || message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        children: [
                          if (title != null)
                            Text(
                              title!,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          if (message != null) ...[
                            const SizedBox(height: 4),
                            Text(message!,
                                style:
                                    TextStyle(fontSize: 13, color: Colors.grey),
                                textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                  if (title != null || message != null)
                    Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.dividerFor(context)),
                  ...actions.map((action) => Column(
                        children: [
                          GestureDetector(
                            onTap: action.onTap,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      action.title,
                                      style: TextStyle(
                                          fontSize: 20,
                                          color: action.isDestructive
                                              ? Colors.red
                                              : AppColors.linkFor(context)),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  if (action.trailing != null) action.trailing!,
                                ],
                              ),
                            ),
                          ),
                          if (actions.indexOf(action) < actions.length - 1)
                            Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: AppColors.dividerFor(context)),
                        ],
                      )),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  cancelText,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.linkFor(context)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TGActionSheetItem {
  final String title;
  final Widget? trailing;
  final bool isDestructive;
  final VoidCallback onTap;

  const _TGActionSheetItem({
    required this.title,
    this.trailing,
    this.isDestructive = false,
    required this.onTap,
  });
}

// 操作按钮
class _TGActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool isActive; // 激活状态（如静音开启时）

  const _TGActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF252932);

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF24272C) : const Color(0xFFE9EAEE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Center(child: Icon(icon, size: 24, color: fg)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withOpacity(0.78) : fg,
            ),
          ),
        ],
      ),
    );
  }
}

// 搜索消息页面
class _SearchMessagesPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;

  const _SearchMessagesPage({
    required this.chatId,
    required this.chatName,
  });

  @override
  ConsumerState<_SearchMessagesPage> createState() =>
      _SearchMessagesPageState();
}

class _SearchMessagesPageState extends ConsumerState<_SearchMessagesPage> {
  final _searchController = TextEditingController();
  List<api.SearchMessageItem> _results = [];
  bool _isSearching = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _lastQuery = '';
      });
      return;
    }

    _lastQuery = query;
    await Future.delayed(const Duration(milliseconds: 300));
    if (_lastQuery != query) return;

    setState(() => _isSearching = true);

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.searchMessages(widget.chatId, query);
      if (!mounted || _lastQuery != query) return;
      setState(() {
        _isSearching = false;
        _results = response.data?.list ?? [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _results = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppColors.backgroundFor(context);
    final cardColor = AppColors.cardFor(context);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: AppColors.primaryFor(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context).get('search_messages'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            color: AppColors.surfaceFor(context),
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBackgroundFor(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _channelProfileText(
                    context,
                    zhCN: '在 ${widget.chatName} 中搜索',
                    zhTW: '在 ${widget.chatName} 中搜尋',
                    en: 'Search in ${widget.chatName}',
                  ),
                  hintStyle: TextStyle(
                    color: AppColors.inputHintFor(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.inputIconFor(context),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: AppColors.inputIconFor(context),
                            size: 20,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: TextStyle(
                  fontSize: 17,
                  color: AppColors.textPrimaryFor(context),
                ),
                onChanged: _search,
              ),
            ),
          ),

          // 结果列表
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? _channelProfileText(
                                      context,
                                      zhCN: '输入关键词搜索消息',
                                      zhTW: '輸入關鍵詞搜尋訊息',
                                      en: 'Enter keywords to search messages',
                                    )
                                  : _channelProfileText(
                                      context,
                                      zhCN: '未找到相关消息',
                                      zhTW: '未找到相關訊息',
                                      en: 'No matching messages found',
                                    ),
                              style:
                                  TextStyle(fontSize: 17, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              title: Text(
                                result.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_formatDate(result.createdAt)),
                              onTap: () => context.push(
                                '/chat/${widget.chatId}?name=${Uri.encodeComponent(widget.chatName)}&type=channel&messageId=${Uri.encodeComponent(result.id)}&messageSeq=${result.seq}',
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MM-dd HH:mm').format(date);
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }
}

// 媒体列表页
class _MediaListPage extends ConsumerStatefulWidget {
  final String chatId;
  final String title;
  final String type; // media, file, link, voice

  const _MediaListPage({
    required this.chatId,
    required this.title,
    required this.type,
  });

  @override
  ConsumerState<_MediaListPage> createState() => _MediaListPageState();
}

class _MediaListPageState extends ConsumerState<_MediaListPage> {
  final List<api.ChatMediaItem> _items = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();

  // 语音播放相关
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingVoiceId;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingVoiceId = null;
          _isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response =
          await chatService.getChatMedia(widget.chatId, widget.type, page: 1);

      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _items.clear();
          _items.addAll(response.data!.list);
          _page = 1;
          _hasMore = _items.length < response.data!.total;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService
          .getChatMedia(widget.chatId, widget.type, page: _page + 1);

      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _items.addAll(response.data!.list);
          _page++;
          _hasMore = _items.length < response.data!.total;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.primaryFor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getEmptyIcon(), size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _channelProfileText(
                context,
                zhCN: '暂无${widget.title}',
                zhTW: '暫無${widget.title}',
                en: 'No ${widget.title}',
              ),
              style: const TextStyle(fontSize: 17, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    switch (widget.type) {
      case 'media':
        return _buildMediaGrid(isDark);
      case 'link':
        return _buildLinkList(isDark);
      case 'file':
        return _buildFileList(isDark);
      case 'voice':
        return _buildVoiceList(isDark);
      default:
        return _buildMediaGrid(isDark);
    }
  }

  IconData _getEmptyIcon() {
    switch (widget.type) {
      case 'media':
        return Icons.photo_library_outlined;
      case 'link':
        return Icons.link_outlined;
      case 'file':
        return Icons.folder_outlined;
      case 'voice':
        return Icons.mic_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  Widget _buildMediaGrid(bool isDark) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final item = _items[index];
        final isVideo = item.type == 3;
        // 视频优先使用缩略图，图片使用原图
        final url = isVideo ? item.thumbnailUrl : item.mediaUrl;

        return GestureDetector(
          onTap: () => _openMediaPreview(item),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      color:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                  errorWidget: (_, __, ___) => Container(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                )
              else
                Container(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  child: const Icon(Icons.image, color: Colors.grey),
                ),
              if (isVideo)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow,
                            color: Colors.white, size: 12),
                        if (item.duration != null)
                          Text(_formatDuration(item.duration!),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLinkList(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }

        final item = _items[index];
        final text = item.text ?? '';
        final urls = _extractUrls(text);

        if (urls.isEmpty) return const SizedBox.shrink();

        final fallbackFileName = _channelProfileText(
          context,
          zhCN: '未知文件',
          zhTW: '未知檔案',
          en: 'Unknown file',
        );
        final voiceTitle = _channelProfileText(
          context,
          zhCN: '语音消息 ${_formatDuration(item.duration ?? 0)}',
          zhTW: '語音訊息 ${_formatDuration(item.duration ?? 0)}',
          en: 'Voice message ${_formatDuration(item.duration ?? 0)}',
        );
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.cardFor(context),
              borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: urls
                .map((url) => ListTile(
                      leading:
                          Icon(Icons.link, color: AppColors.linkFor(context)),
                      title: Text(url,
                          style: TextStyle(
                              color: AppColors.linkFor(context), fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiaryFor(context))),
                      onTap: () => _openUrl(url),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildFileList(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }

        final item = _items[index];
        final fallbackFileName = _channelProfileText(
          context,
          zhCN: '未知文件',
          zhTW: '未知檔案',
          en: 'Unknown file',
        );

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.cardFor(context),
              borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.primaryWithOpacity(context, 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(_getFileIcon(item.fileName),
                  color: AppColors.primaryFor(context)),
            ),
            title: Text(item.fileName ?? fallbackFileName,
                style: TextStyle(
                    fontSize: 15, color: AppColors.textPrimaryFor(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${_formatFileSize(item.fileSize ?? 0)} · ${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiaryFor(context))),
            onTap: () {},
          ),
        );
      },
    );
  }

  Widget _buildVoiceList(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }

        final item = _items[index];
        final isThisPlaying = _playingVoiceId == item.id && _isPlaying;
        final voiceTitle = _channelProfileText(
          context,
          zhCN: '语音消息 ${_formatDuration(item.duration ?? 0)}',
          zhTW: '語音訊息 ${_formatDuration(item.duration ?? 0)}',
          en: 'Voice message ${_formatDuration(item.duration ?? 0)}',
        );

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.cardFor(context),
              borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isThisPlaying
                    ? AppColors.primaryFor(context)
                    : AppColors.primaryWithOpacity(context, 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                isThisPlaying ? Icons.graphic_eq : Icons.mic,
                color: isThisPlaying
                    ? AppColors.onPrimaryFor(context)
                    : AppColors.primaryFor(context),
              ),
            ),
            title: Text(voiceTitle,
                style: TextStyle(
                    fontSize: 15, color: AppColors.textPrimaryFor(context))),
            subtitle: Text(
                '${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiaryFor(context))),
            trailing: GestureDetector(
              onTap: () => _playVoice(item),
              child: Icon(
                isThisPlaying ? Icons.stop_circle : Icons.play_circle,
                color: AppColors.primaryFor(context),
                size: 36,
              ),
            ),
            onTap: () => _playVoice(item),
          ),
        );
      },
    );
  }

  void _openMediaPreview(api.ChatMediaItem item) {
    final isVideo = item.type == 3;
    final url = item.mediaUrl;

    if (url == null) return;

    if (isVideo) {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (ctx, animation, secondaryAnimation) {
            return _VideoPlayerPage(videoUrl: url);
          },
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (ctx, animation, secondaryAnimation) {
            return _ImagePreviewPage(imageUrl: url);
          },
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  void _playVoice(api.ChatMediaItem item) async {
    final voiceUrl = item.voiceUrl;
    if (voiceUrl == null) return;

    if (_playingVoiceId == item.id && _isPlaying) {
      await _audioPlayer.stop();
      setState(() {
        _playingVoiceId = null;
        _isPlaying = false;
      });
    } else {
      try {
        await _audioPlayer.stop();
        await configureVoicePlaybackAudio(_audioPlayer);
        await _audioPlayer.play(UrlSource(voiceUrl));
        setState(() {
          _playingVoiceId = item.id;
          _isPlaying = true;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _channelProfileText(
                context,
                zhCN: '播放失败',
                zhTW: '播放失敗',
                en: 'Playback failed',
              ),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _openUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _channelProfileText(
            context,
            zhCN: '链接已复制',
            zhTW: '連結已複製',
            en: 'Link copied',
          ),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  List<String> _extractUrls(String text) {
    final urlPattern = RegExp(r'https?://[^\s]+');
    return urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MM-dd').format(date);
    }
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  IconData _getFileIcon(String? fileName) {
    if (fileName == null) return Icons.insert_drive_file;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}

// 订阅者列表页
class _SubscriberListPage extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;

  const _SubscriberListPage(
      {required this.channelId, required this.channelName});

  @override
  ConsumerState<_SubscriberListPage> createState() =>
      _SubscriberListPageState();
}

class _SubscriberListPageState extends ConsumerState<_SubscriberListPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final membersAsync = ref.watch(chatMembersProvider(widget.channelId));

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.primaryFor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _channelProfileText(
            context,
            zhCN: '订阅者',
            zhTW: '訂閱者',
            en: 'Subscribers',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surfaceFor(context),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _channelProfileText(
                  context,
                  zhCN: '搜索订阅者',
                  zhTW: '搜尋訂閱者',
                  en: 'Search subscribers',
                ),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.inputBackgroundFor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),

          // 订阅者列表
          Expanded(
            child: membersAsync.when(
              data: (members) {
                final filteredMembers = _searchQuery.isEmpty
                    ? members
                    : members
                        .where((m) =>
                            (m.nickname?.toLowerCase().contains(_searchQuery) ??
                                false) ||
                            (m.username?.toLowerCase().contains(_searchQuery) ??
                                false))
                        .toList();

                if (filteredMembers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? _channelProfileText(
                                  context,
                                  zhCN: '暂无订阅者',
                                  zhTW: '暫無訂閱者',
                                  en: 'No subscribers',
                                )
                              : _channelProfileText(
                                  context,
                                  zhCN: '未找到匹配的订阅者',
                                  zhTW: '未找到匹配的訂閱者',
                                  en: 'No matching subscribers found',
                                ),
                          style: TextStyle(fontSize: 17, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredMembers.length,
                  itemBuilder: (context, index) {
                    final member = filteredMembers[index];
                    final fallbackMemberName = _channelProfileText(
                      context,
                      zhCN: '用户',
                      zhTW: '用戶',
                      en: 'User',
                    );
                    final displayName = member.nickname ??
                        member.username ??
                        fallbackMemberName;
                    return Container(
                      margin: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: index == 0 ? 8 : 0,
                        bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardFor(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: AvatarWidget(
                          avatar: member.avatar,
                          name: displayName,
                          size: 44,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimaryFor(context),
                                ),
                              ),
                            ),
                            if (member.vipVisible) ...[
                              const SizedBox(width: 5),
                              VipBadge(
                                level: member.vipLevel,
                                text: member.vipBadge,
                                iconUrl: member.vipBadgeIcon,
                                height: 18,
                                compact: true,
                              ),
                            ],
                          ],
                        ),
                        subtitle: member.username != null
                            ? Text(
                                '@${member.username}',
                                style: TextStyle(
                                  color: AppColors.textTertiaryFor(context),
                                  fontSize: 13,
                                ),
                              )
                            : null,
                        trailing: member.role >= 2
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryWithOpacity(
                                      context, 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  member.role == 3
                                      ? _channelProfileText(
                                          context,
                                          zhCN: '创建者',
                                          zhTW: '建立者',
                                          en: 'Owner',
                                        )
                                      : _channelProfileText(
                                          context,
                                          zhCN: '管理员',
                                          zhTW: '管理員',
                                          en: 'Admin',
                                        ),
                                  style: TextStyle(
                                    color: AppColors.linkFor(context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () {
                          // 跳转到用户资料页
                          context.push(
                              '/user/${member.userId}?name=${Uri.encodeComponent(displayName)}');
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      _channelProfileText(
                        context,
                        zhCN: '加载失败',
                        zhTW: '載入失敗',
                        en: 'Load failed',
                      ),
                      style: const TextStyle(fontSize: 17, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图片预览页面
class _ImagePreviewPage extends StatefulWidget {
  final String imageUrl;

  const _ImagePreviewPage({required this.imageUrl});

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  double _scale = 1.0;
  double _opacity = 1.0;

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      _scale = (1 - (_dragOffset.abs() / 500)).clamp(0.5, 1.0);
      _opacity = (1 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0;
        _scale = 1.0;
        _opacity = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(_opacity),
        body: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            children: [
              Center(
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: Transform.scale(
                    scale: _scale,
                    child: PhotoView(
                      imageProvider:
                          CachedNetworkImageProvider(widget.imageUrl),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3,
                      backgroundDecoration:
                          const BoxDecoration(color: Colors.transparent),
                      loadingBuilder: (context, event) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 64),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 20),
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

/// 视频播放器页面
class _VideoPlayerPage extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerPage({required this.videoUrl});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        _controller.play();
      }).catchError((e) {
        debugPrint('[Video] Init error: $e');
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final min = duration.inMinutes;
    final sec = duration.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            children: [
              Center(
                child: _isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
              if (_showControls) ...[
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_controller.value.isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                if (_isInitialized)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            _formatDuration(_controller.value.position),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          Expanded(
                            child: Slider(
                              value: _controller.value.position.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                      0,
                                      _controller.value.duration.inMilliseconds
                                          .toDouble()),
                              min: 0,
                              max: _controller.value.duration.inMilliseconds
                                  .toDouble()
                                  .clamp(1, double.infinity),
                              activeColor: AppColors.primaryFor(context),
                              inactiveColor: AppColors.darkTextTertiary,
                              onChanged: (value) {
                                _controller.seekTo(
                                    Duration(milliseconds: value.toInt()));
                              },
                            ),
                          ),
                          Text(
                            _formatDuration(_controller.value.duration),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
