import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'chat_detail_page.dart' show ChatDetailPage, ChatType;
import 'package:photo_view/photo_view.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/qr_payload.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/websocket_service.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';

/// 群组资料页面
class GroupProfilePage extends ConsumerStatefulWidget {
  final String groupId;
  final String? name;
  final String? avatar;
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示

  const GroupProfilePage({
    super.key,
    required this.groupId,
    this.name,
    this.avatar,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<GroupProfilePage> createState() => _GroupProfilePageState();
}

class _GroupProfilePageState extends ConsumerState<GroupProfilePage> {
  api.ChatMediaCounts? _mediaCounts;
  api.Chat? _lastChatDetail;
  final TextEditingController _memberSearchController = TextEditingController();
  bool _showMemberSearch = false;
  String _memberSearchQuery = '';
  Timer? _memberSearchDebounce;

  @override
  void initState() {
    super.initState();
    _loadMediaCounts();
  }

  @override
  void dispose() {
    _memberSearchDebounce?.cancel();
    _memberSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadMediaCounts() async {
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getChatMediaCounts(widget.groupId);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _mediaCounts = response.data;
        });
      }
    } catch (e) {
      // 忽略错误
    }
  }

  List<api.ChatMember> _filterMembers(List<api.ChatMember> members) {
    final query = _memberSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return members;

    return members.where((member) {
      return member.displayName.toLowerCase().contains(query) ||
          member.nickname.toLowerCase().contains(query) ||
          member.username.toLowerCase().contains(query);
    }).toList();
  }

  void _onMemberSearchChanged(String value) {
    _memberSearchDebounce?.cancel();
    _memberSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _memberSearchQuery = value;
      });
    });
  }

  Future<int> _loadJoinRequestCount() async {
    try {
      final response = await ref
          .read(api.chatServiceProvider)
          .getJoinRequests(widget.groupId);
      return response.data?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.groupId));
    ref.listen<AsyncValue<api.Chat?>>(chatDetailProvider(widget.groupId), (
      previous,
      next,
    ) {
      final nextChat = next.valueOrNull;
      if (nextChat == null || nextChat == _lastChatDetail) return;
      if (!mounted) return;
      setState(() => _lastChatDetail = nextChat);
    });
    final chatDetail = chatDetailAsync.valueOrNull ?? _lastChatDetail;
    final membersAsync = ref.watch(chatMembersProvider(widget.groupId));
    final memberKeyword = _memberSearchQuery.trim();
    final searchedMembersAsync = memberKeyword.isEmpty
        ? null
        : ref.watch(
            chatMemberSearchProvider((
              chatId: widget.groupId,
              keyword: memberKeyword,
            )),
          );
    final activeMembersAsync = memberKeyword.isEmpty
        ? membersAsync
        : searchedMembersAsync!;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final separatorColor = isDark
        ? const Color(0xFF38383A)
        : const Color(0xFFC6C6C8);

    // 桌面端使用居中布局
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
              icon: Icon(
                Icons.arrow_back_ios,
                size: 20,
                color: AppColors.primary,
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
              if (chatDetail != null && chatDetail.myRole >= 1)
                FutureBuilder<int>(
                  future: _loadJoinRequestCount(),
                  builder: (context, snapshot) {
                    final pendingCount =
                        (chatDetail.myRole >= 2 && chatDetail.joinApproval)
                        ? (snapshot.data ?? 0)
                        : 0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.more_horiz,
                            color: AppColors.primary,
                          ),
                          onPressed: () => _showMoreMenu(context, chatDetail),
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
                                  color: isDark
                                      ? const Color(0xFF1C1C1E)
                                      : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                )
              else
                const SizedBox.shrink(),
            ],
          ),

          // 头像和基本信息
          SliverToBoxAdapter(
            child: Container(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  // 群头像
                  AvatarWidget(
                    avatar: widget.avatar,
                    name: widget.name ?? '群组',
                    size: 100,
                    borderRadius: 25,
                  ),
                  const SizedBox(height: 12),
                  // 群名称 + 官方标识
                  Consumer(
                    builder: (context, ref, _) {
                      final officialChatsAsync = ref.watch(
                        officialChatsProvider,
                      );
                      final officialChats =
                          officialChatsAsync.valueOrNull ?? {};
                      final isOfficial = officialChats.contains(widget.groupId);

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.name ?? '群组',
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
                  // 成员数
                  Text(
                    chatDetail != null
                        ? '${chatDetail.memberCount} 位成员'
                        : (chatDetailAsync.isLoading ? '加载中...' : '群组'),
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  // 在线人数（有数据时才展示）
                  if (chatDetail != null && chatDetail.onlineCount > 0) ...
                    [
                      const SizedBox(height: 2),
                      Text(
                        '${chatDetail.onlineCount} 人在线',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade400,
                        ),
                      ),
                    ],
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
                  // 获取当前群组的静音状态
                  final chatListState = ref.watch(chatListProvider);
                  final allChats = chatListState.allChats;
                  final currentChat = allChats
                      .where((c) => c.id == widget.groupId)
                      .firstOrNull;
                  final isMuted = currentChat?.isMuted ?? false;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TGActionButton(
                        icon: isMuted
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        label: isMuted ? '取消静音' : '静音',
                        isActive: isMuted,
                        onTap: () {
                          GlobalHaptics.medium();
                          ref
                              .read(chatListProvider.notifier)
                              .toggleMute(widget.groupId);
                        },
                      ),
                      _TGActionButton(
                        icon: Icons.search,
                        label: '搜索',
                        onTap: () => _searchMessages(context),
                      ),
                      _TGActionButton(
                        icon: Icons.campaign_outlined,
                        label: '公告',
                        onTap: () => _openAnnouncements(context),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // 间距
          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 群信息卡片
          SliverToBoxAdapter(
            child: _TGSection(
              cardColor: cardColor,
              separatorColor: separatorColor,
              children: [
                // 群简介
                if (chatDetail != null)
                  _TGInfoCell(
                    title: chatDetail.description?.isNotEmpty == true
                        ? chatDetail.description!
                        : '暂无简介',
                    subtitle: '简介',
                  )
                else if (chatDetailAsync.isLoading)
                  const _TGInfoCell(title: '加载中...', subtitle: '简介')
                else
                  const _TGInfoCell(title: '暂无简介', subtitle: '简介'),
                // 群组号
                if (chatDetail?.username?.isNotEmpty == true)
                  _TGInfoCell(
                    title: '@${chatDetail!.username}',
                    subtitle: '群组号',
                    titleColor: AppColors.primary,
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: '@${chatDetail.username}'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('群组号已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  )
                else
                  const SizedBox.shrink(),
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
                if (chatDetail != null &&
                    (chatDetail.inviteLink?.trim().isNotEmpty ?? false))
                  _TGCell(
                    icon: Icons.qr_code_2_rounded,
                    iconColor: AppColors.primary,
                    title: '群二维码',
                    trailing: _buildChevronTrailing(),
                    onTap: () => _showGroupQrCode(context, chatDetail),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),

          // 成员标题
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 16, 8),
              child: Row(
                children: [
                  Text(
                    '成员',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  activeMembersAsync.when(
                    data: (members) => Text(
                      '${members.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _showMemberSearch ? Icons.close : Icons.search,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () {
                      setState(() {
                        _showMemberSearch = !_showMemberSearch;
                        if (!_showMemberSearch) {
                          _memberSearchQuery = '';
                          _memberSearchController.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // 成员列表
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  // 添加成员（管理员或群主可见）
                  if (chatDetail != null && chatDetail.myRole >= 2)
                    _TGCell(
                      icon: Icons.person_add_outlined,
                      iconColor: AppColors.primary,
                      title: '添加成员',
                      titleColor: AppColors.primary,
                      onTap: () => _showAddMemberSheet(context),
                    )
                  else
                    const SizedBox.shrink(),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: separatorColor,
                    ),
                  ),
                  // 加入请求（管理员可见）
                  if (chatDetail != null &&
                      chatDetail.myRole >= 2 &&
                      chatDetail.joinApproval)
                    Column(
                      children: [
                        _TGCell(
                          icon: Icons.how_to_reg_outlined,
                          iconColor: Colors.orange,
                          title: '加入请求',
                          trailing: _JoinRequestCountBadge(
                            chatId: widget.groupId,
                          ),
                          onTap: () => _showJoinRequests(context),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 56),
                          child: Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: separatorColor,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  if (_showMemberSearch)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: TextField(
                        controller: _memberSearchController,
                        onChanged: _onMemberSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索成员昵称或用户名',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _memberSearchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _memberSearchDebounce?.cancel();
                                    setState(() {
                                      _memberSearchController.clear();
                                      _memberSearchQuery = '';
                                    });
                                  },
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1C1C1E)
                              : const Color(0xFFF2F2F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  if (_showMemberSearch)
                    Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: separatorColor,
                      ),
                    ),
                  // 成员列表
                  activeMembersAsync.when(
                    data: (members) {
                      if (members.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              memberKeyword.isEmpty ? '暂无成员' : '未找到成员',
                            ),
                          ),
                        );
                      }
                      final myRole = chatDetail?.myRole ?? 0;
                      return Column(
                        children: members.asMap().entries.map((entry) {
                          final index = entry.key;
                          final member = entry.value;
                          final isLast = index == members.length - 1;

                          return Column(
                            children: [
                              _MemberCell(
                                member: member,
                                onTap: () {
                                  // 管理员或群主点击显示操作菜单
                                  if (myRole >= 2) {
                                    _showMemberActions(context, member, myRole);
                                  } else {
                                    // 普通成员直接跳转资料页
                                    context.push(
                                      '/user/${member.userId}?name=${Uri.encodeComponent(member.displayName)}${member.avatar != null ? '&avatar=${Uri.encodeComponent(member.avatar!)}' : ''}',
                                    );
                                  }
                                },
                              ),
                              if (!isLast)
                                Padding(
                                  padding: const EdgeInsets.only(left: 72),
                                  child: Divider(
                                    height: 0.5,
                                    thickness: 0.5,
                                    color: separatorColor,
                                  ),
                                ),
                            ],
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('加载失败')),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 加入/退出群组
          SliverToBoxAdapter(
            child: _TGSection(
              cardColor: cardColor,
              separatorColor: separatorColor,
              children: [
                if (chatDetail != null && chatDetail.myRole == 3)
                  // 群主 - 显示解散群组
                  _TGCell(
                    title: '解散群组',
                    titleColor: Colors.red,
                    onTap: () => _showDissolveDialog(context),
                  )
                else if (chatDetail != null && chatDetail.myRole >= 1)
                  // 已加入 - 显示退出群组
                  _TGCell(
                    title: '退出群组',
                    titleColor: Colors.red,
                    onTap: () => _showLeaveDialog(context),
                  )
                else if (chatDetailAsync.isLoading && _lastChatDetail == null)
                  const SizedBox.shrink()
                else
                  // 未加入 - 显示加入群组
                  _TGCell(
                    title: '加入群组',
                    titleColor: AppColors.primary,
                    onTap: () => _joinGroup(context),
                  ),
              ],
            ),
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

  Widget _buildChevronTrailing() {
    return Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22);
  }

  void _showMediaList(BuildContext context, String title, String type) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) =>
            _MediaListPage(chatId: widget.groupId, title: title, type: type),
      ),
    );
  }

  void _showGroupQrCode(BuildContext context, api.Chat chat) {
    final inviteLink = chat.inviteLink?.trim() ?? '';
    if (inviteLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('群二维码暂不可用'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _GroupQrCodePage(
          groupName: chat.name ?? widget.name ?? '群组',
          groupAvatar: chat.avatar ?? widget.avatar,
          memberCount: chat.memberCount,
          inviteLink: inviteLink,
        ),
      ),
    );
  }

  void _showFeatureNotAvailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 功能暂未开放'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _searchMessages(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => SearchMessagesPage(
          chatId: widget.groupId,
          chatName: widget.name ?? '群组',
        ),
      ),
    );
  }

  void _openAnnouncements(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _GroupAnnouncementsPage(
          chatId: widget.groupId,
          chatName: widget.name ?? '群组',
        ),
      ),
    );
  }

  void _showLeaveDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '退出「${widget.name ?? '该群组'}」？',
        message: '退出后将不再接收此群组的消息',
        actions: [
          _TGActionSheetItem(
            title: '退出群组',
            isDestructive: true,
            onTap: () => _leaveGroup(context),
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  Future<void> _leaveGroup(BuildContext context) async {
    Navigator.pop(context); // 关闭底部弹窗

    final (success, _) = await ref
        .read(chatListProvider.notifier)
        .leaveChatFromServer(widget.groupId);

    if (!mounted) return;

    if (success) {
      // 退出成功后返回聊天列表
      context.go('/home');
    }
  }

  Future<void> _joinGroup(BuildContext context) async {
    final (success, _, requiresApproval, approvalMsg) = await ref
        .read(chatListProvider.notifier)
        .joinChatFromServer(widget.groupId);

    if (!mounted) return;

    if (success) {
      if (requiresApproval) {
        // 需要审批 - 这个提示还是需要的
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(approvalMsg ?? '已提交加入申请，请等待审批')));
      } else {
        // 直接加入成功 - 进入聊天页
        ref.invalidate(chatDetailProvider(widget.groupId));
        context.push(
          '/chat/${widget.groupId}?name=${Uri.encodeComponent(widget.name ?? '')}&type=group${widget.avatar != null ? '&avatar=${Uri.encodeComponent(widget.avatar!)}' : ''}',
        );
      }
    }
  }

  Future<void> _showJoinRequests(BuildContext context) async {
    await Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _JoinRequestsPage(
          chatId: widget.groupId,
          chatName: widget.name ?? '群组',
          isChannel: false,
        ),
      ),
    );
    if (!mounted) return;
    ref.invalidate(chatDetailProvider(widget.groupId));
    setState(() {});
  }

  /// 显示添加成员选择器
  void _showAddMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddMemberSheet(
        chatId: widget.groupId,
        onMembersAdded: () {
          ref.invalidate(chatMembersProvider(widget.groupId));
          ref.invalidate(chatDetailProvider(widget.groupId));
        },
      ),
    );
  }

  /// 显示右上角更多菜单
  void _showMoreMenu(BuildContext context, api.Chat chat) {
    final actions = <_TGActionSheetItem>[];

    // 管理员或群主可以编辑群组 (myRole: 2=管理员, 3=群主)
    if (chat.myRole >= 2) {
      actions.add(
        _TGActionSheetItem(
          title: '编辑群组',
          onTap: () {
            Navigator.pop(context);
            _editGroup(context);
          },
        ),
      );
    }

    // 管理员或群主可以处理加入请求
    if (chat.myRole >= 2 && chat.joinApproval) {
      actions.add(
        _TGActionSheetItem(
          title: '加入请求',
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
      );
    }

    // 普通成员和管理员可以退出群组，群主不能退出
    if (chat.myRole >= 1 && chat.myRole < 3) {
      actions.add(
        _TGActionSheetItem(
          title: '退出群组',
          isDestructive: true,
          onTap: () {
            Navigator.pop(context);
            _showLeaveDialog(context);
          },
        ),
      );
    }

    // 只有群主可以解散群组
    if (chat.myRole == 3) {
      actions.add(
        _TGActionSheetItem(
          title: '解散群组',
          isDestructive: true,
          onTap: () {
            Navigator.pop(context);
            _showDissolveDialog(context);
          },
        ),
      );
    }

    if (actions.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(actions: actions, cancelText: '取消'),
    );
  }

  /// 编辑群组
  void _editGroup(BuildContext context) {
    // 桌面端使用面板模式
    if (widget.isDesktopPanel || PlatformUtils.isDesktop) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
        type: DesktopPanelType.groupEdit,
        id: widget.groupId,
        name: widget.name,
        avatar: widget.avatar,
      );
    } else {
      Navigator.push(
        context,
        createPageRoute(
          builder: (context) => _EditGroupPage(
            chatId: widget.groupId,
            name: widget.name,
            avatar: widget.avatar,
          ),
        ),
      );
    }
  }

  /// 显示解散群组对话框
  void _showDissolveDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '解散「${widget.name ?? '该群组'}」？',
        message: '解散后群组将被永久删除，所有成员将被移出',
        actions: [
          _TGActionSheetItem(
            title: '解散群组',
            isDestructive: true,
            onTap: () => _dissolveGroup(context),
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  /// 解散群组
  Future<void> _dissolveGroup(BuildContext context) async {
    Navigator.pop(context);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.delete('/chat/${widget.groupId}');

      if (!mounted) return;

      if (response.isSuccess) {
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '解散失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解散失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 显示成员操作菜单
  void _showMemberActions(
    BuildContext context,
    api.ChatMember member,
    int myRole,
  ) {
    final isOwner = myRole == 3; // 群主
    final isAdmin = myRole == 2; // 管理员
    final isTargetOwner = member.role == 3; // 目标是群主
    final isTargetAdmin = member.role == 2; // 目标是管理员

    final actions = <_TGActionSheetItem>[];

    // 查看资料（所有人都可以）
    actions.add(
      _TGActionSheetItem(
        title: '查看资料',
        onTap: () {
          Navigator.pop(context);
          context.push(
            '/user/${member.userId}?name=${Uri.encodeComponent(member.displayName)}${member.avatar != null ? '&avatar=${Uri.encodeComponent(member.avatar!)}' : ''}',
          );
        },
      ),
    );

    // 群主可以设置/取消管理员（不能操作自己）
    if (isOwner && !isTargetOwner) {
      if (isTargetAdmin) {
        actions.add(
          _TGActionSheetItem(
            title: '取消管理员',
            onTap: () => _setMemberRole(context, member.userId, 0),
          ),
        );
      } else {
        actions.add(
          _TGActionSheetItem(
            title: '设为管理员',
            onTap: () => _setMemberRole(context, member.userId, 1),
          ),
        );
      }
    }

    // 群主和管理员可以禁言（不能禁言群主和管理员，管理员不能禁言管理员）
    if ((isOwner || isAdmin) && !isTargetOwner) {
      if (!(isAdmin && isTargetAdmin)) {
        if (member.isMuted) {
          actions.add(
            _TGActionSheetItem(
              title: '解除禁言',
              onTap: () => _unmuteMember(context, member),
            ),
          );
        } else {
          actions.add(
            _TGActionSheetItem(
              title: '禁言',
              onTap: () => _showMuteOptions(context, member),
            ),
          );
        }
      }
    }

    // 群主和管理员可以移除成员（不能移除群主，管理员不能移除管理员）
    if ((isOwner || isAdmin) && !isTargetOwner) {
      if (!(isAdmin && isTargetAdmin)) {
        actions.add(
          _TGActionSheetItem(
            title: '移出群组',
            isDestructive: true,
            onTap: () => _removeMember(context, member),
          ),
        );
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: member.displayName,
        message: member.role == 3 ? '群主' : (member.role == 2 ? '管理员' : null),
        actions: actions,
        cancelText: '取消',
      ),
    );
  }

  /// 显示禁言时间选项
  void _showMuteOptions(BuildContext context, api.ChatMember member) {
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '禁言 ${member.displayName}',
        actions: [
          _TGActionSheetItem(
            title: '10分钟',
            onTap: () => _muteMember(context, member, 10),
          ),
          _TGActionSheetItem(
            title: '1小时',
            onTap: () => _muteMember(context, member, 60),
          ),
          _TGActionSheetItem(
            title: '1天',
            onTap: () => _muteMember(context, member, 60 * 24),
          ),
          _TGActionSheetItem(
            title: '1周',
            onTap: () => _muteMember(context, member, 60 * 24 * 7),
          ),
          _TGActionSheetItem(
            title: '永久禁言',
            isDestructive: true,
            onTap: () => _muteMember(context, member, 0),
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  /// 禁言成员
  Future<void> _muteMember(
    BuildContext context,
    api.ChatMember member,
    int duration,
  ) async {
    final pageContext = this.context;
    Navigator.pop(context);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/chat/${widget.groupId}/mute',
        data: {'user_id': member.userId, 'duration': duration},
      );

      if (!mounted) return;

      if (response.isSuccess) {
        final durationText = duration == 0
            ? '永久'
            : (duration < 60
                  ? '$duration分钟'
                  : (duration < 1440
                        ? '${duration ~/ 60}小时'
                        : '${duration ~/ 1440}天'));
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('已禁言 ${member.displayName} $durationText'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '禁言失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('禁言失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 解除禁言
  Future<void> _unmuteMember(
    BuildContext context,
    api.ChatMember member,
  ) async {
    Navigator.pop(context);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/chat/${widget.groupId}/unmute',
        data: {'user_id': member.userId},
      );

      if (!mounted) return;

      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已解除 ${member.displayName} 的禁言'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '操作失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 设置成员角色
  Future<void> _setMemberRole(
    BuildContext context,
    String userId,
    int role,
  ) async {
    Navigator.pop(context); // 关闭底部弹窗

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.put(
        '/chat/${widget.groupId}/members/$userId/role',
        data: {'role': role},
      );

      if (!mounted) return;

      if (response.isSuccess) {
        final roleText = role == 1 ? '管理员' : '普通成员';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已设为$roleText'),
            backgroundColor: Colors.green,
          ),
        );
        // 刷新成员列表
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '操作失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 移除成员
  Future<void> _removeMember(
    BuildContext context,
    api.ChatMember member,
  ) async {
    Navigator.pop(context); // 关闭底部弹窗

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出群组'),
        content: Text('确定要将「${member.displayName}」移出群组吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移出'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.delete(
        '/chat/${widget.groupId}/members/${member.userId}',
      );

      if (!mounted) return;

      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已将「${member.displayName}」移出群组'),
            backgroundColor: Colors.green,
          ),
        );
        // 刷新成员列表
        ref.invalidate(chatMembersProvider(widget.groupId));
        ref.invalidate(chatDetailProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '操作失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// 加入请求列表页面
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(approve ? '已通过申请' : '已拒绝申请')));
      _loadRequests(); // 刷新列表
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(response.message ?? '操作失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.isChannel ? '订阅请求' : '加入请求';

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1C1C1E)
          : const Color(0xFFF2F2F7),
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
                  TextButton(onPressed: _loadRequests, child: const Text('重试')),
                ],
              ),
            )
          : _requests.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
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
              name: request.nickname ?? '用户',
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
                    request.nickname ?? '用户',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (request.username != null && request.username!.isNotEmpty)
                    Text(
                      '@${request.username}',
                      style: TextStyle(fontSize: 14, color: AppColors.primary),
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
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: separatorColor,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

//  信息单元格
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
                      color:
                          titleColor ?? (isDark ? Colors.white : Colors.black),
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

//  单元格
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

// 成员单元格
class _MemberCell extends StatelessWidget {
  final api.ChatMember member;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MemberCell({required this.member, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Stack(
              children: [
                AvatarWidget(
                  name: member.displayName,
                  avatar: member.avatar,
                  userId: member.userId,
                  size: 40,
                ),
                if (member.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: ColoredNameWidget(
                          name: member.displayName,
                          nicknameColor: member.nicknameColor,
                          fontSize: 17,
                        ),
                      ),
                      if (member.emojiAvatar != null &&
                          member.emojiAvatar!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        EmojiStatusWidget(emoji: member.emojiAvatar!, size: 18),
                      ],
                      if (member.role >= 2) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: member.role == 3
                                ? AppColors.primary.withOpacity(0.15)
                                : Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            member.role == 3 ? '创建者' : '管理员',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: member.role == 3
                                  ? AppColors.primary
                                  : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        member.isOnline ? '在线' : '离线',
                        style: TextStyle(
                          fontSize: 14,
                          color: member.isOnline ? Colors.green : Colors.grey,
                        ),
                      ),
                      if (member.isMuted) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.volume_off,
                          size: 14,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          member.muteStatusText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade300,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 右侧箭头
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

//  操作表
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          if (title != null)
                            Text(
                              title!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          if (message != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              message!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (title != null || message != null)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: isDark
                          ? const Color(0xFF38383A)
                          : const Color(0xFFC6C6C8),
                    ),
                  ...actions.map(
                    (action) => Column(
                      children: [
                        GestureDetector(
                          onTap: action.onTap,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 16,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    action.title,
                                    style: TextStyle(
                                      fontSize: 20,
                                      color: action.isDestructive
                                          ? Colors.red
                                          : AppColors.primary,
                                    ),
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
                            color: isDark
                                ? const Color(0xFF38383A)
                                : const Color(0xFFC6C6C8),
                          ),
                      ],
                    ),
                  ),
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
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  cancelText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
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

//  操作按钮
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
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
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
class SearchMessagesPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;

  const SearchMessagesPage({required this.chatId, required this.chatName});

  @override
  ConsumerState<SearchMessagesPage> createState() =>
      SearchMessagesPageState();
}

class SearchMessagesPageState extends ConsumerState<SearchMessagesPage> {
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

    // 防抖：等待用户停止输入
    _lastQuery = query;
    await Future.delayed(const Duration(milliseconds: 300));
    if (_lastQuery != query) return; // 用户继续输入，取消本次搜索

    setState(() => _isSearching = true);

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.searchMessages(widget.chatId, query);

      if (mounted && _lastQuery == query) {
        setState(() {
          _isSearching = false;
          _results = response.data?.list ?? [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _results = [];
        });
      }
    }
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
                color: isDark
                    ? const Color(0xFF3A3A3C)
                    : const Color(0xFFF2F2F7),
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
                          icon: Icon(
                            Icons.clear,
                            color: Colors.grey.shade500,
                            size: 20,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                        Icon(
                          Icons.search,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? '输入关键词搜索消息'
                              : '未找到相关消息',
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.grey,
                          ),
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
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: AvatarWidget(
                            avatar: result.senderAvatar,
                            name: result.senderName ?? '',
                            size: 40,
                          ),
                          title: Text(
                            result.senderName ?? '未知用户',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          subtitle: Text(
                            _highlightKeyword(
                              result.text,
                              _searchController.text,
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatDate(result.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          onTap: () {
                            // 关闭搜索页，跳转到聊天页并定位到该消息
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              createPageRoute(
                                builder: (_) => ChatDetailPage(
                                  chatId: widget.chatId,
                                  chatName: widget.chatName,
                                  chatType: ChatType.group,
                                  jumpToMessageId: result.msgId,
                                ),
                              ),
                            );
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

  String _highlightKeyword(String text, String keyword) {
    // 简单返回文本，高亮可以后续用 RichText 实现
    return text;
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
    return DateFormat('yyyy-MM-dd').format(date);
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
      final response = await chatService.getChatMedia(
        widget.chatId,
        widget.type,
        page: 1,
      );

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
      final response = await chatService.getChatMedia(
        widget.chatId,
        widget.type,
        page: _page + 1,
      );

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
      backgroundColor: isDark
          ? const Color(0xFF1C1C1E)
          : const Color(0xFFF2F2F7),
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
            Text(
              '暂无${widget.title}',
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
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 12,
                        ),
                        if (item.duration != null)
                          Text(
                            _formatDuration(item.duration!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
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
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final item = _items[index];
        final text = item.text ?? '';
        final urls = _extractUrls(text);

        if (urls.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: urls
                .map(
                  (url) => ListTile(
                    leading: Icon(Icons.link, color: AppColors.primary),
                    title: Text(
                      url,
                      style: TextStyle(color: AppColors.primary, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    onTap: () => _openUrl(url),
                  ),
                )
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
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final item = _items[index];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(item.fileName),
                color: AppColors.primary,
              ),
            ),
            title: Text(
              item.fileName ?? '未知文件',
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatFileSize(item.fileSize ?? 0)} · ${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            onTap: () => _downloadFile(item),
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
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final item = _items[index];
        final isThisPlaying = _playingVoiceId == item.id && _isPlaying;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isThisPlaying
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                isThisPlaying ? Icons.graphic_eq : Icons.mic,
                color: isThisPlaying ? Colors.white : AppColors.primary,
              ),
            ),
            title: Text(
              '语音消息 ${_formatDuration(item.duration ?? 0)}',
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              '${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
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

  void _downloadFile(api.ChatMediaItem item) {
    final fileUrl = item.fileUrl;
    if (fileUrl != null) {
      Clipboard.setData(ClipboardData(text: fileUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件链接已复制'),
          duration: Duration(seconds: 1),
        ),
      );
    }
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

class _GroupQrCodePage extends StatelessWidget {
  final String groupName;
  final String? groupAvatar;
  final int memberCount;
  final String inviteLink;

  const _GroupQrCodePage({
    required this.groupName,
    required this.groupAvatar,
    required this.memberCount,
    required this.inviteLink,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qrData = buildGroupQrPayload(inviteLink);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1C1C1E)
          : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '群二维码',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  AvatarWidget(
                    avatar: groupAvatar,
                    name: groupName,
                    size: 84,
                    borderRadius: 22,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    groupName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$memberCount 位成员',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 240,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.primary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '扫一扫即可加入群组',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 编辑群组页面
class _EditGroupPage extends ConsumerStatefulWidget {
  final String chatId;
  final String? name;
  final String? avatar;

  const _EditGroupPage({required this.chatId, this.name, this.avatar});

  @override
  ConsumerState<_EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends ConsumerState<_EditGroupPage> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  bool _isLoading = false;
  bool _isSaving = false;

  // 权限设置
  bool _joinApproval = false;
  bool _canSendMessage = true;
  bool _canSendMedia = true;
  bool _canSendLinks = true;
  bool _canAddMembers = true;
  bool _canPinMessages = true;
  bool _memberProtection = false;

  // 群组号
  String? _username;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name ?? '');
    _descController = TextEditingController();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    setState(() => _isLoading = true);
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    if (chatDetail != null) {
      setState(() {
        _descController.text = chatDetail.description ?? '';
        _joinApproval = chatDetail.joinApproval;
        _canSendMessage = chatDetail.canSendMessage;
        _canSendMedia = chatDetail.canSendMedia;
        _canSendLinks = chatDetail.canSendLinks;
        _canAddMembers = chatDetail.canAddMembers;
        _canPinMessages = chatDetail.canPinMessages;
        _memberProtection = chatDetail.memberProtection;
        _username = chatDetail.username;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.put(
        '/chat/${widget.chatId}',
        data: {key: value},
      );

      if (!mounted) return;

      if (response.isSuccess) {
        ref.invalidate(chatDetailProvider(widget.chatId));
      } else {
        // 恢复原值
        _loadGroupInfo();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '设置失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _loadGroupInfo();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('群组名称不能为空'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.put(
        '/chat/${widget.chatId}',
        data: {
          'name': _nameController.text.trim(),
          'description': _descController.text.trim(),
        },
      );

      if (!mounted) return;

      if (response.isSuccess) {
        // 更新聊天列表中对应的聊天项（不要 invalidate 整个 chatListProvider）
        final existingChat = ref
            .read(chatListProvider.notifier)
            .getChatById(widget.chatId);
        if (existingChat != null) {
          final updatedChat = existingChat.copyWith(
            name: _nameController.text.trim(),
            description: _descController.text.trim().isNotEmpty
                ? _descController.text.trim()
                : null,
          );
          ref.read(chatListProvider.notifier).updateChat(updatedChat);
        }
        ref.invalidate(chatDetailProvider(widget.chatId));
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '保存失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除群组'),
        content: const Text('确定要删除此群组吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.delete('/chat/${widget.chatId}');

      if (!mounted) return;

      if (response.isSuccess) {
        ref.read(chatListProvider.notifier).deleteChat(widget.chatId);
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('群组已删除'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '删除失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final separatorColor = isDark
        ? const Color(0xFF38383A)
        : const Color(0xFFE5E5EA);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: AppColors.primary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '编辑群组',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '编辑群组',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '完成',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 群名称
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '用户名长度为 5-32 个字符，只能包含字母、数字和下划线。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Container(
            color: cardColor,
            child: Column(
              children: [
                // 群组号
                if (_username != null && _username!.isNotEmpty)
                  ListTile(
                    leading: Icon(
                      Icons.alternate_email,
                      color: AppColors.primary,
                    ),
                    title: const Text('群组号'),
                    subtitle: Text(
                      '@$_username',
                      style: TextStyle(color: AppColors.primary, fontSize: 14),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: '@$_username'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('群组号已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // 加入设置
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '加入设置',
              style: TextStyle(fontSize: 13, color: AppColors.primary),
            ),
          ),
          Container(
            color: cardColor,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('加入需要审批'),
                  subtitle: const Text(
                    '新成员需要管理员或群主批准才能加入',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  value: _joinApproval,
                  activeColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() => _joinApproval = value);
                    _updateSetting('join_approval', value);
                  },
                ),
              ],
            ),
          ),

          // 权限设置
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '权限设置',
              style: TextStyle(fontSize: 13, color: AppColors.primary),
            ),
          ),
          Container(
            color: cardColor,
            child: Column(
              children: [
                _PermissionTile(
                  icon: Icons.volume_off_outlined,
                  title: '全员禁言',
                  subtitle: '开启后仅管理员和创建者可发言',
                  value: !_canSendMessage,
                  onChanged: (value) {
                    setState(() => _canSendMessage = !value);
                    _updateSetting('can_send_message', !value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.image_outlined,
                  title: '发送媒体',
                  subtitle: '成员可以发送图片、视频和文件',
                  value: _canSendMedia,
                  onChanged: (value) {
                    setState(() => _canSendMedia = value);
                    _updateSetting('can_send_media', value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.link,
                  title: '发送链接',
                  subtitle: '成员可以发送链接预览',
                  value: _canSendLinks,
                  onChanged: (value) {
                    setState(() => _canSendLinks = value);
                    _updateSetting('can_send_links', value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.person_add_outlined,
                  title: '添加成员',
                  subtitle: '成员可以邀请其他人加入',
                  value: _canAddMembers,
                  onChanged: (value) {
                    setState(() => _canAddMembers = value);
                    _updateSetting('can_add_members', value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: '群成员保护',
                  subtitle: '开启后普通成员只能看到管理员和群主，且无法点开成员资料',
                  value: _memberProtection,
                  onChanged: (value) {
                    setState(() => _memberProtection = value);
                    _updateSetting('member_protection', value);
                  },
                ),
              ],
            ),
          ),

          // 删除群组
          const SizedBox(height: 30),
          Container(
            color: cardColor,
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('删除群组', style: TextStyle(color: Colors.red)),
              onTap: _deleteGroup,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// 权限设置项
class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.primary),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      value: value,
      activeColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}

// 添加成员选择器
class _AddMemberSheet extends ConsumerStatefulWidget {
  final String chatId;
  final VoidCallback onMembersAdded;

  const _AddMemberSheet({required this.chatId, required this.onMembersAdded});

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final Set<String> _selectedIds = {};
  bool _isLoading = false;
  bool _isLoadingContacts = true;
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool get _hasCachedContacts => ref.read(contactListProvider).isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 加载联系人列表
    _loadContacts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final notifier = ref.read(contactListProvider.notifier);
    if (mounted) {
      setState(() => _isLoadingContacts = !_hasCachedContacts);
    }
    try {
      await notifier.initialize();
      if (notifier.shouldRefresh) {
        await notifier.loadFromServer();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingContacts = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  Future<void> _addMembers() async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/chat/${widget.chatId}/members',
        data: {'user_ids': _selectedIds.toList()},
      );

      if (!mounted) return;

      if (response.isSuccess) {
        widget.onMembersAdded();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加 ${_selectedIds.length} 位成员'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '添加失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF2F2F7);
    final contactsAsync = ref.watch(contactListProvider);
    final membersAsync = ref.watch(chatMembersProvider(widget.chatId));

    // 获取现有成员ID列表
    final existingMemberIds =
        membersAsync.valueOrNull?.map((m) => m.userId).toSet() ?? {};

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 顶部拖动条
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '取消',
                    style: TextStyle(color: Colors.grey, fontSize: 17),
                  ),
                ),
                Text(
                  '添加成员',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                TextButton(
                  onPressed: _selectedIds.isEmpty || _isLoading
                      ? null
                      : _addMembers,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '添加${_selectedIds.isNotEmpty ? "(${_selectedIds.length})" : ""}',
                          style: TextStyle(
                            color: _selectedIds.isEmpty
                                ? Colors.grey
                                : AppColors.primary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                onChanged: _onSearchChanged,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: '搜索联系人',
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 联系人列表
          Expanded(
            child: _isLoadingContacts
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final contacts = contactsAsync;

                      // 过滤掉已是群成员的联系人
                      var filteredContacts = contacts
                          .where((c) => !existingMemberIds.contains(c.uuid))
                          .toList();

                      // 搜索过滤
                      if (_searchQuery.isNotEmpty) {
                        filteredContacts = filteredContacts
                            .where((c) => c.matchesQuery(_searchQuery))
                            .toList();
                      }

                      if (filteredContacts.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_off_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? '未找到联系人'
                                    : '没有可添加的联系人',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredContacts.length,
                        itemBuilder: (context, index) {
                          final contact = filteredContacts[index];
                          final isSelected = _selectedIds.contains(
                            contact.uuid,
                          );
                          final displayName = contact.name.isNotEmpty
                              ? contact.name
                              : (contact.username ?? '用户');

                          return ListTile(
                            leading: Stack(
                              children: [
                                AvatarWidget(
                                  name: displayName,
                                  avatar: contact.avatar,
                                  userId: contact.uuid,
                                  size: 44,
                                ),
                                if (isSelected)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: bgColor,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: ColoredNameWidget(
                                    name: displayName,
                                    nicknameColor: contact.nicknameColor,
                                    fontSize: 17,
                                  ),
                                ),
                                if (contact.emojiAvatar != null &&
                                    contact.emojiAvatar!.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  EmojiStatusWidget(
                                    emoji: contact.emojiAvatar!,
                                    size: 18,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: contact.username != null
                                ? Text(
                                    '@${contact.username}',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  )
                                : null,
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary,
                                  )
                                : Icon(
                                    Icons.radio_button_unchecked,
                                    color: Colors.grey.shade400,
                                  ),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(contact.uuid);
                                } else {
                                  _selectedIds.add(contact.uuid!);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
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
                    backgroundDecoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    loadingBuilder: (context, event) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
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
      ..initialize()
          .then((_) {
            if (!mounted) return;
            setState(() => _isInitialized = true);
            _controller.play();
          })
          .catchError((e) {
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
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
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
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _controller.value.position.inMilliseconds
                                .toDouble()
                                .clamp(
                                  0,
                                  _controller.value.duration.inMilliseconds
                                      .toDouble(),
                                ),
                            min: 0,
                            max: _controller.value.duration.inMilliseconds
                                .toDouble()
                                .clamp(1, double.infinity),
                            activeColor: AppColors.primary,
                            inactiveColor: Colors.white38,
                            onChanged: (value) {
                              _controller.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                            },
                          ),
                        ),
                        Text(
                          _formatDuration(_controller.value.duration),
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
          ],
        ),
      ),
    );
  }
}

// ============ 群公告页面 ============

class _GroupAnnouncementsPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;

  const _GroupAnnouncementsPage({required this.chatId, required this.chatName});

  @override
  ConsumerState<_GroupAnnouncementsPage> createState() =>
      _GroupAnnouncementsPageState();
}

class _GroupAnnouncementsPageState
    extends ConsumerState<_GroupAnnouncementsPage> {
  List<api.AnnouncementItem> _announcements = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _page = 1;
  bool _isLoadingInProgress = false;
  Timer? _wsDebounceTimer;
  static const _pageSize = 20;

  String? _wsNewId;
  String? _wsUpdatedId;
  String? _wsDeletedId;
  WebSocketService? _wsService;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    _setupWsListeners();
  }

  void _setupWsListeners() {
    _wsService = ref.read(webSocketServiceProvider.notifier);
    _wsNewId = _wsService!.registerHandler(WSMessageType.chatAnnouncement, (
      data,
    ) {
      if (!mounted || data is! Map) return;
      final chatId = data['chat_id']?.toString();
      if (chatId == widget.chatId) _debouncedRefresh();
    });
    _wsUpdatedId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncementUpdated,
      (data) {
        if (!mounted || data is! Map) return;
        final chatId = data['chat_id']?.toString();
        if (chatId == widget.chatId) _debouncedRefresh();
      },
    );
    _wsDeletedId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncementDeleted,
      (data) {
        if (!mounted || data is! Map) return;
        final chatId = data['chat_id']?.toString();
        if (chatId == widget.chatId) _debouncedRefresh();
      },
    );
  }

  void _debouncedRefresh() {
    _wsDebounceTimer?.cancel();
    _wsDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadAnnouncements(refresh: true);
    });
  }

  @override
  void dispose() {
    _wsDebounceTimer?.cancel();
    if (_wsService != null) {
      for (final id in [_wsNewId, _wsUpdatedId, _wsDeletedId]) {
        if (id != null) _wsService!.unregisterHandler(id);
      }
    }
    super.dispose();
  }

  Future<void> _loadAnnouncements({bool refresh = false}) async {
    if (_isLoadingInProgress) return;
    _isLoadingInProgress = true;

    try {
      if (refresh) {
        _page = 1;
        _hasMore = true;
      }
      if (mounted) setState(() => _isLoading = true);

      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getAnnouncements(
        widget.chatId,
        page: refresh ? 1 : _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final result = response.data!;
        setState(() {
          if (refresh || _page == 1) {
            _announcements = result.list;
          } else {
            _announcements.addAll(result.list);
          }
          _hasMore = _announcements.length < result.total;
          _page = (refresh ? 1 : _page) + 1;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _isLoadingInProgress = false;
    }
  }

  bool get _canManage {
    final chat = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    return chat != null && chat.myRole >= 2;
  }

  Future<void> _createOrEditAnnouncement({
    api.AnnouncementItem? existing,
  }) async {
    final controller = TextEditingController(text: existing?.content ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          existing != null ? '编辑公告' : '发布公告',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: controller,
          maxLines: 8,
          minLines: 3,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: '输入公告内容...',
            hintStyle: TextStyle(color: Colors.grey.shade500),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: Text(
              '发布',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = existing != null
          ? await chatService.updateAnnouncement(
              widget.chatId,
              existing.id,
              result,
            )
          : await chatService.createAnnouncement(widget.chatId, result);

      if (!mounted) return;
      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null ? '公告已更新' : '公告已发布'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAnnouncements(refresh: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '操作失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement(api.AnnouncementItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除公告'),
        content: const Text('确定要删除这条公告吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.deleteAnnouncement(
        widget.chatId,
        item.id,
      );
      if (!mounted) return;
      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('公告已删除'), backgroundColor: Colors.green),
        );
        _loadAnnouncements(refresh: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '删除失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canManage = _canManage;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '群公告',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          if (canManage)
            IconButton(
              icon: Icon(Icons.add, color: AppColors.primary),
              onPressed: () => _createOrEditAnnouncement(),
            ),
        ],
      ),
      body: _isLoading && _announcements.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无群公告',
                    style: TextStyle(fontSize: 17, color: Colors.grey.shade500),
                  ),
                  if (canManage) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _createOrEditAnnouncement(),
                      child: Text(
                        '发布公告',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadAnnouncements(refresh: true),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _announcements.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _announcements.length) {
                    if (!_isLoadingInProgress) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _loadAnnouncements();
                      });
                    }
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _buildAnnouncementCard(
                    context,
                    _announcements[index],
                    isDark,
                    canManage,
                  );
                },
              ),
            ),
    );
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    api.AnnouncementItem item,
    bool isDark,
    bool canManage,
  ) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                if (item.authorAvatar != null && item.authorAvatar!.isNotEmpty)
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: CachedNetworkImageProvider(
                      item.authorAvatar!,
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Icon(
                      Icons.person,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.authorName ?? '管理员',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    onSelected: (action) {
                      if (action == 'edit') {
                        _createOrEditAnnouncement(existing: item);
                      } else if (action == 'delete') {
                        _deleteAnnouncement(item);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: SelectableText(
              item.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
