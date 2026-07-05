import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
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
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/platform_utils.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../providers/chat_provider.dart';

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
      final response = await ref.read(api.chatServiceProvider).getJoinRequests(widget.channelId);
      return response.data?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.channelId));
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final separatorColor = isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);
    
    Widget content = Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // iOS 风格导航栏
          SliverAppBar(
            pinned: true,
            backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
              onPressed: () {
                if (widget.isDesktopPanel) {
                  // 桌面面板模式：关闭资料页，返回聊天
                  ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
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
                      final pendingCount = (chat.myRole >= 2 && chat.joinApproval)
                          ? (snapshot.data ?? 0)
                          : 0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: Icon(Icons.more_horiz, color: AppColors.primary),
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
                                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  // 频道头像
                  AvatarWidget(
                    avatar: widget.avatar,
                    name: widget.name ?? '频道',
                    size: 100,
                    borderRadius: 25,
                  ),
                  const SizedBox(height: 12),
                  // 频道名称 + 官方标识
                  Consumer(
                    builder: (context, ref, _) {
                      final officialChatsAsync = ref.watch(officialChatsProvider);
                      final officialChats = officialChatsAsync.valueOrNull ?? {};
                      final isOfficial = officialChats.contains(widget.channelId);
                      
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.name ?? '频道',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
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
                    loading: () => Text('加载中...', style: TextStyle(fontSize: 15, color: Colors.grey)),
                    error: (_, __) => Text('频道', style: TextStyle(fontSize: 15, color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ),

          // 操作按钮
          SliverToBoxAdapter(
            child: Container(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Consumer(
                builder: (context, ref, _) {
                  // 获取当前频道的静音状态
                  final chatListState = ref.watch(chatListProvider);
                  final allChats = chatListState.allChats;
                  final currentChat = allChats.where((c) => c.id == widget.channelId).firstOrNull;
                  final isMuted = currentChat?.isMuted ?? false;
                  
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TGActionButton(
                        icon: isMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                        label: isMuted ? '取消静音' : '静音',
                        isActive: isMuted,
                        onTap: () {
                          GlobalHaptics.medium();
                          ref.read(chatListProvider.notifier).toggleMute(widget.channelId);
                        },
                      ),
                      _TGActionButton(
                        icon: Icons.search,
                        label: '搜索',
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
                    title: chat?.description?.isNotEmpty == true ? chat!.description! : '暂无简介',
                    subtitle: '简介',
                  ),
                  loading: () => const _TGInfoCell(title: '加载中...', subtitle: '简介'),
                  error: (_, __) => const _TGInfoCell(title: '暂无简介', subtitle: '简介'),
                ),
                // 频道号
                chatDetailAsync.when(
                  data: (chat) {
                    final username = chat?.username;
                    if (username == null || username.isEmpty) return const SizedBox.shrink();
                    return _TGInfoCell(
                      title: '@$username',
                      subtitle: '频道号',
                      titleColor: AppColors.primary,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '@$username'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('频道号已复制'), duration: Duration(seconds: 1)),
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
                  iconColor: AppColors.primary,
                  title: '照片和视频',
                  trailing: _buildCountTrailing('${_mediaCounts?.media ?? 0}'),
                  onTap: () => _showMediaList(context, '照片和视频', 'media'),
                ),
                _TGCell(
                  icon: Icons.insert_drive_file_outlined,
                  iconColor: AppColors.primary,
                  title: '文件',
                  trailing: _buildCountTrailing('${_mediaCounts?.file ?? 0}'),
                  onTap: () => _showMediaList(context, '文件', 'file'),
                ),
                _TGCell(
                  icon: Icons.link,
                  iconColor: AppColors.primary,
                  title: '链接',
                  trailing: _buildCountTrailing('${_mediaCounts?.link ?? 0}'),
                  onTap: () => _showMediaList(context, '链接', 'link'),
                ),
                _TGCell(
                  icon: Icons.mic_outlined,
                  iconColor: AppColors.primary,
                  title: '语音消息',
                  trailing: _buildCountTrailing('${_mediaCounts?.voice ?? 0}'),
                  onTap: () => _showMediaList(context, '语音消息', 'voice'),
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
                          title: '订阅者',
                          trailing: _buildCountTrailing(_formatSubscriberCount(chat.memberCount)),
                          onTap: () => _showSubscriberList(context),
                        ),
                        // 订阅请求（管理员可见且开启审批）
                        if (chat.joinApproval) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 56),
                            child: Divider(height: 0.5, thickness: 0.5, color: separatorColor),
                          ),
                          _TGCell(
                            icon: Icons.how_to_reg_outlined,
                            iconColor: Colors.orange,
                            title: '订阅请求',
                            trailing: _JoinRequestCountBadge(chatId: widget.channelId),
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
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
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
                  iconColor: AppColors.primary,
                  title: '分享频道',
                  onTap: () => _shareChannel(context),
                ),
                // _TGCell(
                //   title: '举报',
                //   titleColor: Colors.red,
                //   onTap: () => _showReportDialog(context),
                // ),
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
                      title: '订阅频道',
                      titleColor: AppColors.primary,
                      onTap: () => _subscribeChannel(context),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
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
    if (PlatformUtils.isDesktop) {
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
      return '${(count / 10000).toStringAsFixed(1)}万';
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
          channelName: widget.name ?? '频道',
        ),
      ),
    );
  }

  void _showFeatureNotAvailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 功能暂未开放'), duration: const Duration(seconds: 1)),
    );
  }

  void _searchMessages(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _SearchMessagesPage(
          chatId: widget.channelId,
          chatName: widget.name ?? '频道',
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
      const SnackBar(content: Text('链接已复制，可以分享给好友')),
    );
  }

  /// 显示更多菜单（三点按钮）
  void _showMoreMenu(BuildContext context, api.Chat chat) {
    final isOwner = chat.myRole == 3; // 创建者
    final isAdmin = chat.myRole >= 2; // 管理员
    final isSubscriber = chat.myRole >= 1; // 订阅者
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        actions: [
          if (isAdmin && chat.joinApproval)
            _TGActionSheetItem(
              title: '订阅请求',
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
              title: '取消订阅',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _showLeaveDialog(context);
              },
            ),
          // 创建者可以解散频道
          if (isOwner)
            _TGActionSheetItem(
              title: '解散频道',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _showDisbandDialog(context);
              },
            ),
        ],
        cancelText: '取消',
      ),
    );
  }

  /// 显示解散频道确认对话框
  void _showDisbandDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '解散「${widget.name ?? '该频道'}」？',
        message: '解散后所有订阅者将被移除，频道内容将被删除，此操作不可恢复',
        actions: [
          _TGActionSheetItem(
            title: '解散频道',
            isDestructive: true,
            onTap: () => _disbandChannel(context),
          ),
        ],
        cancelText: '取消',
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
          const SnackBar(content: Text('频道已解散')),
        );
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.message ?? '解散失败')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解散失败: $e')),
      );
    }
  }

  void _showReportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '举报',
        actions: [
          _TGActionSheetItem(title: '垃圾信息', onTap: () => _submitReport(context, '垃圾信息')),
          _TGActionSheetItem(title: '虚假信息', onTap: () => _submitReport(context, '虚假信息')),
          _TGActionSheetItem(title: '暴力内容', onTap: () => _submitReport(context, '暴力内容')),
          _TGActionSheetItem(title: '色情内容', onTap: () => _submitReport(context, '色情内容')),
          _TGActionSheetItem(title: '其他', onTap: () => _submitReport(context, '其他')),
        ],
        cancelText: '取消',
      ),
    );
  }

  void _submitReport(BuildContext context, String reason) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('举报已提交')),
    );
  }

  void _showLeaveDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '取消订阅「${widget.name ?? '该频道'}」？',
        message: '取消订阅后将不再接收此频道的消息',
        actions: [
          _TGActionSheetItem(
            title: '取消订阅',
            isDestructive: true,
            onTap: () => _leaveChannel(context),
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  Future<void> _leaveChannel(BuildContext context) async {
    Navigator.pop(context); // 关闭底部弹窗
    
    final (success, _) = await ref.read(chatListProvider.notifier).leaveChatFromServer(widget.channelId);
    
    if (!mounted) return;
    
    if (success) {
      // 取消订阅成功后返回聊天列表
      context.go('/home');
    }
  }

  Future<void> _subscribeChannel(BuildContext context) async {
    final (success, _, requiresApproval, approvalMsg) = await ref.read(chatListProvider.notifier).joinChatFromServer(widget.channelId);
    
    if (!mounted) return;
    
    if (success) {
      if (requiresApproval) {
        // 需要审批 - 这个提示还是需要的
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approvalMsg ?? '已提交订阅申请，请等待审批')),
        );
      } else {
        // 直接订阅成功 - 进入聊天页
        ref.invalidate(chatDetailProvider(widget.channelId));
        context.push('/chat/${widget.channelId}?name=${Uri.encodeComponent(widget.name ?? '')}&type=channel${widget.avatar != null ? '&avatar=${Uri.encodeComponent(widget.avatar!)}' : ''}');
      }
    }
  }

  Future<void> _showJoinRequests(BuildContext context) async {
    await Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _JoinRequestsPage(
          chatId: widget.channelId,
          chatName: widget.name ?? '频道',
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
          _error = response.message ?? '加载失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '加载失败';
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
        SnackBar(content: Text(approve ? '已通过申请' : '已拒绝申请')),
      );
      _loadRequests(); // 刷新列表
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.message ?? '操作失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.isChannel ? '订阅请求' : '加入请求';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
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
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            '暂无待审批的请求',
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
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
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
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (request.username != null && request.username!.isNotEmpty)
                    Text(
                      '@${request.username}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  Text(
                    _formatTime(request.createdAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey : Colors.grey.shade600,
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
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}月${time.day}日';
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
    final validChildren = children.where((c) => c is! SizedBox || (c as SizedBox).height != 0).toList();
    
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
                child: Divider(height: 0.5, thickness: 0.5, color: separatorColor),
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
                      color: titleColor ?? (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey),
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
                  color: titleColor ?? (isDark ? Colors.white : Colors.black),
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
    final bgColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        children: [
                          if (title != null)
                            Text(
                              title!,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          if (message != null) ...[
                            const SizedBox(height: 4),
                            Text(message!, style: TextStyle(fontSize: 13, color: Colors.grey), textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                  if (title != null || message != null)
                    Divider(height: 0.5, thickness: 0.5, color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8)),
                  ...actions.map((action) => Column(
                    children: [
                      GestureDetector(
                        onTap: action.onTap,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  action.title,
                                  style: TextStyle(fontSize: 20, color: action.isDestructive ? Colors.red : AppColors.primary),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              if (action.trailing != null) action.trailing!,
                            ],
                          ),
                        ),
                      ),
                      if (actions.indexOf(action) < actions.length - 1)
                        Divider(height: 0.5, thickness: 0.5, color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8)),
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
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  cancelText,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.primary),
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
    // 激活状态使用不同颜色
    final activeColor = isActive ? Colors.red : AppColors.primary;
    
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: activeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: isLoading
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : Icon(icon, size: 26, color: activeColor),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isActive 
                  ? Colors.red 
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

// 搜索消息页面
class _SearchMessagesPage extends StatefulWidget {
  final String chatId;
  final String chatName;

  const _SearchMessagesPage({
    required this.chatId,
    required this.chatName,
  });

  @override
  State<_SearchMessagesPage> createState() => _SearchMessagesPageState();
}

class _SearchMessagesPageState extends State<_SearchMessagesPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isSearching = true);

    // TODO: 调用搜索 API
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _isSearching = false;
      _results = []; // 暂时返回空结果
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '搜索消息',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '在 ${widget.chatName} 中搜索',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: TextStyle(
                  fontSize: 17,
                  color: isDark ? Colors.white : Colors.black,
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
                            Icon(Icons.search, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty ? '输入关键词搜索消息' : '未找到相关消息',
                              style: TextStyle(fontSize: 17, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              title: Text(result['content'] ?? ''),
                              subtitle: Text(result['time'] ?? ''),
                              onTap: () {
                                // TODO: 跳转到消息位置
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getChatMedia(widget.chatId, widget.type, page: 1);
      
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
      final response = await chatService.getChatMedia(widget.chatId, widget.type, page: _page + 1);
      
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
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
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
            Text('暂无${widget.title}', style: const TextStyle(fontSize: 17, color: Colors.grey)),
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
      case 'media': return Icons.photo_library_outlined;
      case 'link': return Icons.link_outlined;
      case 'file': return Icons.folder_outlined;
      case 'voice': return Icons.mic_outlined;
      default: return Icons.folder_outlined;
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
                  placeholder: (_, __) => Container(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                        if (item.duration != null)
                          Text(_formatDuration(item.duration!), style: const TextStyle(color: Colors.white, fontSize: 10)),
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
          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
        }
        
        final item = _items[index];
        final text = item.text ?? '';
        final urls = _extractUrls(text);
        
        if (urls.isEmpty) return const SizedBox.shrink();
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2E) : Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: urls.map((url) => ListTile(
              leading: Icon(Icons.link, color: AppColors.primary),
              title: Text(url, style: TextStyle(color: AppColors.primary, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${item.senderName ?? ''} · ${_formatDate(item.createdAt)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              onTap: () => _openUrl(url),
            )).toList(),
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
          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
        }
        
        final item = _items[index];
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2E) : Colors.white, borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(_getFileIcon(item.fileName), color: AppColors.primary),
            ),
            title: Text(item.fileName ?? '未知文件', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_formatFileSize(item.fileSize ?? 0)} · ${item.senderName ?? ''} · ${_formatDate(item.createdAt)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
        }
        
        final item = _items[index];
        final isThisPlaying = _playingVoiceId == item.id && _isPlaying;
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2E) : Colors.white, borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isThisPlaying ? AppColors.primary : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                isThisPlaying ? Icons.graphic_eq : Icons.mic,
                color: isThisPlaying ? Colors.white : AppColors.primary,
              ),
            ),
            title: Text('语音消息 ${_formatDuration(item.duration ?? 0)}', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black)),
            subtitle: Text('${item.senderName ?? ''} · ${_formatDate(item.createdAt)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: GestureDetector(
              onTap: () => _playVoice(item),
              child: Icon(
                isThisPlaying ? Icons.stop_circle : Icons.play_circle,
                color: AppColors.primary,
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
        await _audioPlayer.play(UrlSource(voiceUrl));
        setState(() {
          _playingVoiceId = item.id;
          _isPlaying = true;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放失败'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  void _openUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接已复制'), duration: Duration(seconds: 1)),
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
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MM-dd').format(date);
    }
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  IconData _getFileIcon(String? fileName) {
    if (fileName == null) return Icons.insert_drive_file;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'zip': case 'rar': case '7z': return Icons.folder_zip;
      case 'mp3': case 'wav': case 'aac': return Icons.audio_file;
      case 'mp4': case 'avi': case 'mov': return Icons.video_file;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image;
      default: return Icons.insert_drive_file;
    }
  }
}

// 订阅者列表页
class _SubscriberListPage extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;

  const _SubscriberListPage({required this.channelId, required this.channelName});

  @override
  ConsumerState<_SubscriberListPage> createState() => _SubscriberListPageState();
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
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '订阅者',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索订阅者',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? const Color(0xFF38383A) : const Color(0xFFF2F2F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
          
          // 订阅者列表
          Expanded(
            child: membersAsync.when(
              data: (members) {
                final filteredMembers = _searchQuery.isEmpty
                    ? members
                    : members.where((m) =>
                        (m.nickname?.toLowerCase().contains(_searchQuery) ?? false) ||
                        (m.username?.toLowerCase().contains(_searchQuery) ?? false)
                      ).toList();
                
                if (filteredMembers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty ? '暂无订阅者' : '未找到匹配的订阅者',
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
                    return Container(
                      margin: EdgeInsets.only(
                        left: 16, right: 16, top: index == 0 ? 8 : 0, bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: AvatarWidget(
                          avatar: member.avatar,
                          name: member.nickname ?? member.username ?? '用户',
                          size: 44,
                        ),
                        title: Text(
                          member.nickname ?? member.username ?? '用户',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: member.username != null
                            ? Text(
                                '@${member.username}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              )
                            : null,
                        trailing: member.role >= 2
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  member.role == 3 ? '创建者' : '管理员',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () {
                          // 跳转到用户资料页
                          context.push('/user/${member.userId}?name=${Uri.encodeComponent(member.nickname ?? member.username ?? '用户')}');
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
                    Text('加载失败', style: TextStyle(fontSize: 17, color: Colors.grey)),
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
    return Scaffold(
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
                    imageProvider: CachedNetworkImageProvider(widget.imageUrl),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    loadingBuilder: (context, event) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
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
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
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
        if (kDebugMode) debugPrint('[Video] Init error: $e');
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
    return Scaffold(
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
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
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
                      _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: _controller.value.position.inMilliseconds.toDouble()
                                .clamp(0, _controller.value.duration.inMilliseconds.toDouble()),
                            min: 0,
                            max: _controller.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                            activeColor: AppColors.primary,
                            inactiveColor: Colors.white38,
                            onChanged: (value) {
                              _controller.seekTo(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                        Text(
                          _formatDuration(_controller.value.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
