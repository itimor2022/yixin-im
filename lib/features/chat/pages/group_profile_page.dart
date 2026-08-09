// 文件用途：实现 _GroupProfileIconAssets 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _GroupProfileIconAssets 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/qr_payload.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/voice_playback_audio_context.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/upload_service.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../vip/widgets/vip_badge.dart';
import 'message_search_page.dart';
import 'report_page.dart';

const Color _groupProfileInk = Color(0xFF15171A);
const Color _groupProfileSubtleInk = Color(0xFF6C737F);
const Color _groupProfileMutedInk = Color(0xFF8A9099);
const Color _groupProfileBg = Color(0xFFF1F2F5);
const Color _groupProfileCard = Colors.white;
const Color _groupProfileControlBg = Color(0xFFF0F1F4);
const Color _groupProfileSeparator = Color(0xFFE1E4EA);

Color _groupProfileInkFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textPrimaryFor(context)
        : _groupProfileInk;

Color _groupProfileSubtleInkFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryFor(context)
        : _groupProfileSubtleInk;

Color _groupProfileMutedInkFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textTertiaryFor(context)
        : _groupProfileMutedInk;

const List<Color> _groupProfileActionNeutral = [
  Color(0xFFF7F8FA),
  Color(0xFFE9ECF1),
];
const List<Color> _groupProfileActionNeutralActive = [
  Color(0xFFF2F3F5),
  Color(0xFFE2E5EA),
];
const List<Color> _groupProfileIconNeutral = [
  Color(0xFFF5F6F8),
  Color(0xFFFFFFFF),
];
const List<Color> _groupProfileActionDark = [
  Color(0xFF263342),
  Color(0xFF1D2530),
];
const List<Color> _groupProfileActionDarkActive = [
  Color(0xFF1E4975),
  Color(0xFF193957),
];
const List<Color> _groupProfileIconDark = [
  Color(0xFF263342),
  Color(0xFF1D2530),
];

// 关键声明：group profile page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _GroupProfileIconAssets {
  static const String mute = 'assets/icons/group_profile/lucide_bell_off.svg';
  static const String search = 'assets/icons/group_profile/lucide_search.svg';
  static const String announcement =
      'assets/icons/group_profile/lucide_megaphone.svg';
  static const String photo = 'assets/icons/group_profile/lucide_image.svg';
  static const String file = 'assets/icons/group_profile/lucide_file.svg';
  static const String link = 'assets/icons/group_profile/lucide_link.svg';
  static const String voice = 'assets/icons/group_profile/lucide_mic.svg';
  static const String qr = 'assets/icons/group_profile/lucide_qr_code.svg';
}

String _groupProfileText(
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

String _groupServerMessage(
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

String _groupMemberCountText(BuildContext context, int count) {
  return _groupProfileText(
    context,
    zhCN: '$count 位成员',
    zhTW: '$count 位成員',
    en: '$count members',
  );
}

String _groupRelativeTimeText(BuildContext context, DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return _groupProfileText(context, zhCN: '刚刚', zhTW: '剛剛', en: 'Just now');
  }
  if (diff.inHours < 1) {
    return _groupProfileText(
      context,
      zhCN: '${diff.inMinutes}分钟前',
      zhTW: '${diff.inMinutes}分鐘前',
      en: '${diff.inMinutes} min ago',
    );
  }
  if (diff.inDays < 1) {
    return _groupProfileText(
      context,
      zhCN: '${diff.inHours}小时前',
      zhTW: '${diff.inHours}小時前',
      en: '${diff.inHours} hr ago',
    );
  }
  if (diff.inDays < 7) {
    return _groupProfileText(
      context,
      zhCN: '${diff.inDays}天前',
      zhTW: '${diff.inDays}天前',
      en: '${diff.inDays} days ago',
    );
  }
  return _groupProfileText(
    context,
    zhCN: '${time.month}月${time.day}日',
    zhTW: '${time.month}月${time.day}日',
    en: '${time.month}/${time.day}',
  );
}

String _fallbackGroupName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _groupProfileText(context, zhCN: '群组', zhTW: '群組', en: 'Group');
}

String _fallbackThisGroupName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _groupProfileText(context, zhCN: '该群组', zhTW: '該群組', en: 'this group');
}

String _fallbackUserName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _groupProfileText(context, zhCN: '用户', zhTW: '用戶', en: 'User');
}

String _fallbackAdminName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _groupProfileText(context, zhCN: '管理员', zhTW: '管理員', en: 'Admin');
}

String _unknownFileText(BuildContext context) {
  return _groupProfileText(
    context,
    zhCN: '未知文件',
    zhTW: '未知檔案',
    en: 'Unknown File',
  );
}

String _unknownUserText(BuildContext context) {
  return _groupProfileText(
    context,
    zhCN: '未知用户',
    zhTW: '未知用戶',
    en: 'Unknown User',
  );
}

String _creatorText(BuildContext context) {
  return _groupProfileText(context, zhCN: '创建者', zhTW: '建立者', en: 'Owner');
}

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

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
    // 角色、成员数和群权限以服务端详情为准；本地聊天列表只提供页面占位信息。
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
    final activeMembersAsync =
        memberKeyword.isEmpty ? membersAsync : searchedMembersAsync!;
    final bgColor = isDark ? AppColors.darkBackground : _groupProfileBg;
    final cardColor = isDark ? AppColors.darkCard : _groupProfileCard;
    final separatorColor =
        isDark ? AppColors.darkDivider : _groupProfileSeparator;
    final headerColor = isDark ? AppColors.darkBackground : Colors.white;
    final primaryTextColor =
        isDark ? AppColors.darkTextPrimary : _groupProfileInkFor(context);
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : _groupProfileSubtleInkFor(context);
    final iconColor =
        isDark ? AppColors.primaryFor(context) : _groupProfileInkFor(context);
    final controlBg =
        isDark ? AppColors.darkControlBackground : _groupProfileControlBg;
    final actionIconColor =
        isDark ? AppColors.primaryFor(context) : const Color(0xFF252932);
    final actionGradient =
        isDark ? _groupProfileActionDark : _groupProfileActionNeutral;
    final actionGradientActive = isDark
        ? _groupProfileActionDarkActive
        : _groupProfileActionNeutralActive;
    final mediaIconBackground =
        isDark ? _groupProfileIconDark : _groupProfileIconNeutral;

    // 桌面端使用居中布局
    Widget content = Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // iOS 风格导航栏
          SliverAppBar(
            pinned: true,
            backgroundColor: headerColor,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 20, color: iconColor),
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
                          icon: Icon(Icons.more_horiz, color: iconColor),
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
                                      ? const Color(0xFF111315)
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
              color: headerColor,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  // 群头像
                  AvatarWidget(
                    avatar: widget.avatar,
                    name: widget.name ??
                        _groupProfileText(
                          context,
                          zhCN: '群组',
                          zhTW: '群組',
                          en: 'Group',
                        ),
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
                            widget.name ??
                                _groupProfileText(
                                  context,
                                  zhCN: '群组',
                                  zhTW: '群組',
                                  en: 'Group',
                                ),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: primaryTextColor,
                            ),
                          ),
                          if (isOfficial) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 22,
                              color: iconColor,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  // 成员数
                  Text(
                    chatDetail != null
                        ? _groupMemberCountText(context, chatDetail.memberCount)
                        : (chatDetailAsync.isLoading
                            ? l10n.loading
                            : _groupProfileText(
                                context,
                                zhCN: '群组',
                                zhTW: '群組',
                                en: 'Group',
                              )),
                    style: TextStyle(fontSize: 15, color: secondaryTextColor),
                  ),
                ],
              ),
            ),
          ),

          // 操作按钮
          SliverToBoxAdapter(
            child: Container(
              color: headerColor,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Consumer(
                builder: (context, ref, _) {
                  // 获取当前群组的静音状态
                  final chatListState = ref.watch(chatListProvider);
                  final allChats = chatListState.allChats;
                  final currentChat =
                      allChats.where((c) => c.id == widget.groupId).firstOrNull;
                  final isMuted = currentChat?.isMuted ?? false;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TGActionButton(
                        icon: Icons.notifications_off_outlined,
                        iconAsset: _GroupProfileIconAssets.mute,
                        label: isMuted ? l10n.unmute : l10n.mute,
                        isActive: isMuted,
                        iconColor: actionIconColor,
                        gradientColors:
                            isMuted ? actionGradientActive : actionGradient,
                        onTap: () {
                          GlobalHaptics.medium();
                          ref
                              .read(chatListProvider.notifier)
                              .toggleMute(widget.groupId);
                        },
                      ),
                      _TGActionButton(
                        icon: Icons.search,
                        iconAsset: _GroupProfileIconAssets.search,
                        label: l10n.search,
                        iconColor: actionIconColor,
                        gradientColors: actionGradient,
                        onTap: () => _searchMessages(context),
                      ),
                      _TGActionButton(
                        icon: Icons.campaign_outlined,
                        iconAsset: _GroupProfileIconAssets.announcement,
                        label: _groupProfileText(
                          context,
                          zhCN: '公告',
                          zhTW: '公告',
                          en: 'Announcements',
                        ),
                        iconColor: actionIconColor,
                        gradientColors: actionGradient,
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
                        : _groupProfileText(
                            context,
                            zhCN: '暂无简介',
                            zhTW: '暫無簡介',
                            en: 'No description',
                          ),
                    subtitle: l10n.description,
                  )
                else if (chatDetailAsync.isLoading)
                  _TGInfoCell(title: l10n.loading, subtitle: l10n.description)
                else
                  _TGInfoCell(
                    title: _groupProfileText(
                      context,
                      zhCN: '暂无简介',
                      zhTW: '暫無簡介',
                      en: 'No description',
                    ),
                    subtitle: l10n.description,
                  ),
                // 群组号
                if (chatDetail?.username?.isNotEmpty == true)
                  _TGInfoCell(
                    title: '@${chatDetail!.username}',
                    subtitle: _groupProfileText(
                      context,
                      zhCN: '群组号',
                      zhTW: '群組號',
                      en: 'Group ID',
                    ),
                    titleColor: primaryTextColor,
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: '@${chatDetail.username}'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _groupProfileText(
                              context,
                              zhCN: '群组号已复制',
                              zhTW: '群組號已複製',
                              en: 'Group ID copied',
                            ),
                          ),
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
                  iconAsset: _GroupProfileIconAssets.photo,
                  iconColor: actionIconColor,
                  iconBackgroundColors: mediaIconBackground,
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
                  iconAsset: _GroupProfileIconAssets.file,
                  iconColor: actionIconColor,
                  iconBackgroundColors: mediaIconBackground,
                  title: l10n.file,
                  trailing: _buildCountTrailing('${_mediaCounts?.file ?? 0}'),
                  onTap: () => _showMediaList(context, l10n.file, 'file'),
                ),
                _TGCell(
                  icon: Icons.link,
                  iconAsset: _GroupProfileIconAssets.link,
                  iconColor: actionIconColor,
                  iconBackgroundColors: mediaIconBackground,
                  title: l10n.get('shared_links'),
                  trailing: _buildCountTrailing('${_mediaCounts?.link ?? 0}'),
                  onTap: () =>
                      _showMediaList(context, l10n.get('shared_links'), 'link'),
                ),
                _TGCell(
                  icon: Icons.mic_outlined,
                  iconAsset: _GroupProfileIconAssets.voice,
                  iconColor: actionIconColor,
                  iconBackgroundColors: mediaIconBackground,
                  title: l10n.get('voice_messages'),
                  trailing: _buildCountTrailing('${_mediaCounts?.voice ?? 0}'),
                  onTap: () => _showMediaList(
                    context,
                    l10n.get('voice_messages'),
                    'voice',
                  ),
                ),
                if (chatDetail != null &&
                    (chatDetail.inviteLink?.trim().isNotEmpty ?? false))
                  _TGCell(
                    icon: Icons.qr_code_2_rounded,
                    iconAsset: _GroupProfileIconAssets.qr,
                    iconColor: actionIconColor,
                    iconBackgroundColors: mediaIconBackground,
                    title: _groupProfileText(
                      context,
                      zhCN: '群二维码',
                      zhTW: '群二維碼',
                      en: 'Group QR Code',
                    ),
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
                    l10n.members,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: secondaryTextColor,
                    ),
                  ),
                  const Spacer(),
                  activeMembersAsync.when(
                    data: (members) => Text(
                      '${members.length}',
                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _showMemberSearch ? Icons.close : Icons.search,
                      size: 20,
                      color: iconColor,
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
                      iconColor: iconColor,
                      title: l10n.addMembers,
                      titleColor: primaryTextColor,
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
                          title: l10n.get('join_requests'),
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
                          hintText: _groupProfileText(
                            context,
                            zhCN: '搜索成员昵称或用户名',
                            zhTW: '搜尋成員暱稱或使用者名稱',
                            en: 'Search member nickname or username',
                          ),
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
                          fillColor: AppColors.inputBackgroundFor(context),
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
                              memberKeyword.isEmpty
                                  ? _groupProfileText(
                                      context,
                                      zhCN: '暂无成员',
                                      zhTW: '暫無成員',
                                      en: 'No members',
                                    )
                                  : _groupProfileText(
                                      context,
                                      zhCN: '未找到成员',
                                      zhTW: '未找到成員',
                                      en: 'No members found',
                                    ),
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
                                  final currentUserId =
                                      ref.read(authServiceProvider).user?.uuid;
                                  // 管理员或群主点击显示操作菜单
                                  if (myRole >= 2 ||
                                      currentUserId == member.userId) {
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
                    error: (_, __) => Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text(l10n.get('loading_failed'))),
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
                _TGCell(
                  title: _groupProfileText(
                    context,
                    zhCN: '举报群聊',
                    zhTW: '檢舉群聊',
                    en: 'Report group',
                  ),
                  titleColor: Colors.red,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReportPage(
                        targetId: widget.groupId,
                        targetType: 'group',
                        targetName: _fallbackGroupName(context, widget.name),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: separatorColor,
                  ),
                ),
                if (chatDetail != null && chatDetail.myRole == 3) ...[
                  _TGCell(
                    title: _groupProfileText(
                      context,
                      zhCN: '清空群消息',
                      zhTW: '清空群訊息',
                      en: 'Clear group messages',
                    ),
                    titleColor: Colors.red,
                    onTap: () => _showClearGroupMessagesDialog(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: separatorColor,
                    ),
                  ),
                  // 群主 - 显示解散群组
                  _TGCell(
                    title: l10n.deleteGroup,
                    titleColor: Colors.red,
                    onTap: () => _showDissolveDialog(context),
                  ),
                ] else if (chatDetail != null && chatDetail.myRole >= 1)
                  // 已加入 - 显示退出群组
                  _TGCell(
                    title: l10n.leaveGroup,
                    titleColor: Colors.red,
                    onTap: () => _showLeaveDialog(context),
                  )
                else if (chatDetailAsync.isLoading && _lastChatDetail == null)
                  const SizedBox.shrink()
                else
                  // 未加入 - 显示加入群组
                  _TGCell(
                    title: l10n.get('join_group'),
                    titleColor: primaryTextColor,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 26),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkControlBackgroundStrong
                : const Color(0xFFF4F6F9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : const Color(0xFF9AA1AA),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Icon(
          Icons.chevron_right_rounded,
          color: isDark ? AppColors.darkTextTertiary : Colors.grey.shade400,
          size: 20,
        ),
      ],
    );
  }

  Widget _buildChevronTrailing() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Icon(
      Icons.chevron_right_rounded,
      color: isDark ? AppColors.darkTextTertiary : Colors.grey.shade400,
      size: 20,
    );
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
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '群二维码暂不可用',
              zhTW: '群二維碼暫不可用',
              en: 'Group QR code is unavailable',
            ),
          ),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _GroupQrCodePage(
          groupName: chat.name ??
              widget.name ??
              _groupProfileText(context, zhCN: '群组', zhTW: '群組', en: 'Group'),
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
        content: Text(
          _groupProfileText(
            context,
            zhCN: '$feature 功能暂未开放',
            zhTW: '$feature 功能暫未開放',
            en: '$feature is not available yet',
          ),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _searchMessages(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => MessageSearchPage(
          chatId: widget.groupId,
          chatName: _fallbackGroupName(context, widget.name),
          chatType: 'group',
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
          chatName: _fallbackGroupName(context, widget.name),
        ),
      ),
    );
  }

  void _openAutoMessages(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _GroupAutoMessagesPage(
          chatId: widget.groupId,
          chatName: _fallbackGroupName(context, widget.name),
          isChannel: _lastChatDetail?.type == api.ChatType.channel,
        ),
      ),
    );
  }

  void _showLeaveDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _groupProfileText(
          context,
          zhCN: '退出「${_fallbackThisGroupName(context, widget.name)}」？',
          zhTW: '退出「${_fallbackThisGroupName(context, widget.name)}」？',
          en: 'Leave "${_fallbackThisGroupName(context, widget.name)}"?',
        ),
        message: _groupProfileText(
          context,
          zhCN: '退出后将不再接收此群组的消息',
          zhTW: '退出後將不再接收此群組的訊息',
          en: 'You will stop receiving messages from this group after leaving.',
        ),
        actions: [
          _TGActionSheetItem(
            title: AppLocalizations.of(context).leaveGroup,
            isDestructive: true,
            onTap: () => _leaveGroup(context),
          ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
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
    // 同一个成功响应可能表示“已直接加入”或“申请已提交”，两种状态不能混为一谈。
    final (success, _, requiresApproval, approvalMsg) = await ref
        .read(chatListProvider.notifier)
        .joinChatFromServer(widget.groupId);

    if (!mounted) return;

    if (success) {
      if (requiresApproval) {
        // 需要审批 - 这个提示还是需要的
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approvalMsg ??
                  _groupProfileText(
                    context,
                    zhCN: '已提交加入申请，请等待审批',
                    zhTW: '已提交加入申請，請等待審批',
                    en: 'Join request submitted. Please wait for approval.',
                  ),
            ),
          ),
        );
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
          chatName: _fallbackGroupName(context, widget.name),
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
          title: _groupProfileText(
            context,
            zhCN: '编辑群组',
            zhTW: '編輯群組',
            en: 'Edit Group',
          ),
          onTap: () {
            Navigator.pop(context);
            _editGroup(context);
          },
        ),
      );
      if (chat.myRole >= 3) {
        actions.add(
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '定时群消息',
              zhTW: '定時群訊息',
              en: 'Scheduled Group Messages',
            ),
            onTap: () {
              Navigator.pop(context);
              _openAutoMessages(context);
            },
          ),
        );
      }
    }

    // 管理员或群主可以处理加入请求
    if (chat.myRole >= 2 && chat.joinApproval) {
      actions.add(
        _TGActionSheetItem(
          title: AppLocalizations.of(context).get('join_requests'),
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
          title: AppLocalizations.of(context).leaveGroup,
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
          title: _groupProfileText(
            context,
            zhCN: '清空群消息',
            zhTW: '清空群訊息',
            en: 'Clear group messages',
          ),
          isDestructive: true,
          onTap: () {
            Navigator.pop(context);
            _showClearGroupMessagesDialog(context);
          },
        ),
      );
      actions.add(
        _TGActionSheetItem(
          title: AppLocalizations.of(context).deleteGroup,
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
      builder: (context) => _TGActionSheet(
        actions: actions,
        cancelText: AppLocalizations.of(context).cancel,
      ),
    );
  }

  /// 编辑群组
  void _editGroup(BuildContext context) {
    // 桌面端使用面板模式
    if (widget.isDesktopPanel || PlatformUtils.useDesktopLayout(context)) {
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

  void _showClearGroupMessagesDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _groupProfileText(
          context,
          zhCN: '清空群消息？',
          zhTW: '清空群訊息？',
          en: 'Clear group messages?',
        ),
        message: _groupProfileText(
          context,
          zhCN: '将删除本群所有聊天消息，所有成员都会同步清空。此操作不可恢复。',
          zhTW: '將刪除本群所有聊天訊息，所有成員都會同步清空。此操作無法復原。',
          en: 'All messages in this group will be deleted for every member. This cannot be undone.',
        ),
        actions: [
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '清空群消息',
              zhTW: '清空群訊息',
              en: 'Clear group messages',
            ),
            isDestructive: true,
            onTap: () => _clearGroupMessages(context),
          ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
      ),
    );
  }

  Future<void> _clearGroupMessages(BuildContext context) async {
    Navigator.pop(context);

    try {
      final response = await ref
          .read(api.chatServiceProvider)
          .clearGroupMessages(widget.groupId);

      if (!mounted) return;

      if (response.isSuccess) {
        ref.invalidate(chatDetailProvider(widget.groupId));
        await ref
            .read(chatListProvider.notifier)
            .silentRefresh(bypassDebounce: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '群消息已清空',
                zhTW: '群訊息已清空',
                en: 'Group messages cleared',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '清空群消息失败',
                zhTW: '清空群訊息失敗',
                en: 'Failed to clear group messages',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '清空群消息失败，请重试',
                zhTW: '清空群訊息失敗，請重試',
                en: 'Failed to clear group messages. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 显示解散群组对话框
  void _showDissolveDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _groupProfileText(
          context,
          zhCN: '解散「${_fallbackThisGroupName(context, widget.name)}」？',
          zhTW: '解散「${_fallbackThisGroupName(context, widget.name)}」？',
          en: 'Delete "${_fallbackThisGroupName(context, widget.name)}"?',
        ),
        message: _groupProfileText(
          context,
          zhCN: '解散后群组将被永久删除，所有成员将被移出',
          zhTW: '解散後群組將被永久刪除，所有成員將被移出',
          en: 'This group will be permanently deleted and all members will be removed.',
        ),
        actions: [
          _TGActionSheetItem(
            title: AppLocalizations.of(context).deleteGroup,
            isDestructive: true,
            onTap: () => _dissolveGroup(context),
          ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
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
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '解散失败',
                zhTW: '解散失敗',
                en: 'Failed to delete group',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '解散失败，请重试',
                zhTW: '解散失敗，請重試',
                en: 'Failed to delete group. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
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
    // 这里仅按角色层级控制操作入口；后端仍必须再次校验操作者和目标成员权限。
    final isOwner = myRole == 3; // 群主
    final isAdmin = myRole == 2; // 管理员
    final isTargetOwner = member.role == 3; // 目标是群主
    final isTargetAdmin = member.role == 2; // 目标是管理员
    final currentUserId = ref.read(authServiceProvider).user?.uuid;
    final isSelf = currentUserId == member.userId;

    final actions = <_TGActionSheetItem>[];

    // 查看资料（所有人都可以）
    actions.add(
      _TGActionSheetItem(
        title: _groupProfileText(
          context,
          zhCN: '查看资料',
          zhTW: '查看資料',
          en: 'View Profile',
        ),
        onTap: () {
          Navigator.pop(context);
          context.push(
            '/user/${member.userId}?name=${Uri.encodeComponent(member.displayName)}${member.avatar != null ? '&avatar=${Uri.encodeComponent(member.avatar!)}' : ''}',
          );
        },
      ),
    );

    final canEditNickname = isSelf ||
        ((isOwner || isAdmin) && !isTargetOwner && !(isAdmin && isTargetAdmin));
    if (canEditNickname) {
      actions.add(
        _TGActionSheetItem(
          title: _groupProfileText(
            context,
            zhCN: isSelf ? '修改我的群昵称' : '修改群昵称',
            zhTW: isSelf ? '修改我的群暱稱' : '修改群暱稱',
            en: isSelf ? 'Edit My Group Nickname' : 'Edit Group Nickname',
          ),
          onTap: () => _editMemberNickname(context, member),
        ),
      );
    }

    // 群主可以设置/取消管理员（不能操作自己）
    if (isOwner && !isTargetOwner) {
      if (isTargetAdmin) {
        actions.add(
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '取消管理员',
              zhTW: '取消管理員',
              en: 'Remove Admin',
            ),
            onTap: () => _setMemberRole(context, member.userId, 0),
          ),
        );
      } else {
        actions.add(
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '设为管理员',
              zhTW: '設為管理員',
              en: 'Set as Admin',
            ),
            onTap: () => _setMemberRole(context, member.userId, 1),
          ),
        );
      }
      actions.add(
        _TGActionSheetItem(
          title: _groupProfileText(
            context,
            zhCN: '转让群主',
            zhTW: '轉讓群主',
            en: 'Transfer Ownership',
          ),
          isDestructive: true,
          onTap: () => _transferOwner(context, member),
        ),
      );
    }

    // 群主和管理员可以禁言（不能禁言群主和管理员，管理员不能禁言管理员）
    if ((isOwner || isAdmin) && !isTargetOwner) {
      if (!(isAdmin && isTargetAdmin)) {
        if (member.isMuted) {
          actions.add(
            _TGActionSheetItem(
              title: _groupProfileText(
                context,
                zhCN: '解除禁言',
                zhTW: '解除禁言',
                en: 'Unmute',
              ),
              onTap: () => _unmuteMember(context, member),
            ),
          );
        } else {
          actions.add(
            _TGActionSheetItem(
              title: _groupProfileText(
                context,
                zhCN: '禁言',
                zhTW: '禁言',
                en: 'Mute',
              ),
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
            title: _groupProfileText(
              context,
              zhCN: '移出群组',
              zhTW: '移出群組',
              en: 'Remove from Group',
            ),
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
        message: member.role == 3
            ? _groupProfileText(context, zhCN: '群主', zhTW: '群主', en: 'Owner')
            : (member.role == 2
                ? _groupProfileText(
                    context,
                    zhCN: '管理员',
                    zhTW: '管理員',
                    en: 'Admin',
                  )
                : null),
        actions: actions,
        cancelText: AppLocalizations.of(context).cancel,
      ),
    );
  }

  Future<void> _editMemberNickname(
    BuildContext sheetContext,
    api.ChatMember member,
  ) async {
    Navigator.pop(sheetContext);
    final controller = TextEditingController(text: member.nickname);
    final nickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _groupProfileText(
            dialogContext,
            zhCN: '修改群昵称',
            zhTW: '修改群暱稱',
            en: 'Edit Group Nickname',
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: InputDecoration(
            hintText: _groupProfileText(
              dialogContext,
              zhCN: '留空可恢复原昵称',
              zhTW: '留空可恢復原暱稱',
              en: 'Leave blank to use the profile name',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            child: Text(
              _groupProfileText(
                dialogContext,
                zhCN: '确定',
                zhTW: '確定',
                en: 'Confirm',
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nickname == null || !mounted) return;

    final response = await ref
        .read(api.chatServiceProvider)
        .updateMemberNickname(widget.groupId, member.userId, nickname);
    if (!mounted) return;
    if (response.isSuccess) {
      ref.invalidate(chatMembersProvider(widget.groupId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '群昵称已更新',
              zhTW: '群暱稱已更新',
              en: 'Group nickname updated',
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupServerMessage(
              response.message,
              zhCN: '群昵称修改失败',
              zhTW: '群暱稱修改失敗',
              en: 'Failed to update group nickname',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 显示禁言时间选项
  void _showMuteOptions(BuildContext context, api.ChatMember member) {
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _groupProfileText(
          context,
          zhCN: '禁言 ${member.displayName}',
          zhTW: '禁言 ${member.displayName}',
          en: 'Mute ${member.displayName}',
        ),
        actions: [
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '10分钟',
              zhTW: '10分鐘',
              en: '10 minutes',
            ),
            onTap: () => _muteMember(context, member, 10),
          ),
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '1小时',
              zhTW: '1小時',
              en: '1 hour',
            ),
            onTap: () => _muteMember(context, member, 60),
          ),
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '1天',
              zhTW: '1天',
              en: '1 day',
            ),
            onTap: () => _muteMember(context, member, 60 * 24),
          ),
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '1周',
              zhTW: '1週',
              en: '1 week',
            ),
            onTap: () => _muteMember(context, member, 60 * 24 * 7),
          ),
          _TGActionSheetItem(
            title: _groupProfileText(
              context,
              zhCN: '永久禁言',
              zhTW: '永久禁言',
              en: 'Mute Permanently',
            ),
            isDestructive: true,
            onTap: () => _muteMember(context, member, 0),
          ),
        ],
        cancelText: AppLocalizations.of(context).cancel,
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
            ? _groupProfileText(
                context,
                zhCN: '永久',
                zhTW: '永久',
                en: 'permanently',
              )
            : (duration < 60
                ? _groupProfileText(
                    context,
                    zhCN: '$duration分钟',
                    zhTW: '$duration分鐘',
                    en: '$duration min',
                  )
                : (duration < 1440
                    ? _groupProfileText(
                        context,
                        zhCN: '${duration ~/ 60}小时',
                        zhTW: '${duration ~/ 60}小時',
                        en: '${duration ~/ 60} hr',
                      )
                    : _groupProfileText(
                        context,
                        zhCN: '${duration ~/ 1440}天',
                        zhTW: '${duration ~/ 1440}天',
                        en: '${duration ~/ 1440} day(s)',
                      )));
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '已禁言 ${member.displayName} $durationText',
                zhTW: '已禁言 ${member.displayName} $durationText',
                en: 'Muted ${member.displayName} for $durationText',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '禁言失败',
                zhTW: '禁言失敗',
                en: 'Failed to mute member',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '禁言失败，请重试',
                zhTW: '禁言失敗，請重試',
                en: 'Failed to mute member. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
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
            content: Text(
              _groupProfileText(
                context,
                zhCN: '已解除 ${member.displayName} 的禁言',
                zhTW: '已解除 ${member.displayName} 的禁言',
                en: 'Unmuted ${member.displayName}',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: AppLocalizations.of(context).failed,
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
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
      final response = await ref
          .read(api.chatServiceProvider)
          .setMemberRole(widget.groupId, userId, role);

      if (!mounted) return;

      if (response.isSuccess) {
        final roleText = role == 1
            ? _groupProfileText(context, zhCN: '管理员', zhTW: '管理員', en: 'Admin')
            : _groupProfileText(
                context,
                zhCN: '普通成员',
                zhTW: '普通成員',
                en: 'Member',
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '已设为 $roleText',
                zhTW: '已設為 $roleText',
                en: 'Updated role: $roleText',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        // 角色更新成功后丢弃成员缓存，避免继续展示旧角色标签和操作入口。
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: AppLocalizations.of(context).failed,
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _transferOwner(
    BuildContext context,
    api.ChatMember member,
  ) async {
    Navigator.pop(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _groupProfileText(
            context,
            zhCN: '转让群主',
            zhTW: '轉讓群主',
            en: 'Transfer Ownership',
          ),
        ),
        content: Text(
          _groupProfileText(
            context,
            zhCN: '确定把群主转让给「${member.displayName}」吗？转让后你将变为管理员。',
            zhTW: '確定把群主轉讓給「${member.displayName}」嗎？轉讓後你將變為管理員。',
            en: 'Transfer ownership to "${member.displayName}"? You will become an admin.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              _groupProfileText(
                context,
                zhCN: '确认转让',
                zhTW: '確認轉讓',
                en: 'Transfer',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final response = await ref
          .read(api.chatServiceProvider)
          .transferOwner(widget.groupId, member.userId);
      if (!mounted) return;

      if (response.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '群主已转让',
                zhTW: '群主已轉讓',
                en: 'Ownership transferred',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(chatDetailProvider(widget.groupId));
        // 转让群主同时改变当前用户角色和成员角色，两份服务端投影都需要失效。
        ref.invalidate(chatMembersProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '转让失败',
                zhTW: '轉讓失敗',
                en: 'Transfer failed',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '转让失败，请重试',
              zhTW: '轉讓失敗，請重試',
              en: 'Transfer failed. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
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
        title: Text(
          _groupProfileText(
            context,
            zhCN: '移出群组',
            zhTW: '移出群組',
            en: 'Remove from Group',
          ),
        ),
        content: Text(
          _groupProfileText(
            context,
            zhCN: '确定要将「${member.displayName}」移出群组吗？',
            zhTW: '確定要將「${member.displayName}」移出群組嗎？',
            en: 'Remove "${member.displayName}" from this group?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              _groupProfileText(context, zhCN: '移出', zhTW: '移出', en: 'Remove'),
            ),
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
            content: Text(
              _groupProfileText(
                context,
                zhCN: '已将「${member.displayName}」移出群组',
                zhTW: '已將「${member.displayName}」移出群組',
                en: 'Removed "${member.displayName}" from the group',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        // 刷新成员列表
        ref.invalidate(chatMembersProvider(widget.groupId));
        ref.invalidate(chatDetailProvider(widget.groupId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: AppLocalizations.of(context).failed,
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
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
          _error = _groupServerMessage(
            response.message,
            zhCN: '加载失败',
            zhTW: '載入失敗',
            en: 'Loading failed',
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = _groupProfileText(
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
                ? _groupProfileText(
                    context,
                    zhCN: '已通过申请',
                    zhTW: '已通過申請',
                    en: 'Request approved',
                  )
                : _groupProfileText(
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
            _groupServerMessage(
              response.message,
              zhCN: '操作失败',
              zhTW: '操作失敗',
              en: AppLocalizations.of(context).failed,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.isChannel
        ? _groupProfileText(
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
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _groupProfileText(
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
              name: _fallbackUserName(context, request.nickname),
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
                    _fallbackUserName(context, request.nickname),
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
    return _groupRelativeTimeText(context, time);
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.white.withOpacity(0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.035,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < validChildren.length; i++) ...[
            validChildren[i],
            if (i < validChildren.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Divider(
                  height: 1,
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

//  单元格
class _TGCell extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final Color? iconColor;
  final List<Color>? iconBackgroundColors;
  final String title;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _TGCell({
    this.icon,
    this.iconAsset,
    this.iconColor,
    this.iconBackgroundColors,
    required this.title,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconColor = iconColor ??
        (isDark ? AppColors.primaryFor(context) : _groupProfileInkFor(context));
    final iconBgColors = iconBackgroundColors ??
        (isDark
            ? _groupProfileIconDark
            : const [Color(0xFFF4F6FA), Color(0xFFFFFFFF)]);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (iconAsset != null || icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: iconBgColors,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkDivider
                        : Colors.white.withOpacity(0.85),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.16 : 0.035),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: iconAsset != null
                      ? _GroupProfileAssetIcon(
                          asset: iconAsset!,
                          color: effectiveIconColor,
                          size: 20,
                        )
                      : Icon(icon, color: effectiveIconColor, size: 20),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w500,
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
                          color: AppColors.cardFor(context),
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
                      if (member.role >= 2) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: member.role == 3
                                ? _groupProfileInkFor(context).withOpacity(0.15)
                                : Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            member.role == 3
                                ? _creatorText(context)
                                : _fallbackAdminName(context),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: member.role == 3
                                  ? _groupProfileInkFor(context)
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
                        member.isOnline
                            ? _groupProfileText(
                                context,
                                zhCN: '在线',
                                zhTW: '在線',
                                en: 'Online',
                              )
                            : _groupProfileText(
                                context,
                                zhCN: '离线',
                                zhTW: '離線',
                                en: 'Offline',
                              ),
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
                      color: AppColors.dividerFor(context),
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
                                          : _groupProfileInkFor(context),
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
                            color: AppColors.dividerFor(context),
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
                    color: _groupProfileInkFor(context),
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

class _GroupProfileAssetIcon extends StatelessWidget {
  final String asset;
  final Color color;
  final double size;

  const _GroupProfileAssetIcon({
    required this.asset,
    required this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (asset.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }

    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
    );
  }
}

//  操作按钮
class _TGActionButton extends StatelessWidget {
  final IconData icon;
  final String? iconAsset;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool isActive; // 激活状态（如静音开启时）
  final Color? iconColor;
  final Color? controlColor;
  final List<Color>? gradientColors;

  const _TGActionButton({
    required this.icon,
    this.iconAsset,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.isActive = false,
    this.iconColor,
    this.controlColor,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = iconColor ??
        (isDark ? AppColors.primaryFor(context) : _groupProfileInkFor(context));
    final colors = gradientColors ??
        (isDark
            ? (isActive
                ? _groupProfileActionDarkActive
                : _groupProfileActionDark)
            : [const Color(0xFFE9EAEE), const Color(0xFFE9EAEE)]);

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
              color: controlColor,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(16),
              border: isDark ? Border.all(color: AppColors.darkDivider) : null,
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : iconAsset != null
                    ? Center(
                        child: _GroupProfileAssetIcon(
                          asset: iconAsset!,
                          color: fg,
                          size: 24,
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
              color: isDark
                  ? AppColors.darkTextSecondary
                  : _groupProfileInkFor(context),
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

  const _SearchMessagesPage({required this.chatId, required this.chatName});

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
          _groupProfileText(
            context,
            zhCN: '搜索消息',
            zhTW: '搜尋訊息',
            en: 'Search Messages',
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
                  hintText: _groupProfileText(
                    context,
                    zhCN: '在 ${widget.chatName} 中搜索',
                    zhTW: '在 ${widget.chatName} 中搜尋',
                    en: 'Search in ${widget.chatName}',
                  ),
                  hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                            Icon(
                              Icons.search,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? _groupProfileText(
                                      context,
                                      zhCN: '输入关键词搜索消息',
                                      zhTW: '輸入關鍵字搜尋訊息',
                                      en: 'Enter keywords to search messages',
                                    )
                                  : _groupProfileText(
                                      context,
                                      zhCN: '未找到相关消息',
                                      zhTW: '找不到相關訊息',
                                      en: 'No related messages found',
                                    ),
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
                                result.senderName ?? _unknownUserText(context),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimaryFor(context),
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
                              onTap: () => context.push(
                                '/chat/${widget.chatId}?name=${Uri.encodeComponent(widget.chatName)}&type=group&messageId=${Uri.encodeComponent(result.id)}&messageSeq=${result.seq}',
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
              _groupProfileText(
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
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: urls
                .map(
                  (url) => ListTile(
                    leading: Icon(
                      Icons.link,
                      color: AppColors.linkFor(context),
                    ),
                    title: Text(
                      url,
                      style: TextStyle(
                        color: AppColors.linkFor(context),
                        fontSize: 14,
                      ),
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
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryWithOpacity(context, 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(item.fileName),
                color: AppColors.primaryFor(context),
              ),
            ),
            title: Text(
              item.fileName ?? _unknownFileText(context),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textPrimaryFor(context),
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
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(10),
          ),
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
            title: Text(
              _groupProfileText(
                context,
                zhCN: '语音消息 ${_formatDuration(item.duration ?? 0)}',
                zhTW: '語音訊息 ${_formatDuration(item.duration ?? 0)}',
                en: 'Voice message ${_formatDuration(item.duration ?? 0)}',
              ),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textPrimaryFor(context),
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
              _groupProfileText(
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
          _groupProfileText(
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

  void _downloadFile(api.ChatMediaItem item) {
    final fileUrl = item.fileUrl;
    if (fileUrl != null) {
      Clipboard.setData(ClipboardData(text: fileUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '文件链接已复制',
              zhTW: '檔案連結已複製',
              en: 'File link copied',
            ),
          ),
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
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: _groupProfileInkFor(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _groupProfileText(
            context,
            zhCN: '群二维码',
            zhTW: '群二維碼',
            en: 'Group QR Code',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
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
                color: AppColors.cardFor(context),
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
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _groupMemberCountText(context, memberCount),
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondaryFor(context),
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
                        color: _groupProfileInk,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _groupProfileText(
                      context,
                      zhCN: '扫一扫即可加入群组',
                      zhTW: '掃一掃即可加入群組',
                      en: 'Scan to join this group',
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryFor(context),
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
  bool _allowAnonymous = false;
  bool _allowForward = true;
  bool _allowViewHistory = true;
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
        _allowAnonymous = chatDetail.allowAnonymous;
        _allowForward = chatDetail.allowForward;
        _allowViewHistory = chatDetail.allowViewHistory;
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
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '设置失败',
                zhTW: '設定失敗',
                en: 'Failed to update setting',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _loadGroupInfo();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '设置失败，请重试',
                zhTW: '設定失敗，請重試',
                en: 'Failed to update setting. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '群组名称不能为空',
              zhTW: '群組名稱不能為空',
              en: 'Group name cannot be empty',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (name.characters.length > 32) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '群组名称不能超过32个字符',
              zhTW: '群組名稱不能超過32個字元',
              en: 'Group name cannot exceed 32 characters',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (description.characters.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '群简介不能超过1000个字符',
              zhTW: '群簡介不能超過1000個字元',
              en: 'Group description cannot exceed 1000 characters',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.put(
        '/chat/${widget.chatId}',
        data: {
          'name': name,
          'description': description,
        },
      );

      if (!mounted) return;

      if (response.isSuccess) {
        // 更新聊天列表中对应的聊天项（不要 invalidate 整个 chatListProvider）
        final existingChat =
            ref.read(chatListProvider.notifier).getChatById(widget.chatId);
        if (existingChat != null) {
          final updatedChat = existingChat.copyWith(
            name: name,
            description: description.isNotEmpty ? description : null,
          );
          ref.read(chatListProvider.notifier).updateChat(updatedChat);
        }
        ref.invalidate(chatDetailProvider(widget.chatId));
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '保存成功',
                zhTW: '儲存成功',
                en: 'Saved',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '保存失败',
                zhTW: '儲存失敗',
                en: 'Failed to save',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '保存失败，请重试',
                zhTW: '儲存失敗，請重試',
                en: 'Failed to save. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
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
        title: Text(
          _groupProfileText(
            context,
            zhCN: '删除群组',
            zhTW: '刪除群組',
            en: 'Delete Group',
          ),
        ),
        content: Text(
          _groupProfileText(
            context,
            zhCN: '确定要删除此群组吗？此操作不可恢复。',
            zhTW: '確定要刪除此群組嗎？此操作無法恢復。',
            en: 'Delete this group? This action cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _groupProfileText(context, zhCN: '取消', zhTW: '取消', en: 'Cancel'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              _groupProfileText(context, zhCN: '删除', zhTW: '刪除', en: 'Delete'),
            ),
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
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '群组已删除',
                zhTW: '群組已刪除',
                en: 'Group deleted',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '删除失败',
                zhTW: '刪除失敗',
                en: 'Failed to delete',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '删除失败，请重试',
                zhTW: '刪除失敗，請重試',
                en: 'Failed to delete. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppColors.backgroundFor(context);
    final cardColor = AppColors.cardFor(context);
    final separatorColor = AppColors.dividerFor(context);
    final chatDetail = ref.watch(chatDetailProvider(widget.chatId)).valueOrNull;
    final isOwner = chatDetail?.myRole == 3;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceFor(context),
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: _groupProfileInkFor(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _groupProfileText(
              context,
              zhCN: '编辑群组',
              zhTW: '編輯群組',
              en: 'Edit Group',
            ),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryFor(context),
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
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: _groupProfileInkFor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _groupProfileText(
            context,
            zhCN: '编辑群组',
            zhTW: '編輯群組',
            en: 'Edit Group',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
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
                    _groupProfileText(
                      context,
                      zhCN: '完成',
                      zhTW: '完成',
                      en: 'Done',
                    ),
                    style: TextStyle(
                      color: _groupProfileInkFor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _groupProfileText(
                context,
                zhCN: '群资料',
                zhTW: '群資料',
                en: 'Group Profile',
              ),
              style: TextStyle(
                fontSize: 13,
                color: _groupProfileInkFor(context),
              ),
            ),
          ),
          Container(
            color: cardColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  maxLength: 32,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _groupProfileText(
                      context,
                      zhCN: '群组名称',
                      zhTW: '群組名稱',
                      en: 'Group Name',
                    ),
                    hintText: _groupProfileText(
                      context,
                      zhCN: '输入群组名称',
                      zhTW: '輸入群組名稱',
                      en: 'Enter a group name',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: _groupProfileText(
                      context,
                      zhCN: '群简介',
                      zhTW: '群簡介',
                      en: 'Group Description',
                    ),
                    hintText: _groupProfileText(
                      context,
                      zhCN: '介绍一下这个群组',
                      zhTW: '介紹一下這個群組',
                      en: 'Describe this group',
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_username != null && _username!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                _groupProfileText(
                  context,
                  zhCN: '用户名长度为 5-32 个字符，只能包含字母、数字和下划线。',
                  zhTW: '使用者名稱長度為 5-32 個字元，只能包含字母、數字和底線。',
                  en: 'The username must be 5-32 characters and can contain only letters, numbers, and underscores.',
                ),
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            Container(
              color: cardColor,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.alternate_email,
                      color: _groupProfileInkFor(context),
                    ),
                    title: Text(
                      _groupProfileText(
                        context,
                        zhCN: '群组号',
                        zhTW: '群組號',
                        en: 'Group ID',
                      ),
                    ),
                    subtitle: Text(
                      '@$_username',
                      style: TextStyle(
                        color: _groupProfileInkFor(context),
                        fontSize: 14,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: '@$_username'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _groupProfileText(
                              context,
                              zhCN: '群组号已复制',
                              zhTW: '群組號已複製',
                              en: 'Group ID copied',
                            ),
                          ),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          // 加入设置
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              _groupProfileText(
                context,
                zhCN: '加入设置',
                zhTW: '加入設定',
                en: 'Join Settings',
              ),
              style: TextStyle(
                fontSize: 13,
                color: _groupProfileInkFor(context),
              ),
            ),
          ),
          Container(
            color: cardColor,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    _groupProfileText(
                      context,
                      zhCN: '加入需要审批',
                      zhTW: '加入需要審批',
                      en: 'Join requests require approval',
                    ),
                  ),
                  subtitle: Text(
                    _groupProfileText(
                      context,
                      zhCN: '新成员需要管理员或群主批准才能加入',
                      zhTW: '新成員需要管理員或群主批准才能加入',
                      en: 'New members must be approved by an admin or the owner.',
                    ),
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  value: _joinApproval,
                  activeColor: _groupProfileInkFor(context),
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
              _groupProfileText(
                context,
                zhCN: '权限设置',
                zhTW: '權限設定',
                en: 'Permissions',
              ),
              style: TextStyle(
                fontSize: 13,
                color: _groupProfileInkFor(context),
              ),
            ),
          ),
          Container(
            color: cardColor,
            child: Column(
              children: [
                _PermissionTile(
                  icon: Icons.volume_off_outlined,
                  title: _groupProfileText(
                    context,
                    zhCN: '全员禁言',
                    zhTW: '全員禁言',
                    en: 'Only admins can send messages',
                  ),
                  subtitle: _groupProfileText(
                    context,
                    zhCN: '开启后仅管理员和创建者可发言',
                    zhTW: '開啟後僅管理員和建立者可發言',
                    en: 'When enabled, only admins and the owner can speak.',
                  ),
                  value: !_canSendMessage,
                  onChanged: (value) {
                    setState(() => _canSendMessage = !value);
                    _updateSetting('can_send_message', !value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.image_outlined,
                  title: _groupProfileText(
                    context,
                    zhCN: '发送媒体',
                    zhTW: '傳送媒體',
                    en: 'Send media',
                  ),
                  subtitle: _groupProfileText(
                    context,
                    zhCN: '成员可以发送图片、视频和文件',
                    zhTW: '成員可以傳送圖片、影片和檔案',
                    en: 'Members can send images, videos, and files.',
                  ),
                  value: _canSendMedia,
                  onChanged: (value) {
                    setState(() => _canSendMedia = value);
                    _updateSetting('can_send_media', value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.link,
                  title: _groupProfileText(
                    context,
                    zhCN: '发送链接',
                    zhTW: '傳送連結',
                    en: 'Send links',
                  ),
                  subtitle: _groupProfileText(
                    context,
                    zhCN: '成员可以发送链接预览',
                    zhTW: '成員可以傳送連結預覽',
                    en: 'Members can send link previews.',
                  ),
                  value: _canSendLinks,
                  onChanged: (value) {
                    setState(() => _canSendLinks = value);
                    _updateSetting('can_send_links', value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                _PermissionTile(
                  icon: Icons.person_add_outlined,
                  title: _groupProfileText(
                    context,
                    zhCN: '添加成员',
                    zhTW: '新增成員',
                    en: 'Add members',
                  ),
                  subtitle: _groupProfileText(
                    context,
                    zhCN: '成员可以邀请其他人加入',
                    zhTW: '成員可以邀請其他人加入',
                    en: 'Members can invite other people to join.',
                  ),
                  value: _canAddMembers,
                  onChanged: (value) {
                    setState(() => _canAddMembers = value);
                    _updateSetting('can_add_members', value);
                  },
                ),
                Divider(height: 0.5, indent: 56, color: separatorColor),
                if (isOwner) ...[
                  _PermissionTile(
                    icon: Icons.badge_outlined,
                    title: _groupProfileText(
                      context,
                      zhCN: '允许匿名发言',
                      zhTW: '允許匿名發言',
                      en: 'Allow anonymous messages',
                    ),
                    subtitle: _groupProfileText(
                      context,
                      zhCN: '开启后成员可以用匿名身份在群里发消息',
                      zhTW: '開啟後成員可以用匿名身份在群裡發訊息',
                      en: 'Members can send messages anonymously in this group.',
                    ),
                    value: _allowAnonymous,
                    onChanged: (value) {
                      setState(() => _allowAnonymous = value);
                      _updateSetting('allow_anonymous', value);
                    },
                  ),
                  Divider(height: 0.5, indent: 56, color: separatorColor),
                  _PermissionTile(
                    icon: Icons.forward_outlined,
                    title: _groupProfileText(
                      context,
                      zhCN: '允许转发本群消息',
                      zhTW: '允許轉發本群訊息',
                      en: 'Allow forwarding group messages',
                    ),
                    subtitle: _groupProfileText(
                      context,
                      zhCN: '关闭后普通成员不能把本群消息转发到其他会话',
                      zhTW: '關閉後普通成員不能把本群訊息轉發到其他會話',
                      en: 'When off, regular members cannot forward messages from this group.',
                    ),
                    value: _allowForward,
                    onChanged: (value) {
                      setState(() => _allowForward = value);
                      _updateSetting('allow_forward', value);
                    },
                  ),
                  Divider(height: 0.5, indent: 56, color: separatorColor),
                  _PermissionTile(
                    icon: Icons.history_outlined,
                    title: _groupProfileText(
                      context,
                      zhCN: '历史消息',
                      zhTW: '歷史訊息',
                      en: 'History',
                    ),
                    subtitle: _groupProfileText(
                      context,
                      zhCN: '关闭后，新进群的普通成员只能查看入群后的消息',
                      zhTW: '關閉後，新進群的普通成員只能查看入群後的訊息',
                      en: 'When off, new regular members only see messages sent after they joined.',
                    ),
                    value: _allowViewHistory,
                    onChanged: (value) {
                      setState(() => _allowViewHistory = value);
                      _updateSetting('allow_view_history', value);
                    },
                  ),
                  Divider(height: 0.5, indent: 56, color: separatorColor),
                ],
                _PermissionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: _groupProfileText(
                    context,
                    zhCN: '群成员保护',
                    zhTW: '群成員保護',
                    en: 'Protect member list',
                  ),
                  subtitle: _groupProfileText(
                    context,
                    zhCN: '开启后普通成员只能看到管理员和群主，且无法点开成员资料',
                    zhTW: '開啟後普通成員只能看到管理員和群主，且無法打開成員資料',
                    en: 'Regular members can only see admins and the owner, and cannot open member profiles.',
                  ),
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
              title: Text(
                _groupProfileText(
                  context,
                  zhCN: '删除群组',
                  zhTW: '刪除群組',
                  en: 'Delete Group',
                ),
                style: const TextStyle(color: Colors.red),
              ),
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
      secondary: Icon(icon, color: _groupProfileInkFor(context)),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      value: value,
      activeColor: _groupProfileInkFor(context),
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
            content: Text(
              _groupProfileText(
                context,
                zhCN: '已添加 ${_selectedIds.length} 位成员',
                zhTW: '已新增 ${_selectedIds.length} 位成員',
                en: 'Added ${_selectedIds.length} members',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '添加失败',
                zhTW: '新增失敗',
                en: 'Failed to add members',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '添加失败，请重试',
                zhTW: '新增失敗，請重試',
                en: 'Failed to add members. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppColors.surfaceFor(context);
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.cardFor(context)
        : AppColors.lightBackground;
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
                    _groupProfileText(
                      context,
                      zhCN: '取消',
                      zhTW: '取消',
                      en: 'Cancel',
                    ),
                    style: TextStyle(color: Colors.grey, fontSize: 17),
                  ),
                ),
                Text(
                  _groupProfileText(
                    context,
                    zhCN: '添加成员',
                    zhTW: '新增成員',
                    en: 'Add Members',
                  ),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                TextButton(
                  onPressed:
                      _selectedIds.isEmpty || _isLoading ? null : _addMembers,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _groupProfileText(
                            context,
                            zhCN:
                                '添加${_selectedIds.isNotEmpty ? "(${_selectedIds.length})" : ""}',
                            zhTW:
                                '新增${_selectedIds.isNotEmpty ? "(${_selectedIds.length})" : ""}',
                            en: _selectedIds.isNotEmpty
                                ? 'Add (${_selectedIds.length})'
                                : 'Add',
                          ),
                          style: TextStyle(
                            color: _selectedIds.isEmpty
                                ? Colors.grey
                                : _groupProfileInkFor(context),
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
                style: TextStyle(color: AppColors.textPrimaryFor(context)),
                decoration: InputDecoration(
                  hintText: _groupProfileText(
                    context,
                    zhCN: '搜索联系人',
                    zhTW: '搜尋聯絡人',
                    en: 'Search contacts',
                  ),
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
                                    ? _groupProfileText(
                                        context,
                                        zhCN: '未找到联系人',
                                        zhTW: '找不到聯絡人',
                                        en: 'No contacts found',
                                      )
                                    : _groupProfileText(
                                        context,
                                        zhCN: '没有可添加的联系人',
                                        zhTW: '沒有可新增的聯絡人',
                                        en: 'No contacts available to add',
                                      ),
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
                              : _fallbackUserName(context, contact.username);

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
                                        color: _groupProfileInkFor(context),
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
                                    color: _groupProfileInkFor(context),
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
                      backgroundDecoration: const BoxDecoration(
                        color: Colors.transparent,
                      ),
                      loadingBuilder: (context, event) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
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
                              activeColor: _groupProfileInkFor(context),
                              inactiveColor: AppColors.darkTextTertiary,
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
        backgroundColor: AppColors.cardFor(context),
        title: Text(
          existing != null
              ? _groupProfileText(
                  context,
                  zhCN: '编辑公告',
                  zhTW: '編輯公告',
                  en: 'Edit Announcement',
                )
              : _groupProfileText(
                  context,
                  zhCN: '发布公告',
                  zhTW: '發布公告',
                  en: 'Post Announcement',
                ),
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
        ),
        content: TextField(
          controller: controller,
          maxLines: 8,
          minLines: 3,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimaryFor(context)),
          decoration: InputDecoration(
            hintText: _groupProfileText(
              context,
              zhCN: '输入公告内容...',
              zhTW: '輸入公告內容...',
              en: 'Enter announcement content...',
            ),
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
              borderSide: BorderSide(
                color: _groupProfileInkFor(context),
                width: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _groupProfileText(context, zhCN: '取消', zhTW: '取消', en: 'Cancel'),
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: Text(
              _groupProfileText(context, zhCN: '发布', zhTW: '發布', en: 'Publish'),
              style: TextStyle(
                color: _groupProfileInkFor(context),
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
            content: Text(
              existing != null
                  ? _groupProfileText(
                      context,
                      zhCN: '公告已更新',
                      zhTW: '公告已更新',
                      en: 'Announcement updated',
                    )
                  : _groupProfileText(
                      context,
                      zhCN: '公告已发布',
                      zhTW: '公告已發布',
                      en: 'Announcement published',
                    ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadAnnouncements(refresh: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: 'Operation failed',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement(api.AnnouncementItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _groupProfileText(
            context,
            zhCN: '删除公告',
            zhTW: '刪除公告',
            en: 'Delete Announcement',
          ),
        ),
        content: Text(
          _groupProfileText(
            context,
            zhCN: '确定要删除这条公告吗？',
            zhTW: '確定要刪除這條公告嗎？',
            en: 'Delete this announcement?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _groupProfileText(context, zhCN: '取消', zhTW: '取消', en: 'Cancel'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _groupProfileText(context, zhCN: '删除', zhTW: '刪除', en: 'Delete'),
              style: const TextStyle(color: Colors.red),
            ),
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
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '公告已删除',
                zhTW: '公告已刪除',
                en: 'Announcement deleted',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadAnnouncements(refresh: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '删除失败',
                zhTW: '刪除失敗',
                en: 'Failed to delete',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '删除失败，请重试',
                zhTW: '刪除失敗，請重試',
                en: 'Failed to delete. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _acknowledgeAnnouncement(api.AnnouncementItem item) async {
    if (item.acknowledged) return;
    try {
      final response = await ref
          .read(api.chatServiceProvider)
          .acknowledgeAnnouncement(widget.chatId, item.id);
      if (!mounted) return;
      if (response.isSuccess) {
        await _loadAnnouncements(refresh: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupProfileText(
                context,
                zhCN: '已确认收到公告',
                zhTW: '已確認收到公告',
                en: 'Announcement acknowledged',
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _groupServerMessage(
                response.message,
                zhCN: '确认失败',
                zhTW: '確認失敗',
                en: 'Failed to acknowledge',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '确认失败，请重试',
              zhTW: '確認失敗，請重試',
              en: 'Failed to acknowledge. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canManage = _canManage;

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: _groupProfileInkFor(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _groupProfileText(
            context,
            zhCN: '群公告',
            zhTW: '群公告',
            en: 'Announcements',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
        actions: [
          if (canManage)
            IconButton(
              icon: Icon(Icons.add, color: _groupProfileInkFor(context)),
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
                        _groupProfileText(
                          context,
                          zhCN: '暂无群公告',
                          zhTW: '暫無群公告',
                          en: 'No announcements yet',
                        ),
                        style: TextStyle(
                            fontSize: 17, color: Colors.grey.shade500),
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _createOrEditAnnouncement(),
                          child: Text(
                            _groupProfileText(
                              context,
                              zhCN: '发布公告',
                              zhTW: '發布公告',
                              en: 'Post Announcement',
                            ),
                            style: TextStyle(
                              color: _groupProfileInkFor(context),
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
        color: AppColors.surfaceFor(context),
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
                    backgroundColor: _groupProfileInkFor(
                      context,
                    ).withOpacity(0.15),
                    child: Icon(
                      Icons.person,
                      size: 18,
                      color: _groupProfileInkFor(context),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fallbackAdminName(context, item.authorName),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
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
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          _groupProfileText(
                            context,
                            zhCN: '编辑',
                            zhTW: '編輯',
                            en: 'Edit',
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          _groupProfileText(
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
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _groupProfileText(
                      context,
                      zhCN: '已确认 ${item.acknowledgedCount}/${item.memberCount}',
                      zhTW: '已確認 ${item.acknowledgedCount}/${item.memberCount}',
                      en: '${item.acknowledgedCount}/${item.memberCount} acknowledged',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                if (item.acknowledged)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 18, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        _groupProfileText(
                          context,
                          zhCN: '已确认',
                          zhTW: '已確認',
                          en: 'Acknowledged',
                        ),
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => _acknowledgeAnnouncement(item),
                    child: Text(
                      _groupProfileText(
                        context,
                        zhCN: '确认收到',
                        zhTW: '確認收到',
                        en: 'Acknowledge',
                      ),
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

class GroupAutoMessagesPage extends StatelessWidget {
  final String chatId;
  final String chatName;
  final bool isChannel;

  const GroupAutoMessagesPage({
    super.key,
    required this.chatId,
    required this.chatName,
    this.isChannel = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GroupAutoMessagesPage(
      chatId: chatId,
      chatName: chatName,
      isChannel: isChannel,
    );
  }
}

class _GroupAutoMessagesPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final bool isChannel;

  const _GroupAutoMessagesPage({
    required this.chatId,
    required this.chatName,
    required this.isChannel,
  });

  @override
  ConsumerState<_GroupAutoMessagesPage> createState() =>
      _GroupAutoMessagesPageState();
}

class _GroupAutoMessagesPageState
    extends ConsumerState<_GroupAutoMessagesPage> {
  final List<api.ChatAutoMessage> _items = [];
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAutoMessages();
  }

  Future<void> _loadAutoMessages() async {
    setState(() => _isLoading = true);
    final response =
        await ref.read(api.chatServiceProvider).getAutoMessages(widget.chatId);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(response.data ?? const []);
      _isLoading = false;
    });
    if (!response.isSuccess && mounted) {
      _showError(response.message, '加载定时群消息失败');
    }
  }

  void _showError(String? raw, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _groupServerMessage(
            raw,
            zhCN: fallback,
            zhTW: fallback,
            en: fallback,
          ),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _scheduleLabel(api.ChatAutoMessage item) {
    switch (item.scheduleType) {
      case 'daily':
        return _groupProfileText(
          context,
          zhCN: '每天 ${item.dailyTime.isEmpty ? '09:00' : item.dailyTime}',
          zhTW: '每天 ${item.dailyTime.isEmpty ? '09:00' : item.dailyTime}',
          en: 'Daily at ${item.dailyTime.isEmpty ? '09:00' : item.dailyTime}',
        );
      case 'interval':
        final minutes = (item.intervalSeconds / 60).round().clamp(1, 1000000);
        return _groupProfileText(
          context,
          zhCN: '每 $minutes 分钟',
          zhTW: '每 $minutes 分鐘',
          en: 'Every $minutes minutes',
        );
      default:
        final sendAt = item.sendAt;
        return sendAt == null
            ? _groupProfileText(context, zhCN: '一次发送', zhTW: '一次發送', en: 'Once')
            : _groupProfileText(
                context,
                zhCN: '一次：${DateFormat('yyyy-MM-dd HH:mm').format(sendAt)}',
                zhTW: '一次：${DateFormat('yyyy-MM-dd HH:mm').format(sendAt)}',
                en: 'Once: ${DateFormat('yyyy-MM-dd HH:mm').format(sendAt)}',
              );
    }
  }

  String _autoMessageDisplayText(api.ChatAutoMessage item) {
    if (item.content.trim().isNotEmpty) return item.content;
    if (item.messageType == 2) {
      return _groupProfileText(
        context,
        zhCN: '[图片]',
        zhTW: '[圖片]',
        en: '[Image]',
      );
    }
    return '';
  }

  Future<void> _toggleEnabled(api.ChatAutoMessage item) async {
    final response = await ref.read(api.chatServiceProvider).updateAutoMessage(
          widget.chatId,
          item.id,
          api.ChatAutoMessagePayload(enabled: !item.enabled),
        );
    if (!mounted) return;
    if (response.isSuccess) {
      await _loadAutoMessages();
    } else {
      _showError(response.message, '更新定时群消息失败');
    }
  }

  Future<void> _deleteAutoMessage(api.ChatAutoMessage item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _groupProfileText(
            context,
            zhCN: '删除定时群消息',
            zhTW: '刪除定時群訊息',
            en: 'Delete Scheduled Message',
          ),
        ),
        content: Text(
          _groupProfileText(
            context,
            zhCN: '确认删除这条定时群消息规则吗？',
            zhTW: '確認刪除這條定時群訊息規則嗎？',
            en: 'Delete this scheduled group message rule?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _groupProfileText(context, zhCN: '删除', zhTW: '刪除', en: 'Delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final response = await ref
        .read(api.chatServiceProvider)
        .deleteAutoMessage(widget.chatId, item.id);
    if (!mounted) return;
    if (response.isSuccess) {
      await _loadAutoMessages();
    } else {
      _showError(response.message, '删除定时群消息失败');
    }
  }

  Future<void> _editAutoMessage([api.ChatAutoMessage? existing]) async {
    final result = await showModalBottomSheet<api.ChatAutoMessagePayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AutoMessageEditorSheet(existing: existing),
    );
    if (result == null || !mounted || _isSaving) return;

    setState(() => _isSaving = true);
    final service = ref.read(api.chatServiceProvider);
    final response = existing == null
        ? await service.createAutoMessage(widget.chatId, result)
        : await service.updateAutoMessage(widget.chatId, existing.id, result);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (response.isSuccess) {
      await _loadAutoMessages();
    } else {
      _showError(response.message, '保存定时群消息失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: _groupProfileInkFor(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _groupProfileText(
            context,
            zhCN: '定时群消息',
            zhTW: '定時群訊息',
            en: 'Scheduled Group Messages',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: _groupProfileInkFor(context)),
            onPressed: _isSaving ? null : () => _editAutoMessage(),
          ),
        ],
      ),
      body: _isLoading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAutoMessages,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: _groupProfileInkFor(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _groupProfileText(
                              context,
                              zhCN: '到点后会作为群聊消息发送到聊天窗口，不会发布为公告。',
                              zhTW: '到點後會作為群聊訊息發送到聊天視窗，不會發布為公告。',
                              en: 'These rules send real group chat messages, not announcements.',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(
                            Icons.schedule_send_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _groupProfileText(
                              context,
                              zhCN: '暂无定时群消息',
                              zhTW: '暫無定時群訊息',
                              en: 'No scheduled group messages yet',
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._items.map(_buildAutoMessageCard),
                ],
              ),
            ),
    );
  }

  Widget _buildAutoMessageCard(api.ChatAutoMessage item) {
    final nextRun = item.nextRunAt == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm').format(item.nextRunAt!);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title.isEmpty ? _scheduleLabel(item) : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              Switch(
                value: item.enabled,
                onChanged: (_) => _toggleEnabled(item),
              ),
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') {
                    _editAutoMessage(item);
                  } else if (action == 'delete') {
                    _deleteAutoMessage(item);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      _groupProfileText(
                        context,
                        zhCN: '编辑',
                        zhTW: '編輯',
                        en: 'Edit',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      _groupProfileText(
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
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _autoMessageDisplayText(item),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nextRun.isEmpty
                ? _scheduleLabel(item)
                : '${_scheduleLabel(item)} · ${_groupProfileText(context, zhCN: '下次', zhTW: '下次', en: 'Next')}: $nextRun',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoMessageEditorSheet extends ConsumerStatefulWidget {
  final api.ChatAutoMessage? existing;

  const _AutoMessageEditorSheet({this.existing});

  @override
  ConsumerState<_AutoMessageEditorSheet> createState() =>
      _AutoMessageEditorSheetState();
}

class _AutoMessageEditorSheetState
    extends ConsumerState<_AutoMessageEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  int _messageType = 1;
  Map<String, dynamic> _media = const {};
  bool _uploadingImage = false;
  String _scheduleType = 'once';
  DateTime _sendAt = DateTime.now().add(const Duration(minutes: 5));
  TimeOfDay _dailyTime = const TimeOfDay(hour: 9, minute: 0);
  int _intervalMinutes = 60;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _titleController = TextEditingController(text: item?.title ?? '');
    _contentController = TextEditingController(text: item?.content ?? '');
    _messageType = item?.messageType == 2 ? 2 : 1;
    _media = item?.media ?? const {};
    _scheduleType = item?.scheduleType ?? 'once';
    _sendAt = item?.sendAt ?? DateTime.now().add(const Duration(minutes: 5));
    final dailyParts = (item?.dailyTime ?? '09:00').split(':');
    _dailyTime = TimeOfDay(
      hour: int.tryParse(dailyParts.first) ?? 9,
      minute: dailyParts.length > 1 ? int.tryParse(dailyParts[1]) ?? 0 : 0,
    );
    if ((item?.intervalSeconds ?? 0) > 0) {
      _intervalMinutes = (item!.intervalSeconds / 60).round().clamp(1, 100000);
    }
    _enabled = item?.enabled ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  String _dailyTimeText() =>
      '${_dailyTime.hour.toString().padLeft(2, '0')}:${_dailyTime.minute.toString().padLeft(2, '0')}';

  String _uploadRelativeImageUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = Uri.tryParse(value);
    final path = parsed?.path ?? value;
    if (path.startsWith('/uploads/images/')) return path;
    if (value.startsWith('uploads/images/')) return '/$value';
    return value;
  }

  Future<void> _pickAutoMessageImage() async {
    if (_uploadingImage) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      int? width;
      int? height;
      try {
        final decoded = await decodeImageFromList(bytes);
        width = decoded.width;
        height = decoded.height;
      } catch (_) {}

      final url = await ref.read(uploadServiceProvider).uploadImage(picked);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        throw Exception(
          _groupProfileText(
            context,
            zhCN: '图片上传失败',
            zhTW: '圖片上傳失敗',
            en: 'Image upload failed',
          ),
        );
      }
      final size = await picked.length();
      setState(() {
        _messageType = 2;
        _media = {
          'url': _uploadRelativeImageUrl(url),
          if (width != null) 'width': width,
          if (height != null) 'height': height,
          'size': size,
          'mime_type': picked.mimeType ?? 'image/jpeg',
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Widget _buildImagePicker() {
    final imageUrl = ApiConfig.getMediaUrl(_media['url']?.toString());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _groupProfileText(
                  context,
                  zhCN: '未选择图片',
                  zhTW: '未選擇圖片',
                  en: 'No image',
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _uploadingImage ? null : _pickAutoMessageImage,
                icon: _uploadingImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_outlined),
                label: Text(
                  imageUrl.isEmpty
                      ? _groupProfileText(
                          context,
                          zhCN: '选择图片',
                          zhTW: '選擇圖片',
                          en: 'Choose image',
                        )
                      : _groupProfileText(
                          context,
                          zhCN: '更换图片',
                          zhTW: '更換圖片',
                          en: 'Replace',
                        ),
                ),
              ),
              const SizedBox(width: 8),
              if (imageUrl.isNotEmpty)
                TextButton(
                  onPressed: _uploadingImage
                      ? null
                      : () => setState(() => _media = const {}),
                  child: Text(
                    _groupProfileText(
                      context,
                      zhCN: '移除',
                      zhTW: '移除',
                      en: 'Remove',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final content = _contentController.text.trim();
    if (_messageType == 1 && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '请输入定时群消息内容',
              zhTW: '請輸入定時群訊息內容',
              en: 'Enter scheduled message content',
            ),
          ),
        ),
      );
      return;
    }
    if (_messageType == 2 &&
        (_media['url']?.toString().trim().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupProfileText(
              context,
              zhCN: '请选择定时发送的图片',
              zhTW: '請選擇定時發送的圖片',
              en: 'Choose an image to schedule',
            ),
          ),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      api.ChatAutoMessagePayload(
        title: _titleController.text.trim(),
        content: content,
        messageType: _messageType,
        media: _messageType == 2
            ? {
                ..._media,
                'url': _uploadRelativeImageUrl(_media['url']?.toString() ?? ''),
              }
            : null,
        scheduleType: _scheduleType,
        sendAt: _scheduleType == 'once' ? _sendAt : null,
        dailyTime: _scheduleType == 'daily' ? _dailyTimeText() : null,
        intervalMinutes: _scheduleType == 'interval' ? _intervalMinutes : null,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Container(
        margin: EdgeInsets.only(bottom: bottom),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context).cancel),
                  ),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? _groupProfileText(
                              context,
                              zhCN: '新增定时群消息',
                              zhTW: '新增定時群訊息',
                              en: 'New Scheduled Message',
                            )
                          : _groupProfileText(
                              context,
                              zhCN: '编辑定时群消息',
                              zhTW: '編輯定時群訊息',
                              en: 'Edit Scheduled Message',
                            ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _submit,
                    child: Text(
                      _groupProfileText(
                        context,
                        zhCN: '保存',
                        zhTW: '儲存',
                        en: 'Save',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: _groupProfileText(
                    context,
                    zhCN: '标题（可选）',
                    zhTW: '標題（可選）',
                    en: 'Title (optional)',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: _groupProfileText(
                    context,
                    zhCN: '消息内容',
                    zhTW: '訊息內容',
                    en: 'Message content',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 1,
                    label: Text(
                      _groupProfileText(
                        context,
                        zhCN: '文字',
                        zhTW: '文字',
                        en: 'Text',
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text(
                      _groupProfileText(
                        context,
                        zhCN: '图片',
                        zhTW: '圖片',
                        en: 'Image',
                      ),
                    ),
                  ),
                ],
                selected: {_messageType},
                onSelectionChanged: (values) =>
                    setState(() => _messageType = values.first),
              ),
              if (_messageType == 2) ...[
                const SizedBox(height: 12),
                _buildImagePicker(),
              ],
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'once',
                    label: Text(
                      _groupProfileText(
                        context,
                        zhCN: '一次',
                        zhTW: '一次',
                        en: 'Once',
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: 'daily',
                    label: Text(
                      _groupProfileText(
                        context,
                        zhCN: '每天',
                        zhTW: '每天',
                        en: 'Daily',
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: 'interval',
                    label: Text(
                      _groupProfileText(
                        context,
                        zhCN: '间隔',
                        zhTW: '間隔',
                        en: 'Interval',
                      ),
                    ),
                  ),
                ],
                selected: {_scheduleType},
                onSelectionChanged: (values) =>
                    setState(() => _scheduleType = values.first),
              ),
              const SizedBox(height: 12),
              if (_scheduleType == 'once')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _groupProfileText(
                      context,
                      zhCN: '发送时间',
                      zhTW: '發送時間',
                      en: 'Send time',
                    ),
                  ),
                  subtitle: Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(_sendAt),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _sendAt,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date == null || !mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_sendAt),
                    );
                    if (time == null) return;
                    setState(() {
                      _sendAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                )
              else if (_scheduleType == 'daily')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _groupProfileText(
                      context,
                      zhCN: '每天发送时间',
                      zhTW: '每天發送時間',
                      en: 'Daily send time',
                    ),
                  ),
                  subtitle: Text(_dailyTimeText()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _dailyTime,
                    );
                    if (time != null) setState(() => _dailyTime = time);
                  },
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _groupProfileText(
                      context,
                      zhCN: '间隔分钟',
                      zhTW: '間隔分鐘',
                      en: 'Interval minutes',
                    ),
                  ),
                  subtitle: Slider(
                    min: 1,
                    max: 1440,
                    divisions: 1439,
                    value: _intervalMinutes.clamp(1, 1440).toDouble(),
                    label: '$_intervalMinutes',
                    onChanged: (value) =>
                        setState(() => _intervalMinutes = value.round()),
                  ),
                  trailing: SizedBox(
                    width: 64,
                    child: TextFormField(
                      initialValue: _intervalMinutes.toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          _intervalMinutes = parsed;
                        }
                      },
                    ),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _groupProfileText(
                    context,
                    zhCN: '启用',
                    zhTW: '啟用',
                    en: 'Enabled',
                  ),
                ),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
