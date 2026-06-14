import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/premium_theme_tokens.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/platform_utils.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/call_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../../shared/widgets/member_badge_widget.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../../../shared/widgets/premium_widgets.dart';
import '../../contacts/providers/contact_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/message_provider.dart';
import 'chat_detail_page.dart' show ChatType;

/// 用户资料页面
class UserProfilePage extends ConsumerStatefulWidget {
  final String userId;
  final String? name;
  final String? avatar;
  final String? chatId; // 可选的私聊 ID
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示

  const UserProfilePage({
    super.key,
    required this.userId,
    this.name,
    this.avatar,
    this.chatId,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  bool _isLoading = false;
  bool _isContact = false;
  List<Map<String, dynamic>> _commonGroups = [];
  bool _loadingGroups = true;

  // 用户详细信息
  String? _realUsername;
  String? _realNickname;
  String? _realBio;
  String? _realAvatar;
  String? _nicknameColor; // 用户背景颜色
  String? _premiumType; // 会员类型
  bool _isMember = false; // 是否会员
  String? _badgeText; // 徽章文字
  String? _badgeColor; // 徽章颜色
  String? _emojiAvatar; // 表情状态
  String? _userUuid; // 用户 UUID（用于官方用户检查）
  String? _contactRemark;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _loadingUserInfo = true;

  // 私聊信息和媒体统计
  String? _privateChatId;
  api.ChatMediaCounts? _mediaCounts;

  // 静音状态
  bool _isMuted = false;

  // 屏蔽状态
  bool _isBlocked = false;
  bool _loadingBlockStatus = true;

  // WebSocket 在线状态监听
  Function(dynamic)? _userStatusHandler;
  Function(dynamic)? _userProfileHandler;

  @override
  void initState() {
    super.initState();
    _checkIsContact();
    Future.microtask(() {
      ref.read(contactListProvider.notifier).silentRefresh();
    });
    _loadUserInfo();
    _loadBlockStatus();
    _setupUserStatusListener();
    _setupUserProfileListener();
    _loadMuteStatus();
    // 延迟加载非必要数据，优化页面打开速度
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _loadCommonGroups();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _findPrivateChatAndLoadCounts();
    });
  }

  @override
  void dispose() {
    _removeUserStatusListener();
    _removeUserProfileListener();
    super.dispose();
  }

  /// 监听用户在线状态变化
  void _setupUserStatusListener() {
    final ws = ref.read(webSocketServiceProvider.notifier);
    _userStatusHandler = (data) {
      final userId = data['user_id']?.toString();
      final isOnline = data['is_online'] as bool? ?? false;
      // 检查是否是当前页面展示的用户
      if (userId == widget.userId || userId == _userUuid) {
        if (mounted) {
          setState(() {
            _isOnline = isOnline;
            if (!isOnline) {
              _lastSeen = DateTime.now();
            }
          });
        }
      }
    };
    ws.registerHandler('user_status', _userStatusHandler!);
  }

  /// 移除监听
  void _removeUserStatusListener() {
    if (_userStatusHandler != null) {
      try {
        final ws = ref.read(webSocketServiceProvider.notifier);
        ws.removeSpecificHandler('user_status', _userStatusHandler!);
      } catch (_) {}
    }
  }

  /// 监听用户资料变化
  void _setupUserProfileListener() {
    final ws = ref.read(webSocketServiceProvider.notifier);
    _userProfileHandler = (data) {
      final userId = data['user_id']?.toString();
      if (userId != widget.userId && userId != _userUuid) return;

      String? avatarUrl = data['avatar']?.toString();
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
      }

      if (!mounted) return;
      setState(() {
        final nextName = (data['nickname'] ?? data['name'])?.toString();
        if (nextName != null && nextName.isNotEmpty) {
          _realNickname = nextName;
        }
        _realUsername = data['username']?.toString() ?? _realUsername;
        _realBio = data['bio']?.toString() ?? _realBio;
        _realAvatar = avatarUrl ?? _realAvatar;
        _nicknameColor = data['nickname_color']?.toString() ?? _nicknameColor;
        _premiumType = data['premium_type']?.toString() ?? _premiumType;
        _emojiAvatar = data['emoji_avatar']?.toString() ?? _emojiAvatar;
      });
    };
    ws.registerHandler('user_profile', _userProfileHandler!);
  }

  void _removeUserProfileListener() {
    if (_userProfileHandler != null) {
      try {
        final ws = ref.read(webSocketServiceProvider.notifier);
        ws.removeSpecificHandler('user_profile', _userProfileHandler!);
      } catch (_) {}
    }
  }

  /// 加载屏蔽状态
  Future<void> _loadBlockStatus() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final userUuid = _userUuid ?? widget.userId;
      final response = await apiClient.get<Map<String, dynamic>>(
        '/user/blocked/check?user_id=$userUuid',
      );
      if (response.isSuccess && response.data != null) {
        if (mounted) {
          setState(() {
            _isBlocked = response.data!['is_blocked'] as bool? ?? false;
            _loadingBlockStatus = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[UserProfile] Load block status error: $e');
    } finally {
      if (mounted && _loadingBlockStatus) {
        setState(() => _loadingBlockStatus = false);
      }
    }
  }

  /// 切换屏蔽/取消屏蔽
  Future<void> _toggleBlock(BuildContext context) async {
    if (_isBlocked) {
      // 取消屏蔽
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('取消屏蔽'),
          content: Text(
            '确定要取消对 "${_realNickname ?? widget.name ?? '该用户'}" 的屏蔽吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                '取消屏蔽',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final apiClient = ref.read(apiClientProvider);
        final userUuid = _userUuid ?? widget.userId;
        final response = await apiClient.delete('/user/blocked/$userUuid');
        if (!mounted) return;
        if (response.isSuccess) {
          setState(() => _isBlocked = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已取消屏蔽')));
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(response.message)));
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
      }
    } else {
      // 屏蔽用户
      _showBlockDialog(context);
    }
  }

  /// 查找私聊并加载媒体数量和静音状态
  Future<void> _findPrivateChatAndLoadCounts() async {
    // 如果直接传入了 chatId，直接使用
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      _privateChatId = widget.chatId;
      _loadMediaCounts();
      _loadMuteStatusFromChat();
      return;
    }

    // 从聊天列表中查找与该用户的私聊
    final chatState = ref.read(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];

    for (final chat in allChats) {
      if (chat.type == ChatItemType.private) {
        // 检查多种匹配方式：targetUserId、targetUserUuid、id
        if (chat.targetUserId == widget.userId ||
            chat.targetUserUuid == widget.userId ||
            chat.id == widget.userId) {
          _privateChatId = chat.id;
          // 同时加载静音状态
          if (mounted) {
            setState(() => _isMuted = chat.isMuted);
          }
          break;
        }
      }
    }

    // 如果找到私聊，加载媒体数量
    if (_privateChatId != null) {
      _loadMediaCounts();
    }
  }

  /// 从聊天列表加载静音状态
  void _loadMuteStatusFromChat() {
    final chatState = ref.read(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];

    for (final chat in allChats) {
      if (chat.id == _privateChatId) {
        if (mounted) {
          setState(() => _isMuted = chat.isMuted);
        }
        break;
      }
    }
  }

  /// 加载媒体数量统计
  Future<void> _loadMediaCounts() async {
    if (_privateChatId == null) return;

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getChatMediaCounts(_privateChatId!);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _mediaCounts = response.data;
        });
      }
    } catch (e) {
      // 忽略错误
    }
  }

  void _checkIsContact() {
    final contacts = ref.read(contactListProvider);
    ContactItem? matchedContact;
    for (final contact in contacts) {
      if (contact.id == widget.userId || contact.uuid == widget.userId) {
        matchedContact = contact;
        break;
      }
    }
    setState(() {
      _isContact = matchedContact != null;
      _contactRemark = matchedContact?.remark;
    });
  }

  /// 加载用户详细信息
  Future<void> _loadUserInfo() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/user/${widget.userId}');
      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        String? avatarUrl = response.data['avatar'];
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
        }

        ContactItem? matchedContact;
        for (final contact in ref.read(contactListProvider)) {
          if (contact.id == widget.userId || contact.uuid == widget.userId) {
            matchedContact = contact;
            break;
          }
        }
        final inferredRemark = matchedContact != null &&
                (matchedContact.remark?.trim().isNotEmpty != true) &&
                matchedContact.name.trim().isNotEmpty &&
                matchedContact.name.trim() !=
                    (response.data['nickname']?.toString().trim() ?? '')
            ? matchedContact.name.trim()
            : matchedContact?.remark;

        setState(() {
          _realUsername = response.data['username'];
          _realNickname = response.data['nickname'];
          _realBio = response.data['bio'];
          _realAvatar = avatarUrl;
          _nicknameColor = response.data['nickname_color'];
          _premiumType = response.data['premium_type'];
          _isMember = response.data['is_member'] == true || response.data['is_member'] == 1;
          _badgeText = response.data['badge_text'];
          _badgeColor = response.data['badge_color'];
          _emojiAvatar = response.data['emoji_avatar'];
          _userUuid = response.data['id']?.toString();
          _contactRemark = inferredRemark;
          _isOnline = response.data['status'] == 1;
          if (response.data['last_seen'] != null) {
            _lastSeen = DateTime.tryParse(
              response.data['last_seen'],
            )?.toLocal();
          }
          _loadingUserInfo = false;
        });
      } else {
        setState(() => _loadingUserInfo = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingUserInfo = false);
    }
  }

  Future<void> _loadCommonGroups() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/user/${widget.userId}/common-groups');
      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        final groupsData = response.data['groups'];
        setState(() {
          _commonGroups = groupsData is List
              ? List<Map<String, dynamic>>.from(groupsData)
              : [];
          _loadingGroups = false;
        });
      } else {
        setState(() => _loadingGroups = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  bool get _isCurrentUser {
    final currentUser = ref.read(authServiceProvider).user;
    return currentUser?.uuid == widget.userId;
  }

  /// 显示名称（优先 nickname）
  String get _displayName {
    if (_contactRemark != null && _contactRemark!.trim().isNotEmpty) {
      return _contactRemark!.trim();
    }
    if (_realNickname != null && _realNickname!.isNotEmpty) {
      return _realNickname!;
    }
    return widget.name ?? '用户';
  }

  /// 在线状态文本
  String get _onlineStatusText {
    if (_loadingUserInfo) return '加载中...';
    if (_isOnline) return '在线';
    if (_lastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(_lastSeen!);
      if (diff.inMinutes < 1) return '刚刚在线';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前在线';
      if (diff.inHours < 24) return '${diff.inHours}小时前在线';
      if (diff.inDays < 7) return '${diff.inDays}天前在线';
      return '很久没上线';
    }
    return '离线';
  }

  // 个人资料页背景渐变色（与 personalization_page.dart 保持一致）
  static const List<List<Color>> _profileBgGradients = [
    [Color(0xFF5B9EE1), Color(0xFF2575BC)], // 蓝色
    [Color(0xFF43C6AC), Color(0xFF1D976C)], // 绿色
    [Color(0xFFFFB347), Color(0xFFFF8008)], // 橙色
    [Color(0xFFFF6B6B), Color(0xFFEE0979)], // 红色
    [Color(0xFFA18CD1), Color(0xFF6A3093)], // 紫色
    [Color(0xFF4ECDC4), Color(0xFF009688)], // 青色
    [Color(0xFFFF9A9E), Color(0xFFFECFEF)], // 粉色
    [Color(0xFF8E9AAF), Color(0xFF5C6B7A)], // 灰色
  ];

  /// 获取用户背景颜色
  Color _getUserBackgroundColor() {
    if (_nicknameColor != null && _nicknameColor!.isNotEmpty) {
      // 解析格式 "bg:0,name:0"
      final parts = _nicknameColor!.split(',');
      for (final part in parts) {
        if (part.startsWith('bg:')) {
          final index = int.tryParse(part.substring(3)) ?? 0;
          final clampedIndex = index.clamp(0, _profileBgGradients.length - 1);
          return _profileBgGradients[clampedIndex][0];
        }
      }
    }
    // 默认使用基于用户 ID 的颜色
    return AppColors.getAvatarColor(widget.userId);
  }

  /// 获取用户背景渐变色
  List<Color> _getUserBackgroundGradient() {
    if (_premiumType != null && _premiumType!.isNotEmpty) {
      if (_premiumType == 'yearly') {
        return const [Color(0xFF111827), Color(0xFF7C2D12), Color(0xFFF59E0B)];
      }
      if (_premiumType == 'quarterly') {
        return const [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF06B6D4)];
      }
      return const [Color(0xFF0F172A), Color(0xFF312E81), Color(0xFF7C3AED)];
    }
    if (_nicknameColor != null && _nicknameColor!.isNotEmpty) {
      // 解析格式 "bg:0,name:0"
      final parts = _nicknameColor!.split(',');
      for (final part in parts) {
        if (part.startsWith('bg:')) {
          final index = int.tryParse(part.substring(3)) ?? 0;
          final clampedIndex = index.clamp(0, _profileBgGradients.length - 1);
          return _profileBgGradients[clampedIndex];
        }
      }
    }
    // 默认使用基于用户 ID 的颜色
    final baseColor = AppColors.getAvatarColor(widget.userId);
    return [baseColor, baseColor.withOpacity(0.8)];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final separatorColor =
        isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

    // 监听联系人列表变化
    ref.listen(contactListProvider, (_, contacts) {
      final isContact = contacts.any(
        (c) => c.id == widget.userId || c.uuid == widget.userId,
      );
      if (isContact != _isContact) {
        setState(() => _isContact = isContact);
      }

      ContactItem? matchedContact;
      for (final contact in contacts) {
        if (contact.id == widget.userId || contact.uuid == widget.userId) {
          matchedContact = contact;
          break;
        }
      }
      if (matchedContact == null) return;

      final nextName = matchedContact.name;
      final nextAvatar = matchedContact.avatar;
      final nextNicknameColor = matchedContact.nicknameColor;
      final nextPremiumType = matchedContact.premiumType;
      final nextEmojiAvatar = matchedContact.emojiAvatar;
      final nextRemark = matchedContact.remark;
      final nextNickname = nextRemark?.trim().isNotEmpty == true
          ? _realNickname
          : nextName;

      if (_realNickname == nextNickname &&
          _realAvatar == nextAvatar &&
          _nicknameColor == nextNicknameColor &&
          _premiumType == nextPremiumType &&
          _emojiAvatar == nextEmojiAvatar &&
          _contactRemark == nextRemark) {
        return;
      }

      setState(() {
        _realNickname = nextNickname;
        _realAvatar = nextAvatar;
        _nicknameColor = nextNicknameColor;
        _premiumType = nextPremiumType;
        _emojiAvatar = nextEmojiAvatar;
        _contactRemark = nextRemark;
      });
    });

    final profileBgGradient = _getUserBackgroundGradient();
    final profileBgColor = profileBgGradient[0];

    Widget content = Scaffold(
      backgroundColor: bgColor, // 页面背景
      body: Stack(
        children: [
          // 顶部背景（渐变+SVG图案，覆盖到四个按钮以下）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 450,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: profileBgGradient,
                ),
              ),
              child: Opacity(
                opacity: 0.2,
                child: SvgPicture.asset(
                  'assets/images/backgrounds/bg5.svg',
                  fit: BoxFit.cover,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
          // 主内容
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // iOS 风格导航栏（透明，让底层SVG图案显示）
              SliverAppBar(
                pinned: true,
                stretch: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: Colors.white,
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
                  if (_isCurrentUser)
                    TextButton(
                      onPressed: () => context.push('/settings/profile'),
                      child: const Text(
                        '编辑',
                        style: TextStyle(color: Colors.white, fontSize: 17),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () => _showMoreOptions(context),
                    ),
                ],
              ),

              // 头像、名字、在线状态和操作按钮（透明背景，由底层提供图案）
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // 头像
                    GestureDetector(
                      onTap: () => _showAvatarFullScreen(context),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(
                              _premiumType?.isNotEmpty == true ? 0.0 : 1.0,
                            ),
                            width: _premiumType?.isNotEmpty == true ? 0 : 4,
                          ),
                        ),
                        child: Hero(
                          tag: 'avatar_${widget.userId}',
                          child: AvatarWidget(
                            name: _displayName,
                            avatar: _realAvatar ?? widget.avatar,
                            userId: widget.userId,
                            size: 100,
                            premiumType: _premiumType,
                            isMember: _isMember,
                            memberBadgeColor: _badgeColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 名称 + 表情状态 + 官方标识
                    Consumer(
                      builder: (context, ref, _) {
                        final officialUsersAsync = ref.watch(
                          officialUsersProvider,
                        );
                        final officialUsers =
                            officialUsersAsync.valueOrNull ?? {};
                        // 使用 _userUuid 来检查是否是官方用户，如果还没加载完则尝试 widget.userId
                        final userUuidToCheck = _userUuid ?? widget.userId;
                        final isOfficial = officialUsers.contains(
                          userUuidToCheck,
                        );

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ColoredNameWidget(
                              name: _displayName,
                              nicknameColor: _nicknameColor,
                              premiumType: _premiumType,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              defaultColor: Colors.white,
                            ),
                            if (_emojiAvatar != null &&
                                _emojiAvatar!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              EmojiStatusWidget(emoji: _emojiAvatar!, size: 26),
                            ],
                            // 会员徽章
                            MemberBadgeWidget(
                              isMember: _isMember,
                              badgeText: _badgeText,
                              badgeColor: _badgeColor,
                              fontSize: 11,
                              margin: const EdgeInsets.only(left: 6),
                            ),
                            // 官方认证标识
                            if (isOfficial) ...[
                              const SizedBox(width: 6),
                              const OfficialBadge(size: 22),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    // 在线状态
                    Text(
                      _onlineStatusText,
                      style: TextStyle(
                        fontSize: 15,
                        color: _isOnline ? Colors.white : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 操作按钮（不显示给自己）
                    if (!_isCurrentUser)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // F-12: 非好友且未开启「允许非好友消息」时，显示「加好友」替代「消息」
                            (!_isContact &&
                                    !(ref
                                            .watch(systemSettingsProvider)
                                            .valueOrNull
                                            ?.allowStrangerMessage ??
                                        false))
                                ? _TGActionButton(
                                    icon: Icons.person_add_alt_1,
                                    label: l10n.get('add_contact') ?? '加好友',
                                    onTap: () => _toggleContact(),
                                    isLoading: _isLoading,
                                    lightStyle: true,
                                  )
                                : _TGActionButton(
                                    icon: Icons.chat_bubble_outline,
                                    label: l10n.get('message') ?? '消息',
                                    onTap: () => _startChat(context),
                                    isLoading: _isLoading,
                                    lightStyle: true,
                                  ),
                            _TGActionButton(
                              icon: Icons.call_outlined,
                              label: l10n.get('call') ?? '通话',
                              onTap: () => _startCall(context, CallType.voice),
                              lightStyle: true,
                            ),
                            _TGActionButton(
                              icon: Icons.videocam_outlined,
                              label: l10n.get('video') ?? '视频',
                              onTap: () => _startCall(context, CallType.video),
                              lightStyle: true,
                            ),
                            _TGActionButton(
                              icon: _isMuted
                                  ? Icons.volume_up_outlined
                                  : Icons.volume_off_outlined,
                              label: _isMuted
                                  ? (l10n.get('unmute') ?? '取消静音')
                                  : (l10n.get('mute') ?? '静音'),
                              onTap: () => _toggleMute(),
                              lightStyle: true,
                            ),
                          ],
                        ),
                      ),
                    if (_isCurrentUser) const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: PremiumCard(
                        isDark: true,
                        premiumType: _premiumType,
                        padding: const EdgeInsets.all(18),
                        borderRadius: BorderRadius.circular(24),
                        colors: profileBgGradient,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.white.withOpacity(0.95),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  PremiumThemeTokens.isPremium(_premiumType)
                                      ? 'Premium Profile'
                                      : 'Profile Snapshot',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              (_realBio != null && _realBio!.isNotEmpty)
                                  ? _realBio!
                                  : (l10n.get('no_bio') ?? '这个人很懒，什么都没留下'),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.84),
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                            if (_realUsername != null &&
                                _realUsername!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              PremiumContainer(
                                premiumType: _premiumType,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.alternate_email,
                                        size: 16,
                                        color: Colors.white.withOpacity(0.92),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '@$_realUsername',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
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
                  ],
                ),
              ),

              // 间距
              SliverToBoxAdapter(child: SizedBox(height: 20)),

              // 用户信息卡片
              SliverToBoxAdapter(
                child: _TGSection(
                  cardColor: cardColor,
                  separatorColor: separatorColor,
                  children: [
                    if (_realUsername != null && _realUsername!.isNotEmpty)
                      _TGInfoCell(
                        title: '@$_realUsername',
                        subtitle: l10n.username,
                        onTap: () => _copyToClipboard('@$_realUsername'),
                      ),
                    _TGInfoCell(
                      title: (_realBio != null && _realBio!.isNotEmpty)
                          ? _realBio!
                          : (l10n.get('no_bio') ?? '这个人很懒，什么都没留下'),
                      subtitle: l10n.bio,
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
                      title: l10n.get('photos_and_videos') ?? '照片和视频',
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.media ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('photos_and_videos') ?? '照片和视频',
                        'media',
                      ),
                    ),
                    _TGCell(
                      icon: Icons.link,
                      iconColor: AppColors.primary,
                      title: l10n.get('shared_links') ?? '共享链接',
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.link ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('shared_links') ?? '共享链接',
                        'link',
                      ),
                    ),
                    _TGCell(
                      icon: Icons.insert_drive_file_outlined,
                      iconColor: AppColors.primary,
                      title: l10n.get('files') ?? '文件',
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.file ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('files') ?? '文件',
                        'file',
                      ),
                    ),
                    _TGCell(
                      icon: Icons.mic_outlined,
                      iconColor: AppColors.primary,
                      title: l10n.get('voice_messages') ?? '语音消息',
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.voice ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('voice_messages') ?? '语音消息',
                        'voice',
                      ),
                    ),
                  ],
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: 20)),

              // 共同群组
              SliverToBoxAdapter(
                child: _TGSection(
                  cardColor: cardColor,
                  separatorColor: separatorColor,
                  children: [
                    _TGCell(
                      icon: Icons.group_outlined,
                      iconColor: Colors.green,
                      title: l10n.get('common_groups') ?? '共同群组',
                      titlePrefix:
                          '${_commonGroups.length} ${l10n.get('count_suffix') ?? '个'}',
                      trailing: _buildArrowTrailing(),
                      onTap: () => _showCommonGroups(context),
                    ),
                  ],
                ),
              ),

              // 危险操作（不显示给自己）
              if (!_isCurrentUser) ...[
                SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverToBoxAdapter(
                  child: _TGSection(
                    cardColor: cardColor,
                    separatorColor: separatorColor,
                    children: [
                      _TGCell(
                        title: _isBlocked
                            ? (l10n.get('unblock_user') ?? '取消屏蔽')
                            : (l10n.get('block_user') ?? '屏蔽用户'),
                        titleColor: _isBlocked ? Colors.orange : Colors.red,
                        trailing: _loadingBlockStatus
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _loadingBlockStatus
                            ? null
                            : () => _toggleBlock(context),
                      ),
                      _TGCell(
                        title: l10n.get('report') ?? '举报',
                        titleColor: Colors.red,
                        onTap: () => _showReportPage(context),
                      ),
                    ],
                  ),
                ),
              ],

              SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
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

  Widget _buildArrowTrailing() {
    return Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22);
  }

  void _showFeatureNotAvailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature 功能暂未开放')));
  }

  void _showAvatarFullScreen(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _AvatarFullScreen(
          name: _displayName,
          avatar: _realAvatar ?? widget.avatar,
          userId: widget.userId,
        ),
      ),
    );
  }

  void _startChat(BuildContext context) async {
    // F-12: 非好友且未开启「允许非好友消息」时，拦截发消息
    final allowStranger =
        ref.read(systemSettingsProvider).valueOrNull?.allowStrangerMessage ??
            false;
    if (!_isContact && !allowStranger && !_isCurrentUser) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要先添加对方为好友才能发送消息'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    // 桌面端：如果已经在聊天页面了，只需关闭资料面板
    if (widget.isDesktopPanel && widget.chatId != null) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
      return;
    }

    setState(() => _isLoading = true);

    try {
      final chat =
          await ref.read(chatListProvider.notifier).createPrivateChatFromServer(
                targetUserId: widget.userId,
                targetUserName: widget.name ?? '用户',
                avatar: widget.avatar,
              );
      if (chat != null && mounted) {
        // 桌面端：选中聊天并关闭资料面板
        if (widget.isDesktopPanel || PlatformUtils.isDesktop) {
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: widget.name ?? '用户',
            avatar: widget.avatar,
            chatType: ChatType.private,
          );
          ref.read(desktopProfileProvider.notifier).state =
              DesktopProfileInfo.none;
        } else {
          context.push(
            '/chat/${chat.id}?name=${Uri.encodeComponent(widget.name ?? '用户')}&type=private',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 直接发起通话（无需先跳转聊天页）
  void _startCall(BuildContext context, CallType callType) async {
    setState(() => _isLoading = true);

    try {
      final callService = ref.read(callServiceProvider.notifier);

      // 直接发起通话
      final success = await callService.startCall(
        targetUserId: widget.userId,
        targetName: widget.name ?? '用户',
        targetAvatar: widget.avatar,
        type: callType,
      );

      if (success && mounted) {
        // 导航到通话页面
        context.push('/call');
      } else if (mounted) {
        // 显示错误信息
        final errorMsg = ref.read(callServiceProvider).errorMessage;
        if (errorMsg != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMsg)));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 加载静音状态（从聊天列表获取）
  void _loadMuteStatus() {
    // 静音状态会在 _findPrivateChatAndLoadCounts 中加载
    // 这里作为备用，提前尝试加载
    if (widget.chatId != null) {
      _loadMuteStatusFromChatId(widget.chatId!);
    }
  }

  void _loadMuteStatusFromChatId(String chatId) {
    final chatState = ref.read(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];

    for (final chat in allChats) {
      if (chat.id == chatId) {
        if (mounted) {
          setState(() => _isMuted = chat.isMuted);
        }
        break;
      }
    }
  }

  /// 切换静音状态
  Future<void> _toggleMute() async {
    // 先创建或获取聊天
    String? chatId = _privateChatId ?? widget.chatId;
    if (chatId == null) {
      final chat =
          await ref.read(chatListProvider.notifier).createPrivateChatFromServer(
                targetUserId: widget.userId,
                targetUserName: widget.name ?? '用户',
                avatar: widget.avatar,
              );
      if (chat != null) {
        chatId = chat.id;
        _privateChatId = chat.id;
      }
    }

    if (chatId == null) return;

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.toggleMuteChat(chatId);
      if (response.isSuccess && mounted) {
        final newMuteState = response.data ?? !_isMuted;
        setState(() => _isMuted = newMuteState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newMuteState ? '已静音' : '已取消静音'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置失败: ${response.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败')));
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        actions: [
          // 添加/移除联系人
          _TGActionSheetItem(
            title: _isContact ? '从联系人中移除' : '添加到联系人',
            isDestructive: _isContact,
            onTap: () {
              Navigator.pop(context);
              _toggleContact();
            },
          ),
          if (_isContact)
            _TGActionSheetItem(
              title: '修改备注',
              onTap: () {
                Navigator.pop(context);
                _showEditRemarkDialog();
              },
            ),
          _TGActionSheetItem(
            title: '分享联系人',
            onTap: () {
              Navigator.pop(context);
              _shareContact(context);
            },
          ),
          _TGActionSheetItem(
            title: '搜索消息',
            onTap: () {
              Navigator.pop(context);
              _searchMessages(context);
            },
          ),
          _TGActionSheetItem(
            title: '清空聊天记录',
            isDestructive: true,
            onTap: () {
              Navigator.pop(context);
              _showClearChatDialog(context);
            },
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  Future<void> _showEditRemarkDialog() async {
    final controller = TextEditingController(text: _contactRemark ?? '');
    final remark = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '填写备注名，留空则显示昵称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (remark == null) return;
    final userUuid = _userUuid ?? widget.userId;
    final success = await ref
        .read(contactListProvider.notifier)
        .updateRemark(userUuid, remark);
    if (!mounted) return;
    if (success) {
      setState(() => _contactRemark = remark);
      final fallbackName = _realNickname?.trim().isNotEmpty == true
          ? _realNickname!.trim()
          : (widget.name?.trim().isNotEmpty == true ? widget.name!.trim() : '用户');
      final nextDisplayName = remark.trim().isNotEmpty
          ? remark.trim()
          : fallbackName;
      ref.read(chatListProvider.notifier).updatePrivateChatDisplayName(
            userId: userUuid,
            name: nextDisplayName,
          );
      ref.read(chatListProvider.notifier).silentRefresh(bypassDebounce: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('备注已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('备注保存失败，请重试'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _toggleContact() async {
    // 使用UUID进行API调用，优先使用 _userUuid
    final userUuid = _userUuid ?? widget.userId;

    if (_isContact) {
      // 移除联系人 - 显示确认对话框
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('移除联系人'),
          content: Text('确定要将 ${_displayName} 从联系人中移除吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('移除'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final success =
          await ref.read(contactListProvider.notifier).removeContact(userUuid);
      if (success && mounted) {
        // 从会话列表移除该私聊会话
        final chatId = widget.chatId;
        if (chatId != null && chatId.isNotEmpty) {
          ref.read(chatListProvider.notifier).removeChat(chatId);
        }
        // 直接返回到上一页，不在资料页停留
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/');
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('移除失败，请重试'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    } else {
      // 添加联系人
      final result = await ref
          .read(contactListProvider.notifier)
          .addContactWithStatus(userUuid);
      if (!mounted) return;
      if (result.success) {
        setState(() => _isContact = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已将 ${_displayName} 添加到联系人'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (result.pending) {
        // 已发送申请，等待对方验证——不算失败
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('好友申请已发送，等待 ${_displayName} 验证'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message?.isNotEmpty == true ? result.message! : '添加失败，请重试'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _shareContact(BuildContext context) {
    final username = _realUsername ?? '';
    final contactInfo = '''
$_displayName
${username.isNotEmpty ? '@$username' : ''}
${(_realBio != null && _realBio!.isNotEmpty) ? _realBio : ''}
'''
        .trim();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 显示分享选项
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 名片预览
            PremiumCard(
              isDark: isDark,
              premiumType: _premiumType,
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(14),
              colors: isDark
                  ? const [Color(0xFF2C2C2E), Color(0xFF1F2937)]
                  : const [Colors.white, Color(0xFFF8FAFF)],
              child: Column(
                children: [
                  // 标题
                  Text(
                    '分享联系人',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 名片预览
                  PremiumCard(
                    isDark: isDark,
                    premiumType: _premiumType,
                    padding: const EdgeInsets.all(12),
                    borderRadius: BorderRadius.circular(12),
                    colors: isDark
                        ? [
                            Colors.white.withOpacity(0.05),
                            Colors.white.withOpacity(0.02),
                          ]
                        : const [Color(0xFFF8FAFF), Color(0xFFF3F4F6)],
                    child: Row(
                      children: [
                        AvatarWidget(
                          avatar: _realAvatar ?? widget.avatar,
                          name: _displayName,
                          userId: widget.userId,
                          size: 48,
                          premiumType: _premiumType,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ColoredNameWidget(
                                name: _displayName,
                                nicknameColor: _nicknameColor,
                                premiumType: _premiumType,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                defaultColor:
                                    isDark ? Colors.white : Colors.black87,
                              ),
                              if (username.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '@$username',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 复制按钮
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: contactInfo));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text('联系人信息已复制'),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.success,
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 20,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '复制联系人信息',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 发送名片按钮
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _sendContactCard(context);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '发送名片给好友',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 取消按钮
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor:
                      isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  /// 发送联系人名片
  void _sendContactCard(BuildContext context) {
    // 显示好友选择器
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FriendSelectorSheet(
        onSelect: (friendId, friendName) async {
          Navigator.pop(context);

          // 使用UUID
          final userUuid = _userUuid ?? widget.userId;

          // 创建与好友的私聊并发送名片
          final api = ref.read(apiClientProvider);

          try {
            final chatResponse = await api.post(
              '/chat/create',
              data: {
                'type': 1,
                'member_ids': [friendId],
              },
            );

            if (chatResponse.isSuccess && chatResponse.data != null) {
              final chatId = chatResponse.data['uuid'];

              // 发送联系人名片消息
              final sendResponse = await api.post(
                '/message/send',
                data: {
                  'chat_id': chatId,
                  'type': 10, // 名片类型
                  'content': {
                    'contact': {
                      'user_id': userUuid,
                      'nickname': _displayName,
                      'username': _realUsername ?? '',
                      'avatar': _realAvatar ?? widget.avatar ?? '',
                      'bio': _realBio ?? '',
                      'nickname_color': _nicknameColor ?? '',
                      'emoji_avatar': _emojiAvatar ?? '',
                      'premium_type': _premiumType ?? '',
                    },
                  },
                },
              );

              if (mounted) {
                if (sendResponse.isSuccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text('已将 $_displayName 的名片发送给 $friendName'),
                        ],
                      ),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(sendResponse.message ?? '发送失败'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(chatResponse.message ?? '创建会话失败'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.error,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('发送失败，请重试'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _searchMessages(BuildContext context) {
    // 导航到搜索页面
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _SearchMessagesPage(
          userId: widget.userId,
          userName: widget.name ?? '用户',
        ),
      ),
    );
  }

  void _showClearChatDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: '清空与 ${widget.name ?? '该用户'} 的聊天记录？',
        message: '此操作无法撤销',
        actions: [
          _TGActionSheetItem(
            title: '仅为我清空',
            isDestructive: true,
            onTap: () async {
              Navigator.pop(context);
              await _clearChatHistory();
            },
          ),
          _TGActionSheetItem(
            title: '为双方清空',
            isDestructive: true,
            onTap: () async {
              Navigator.pop(context);
              await _clearChatHistory(forBoth: true);
            },
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  /// 清空聊天记录
  Future<void> _clearChatHistory({bool forBoth = false}) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final chatService = ref.read(api.chatServiceProvider);

      // 首先获取或创建私聊
      final userUuid = _userUuid ?? widget.userId;
      final chatResponse = await apiClient.post(
        '/chat/create',
        data: {
          'type': 1, // 私聊
          'member_ids': [userUuid],
        },
      );

      if (chatResponse.isSuccess && chatResponse.data != null) {
        final chatId = chatResponse.data['uuid'];
        _privateChatId = chatId?.toString();
        if (chatId == null || chatId.toString().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('清空失败，请重试')));
          }
          return;
        }

        // 调用清空聊天记录 API
        final clearResponse = forBoth
            ? await chatService.clearChatHistoryForBoth(chatId.toString())
            : await chatService.clearChatHistory(chatId.toString());

        if (clearResponse.isSuccess && mounted) {
          // 刷新当前会话消息缓存（若会话页仍在栈中可立即生效）
          ref.invalidate(messageListProvider(chatId.toString()));
          // 刷新聊天列表
          ref.read(chatListProvider.notifier).refresh();

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(content: Text(forBoth ? '已为双方清空聊天记录' : '聊天记录已清空')),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(clearResponse.message ?? '清空失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清空失败，请重试')));
      }
    }
  }

  void _showCommonGroups(BuildContext context) {
    if (_commonGroups.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无共同群组')));
      return;
    }

    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _CommonGroupsPage(
          groups: _commonGroups,
          userName: widget.name ?? '用户',
        ),
      ),
    );
  }

  void _showMediaList(BuildContext context, String title, String type) {
    if (_privateChatId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无聊天记录')));
      return;
    }
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) =>
            _MediaListPage(chatId: _privateChatId!, title: title, type: type),
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    // 提前保存页面级 context，防止被 builder 参数遮蔽后失效
    final pageContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TGActionSheet(
        title: '屏蔽 ${widget.name ?? '该用户'}？',
        message: '屏蔽后将无法收到对方的消息',
        actions: [
          _TGActionSheetItem(
            title: '屏蔽',
            isDestructive: true,
            onTap: () async {
              Navigator.pop(sheetContext);
              try {
                final api = ref.read(apiClientProvider);
                final userUuid = _userUuid ?? widget.userId;
                final response = await api.post<Map<String, dynamic>>(
                  '/user/blocked',
                  data: {'user_id': userUuid},
                );
                if (!mounted) return;
                if (response.isSuccess || response.message == '已经屏蔽该用户') {
                  setState(() => _isBlocked = true);
                  ScaffoldMessenger.of(
                    pageContext,
                  ).showSnackBar(const SnackBar(content: Text('已屏蔽')));
                } else {
                  ScaffoldMessenger.of(
                    pageContext,
                  ).showSnackBar(SnackBar(content: Text(response.message)));
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  pageContext,
                ).showSnackBar(const SnackBar(content: Text('屏蔽失败，请重试')));
              }
            },
          ),
        ],
        cancelText: '取消',
      ),
    );
  }

  void _showReportPage(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _ReportPage(
          targetId: widget.userId,
          targetType: 'user',
          targetName: widget.name ?? '用户',
        ),
      ),
    );
  }
}

//  操作按钮
class _TGActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool lightStyle; // 浅色样式，用于彩色背景

  const _TGActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.lightStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = lightStyle
        ? Colors.white.withOpacity(0.2)
        : AppColors.primary.withOpacity(0.1);
    final iconColor = lightStyle ? Colors.white : AppColors.primary;
    final textColor = lightStyle ? Colors.white : AppColors.primary;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    ),
                  )
                : Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: textColor)),
        ],
      ),
    );
  }
}

//  卡片容器
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
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

//  信息单元格（值在上，标签在下）
class _TGInfoCell extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _TGInfoCell({required this.title, required this.subtitle, this.onTap});

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
                      color: isDark ? Colors.white : Colors.black,
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
  final String? titlePrefix;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _TGCell({
    this.icon,
    this.iconColor,
    required this.title,
    this.titlePrefix,
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
              child: Text.rich(
                TextSpan(
                  children: [
                    if (titlePrefix != null)
                      TextSpan(
                        text: '$titlePrefix ',
                        style: TextStyle(
                          fontSize: 17,
                          color: titleColor ??
                              (isDark ? Colors.white : Colors.black),
                        ),
                      ),
                    TextSpan(
                      text: title,
                      style: TextStyle(
                        fontSize: 17,
                        color: titleColor ??
                            (isDark ? Colors.white : Colors.black),
                      ),
                    ),
                  ],
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
  final bool isDestructive;
  final VoidCallback onTap;

  const _TGActionSheetItem({
    required this.title,
    this.isDestructive = false,
    required this.onTap,
  });
}

// 头像全屏查看
class _AvatarFullScreen extends StatelessWidget {
  final String name;
  final String? avatar;
  final String userId;

  const _AvatarFullScreen({
    required this.name,
    this.avatar,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Hero(
            tag: 'avatar_$userId',
            child: AvatarWidget(
              name: name,
              avatar: avatar,
              userId: userId,
              size: 280,
            ),
          ),
        ),
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
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
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

    // 根据类型显示不同的布局
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

  // 图片/视频网格
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

  // 链接列表
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
                      style: TextStyle(fontSize: 12, color: Colors.grey),
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

  // 文件列表
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

  // 语音列表
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
      // 打开视频播放器
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
      // 打开图片预览
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
      // 停止播放
      await _audioPlayer.stop();
      setState(() {
        _playingVoiceId = null;
        _isPlaying = false;
      });
    } else {
      // 播放新语音
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

// 搜索消息页面
class _SearchMessagesPage extends ConsumerStatefulWidget {
  final String userId;
  final String userName;

  const _SearchMessagesPage({required this.userId, required this.userName});

  @override
  ConsumerState<_SearchMessagesPage> createState() =>
      _SearchMessagesPageState();
}

class _SearchMessagesPageState extends ConsumerState<_SearchMessagesPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String? _chatId;

  @override
  void initState() {
    super.initState();
    _getChatId();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 获取私聊 ID
  Future<void> _getChatId() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post(
        '/chat/create',
        data: {
          'type': 1,
          'member_ids': [widget.userId],
        },
      );
      if (response.isSuccess && response.data != null) {
        setState(() => _chatId = response.data['uuid']);
      }
    } catch (e) {
      // 忽略错误
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty || _chatId == null) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get(
        '/chat/$_chatId/search',
        queryParameters: {'keyword': query},
      );

      if (response.isSuccess && response.data != null && mounted) {
        final list = response.data['list'] as List? ?? [];
        setState(() {
          _isSearching = false;
          _results = list.map((e) => e as Map<String, dynamic>).toList();
        });
      } else if (mounted) {
        setState(() {
          _isSearching = false;
          _results = [];
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
                color:
                    isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '在与 ${widget.userName} 的对话中搜索',
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
                              horizontal: 16,
                              vertical: 4,
                            ),
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

// 共同群组页面
class _CommonGroupsPage extends StatelessWidget {
  final List<Map<String, dynamic>> groups;
  final String userName;

  const _CommonGroupsPage({required this.groups, required this.userName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '与 $userName 的共同群组',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: groups.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    '暂无共同群组',
                    style: TextStyle(fontSize: 17, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final groupName = group['name'] ?? '群组';
                // 处理头像 URL（相对路径需要加上服务器地址）
                String? groupAvatar = group['avatar'] as String?;
                if (groupAvatar != null && groupAvatar.isNotEmpty) {
                  if (groupAvatar.startsWith('/uploads')) {
                    groupAvatar = '${ApiConfig.serverUrl}$groupAvatar';
                  } else if (!groupAvatar.startsWith('http')) {
                    groupAvatar = '${ApiConfig.serverUrl}/$groupAvatar';
                  }
                }
                final memberCount = group['member_count'] ?? 0;

                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: AvatarWidget(
                      avatar: groupAvatar,
                      name: groupName,
                      size: 48,
                    ),
                    title: Text(
                      groupName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      '$memberCount 位成员',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                    ),
                    onTap: () {
                      context.push(
                        '/chat/${group['id']}?name=${Uri.encodeComponent(groupName)}&type=group',
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// 举报页面
class _ReportPage extends ConsumerStatefulWidget {
  final String targetId;
  final String targetType; // user, group, channel
  final String targetName;

  const _ReportPage({
    required this.targetId,
    required this.targetType,
    required this.targetName,
  });

  @override
  ConsumerState<_ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<_ReportPage> {
  String? _selectedReason;
  final _descController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _reasons = [
    {'id': 'spam', 'title': '垃圾信息', 'icon': Icons.mail_outline},
    {'id': 'fake', 'title': '虚假信息/诈骗', 'icon': Icons.warning_amber_outlined},
    {'id': 'violence', 'title': '暴力或危险内容', 'icon': Icons.dangerous_outlined},
    {'id': 'porn', 'title': '色情内容', 'icon': Icons.block},
    {'id': 'harassment', 'title': '骚扰或欺凌', 'icon': Icons.person_off_outlined},
    {'id': 'copyright', 'title': '侵犯版权', 'icon': Icons.copyright},
    {'id': 'other', 'title': '其他', 'icon': Icons.more_horiz},
  ];

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择举报原因')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post(
        '/report',
        data: {
          'target_id': widget.targetId,
          'target_type': widget.targetType,
          'reason': _selectedReason,
          'description': _descController.text.trim(),
        },
      );

      if (response.isSuccess && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('举报已提交，我们会尽快处理')));
      } else {
        // 显示具体的错误信息
        final errorMsg = response.message ?? '提交失败，请重试';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      // 解析错误信息
      String errorMsg = '提交失败，请重试';
      if (e.toString().contains('400')) {
        errorMsg = '您已举报过该内容，请等待处理';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMsg)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final separatorColor =
        isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

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
          '举报',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submitReport,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '提交',
                    style: TextStyle(color: AppColors.primary, fontSize: 17),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 举报对象
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.targetType == 'user'
                        ? Icons.person
                        : widget.targetType == 'group'
                            ? Icons.group
                            : Icons.campaign,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '举报对象',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.targetName,
                          style: TextStyle(
                            fontSize: 17,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 举报原因标题
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 16, 8),
              child: Text(
                '选择举报原因',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),

            // 举报原因列表
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: _reasons.asMap().entries.map((entry) {
                  final index = entry.key;
                  final reason = entry.value;
                  final isSelected = _selectedReason == reason['id'];
                  final isLast = index == _reasons.length - 1;

                  return Column(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            setState(() => _selectedReason = reason['id']),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                reason['icon'] as IconData,
                                color: Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  reason['title'] as String,
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (!isLast)
                        Padding(
                          padding: const EdgeInsets.only(left: 56),
                          child: Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: separatorColor,
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),

            // 补充说明
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 16, 8),
              child: Text(
                '补充说明（可选）',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TextField(
                  controller: _descController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: '请详细描述问题，帮助我们更好地处理...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: cardColor,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    counterStyle: TextStyle(color: Colors.grey.shade500),
                    counterText: '',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            // 字数统计
            Padding(
              padding: const EdgeInsets.only(right: 24, top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _descController,
                  builder: (context, value, child) {
                    return Text(
                      '${value.text.length}/500',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 提示
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '我们会对举报内容进行审核，如确认违规将采取相应措施。感谢您帮助维护社区环境。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 好友选择器底部弹窗
class _FriendSelectorSheet extends ConsumerWidget {
  final Function(String friendId, String friendName) onSelect;

  const _FriendSelectorSheet({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contacts = ref.watch(contactListProvider);
    final chatState = ref.watch(chatListProvider);

    // 合并联系人和最近私聊
    final List<_FriendItem> friends = [];
    final seenIds = <String>{};
    final seenNames = <String>{}; // 额外按名字去重

    // 先添加联系人
    for (final contact in contacts) {
      final id = contact.uuid ?? contact.id;
      final name = contact.name;
      if (!seenIds.contains(id) && !seenNames.contains(name)) {
        seenIds.add(id);
        seenNames.add(name);
        friends.add(
          _FriendItem(
            id: id,
            name: name,
            avatar: contact.avatar,
            username: contact.username,
          ),
        );
      }
    }

    // 再添加最近私聊（私聊）
    final chats = [...chatState.pinnedChats, ...chatState.regularChats];
    for (final chat in chats) {
      if (chat.type == ChatItemType.private && chat.targetUserId != null) {
        final id = chat.targetUserUuid ?? chat.targetUserId!;
        final name = chat.name;
        if (!seenIds.contains(id) && !seenNames.contains(name)) {
          seenIds.add(id);
          seenNames.add(name);
          friends.add(_FriendItem(id: id, name: name, avatar: chat.avatar));
        }
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖动条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '选择好友',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 联系人列表
          Expanded(
            child: friends.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无可发送的好友',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      return ListTile(
                        leading: AvatarWidget(
                          name: friend.name,
                          avatar: friend.avatar,
                          userId: friend.id,
                          size: 44,
                        ),
                        title: Text(
                          friend.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: friend.username != null
                            ? Text(
                                '@${friend.username}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              )
                            : null,
                        onTap: () => onSelect(friend.id, friend.name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 好友项
class _FriendItem {
  final String id;
  final String name;
  final String? avatar;
  final String? username;

  _FriendItem({
    required this.id,
    required this.name,
    this.avatar,
    this.username,
  });
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
  bool _isDragging = false;

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
            // 关闭按钮
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
        setState(() {
          _isInitialized = true;
        });
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
        onTap: () {
          setState(() => _showControls = !_showControls);
        },
        child: Stack(
          children: [
            // 视频
            Center(
              child: _isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            // 控制栏
            if (_showControls) ...[
              // 关闭按钮
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
              // 播放/暂停按钮
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
              // 底部进度条
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
