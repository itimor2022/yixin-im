// 文件用途：实现 _ProfileShareTarget 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ProfileShareTarget 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/utils/qr_payload.dart';
import '../../../core/utils/profile_share_link.dart';
import '../../../core/utils/platform_utils.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/voice_playback_audio_context.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../../shared/widgets/page_transitions.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../vip/models/vip_profile_summary.dart';
import '../../vip/widgets/vip_avatar_frame.dart';
import '../../vip/widgets/vip_badge.dart';
import '../providers/chat_provider.dart';
import '../providers/message_provider.dart';
import 'chat_detail_page.dart' show ChatType;
import 'message_search_page.dart';
import 'report_page.dart';

String _userProfileText(
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

String _userProfileServerMessage(
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

String _fallbackUserName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _userProfileText(
    context,
    zhCN: '用户',
    zhTW: '用戶',
    en: 'User',
  );
}

String _fallbackThisUserName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _userProfileText(
    context,
    zhCN: '该用户',
    zhTW: '該用戶',
    en: 'This user',
  );
}

String _fallbackGroupName(BuildContext context, [String? value]) {
  if (value != null && value.trim().isNotEmpty) {
    return value.trim();
  }
  return _userProfileText(
    context,
    zhCN: '群组',
    zhTW: '群組',
    en: 'Group',
  );
}

// 关键声明：user profile page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _ProfileShareTarget {
  final String webUrl;
  final String qrPayload;

  const _ProfileShareTarget({
    required this.webUrl,
    required this.qrPayload,
  });

  String get primaryText => webUrl.isNotEmpty ? webUrl : qrPayload;
  bool get isAvailable => primaryText.isNotEmpty;
}

String _groupMembersText(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  if (l10n.language == AppLanguage.en) {
    return count == 1 ? '1 member' : '$count members';
  }
  return '$count ${l10n.get('members_count')}';
}

String _reportReasonTitle(BuildContext context, String reasonId) {
  switch (reasonId) {
    case 'spam':
      return _userProfileText(
        context,
        zhCN: '垃圾信息',
        zhTW: '垃圾訊息',
        en: 'Spam',
      );
    case 'fake':
      return _userProfileText(
        context,
        zhCN: '虚假信息/诈骗',
        zhTW: '虛假資訊／詐騙',
        en: 'False Information / Scam',
      );
    case 'violence':
      return _userProfileText(
        context,
        zhCN: '暴力或危险内容',
        zhTW: '暴力或危險內容',
        en: 'Violence or Dangerous Content',
      );
    case 'porn':
      return _userProfileText(
        context,
        zhCN: '色情内容',
        zhTW: '色情內容',
        en: 'Sexual Content',
      );
    case 'harassment':
      return _userProfileText(
        context,
        zhCN: '骚扰或欺凌',
        zhTW: '騷擾或霸凌',
        en: 'Harassment or Bullying',
      );
    case 'copyright':
      return _userProfileText(
        context,
        zhCN: '侵犯版权',
        zhTW: '侵犯版權',
        en: 'Copyright Infringement',
      );
    case 'other':
    default:
      return _userProfileText(
        context,
        zhCN: '其他',
        zhTW: '其他',
        en: 'Other',
      );
  }
}

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
  int _commonGroupCount = 0;
  int _commonContactCount = 0;
  List<Map<String, dynamic>> _commonContacts = [];
  bool _loadingCommonInfo = true;

  // 用户详细信息
  String? _realUsername;
  String? _realNickname;
  String? _realBio;
  String? _realAvatar;
  String? _nicknameColor; // 用户背景颜色
  String? _emojiAvatar; // 表情状态
  VipProfileSummary _vip = VipProfileSummary.inactive;
  String? _userUuid; // 用户 UUID（用于官方用户检查）
  String? _contactRemark;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _loadingUserInfo = true;
  String? _realInviteCode; // 用户的个人邀请码（10 位数字，扫码场景展示）

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

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _loadCommonInfo();
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
        _emojiAvatar = data['emoji_avatar']?.toString() ?? _emojiAvatar;
        if (data.containsKey('vip')) {
          _vip = VipProfileSummary.fromJson(data['vip']);
        }
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
      debugPrint('[UserProfile] Load block status error: $e');
    } finally {
      if (mounted && _loadingBlockStatus) {
        setState(() => _loadingBlockStatus = false);
      }
    }
  }

  /// 切换屏蔽/取消屏蔽
  Future<void> _toggleBlock(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    if (_isBlocked) {
      // 取消屏蔽
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            _translate(
              context,
              'unblock_title',
              _userProfileText(
                context,
                zhCN: '取消屏蔽',
                zhTW: '取消封鎖',
                en: 'Unblock',
              ),
            ),
          ),
          content: Text(
            _translate(
              context,
              'unblock_confirm',
              _userProfileText(
                context,
                zhCN: '确定要取消对 "{name}" 的屏蔽吗？',
                zhTW: '確定要取消對「{name}」的封鎖嗎？',
                en: 'Unblock "{name}"?',
              ),
              {
                'name':
                    _fallbackThisUserName(context, _realNickname ?? widget.name)
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                _translate(
                  context,
                  'unblock_title',
                  _userProfileText(
                    context,
                    zhCN: '取消屏蔽',
                    zhTW: '取消封鎖',
                    en: 'Unblock',
                  ),
                ),
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
          ).showSnackBar(
            SnackBar(
              content: Text(
                _translate(
                  context,
                  'unblock_success',
                  _userProfileText(
                    context,
                    zhCN: '已取消屏蔽',
                    zhTW: '已取消封鎖',
                    en: 'Unblocked',
                  ),
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _userProfileServerMessage(
                  response.message,
                  zhCN: '操作失败，请重试',
                  zhTW: '操作失敗，請重試',
                  en: 'Operation failed. Please try again.',
                ),
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _translate(
                context,
                'unblock_failed',
                _userProfileText(
                  context,
                  zhCN: '操作失败，请重试',
                  zhTW: '操作失敗，請稍後重試',
                  en: 'Operation failed, please try again',
                ),
              ),
            ),
          ),
        );
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
          _emojiAvatar = response.data['emoji_avatar'];
          _vip = response.data.containsKey('vip')
              ? VipProfileSummary.fromJson(response.data['vip'])
              : matchedContact?.vip ?? _vip;
          _userUuid = response.data['id']?.toString();
          _contactRemark = inferredRemark;
          _isOnline = response.data['status'] == 1;
          _realInviteCode =
              response.data['invite_code']?.toString().trim();
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

  Future<void> _loadCommonInfo() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/user/${widget.userId}/common-info');
      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        final contactsData = response.data['common_contacts'];
        setState(() {
          _commonGroupCount = int.tryParse(
                response.data['common_group_count']?.toString() ?? '',
              ) ??
              0;
          _commonContactCount = int.tryParse(
                response.data['common_contact_count']?.toString() ?? '',
              ) ??
              0;
          _commonContacts = contactsData is List
              ? List<Map<String, dynamic>>.from(contactsData)
              : [];
          _loadingCommonInfo = false;
        });
      } else {
        setState(() => _loadingCommonInfo = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCommonInfo = false);
    }
  }

  bool get _isCurrentUser {
    final currentUser = ref.read(authServiceProvider).user;
    return currentUser?.uuid == widget.userId;
  }

  /// 显示名称（优先 nickname）
  String get _displayName {
    if (_isContact &&
        _contactRemark != null &&
        _contactRemark!.trim().isNotEmpty) {
      return _contactRemark!.trim();
    }
    if (_realNickname != null && _realNickname!.isNotEmpty) {
      return _realNickname!;
    }
    return _fallbackUserName(context, widget.name);
  }

  bool get _hasRemark =>
      _isContact && _contactRemark?.trim().isNotEmpty == true;

  String _remarkTagsValue(BuildContext context) {
    if (!_isContact) {
      return _userProfileText(
        context,
        zhCN: '非联系人',
        zhTW: '非聯絡人',
        en: 'Not a contact',
      );
    }
    final remark = _contactRemark?.trim();
    if (remark != null && remark.isNotEmpty) return remark;
    return _userProfileText(
      context,
      zhCN: '未设置',
      zhTW: '未設定',
      en: 'Not set',
    );
  }

  String _translate(
    BuildContext context,
    String key,
    String fallback, [
    Map<String, String> variables = const {},
  ]) {
    var text = AppLocalizations.of(context).get(key);
    if (text == key) {
      text = fallback;
    }
    for (final entry in variables.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  /// 在线状态文本
  String _onlineStatusText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEnglish = l10n.language == AppLanguage.en;
    if (_loadingUserInfo) return l10n.loading;
    if (_isOnline) return l10n.online;
    if (_lastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(_lastSeen!);
      if (diff.inMinutes < 1) {
        return isEnglish
            ? '${l10n.justNow} ${l10n.online}'
            : '${l10n.justNow}${l10n.online}';
      }
      if (diff.inMinutes < 60) {
        return isEnglish
            ? '${diff.inMinutes} ${l10n.minutesAgo} ${l10n.online}'
            : '${diff.inMinutes}${l10n.minutesAgo}${l10n.online}';
      }
      if (diff.inHours < 24) {
        return isEnglish
            ? '${diff.inHours} ${l10n.hoursAgo} ${l10n.online}'
            : '${diff.inHours}${l10n.hoursAgo}${l10n.online}';
      }
      if (diff.inDays < 7) {
        return isEnglish
            ? '${diff.inDays} ${l10n.daysAgo} ${l10n.online}'
            : '${diff.inDays}${l10n.daysAgo}${l10n.online}';
      }
      return l10n.longTimeAgo;
    }
    return l10n.offline;
  }

  DateTime? _recentInteractionTime(ChatListState chatState) {
    final chatId = _privateChatId ?? widget.chatId;
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
    for (final chat in allChats) {
      if (chat.type != ChatItemType.private) continue;
      final matchesChatId =
          chatId != null && chatId.isNotEmpty && chat.id == chatId;
      final matchesUser = chat.targetUserId == widget.userId ||
          chat.targetUserUuid == widget.userId ||
          chat.targetUserId == _userUuid ||
          chat.targetUserUuid == _userUuid;
      if (matchesChatId || matchesUser) {
        return chat.lastMessageTime;
      }
    }
    return null;
  }

  String _recentInteractionText(BuildContext context, DateTime? time) {
    if (time == null) {
      return _userProfileText(
        context,
        zhCN: '暂无互动',
        zhTW: '暫無互動',
        en: 'No activity',
      );
    }
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) {
      return _userProfileText(
        context,
        zhCN: '今天 ${DateFormat('HH:mm').format(local)}',
        zhTW: '今天 ${DateFormat('HH:mm').format(local)}',
        en: 'Today ${DateFormat('HH:mm').format(local)}',
      );
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return _userProfileText(
        context,
        zhCN: '昨天 ${DateFormat('HH:mm').format(local)}',
        zhTW: '昨天 ${DateFormat('HH:mm').format(local)}',
        en: 'Yesterday ${DateFormat('HH:mm').format(local)}',
      );
    }
    return DateFormat('yyyy/MM/dd').format(local);
  }

  int get _sharedMediaTotal {
    final counts = _mediaCounts;
    if (counts == null) return 0;
    return counts.media + counts.file + counts.link + counts.voice;
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
    if (_vip.visible) {
      if (_vip.level >= 2) {
        return const [
          Color(0xFF18130C),
          Color(0xFF5B4521),
          Color(0xFFD2B06A),
        ];
      }
      return const [
        Color(0xFFDDE7F2),
        Color(0xFFA9BCD2),
        Color(0xFF7F9BB9),
      ];
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
    final bgColor = AppColors.backgroundFor(context);
    final cardColor = AppColors.cardFor(context);
    final separatorColor = AppColors.dividerFor(context);
    // 监听联系人列表变化
    ref.listen(contactListProvider, (_, contacts) {
      ContactItem? matchedContact;
      for (final contact in contacts) {
        if (contact.id == widget.userId || contact.uuid == widget.userId) {
          matchedContact = contact;
          break;
        }
      }
      if (matchedContact == null) {
        if (_isContact || _contactRemark != null) {
          setState(() {
            _isContact = false;
            _contactRemark = null;
          });
        }
        return;
      }

      final nextName = matchedContact.name;
      final nextAvatar = matchedContact.avatar;
      final nextNicknameColor = matchedContact.nicknameColor;
      final nextEmojiAvatar = matchedContact.emojiAvatar;
      final nextVip = matchedContact.vip;
      final nextRemark = matchedContact.remark;
      final nextNickname =
          nextRemark?.trim().isNotEmpty == true ? _realNickname : nextName;

      if (_isContact &&
          _realNickname == nextNickname &&
          _realAvatar == nextAvatar &&
          _nicknameColor == nextNicknameColor &&
          _emojiAvatar == nextEmojiAvatar &&
          _vip == nextVip &&
          _contactRemark == nextRemark) {
        return;
      }

      setState(() {
        _isContact = true;
        _realNickname = nextNickname;
        _realAvatar = nextAvatar;
        _nicknameColor = nextNicknameColor;
        _emojiAvatar = nextEmojiAvatar;
        _vip = nextVip;
        _contactRemark = nextRemark;
      });
    });

    final profileBgGradient = _getUserBackgroundGradient();
    final vipLevel = _vip.visible ? _vip.level : 0;
    final isVip = vipLevel > 0;
    final isSvip = vipLevel >= 2;
    const headerForeground = Colors.white;
    final headerMutedForeground = Colors.white.withOpacity(0.78);
    final patternOpacity = isSvip ? 0.09 : (isVip ? 0.10 : 0.12);
    final mediaQuery = MediaQuery.of(context);
    final viewportWidth = mediaQuery.size.width;
    final viewportHeight = mediaQuery.size.height;
    final isNarrowScreen = viewportWidth < 360;
    final isShortScreen = viewportHeight < 700;
    final isCompactHeader = isNarrowScreen || isShortScreen;
    final isWideProfile =
        widget.isDesktopPanel || PlatformUtils.useDesktopLayout(context);
    final fixedHeaderContentHeight = isCompactHeader
        ? 300.0
        : isWideProfile
            ? 304.0
            : 312.0;
    final headerBodyHeight = fixedHeaderContentHeight - kToolbarHeight;
    final avatarSize = isCompactHeader ? 76.0 : (isWideProfile ? 80.0 : 84.0);
    final actionButtonSize = isCompactHeader ? 44.0 : 48.0;
    final headerTopGap = isCompactHeader ? 8.0 : 10.0;
    final headerNameGap = isCompactHeader ? 7.0 : 9.0;
    final headerBottomGap = isCompactHeader ? 8.0 : 10.0;
    final headerNameFontSize = isNarrowScreen ? 20.0 : 22.0;
    final profileHeaderHeight =
        mediaQuery.padding.top + fixedHeaderContentHeight;

    Widget content = Scaffold(
      backgroundColor: bgColor, // 页面背景
      body: Stack(
        children: [
          // 顶部背景（渐变+SVG图案，覆盖到四个按钮以下）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: profileHeaderHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: profileBgGradient,
                    ),
                  ),
                ),
                Opacity(
                  opacity: patternOpacity,
                  child: SvgPicture.asset(
                    'assets/images/backgrounds/bg5.svg',
                    fit: BoxFit.cover,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.54, 1],
                      colors: [
                        Color(0x52000000),
                        Color(0x24000000),
                        Color(0x70000000),
                      ],
                    ),
                  ),
                ),
              ],
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
                systemOverlayStyle: AppSystemUiStyles.onDarkBackground,
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: headerForeground,
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
                      child: Text(
                        AppLocalizations.of(context).edit,
                        style: TextStyle(
                          color: headerForeground,
                          fontSize: 17,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.more_horiz, color: headerForeground),
                      onPressed: () => _showMoreOptions(context),
                    ),
                ],
              ),

              // 头像、名字、在线状态和操作按钮（透明背景，由底层提供图案）
              SliverToBoxAdapter(
                child: SizedBox(
                  height: headerBodyHeight,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Column(
                      children: [
                        SizedBox(height: headerTopGap),
                        // 头像
                        GestureDetector(
                          onTap: () => _showAvatarFullScreen(context),
                          child: VipAvatarFrame(
                            level: vipLevel,
                            size: avatarSize,
                            isCircle: true,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(
                                    isVip ? 0.96 : 1,
                                  ),
                                  width: isVip ? 2 : 4,
                                ),
                              ),
                              child: Hero(
                                tag: 'avatar_${widget.userId}',
                                child: AvatarWidget(
                                  name: _displayName,
                                  avatar: _realAvatar ?? widget.avatar,
                                  userId: widget.userId,
                                  size: avatarSize,
                                  isCircle: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: headerNameGap),
                        // 第一行只展示昵称和官方认证；会员与状态放到第二行。
                        Consumer(
                          builder: (context, ref, _) {
                            final officialUsersAsync = ref.watch(
                              officialUsersProvider,
                            );
                            final officialUsers =
                                officialUsersAsync.valueOrNull ?? {};
                            final userUuidToCheck = _userUuid ?? widget.userId;
                            final isOfficial = officialUsers.contains(
                              userUuidToCheck,
                            );
                            final hasVip = _vip.visible;
                            final hasEmoji = _emojiAvatar != null &&
                                _emojiAvatar!.isNotEmpty;

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: ColoredNameWidget(
                                          name: _displayName,
                                          nicknameColor: null,
                                          fontSize: headerNameFontSize,
                                          fontWeight: FontWeight.w700,
                                          defaultColor: headerForeground,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isOfficial) ...[
                                        const SizedBox(width: 6),
                                        const OfficialBadge(size: 20),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (hasVip)
                                        VipBadge(
                                          level: _vip.level,
                                          text: _vip.badge,
                                          iconUrl: _vip.badgeIcon,
                                          height: 18,
                                          compact: true,
                                        ),
                                      if (hasVip && hasEmoji)
                                        const SizedBox(width: 6),
                                      if (hasEmoji)
                                        EmojiStatusWidget(
                                          emoji: _emojiAvatar!,
                                          size: 18,
                                        ),
                                      if (hasVip || hasEmoji)
                                        const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _onlineStatusText(context),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.15,
                                            color: _isOnline
                                                ? headerForeground
                                                : headerMutedForeground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // 邀请码：扫码场景核心入口，访客复制后可去注册页填写
                                  _buildHeaderInviteCode(
                                    context,
                                    headerForeground,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        // 操作按钮（不显示给自己）
                        if (!_isCurrentUser)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              isNarrowScreen ? 8 : 12,
                              0,
                              isNarrowScreen ? 8 : 12,
                              headerBottomGap,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _TGActionButton(
                                    icon: Icons.chat_bubble_outline,
                                    label: l10n.get('message') ??
                                        _userProfileText(
                                          context,
                                          zhCN: '消息',
                                          zhTW: '訊息',
                                          en: 'Message',
                                        ),
                                    onTap: () => _startChat(context),
                                    isLoading: _isLoading,
                                    lightStyle: true,
                                    foregroundColor: headerForeground,
                                    buttonSize: actionButtonSize,
                                  ),
                                ),
                                Expanded(
                                  child: _TGActionButton(
                                    icon: Icons.call_outlined,
                                    label: l10n.get('call') ??
                                        _userProfileText(
                                          context,
                                          zhCN: '通话',
                                          zhTW: '通話',
                                          en: 'Call',
                                        ),
                                    onTap: () =>
                                        _startCall(context, CallType.voice),
                                    lightStyle: true,
                                    foregroundColor: headerForeground,
                                    buttonSize: actionButtonSize,
                                  ),
                                ),
                                Expanded(
                                  child: _TGActionButton(
                                    icon: Icons.videocam_outlined,
                                    label: l10n.get('video') ??
                                        _userProfileText(
                                          context,
                                          zhCN: '视频',
                                          zhTW: '影片',
                                          en: 'Video',
                                        ),
                                    onTap: () =>
                                        _startCall(context, CallType.video),
                                    lightStyle: true,
                                    foregroundColor: headerForeground,
                                    buttonSize: actionButtonSize,
                                  ),
                                ),
                                Expanded(
                                  child: _TGActionButton(
                                    icon: Icons.search_rounded,
                                    label: l10n.get('search') ??
                                        _userProfileText(
                                          context,
                                          zhCN: '搜索',
                                          zhTW: '搜尋',
                                          en: 'Search',
                                        ),
                                    onTap: () => _searchMessages(context),
                                    lightStyle: true,
                                    foregroundColor: headerForeground,
                                    buttonSize: actionButtonSize,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_isCurrentUser) SizedBox(height: headerBottomGap),
                      ],
                    ),
                  ),
                ),
              ),

              // 间距
              SliverToBoxAdapter(child: SizedBox(height: 16)),

              // 资料信息
              SliverToBoxAdapter(
                child: _ProfileDetailsCard(
                  cardColor: cardColor,
                  isDark: isDark,
                  bioLabel: l10n.bio,
                  bio: (_realBio != null && _realBio!.isNotEmpty)
                      ? _realBio!
                      : (l10n.get('no_bio') ??
                          _userProfileText(
                            context,
                            zhCN: '这个人很懒，什么都没留下',
                            zhTW: '這個人很懶，什麼都沒留下',
                            en: 'No bio yet',
                          )),
                  usernameLabel: l10n.username,
                  username: _realUsername?.trim(),
                  onUsernameTap: (_realUsername?.trim().isNotEmpty == true)
                      ? () => _copyToClipboard('@${_realUsername!.trim()}')
                      : null,
                  onQrTap: () => _showProfileQrCard(context),
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
                      title: l10n.get('photos_and_videos') ??
                          _userProfileText(
                            context,
                            zhCN: '照片和视频',
                            zhTW: '照片和影片',
                            en: 'Photos & Videos',
                          ),
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.media ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('photos_and_videos') ??
                            _userProfileText(
                              context,
                              zhCN: '照片和视频',
                              zhTW: '照片和影片',
                              en: 'Photos & Videos',
                            ),
                        'media',
                      ),
                    ),
                    _TGCell(
                      icon: Icons.link,
                      iconColor: AppColors.primaryFor(context),
                      title: l10n.get('shared_links') ??
                          _userProfileText(
                            context,
                            zhCN: '共享链接',
                            zhTW: '共享連結',
                            en: 'Shared Links',
                          ),
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.link ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('shared_links') ??
                            _userProfileText(
                              context,
                              zhCN: '共享链接',
                              zhTW: '共享連結',
                              en: 'Shared Links',
                            ),
                        'link',
                      ),
                    ),
                    _TGCell(
                      icon: Icons.insert_drive_file_outlined,
                      iconColor: AppColors.primaryFor(context),
                      title: l10n.get('files') ??
                          _userProfileText(
                            context,
                            zhCN: '文件',
                            zhTW: '檔案',
                            en: 'Files',
                          ),
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.file ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('files') ??
                            _userProfileText(
                              context,
                              zhCN: '文件',
                              zhTW: '檔案',
                              en: 'Files',
                            ),
                        'file',
                      ),
                    ),
                    _TGCell(
                      icon: Icons.mic_outlined,
                      iconColor: AppColors.primaryFor(context),
                      title: l10n.get('voice_messages') ??
                          _userProfileText(
                            context,
                            zhCN: '语音消息',
                            zhTW: '語音訊息',
                            en: 'Voice Messages',
                          ),
                      trailing: _buildCountTrailing(
                        '${_mediaCounts?.voice ?? 0}',
                      ),
                      onTap: () => _showMediaList(
                        context,
                        l10n.get('voice_messages') ??
                            _userProfileText(
                              context,
                              zhCN: '语音消息',
                              zhTW: '語音訊息',
                              en: 'Voice Messages',
                            ),
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
                      title: l10n.get('common_groups') ??
                          _userProfileText(
                            context,
                            zhCN: '共同群组',
                            zhTW: '共同群組',
                            en: 'Groups in Common',
                          ),
                      titlePrefix:
                          '${_commonGroups.length} ${l10n.get('count_suffix') ?? _userProfileText(context, zhCN: '个', zhTW: '個', en: '')}',
                      trailing: _buildArrowTrailing(),
                      onTap: () => _showCommonGroups(context),
                    ),
                  ],
                ),
              ),

              // 隐私操作（不显示给自己）
              if (!_isCurrentUser) ...[
                SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverToBoxAdapter(
                  child: _TGSection(
                    cardColor: cardColor,
                    separatorColor: separatorColor,
                    children: [
                      _TGCell(
                        icon: _isMuted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_outlined,
                        iconColor: AppColors.primaryFor(context),
                        title: _userProfileText(
                          context,
                          zhCN: '消息免打扰',
                          zhTW: '訊息免打擾',
                          en: 'Mute Notifications',
                        ),
                        trailing: Switch.adaptive(
                          value: _isMuted,
                          activeColor: AppColors.primaryFor(context),
                          onChanged: (_) => _toggleMute(),
                        ),
                        onTap: () => _toggleMute(),
                      ),
                      _TGCell(
                        icon: Icons.delete_sweep_outlined,
                        iconColor: Colors.orange,
                        title: _translate(
                          context,
                          'clear_chat_history',
                          _userProfileText(
                            context,
                            zhCN: '清空聊天记录',
                            zhTW: '清空聊天記錄',
                            en: 'Clear Chat History',
                          ),
                        ),
                        titleColor: Colors.orange,
                        trailing: _buildArrowTrailing(),
                        onTap: () => _showClearChatDialog(context),
                      ),
                      _TGCell(
                        icon: _isBlocked
                            ? Icons.lock_open_outlined
                            : Icons.block_outlined,
                        iconColor: _isBlocked ? Colors.orange : Colors.red,
                        title: _isBlocked
                            ? (l10n.get('unblock_user') ??
                                _userProfileText(
                                  context,
                                  zhCN: '取消屏蔽',
                                  zhTW: '取消封鎖',
                                  en: 'Unblock User',
                                ))
                            : (l10n.get('block_user') ??
                                _userProfileText(
                                  context,
                                  zhCN: '屏蔽用户',
                                  zhTW: '封鎖用戶',
                                  en: 'Block User',
                                )),
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
                        icon: Icons.report_gmailerrorred_outlined,
                        iconColor: Colors.red,
                        title: l10n.get('report') ??
                            _userProfileText(
                              context,
                              zhCN: '举报',
                              zhTW: '檢舉',
                              en: 'Report',
                            ),
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

  Widget _buildArrowTrailing() {
    return Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22);
  }

  void _showFeatureNotAvailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _userProfileText(
            context,
            zhCN: '$feature 功能暂未开放',
            zhTW: '$feature 功能暫未開放',
            en: '$feature is not available yet',
          ),
        ),
      ),
    );
  }

  void _showContactRequiredForRemark(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _userProfileText(
            context,
            zhCN: '添加为联系人后可设置备注和标签',
            zhTW: '加入聯絡人後可設定備註和標籤',
            en: 'Add as a contact to set remarks and tags',
          ),
        ),
      ),
    );
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
                targetUserName: _fallbackUserName(context, widget.name),
                avatar: widget.avatar,
              );
      if (chat != null && mounted) {
        // 桌面端：选中聊天并关闭资料面板
        if (widget.isDesktopPanel || PlatformUtils.useDesktopLayout(context)) {
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: _fallbackUserName(context, widget.name),
            avatar: widget.avatar,
            chatType: ChatType.private,
          );
          ref.read(desktopProfileProvider.notifier).state =
              DesktopProfileInfo.none;
        } else {
          context.push(
            '/chat/${chat.id}?name=${Uri.encodeComponent(_fallbackUserName(context, widget.name))}&type=private',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 直接发起通话（无需先跳转聊天页）
  void _startCall(BuildContext context, CallType callType) async {
    if (_isBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '已屏蔽该用户，无法发起通话',
                zhTW: '已封鎖該用戶，無法發起通話',
                en: 'This user is blocked and cannot be called',
              ),
            ),
          ),
        );
      }
      return;
    }
    setState(() => _isLoading = true);

    try {
      final callService = ref.read(callServiceProvider.notifier);

      // 直接发起通话
      final success = await callService.startCall(
        targetUserId: widget.userId,
        targetName: _fallbackUserName(context, widget.name),
        targetAvatar: widget.avatar,
        type: callType,
      );

      if (success && mounted) {
        // 导航到通话页面
        context.push('/call');
      } else if (mounted) {
        // 显示错误信息
        final failedState = ref.read(callServiceProvider);
        if (failedState.permissionIssue != null) {
          final issue = failedState.permissionIssue!;
          final canUseVoice = callType == CallType.video &&
              callPermissionSupportsVoiceFallback(issue);
          final action = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                _userProfileText(
                  context,
                  zhCN: '通话权限未开启',
                  zhTW: '通話權限未開啟',
                  en: 'Call permission required',
                ),
              ),
              content: Text(failedState.errorMessage ?? ''),
              actions: [
                if (canUseVoice)
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop('voice'),
                    child: Text(
                      _userProfileText(
                        context,
                        zhCN: '改用语音',
                        zhTW: '改用語音',
                        en: 'Use voice',
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop('settings'),
                  child: Text(
                    _userProfileText(
                      context,
                      zhCN: '前往设置',
                      zhTW: '前往設定',
                      en: 'Open settings',
                    ),
                  ),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (action == 'voice') {
            _startCall(context, CallType.voice);
          } else if (action == 'settings') {
            await callService.openCallPermissionSettings();
          }
          return;
        }
        final errorMsg = failedState.errorMessage;
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
                targetUserName: _fallbackUserName(context, widget.name),
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
            content: Text(
              newMuteState
                  ? (AppLocalizations.of(context).get('muted') ??
                      _userProfileText(
                        context,
                        zhCN: '已静音',
                        zhTW: '已靜音',
                        en: 'Muted',
                      ))
                  : _userProfileText(
                      context,
                      zhCN: '已取消静音',
                      zhTW: '已取消靜音',
                      en: 'Unmuted',
                    ),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (mounted) {
        final localizedError = _userProfileServerMessage(
          response.message,
          zhCN: '设置失败',
          zhTW: '設定失敗',
          en: 'Update failed',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '设置失败: $localizedError',
                zhTW: '設定失敗：$localizedError',
                en: 'Failed to update: $localizedError',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: 'Operation failed',
              ),
            ),
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).get('copied')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        actions: [
          // 添加/移除联系人
          _TGActionSheetItem(
            title: _isContact
                ? _translate(
                    context,
                    'remove_contact_title',
                    _userProfileText(
                      context,
                      zhCN: '从联系人中移除',
                      zhTW: '從聯絡人中移除',
                      en: 'Remove from Contacts',
                    ),
                  )
                : _translate(
                    context,
                    'add_contact',
                    _userProfileText(
                      context,
                      zhCN: '添加到联系人',
                      zhTW: '加入聯絡人',
                      en: 'Add to Contacts',
                    ),
                  ),
            isDestructive: _isContact,
            onTap: () {
              Navigator.pop(context);
              _toggleContact();
            },
          ),
          if (_isContact)
            _TGActionSheetItem(
              title: _userProfileText(
                context,
                zhCN: '编辑联系人信息',
                zhTW: '編輯聯絡人資訊',
                en: 'Edit Contact Info',
              ),
              onTap: () {
                Navigator.pop(context);
                _openEditContactInfoPage();
              },
            ),
          _TGActionSheetItem(
            title: _translate(
              context,
              'share_contact',
              _userProfileText(
                context,
                zhCN: '分享联系人',
                zhTW: '分享聯絡人',
                en: 'Share Contact',
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              // The action-sheet context is disposed as soon as this route is
              // closed. Open the next sheet from this page's live context.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _shareContact();
              });
            },
          ),
          _TGActionSheetItem(
            title: _translate(
              context,
              'search_messages',
              _userProfileText(
                context,
                zhCN: '搜索消息',
                zhTW: '搜尋訊息',
                en: 'Search Messages',
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              _searchMessages(context);
            },
          ),
        ],
        cancelText: l10n.cancel,
      ),
    );
  }

  Future<void> _openEditContactInfoPage() async {
    if (!_isContact) {
      _showContactRequiredForRemark(context);
      return;
    }

    final nickname = _realNickname?.trim().isNotEmpty == true
        ? _realNickname!.trim()
        : _fallbackUserName(context, widget.name);
    final result = await Navigator.of(context).push<_EditContactInfoResult>(
      MaterialPageRoute(
        builder: (_) => _EditContactInfoPage(
          displayName: nickname,
          username: _realUsername,
          userId: _userUuid ?? widget.userId,
          initialRemark: _contactRemark?.trim() ?? '',
        ),
      ),
    );
    if (result == null || !mounted) return;

    await _applyEditedContactRemark(_userUuid ?? widget.userId, result.remark);
  }

  Future<void> _applyEditedContactRemark(
    String userUuid,
    String remark,
  ) async {
    final nextRemark = remark.trim();
    if ((_contactRemark?.trim() ?? '') == nextRemark) return;

    final success = await ref
        .read(contactListProvider.notifier)
        .updateRemark(userUuid, nextRemark);
    if (!mounted) return;
    if (success) {
      setState(() => _contactRemark = nextRemark);
      final fallbackName = _realNickname?.trim().isNotEmpty == true
          ? _realNickname!.trim()
          : (widget.name?.trim().isNotEmpty == true
              ? widget.name!.trim()
              : _fallbackUserName(context));
      final nextDisplayName = nextRemark.isNotEmpty ? nextRemark : fallbackName;
      ref.read(chatListProvider.notifier).updatePrivateChatDisplayName(
            userId: userUuid,
            name: nextDisplayName,
          );
      ref.read(chatListProvider.notifier).silentRefresh(bypassDebounce: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'remark_saved',
              _userProfileText(
                context,
                zhCN: '备注已保存',
                zhTW: '備註已儲存',
                en: 'Remark saved',
              ),
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'remark_save_failed',
              _userProfileText(
                context,
                zhCN: '备注保存失败，请重试',
                zhTW: '備註儲存失敗，請稍後重試',
                en: 'Failed to save remark, please try again',
              ),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _toggleContact() async {
    final l10n = AppLocalizations.of(context);
    // 使用UUID进行API调用，优先使用 _userUuid
    final userUuid = _userUuid ?? widget.userId;

    if (_isContact) {
      // 移除联系人 - 显示确认对话框
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _translate(
              context,
              'remove_contact_title',
              _userProfileText(
                context,
                zhCN: '从联系人中移除',
                zhTW: '從聯絡人中移除',
                en: 'Remove from Contacts',
              ),
            ),
          ),
          content: Text(
            _translate(
              context,
              'remove_contact_confirm',
              _userProfileText(
                context,
                zhCN: '确定要将 {name} 从联系人中移除吗？',
                zhTW: '確定要將 {name} 從聯絡人中移除嗎？',
                en: 'Remove {name} from your contacts?',
              ),
              {'name': _displayName},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(
                _userProfileText(
                  context,
                  zhCN: '移除',
                  zhTW: '移除',
                  en: 'Remove',
                ),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final success =
          await ref.read(contactListProvider.notifier).removeContact(userUuid);
      if (success && mounted) {
        setState(() {
          _isContact = false;
          _contactRemark = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _translate(
                context,
                'remove_contact_success',
                _userProfileText(
                  context,
                  zhCN: '已将 {name} 从联系人中移除',
                  zhTW: '已將 {name} 從聯絡人中移除',
                  en: 'Removed {name} from contacts',
                ),
                {'name': _displayName},
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _translate(
                context,
                'remove_contact_failed',
                _userProfileText(
                  context,
                  zhCN: '移除失败，请重试',
                  zhTW: '移除失敗，請稍後重試',
                  en: 'Remove failed, please try again',
                ),
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    } else {
      final friendAddMode =
          ref.read(systemSettingsProvider).valueOrNull?.friendAddMode ??
              FriendAddMode.approval;
      if (friendAddMode == FriendAddMode.disabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '管理员已关闭添加好友功能',
                zhTW: '管理員已關閉新增好友功能',
                en: 'Adding friends has been disabled by the administrator.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (friendAddMode == FriendAddMode.direct) {
        final success =
            await ref.read(contactListProvider.notifier).addContact(userUuid);
        if (!mounted) return;
        if (success) {
          setState(() {
            _isContact = true;
            _contactRemark = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? _userProfileText(
                      context,
                      zhCN: '已添加为好友',
                      zhTW: '已新增為好友',
                      en: 'Friend added',
                    )
                  : _userProfileText(
                      context,
                      zhCN: '添加失败，请重试',
                      zhTW: '新增失敗，請重試',
                      en: 'Failed to add friend. Please try again.',
                    ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: success ? null : AppColors.error,
          ),
        );
        return;
      }

      final controller = TextEditingController(
        text: _userProfileText(
          context,
          zhCN: '你好，我想添加你为好友',
          zhTW: '你好，我想加你為好友',
          en: 'Hi, I would like to add you as a friend.',
        ),
      );
      final verification = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            _userProfileText(
              context,
              zhCN: '发送好友申请',
              zhTW: '傳送好友申請',
              en: 'Send Friend Request',
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 200,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _userProfileText(
                context,
                zhCN: '验证消息',
                zhTW: '驗證訊息',
                en: 'Verification message',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: Text(
                _userProfileText(
                  context,
                  zhCN: '发送',
                  zhTW: '傳送',
                  en: 'Send',
                ),
              ),
            ),
          ],
        ),
      );
      controller.dispose();
      if (verification == null || !mounted) return;

      final result = await ref
          .read(contactListProvider.notifier)
          .sendFriendRequest(userUuid, message: verification);
      if (result != null && mounted) {
        final accepted =
            result.autoAccepted || result.request.status == 'accepted';
        if (accepted) {
          setState(() {
            _isContact = true;
            _contactRemark = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted
                  ? _userProfileText(
                      context,
                      zhCN: '双方已互相申请，已成为好友',
                      zhTW: '雙方已互相申請，已成為好友',
                      en: 'You both sent requests and are now contacts.',
                    )
                  : result.created
                      ? _userProfileText(
                          context,
                          zhCN: '好友申请已发送',
                          zhTW: '好友申請已傳送',
                          en: 'Friend request sent',
                        )
                      : _userProfileText(
                          context,
                          zhCN: '好友申请正在等待对方处理',
                          zhTW: '好友申請正在等待對方處理',
                          en: 'The friend request is already pending.',
                        ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '好友申请发送失败，请重试',
                zhTW: '好友申請傳送失敗，請重試',
                en: 'Failed to send friend request. Please try again.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _shareContact() {
    final pageContext = context;
    final l10n = AppLocalizations.of(pageContext);
    final username = _realUsername ?? '';
    final isDark = Theme.of(pageContext).brightness == Brightness.dark;
    final cardColor = AppColors.cardFor(pageContext);

    showModalBottomSheet(
      context: pageContext,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      _userProfileText(
                        sheetContext,
                        zhCN: '个人名片',
                        zhTW: '個人名片',
                        en: 'Profile Card',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondaryFor(sheetContext),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ProfileSharePreview(
                      name: _displayName,
                      username: username,
                      avatar: _realAvatar ?? widget.avatar,
                      userId: widget.userId,
                      nicknameColor: _nicknameColor,
                      bio: _realBio,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.82,
                      children: [
                        _ProfileShareAction(
                          icon: Icons.ios_share_rounded,
                          label: _userProfileText(
                            sheetContext,
                            zhCN: '分享名片',
                            zhTW: '分享名片',
                            en: 'Share',
                          ),
                          color: AppColors.primaryFor(context),
                          isDark: isDark,
                          onTap: () async {
                            // Invoke the platform share while this click still
                            // owns browser user activation, then close the sheet.
                            await _shareProfileCard(pageContext);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                        ),
                        _ProfileShareAction(
                          icon: Icons.qr_code_2_rounded,
                          label: _userProfileText(
                            sheetContext,
                            zhCN: '二维码名片',
                            zhTW: 'QR 名片',
                            en: 'QR Card',
                          ),
                          color: Colors.teal,
                          isDark: isDark,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _showProfileQrCard(pageContext);
                            });
                          },
                        ),
                        _ProfileShareAction(
                          icon: Icons.link_rounded,
                          label: _userProfileText(
                            sheetContext,
                            zhCN: '复制链接',
                            zhTW: '複製連結',
                            en: 'Copy Link',
                          ),
                          color: AppColors.primaryLight,
                          isDark: isDark,
                          onTap: () async {
                            // Clipboard writes on web must happen directly in
                            // the click callback, before user activation expires.
                            await _copyAccountLink(pageContext);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                        ),
                        _ProfileShareAction(
                          icon: Icons.send_rounded,
                          label: _userProfileText(
                            sheetContext,
                            zhCN: '发送给好友',
                            zhTW: '傳送好友',
                            en: 'Send',
                          ),
                          color: Colors.green,
                          isDark: isDark,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _sendContactCard(pageContext);
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(sheetContext),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    l10n.cancel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryFor(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _profileCardText(_ProfileShareTarget target) {
    final username = _realUsername ?? '';
    final lines = <String>[
      _userProfileText(
        context,
        zhCN: '这是 $_displayName 的个人名片',
        zhTW: '這是 $_displayName 的個人名片',
        en: 'Profile card for $_displayName',
      ),
      if (username.isNotEmpty) '@$username',
      if ((_realBio ?? '').trim().isNotEmpty) _realBio!.trim(),
      if (target.webUrl.isNotEmpty) target.webUrl,
      if (target.webUrl.isEmpty && target.qrPayload.isNotEmpty)
        target.qrPayload,
    ];
    return lines.join('\n');
  }

  _ProfileShareTarget _buildProfileShareTarget() {
    final userUuid = _userUuid ?? widget.userId;
    final qrPayload = buildUserQrPayload(userUuid);
    // Do not wait for network settings here. Web clipboard/share APIs require
    // an immediate user gesture; the app deep-link is a safe local fallback.
    final settings = ref.read(systemSettingsProvider).valueOrNull;

    const compiledPublicH5Url = String.fromEnvironment(
      'GENERIC_IM_PUBLIC_H5_URL',
    );
    final webUrl = buildUserProfileShareUrl(
      userId: userUuid,
      name: _displayName,
      avatar: _realAvatar ?? widget.avatar,
      configuredBaseUrl: settings?.registerBaseUrl ?? '',
      compiledPublicH5Url: compiledPublicH5Url,
      currentWebUri: kIsWeb ? Uri.base : null,
    );
    return _ProfileShareTarget(webUrl: webUrl, qrPayload: qrPayload);
  }

  Future<void> _shareProfileCard(BuildContext context) async {
    try {
      final target = _buildProfileShareTarget();
      if (!mounted) return;
      if (!target.isAvailable) {
        _showShareUnavailable(context);
        return;
      }
      final renderBox = context.findRenderObject();
      final shareOrigin = renderBox is RenderBox && renderBox.hasSize
          ? renderBox.localToGlobal(Offset.zero) & renderBox.size
          : null;
      await Share.share(
        _profileCardText(target),
        subject: _userProfileText(
          context,
          zhCN: '分享名片',
          zhTW: '分享名片',
          en: 'Share Profile Card',
        ),
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      if (mounted) {
        _showShareUnavailable(context);
      }
    }
  }

  Future<void> _copyAccountLink(BuildContext context) async {
    try {
      final target = _buildProfileShareTarget();
      if (!mounted) return;
      if (!target.isAvailable) {
        _showShareUnavailable(context);
        return;
      }
      await Clipboard.setData(ClipboardData(text: target.primaryText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _userProfileText(
              context,
              zhCN: target.webUrl.isNotEmpty ? '账号链接已复制' : '二维码内容已复制',
              zhTW: target.webUrl.isNotEmpty ? '帳號連結已複製' : 'QR 內容已複製',
              en: target.webUrl.isNotEmpty
                  ? 'Account link copied'
                  : 'QR code content copied',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (mounted) {
        _showShareUnavailable(context);
      }
    }
  }

  void _showShareUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _userProfileText(
            context,
            zhCN: '名片暂不可用，请稍后重试',
            zhTW: '名片暫不可用，請稍後重試',
            en: 'Profile card is unavailable. Please try again later.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
      ),
    );
  }

  /// 渲染名字下方的邀请码行。
  /// - 已拉到 invite_code：显示 10 位数字 + 复制图标，整体可点击复制并 SnackBar 提示。
  /// - 尚未拉到（旧账号或后端未下发）：返回 SizedBox 不渲染，避免占位空白。
  /// - 是自己（_isCurrentUser）：不渲染，避免与 ProfilePage 自身的邀请码重复入口。
  Widget _buildHeaderInviteCode(BuildContext context, Color foreground) {
    if (_isCurrentUser) return const SizedBox.shrink();
    final raw = _realInviteCode?.trim() ?? '';
    if (raw.isEmpty) return const SizedBox.shrink();

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _copyToClipboard(raw),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                raw,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                  color: foreground.withOpacity(0.78),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.copy_rounded,
                size: 14,
                color: foreground.withOpacity(0.78),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileQrCard(BuildContext context) {
    final pageContext = context;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userUuid = _userUuid ?? widget.userId;
    final username = _realUsername ?? '';
    final qrData = buildUserQrPayload(userUuid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                decoration: BoxDecoration(
                  color: AppColors.cardFor(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      _userProfileText(
                        context,
                        zhCN: '二维码名片',
                        zhTW: 'QR 名片',
                        en: 'QR Profile Card',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AvatarWidget(
                      avatar: _realAvatar ?? widget.avatar,
                      name: _displayName,
                      userId: widget.userId,
                      size: 68,
                      isCircle: true,
                    ),
                    const SizedBox(height: 10),
                    ColoredNameWidget(
                      name: _displayName,
                      nicknameColor: _nicknameColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      defaultColor: AppColors.textPrimaryFor(context),
                    ),
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@$username',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      width: 232,
                      height: 232,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.primaryFor(context),
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.primaryFor(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _userProfileText(
                        context,
                        zhCN: '扫码添加好友或打开资料页',
                        zhTW: '掃碼新增好友或開啟資料頁',
                        en: 'Scan to add friend or open profile',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _sendContactCard(pageContext);
                            },
                            icon: const Icon(Icons.ios_share_rounded, size: 20),
                            label: Text(
                              _userProfileText(
                                context,
                                zhCN: '分享名片',
                                zhTW: '分享名片',
                                en: 'Share Card',
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.onPrimaryFor(context),
                              backgroundColor: AppColors.primaryFor(context),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _copyAccountLink(pageContext);
                            },
                            icon: const Icon(Icons.link_rounded, size: 20),
                            label: Text(
                              _userProfileText(
                                context,
                                zhCN: '复制链接',
                                zhTW: '複製連結',
                                en: 'Copy Link',
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primaryFor(context),
                              backgroundColor:
                                  AppColors.primaryWithOpacity(context, 0.12),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                    color: AppColors.cardFor(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    AppLocalizations.of(context).cancel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.linkFor(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送联系人名片
  Future<void> _sendContactCard(BuildContext context) async {
    final pageContext = context;
    // Start a refresh, but do not block opening the selector. A slow request
    // previously made the button look completely unresponsive on all clients.
    final refreshFuture = ref.read(contactListProvider.notifier).refresh();
    if (!mounted) return;

    showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FriendSelectorSheet(
        onSelect: (friendId, friendName, friendAvatar) async {
          Navigator.pop(context);

          final userUuid = _userUuid ?? widget.userId;
          if (userUuid.trim().isEmpty || friendId.trim().isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(pageContext).showSnackBar(
              SnackBar(
                content: Text(
                  _userProfileText(
                    pageContext,
                    zhCN: '名片信息不完整，发送失败',
                    zhTW: '名片資訊不完整，傳送失敗',
                    en: 'Profile card is incomplete and cannot be sent.',
                  ),
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.error,
              ),
            );
            return;
          }

          try {
            final chat = await ref
                .read(chatListProvider.notifier)
                .createPrivateChatFromServer(
                  targetUserId: friendId,
                  targetUserName: friendName,
                  avatar: friendAvatar,
                );

            if (!mounted) return;
            if (chat == null) {
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _userProfileText(
                      pageContext,
                      zhCN: '创建会话失败',
                      zhTW: '建立會話失敗',
                      en: 'Failed to create chat',
                    ),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }

            final contact = api.ContactCardInfo(
              userId: userUuid,
              nickname: _displayName,
              username: (_realUsername ?? '').trim().isEmpty
                  ? null
                  : _realUsername!.trim(),
              avatar: (_realAvatar ?? widget.avatar ?? '').trim().isEmpty
                  ? null
                  : (_realAvatar ?? widget.avatar)!.trim(),
              bio: (_realBio ?? '').trim().isEmpty ? null : _realBio!.trim(),
              nicknameColor: (_nicknameColor ?? '').trim().isEmpty
                  ? null
                  : _nicknameColor!.trim(),
              emojiAvatar: (_emojiAvatar ?? '').trim().isEmpty
                  ? null
                  : _emojiAvatar!.trim(),
            );

            final sendResponse =
                await ref.read(api.chatServiceProvider).sendMessage(
                      chatId: chat.id,
                      type: 10,
                      content: api.MessageContent(contact: contact),
                    );

            if (!mounted) return;
            if (sendResponse.isSuccess && sendResponse.data != null) {
              ref
                  .read(messageListProvider(chat.id).notifier)
                  .handleRealtimeMessage(sendResponse.data!,
                      source: 'profile_card_send');
              await ref.read(chatListProvider.notifier).refresh();

              if (!mounted) return;
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _translate(
                            pageContext,
                            'send_contact_success',
                            _userProfileText(
                              pageContext,
                              zhCN: '已将 {name} 的名片发送给 {friend}',
                              zhTW: '已將 {name} 的名片傳送給 {friend}',
                              en: 'Sent {name}\'s contact card to {friend}',
                            ),
                            {'name': _displayName, 'friend': friendName},
                          ),
                        ),
                      ),
                    ],
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                ),
              );
            } else {
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _userProfileServerMessage(
                      sendResponse.message,
                      zhCN: '发送失败',
                      zhTW: '發送失敗',
                      en: AppLocalizations.of(pageContext).failed,
                    ),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.error,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _userProfileText(
                      pageContext,
                      zhCN: '发送失败，请重试',
                      zhTW: '發送失敗，請稍後重試',
                      en: 'Send failed, please try again',
                    ),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        },
      ),
    );

    try {
      await refreshFuture;
    } catch (_) {}
  }

  void _searchMessages(BuildContext context) {
    // 导航到搜索页面
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => MessageSearchPage(
          targetUserId: widget.userId,
          chatName: _fallbackUserName(context, widget.name),
          chatType: 'private',
        ),
      ),
    );
  }

  void _showClearChatDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TGActionSheet(
        title: _translate(
          context,
          'clear_chat_with_user',
          _userProfileText(
            context,
            zhCN: '清空与 {name} 的聊天记录？',
            zhTW: '清空與 {name} 的聊天記錄？',
            en: 'Clear chat history with {name}?',
          ),
          {'name': _fallbackThisUserName(context, widget.name)},
        ),
        message: _translate(
          context,
          'cannot_undo',
          _userProfileText(
            context,
            zhCN: '此操作无法撤销',
            zhTW: '此操作無法復原',
            en: 'This action cannot be undone',
          ),
        ),
        actions: [
          _TGActionSheetItem(
            title: _translate(
              context,
              'clear_for_me_only',
              _userProfileText(
                context,
                zhCN: '仅为我清空',
                zhTW: '僅為我清空',
                en: 'Clear for Me',
              ),
            ),
            isDestructive: true,
            onTap: () async {
              Navigator.pop(context);
              await _clearChatHistory();
            },
          ),
          _TGActionSheetItem(
            title: _translate(
              context,
              'clear_for_both',
              _userProfileText(
                context,
                zhCN: '为双方清空',
                zhTW: '為雙方清空',
                en: 'Clear for Both',
              ),
            ),
            isDestructive: true,
            onTap: () async {
              Navigator.pop(context);
              await _clearChatHistory(forBoth: true);
            },
          ),
        ],
        cancelText: l10n.cancel,
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
            ).showSnackBar(
              SnackBar(
                content: Text(
                  _userProfileText(
                    context,
                    zhCN: '清空失败，请重试',
                    zhTW: '清空失敗，請重試',
                    en: 'Clear failed, please try again',
                  ),
                ),
              ),
            );
          }
          return;
        }

        // 调用清空聊天记录 API
        final clearResponse = forBoth
            ? await chatService.clearChatHistoryForBoth(chatId.toString())
            : await chatService.clearChatHistory(chatId.toString());

        if (clearResponse.isSuccess && mounted) {
          ref
              .read(chatListProvider.notifier)
              .clearHistoryPreview(chatId.toString());
          // 刷新当前会话消息缓存（若会话页仍在栈中可立即生效）
          ref.invalidate(messageListProvider(chatId.toString()));
          // 刷新聊天列表
          ref.read(chatListProvider.notifier).refresh();

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                forBoth
                    ? _translate(
                        context,
                        'chat_history_cleared_for_both',
                        _userProfileText(
                          context,
                          zhCN: '已为双方清空聊天记录',
                          zhTW: '已為雙方清空聊天記錄',
                          en: 'Chat history cleared for both sides',
                        ),
                      )
                    : _translate(
                        context,
                        'chat_history_cleared',
                        _userProfileText(
                          context,
                          zhCN: '聊天记录已清空',
                          zhTW: '聊天記錄已清空',
                          en: 'Chat history cleared',
                        ),
                      ),
              ),
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _userProfileServerMessage(
                  clearResponse.message,
                  zhCN: '清空失败',
                  zhTW: '清空失敗',
                  en: 'Clear failed',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '清空失败，请重试',
                zhTW: '清空失敗，請重試',
                en: 'Clear failed, please try again',
              ),
            ),
          ),
        );
      }
    }
  }

  void _showCommonGroups(BuildContext context) {
    if (_commonGroups.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'no_common_groups',
              _userProfileText(
                context,
                zhCN: '暂无共同群组',
                zhTW: '暫無共同群組',
                en: 'No common groups yet',
              ),
            ),
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => _CommonGroupsPage(
          groups: _commonGroups,
          userName: _fallbackUserName(context, widget.name),
        ),
      ),
    );
  }

  void _showCommonContacts(BuildContext context) {
    if (_commonContactCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _userProfileText(
              context,
              zhCN: '暂无共同联系人',
              zhTW: '暫無共同聯絡人',
              en: 'No mutual contacts yet',
            ),
          ),
        ),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppColors.cardFor(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _userProfileText(
                        context,
                        zhCN: '共同联系人',
                        zhTW: '共同聯絡人',
                        en: 'Mutual Contacts',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_commonContacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          _userProfileText(
                            context,
                            zhCN: '共有 $_commonContactCount 位共同联系人',
                            zhTW: '共有 $_commonContactCount 位共同聯絡人',
                            en: '$_commonContactCount mutual contacts',
                          ),
                          style: TextStyle(
                            color: AppColors.textSecondaryFor(context),
                            fontSize: 16,
                          ),
                        ),
                      )
                    else
                      ..._commonContacts.map((item) {
                        final name = (item['nickname'] ??
                                item['username'] ??
                                _userProfileText(
                                  context,
                                  zhCN: '联系人',
                                  zhTW: '聯絡人',
                                  en: 'Contact',
                                ))
                            .toString();
                        final username = item['username']?.toString() ?? '';
                        final userId = item['id']?.toString() ?? '';
                        final avatar = item['avatar']?.toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: AvatarWidget(
                            avatar: avatar,
                            name: name,
                            userId: userId,
                            size: 42,
                          ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimaryFor(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: username.isEmpty
                              ? null
                              : Text(
                                  '@$username',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: userId.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  context.push(
                                    '/user/$userId?name=${Uri.encodeComponent(name)}',
                                  );
                                },
                        );
                      }),
                    if (_commonContactCount > _commonContacts.length)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _userProfileText(
                            context,
                            zhCN:
                                '还有 ${_commonContactCount - _commonContacts.length} 位共同联系人',
                            zhTW:
                                '還有 ${_commonContactCount - _commonContacts.length} 位共同聯絡人',
                            en: '${_commonContactCount - _commonContacts.length} more mutual contacts',
                          ),
                          style: TextStyle(
                            color: AppColors.textSecondaryFor(context),
                            fontSize: 13,
                          ),
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
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    AppLocalizations.of(context).cancel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.linkFor(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaList(BuildContext context, String title, String type) {
    if (_privateChatId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'no_chat_history',
              _userProfileText(
                context,
                zhCN: '暂无聊天记录',
                zhTW: '暫無聊天記錄',
                en: 'No chat history yet',
              ),
            ),
          ),
        ),
      );
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
    final l10n = AppLocalizations.of(context);
    // 提前保存页面级 context，防止被 builder 参数遮蔽后失效
    final pageContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TGActionSheet(
        title: _translate(
          context,
          'block_user_title',
          _userProfileText(
            context,
            zhCN: '屏蔽 {name}？',
            zhTW: '封鎖 {name}？',
            en: 'Block {name}?',
          ),
          {'name': _fallbackThisUserName(context, widget.name)},
        ),
        message: _translate(
          context,
          'block_user_message',
          _userProfileText(
            context,
            zhCN: '屏蔽后将无法收到对方的消息',
            zhTW: '封鎖後將無法收到對方的訊息',
            en: 'You will no longer receive messages from this user after blocking',
          ),
        ),
        actions: [
          _TGActionSheetItem(
            title: _translate(
              context,
              'block_user',
              _userProfileText(
                context,
                zhCN: '屏蔽用户',
                zhTW: '封鎖用戶',
                en: 'Block User',
              ),
            ),
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
                if (response.isSuccess ||
                    response.message.contains('已经屏蔽该用户') ||
                    response.message.contains('已屏蔽该用户') ||
                    (response.message.toLowerCase().contains('already') &&
                        response.message.toLowerCase().contains('block'))) {
                  setState(() => _isBlocked = true);
                  ScaffoldMessenger.of(
                    pageContext,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _translate(
                          pageContext,
                          'block_success',
                          _userProfileText(
                            pageContext,
                            zhCN: '已屏蔽',
                            zhTW: '已封鎖',
                            en: 'Blocked',
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(
                    pageContext,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _userProfileServerMessage(
                          response.message,
                          zhCN: '屏蔽失败，请重试',
                          zhTW: '封鎖失敗，請重試',
                          en: 'Block failed. Please try again.',
                        ),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  pageContext,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _translate(
                        pageContext,
                        'block_failed',
                        _userProfileText(
                          pageContext,
                          zhCN: '屏蔽失败，请重试',
                          zhTW: '封鎖失敗，請稍後重試',
                          en: 'Block failed, please try again',
                        ),
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ],
        cancelText: l10n.cancel,
      ),
    );
  }

  void _showReportPage(BuildContext context) {
    Navigator.push(
      context,
      createPageRoute(
        builder: (context) => ReportPage(
          targetId: widget.userId,
          targetType: 'user',
          targetName: _fallbackUserName(context, widget.name),
        ),
      ),
    );
  }
}

class _ProfileSharePreview extends StatelessWidget {
  final String name;
  final String username;
  final String? avatar;
  final String userId;
  final String? nicknameColor;
  final String? bio;
  final bool isDark;

  const _ProfileSharePreview({
    required this.name,
    required this.username,
    required this.avatar,
    required this.userId,
    required this.nicknameColor,
    required this.bio,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = AppColors.textSecondaryFor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AvatarWidget(
            avatar: avatar,
            name: name,
            userId: userId,
            size: 54,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ColoredNameWidget(
                  name: name,
                  nicknameColor: nicknameColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  defaultColor: AppColors.textPrimaryFor(context),
                ),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: subColor),
                  ),
                ],
                if ((bio ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    bio!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: subColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileShareAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ProfileShareAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(isDark ? 0.24 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    color: AppColors.textSecondaryFor(context),
                    fontWeight: FontWeight.w500,
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

class _CommonInfoGrid extends StatelessWidget {
  final bool isDark;
  final bool isLoading;
  final int commonGroupCount;
  final int commonContactCount;
  final List<String> commonContactNames;
  final String recentInteraction;
  final int sharedMediaTotal;
  final VoidCallback onCommonGroupsTap;
  final VoidCallback onCommonContactsTap;
  final VoidCallback onSharedMediaTap;

  const _CommonInfoGrid({
    required this.isDark,
    required this.isLoading,
    required this.commonGroupCount,
    required this.commonContactCount,
    required this.commonContactNames,
    required this.recentInteraction,
    required this.sharedMediaTotal,
    required this.onCommonGroupsTap,
    required this.onCommonContactsTap,
    required this.onSharedMediaTap,
  });

  @override
  Widget build(BuildContext context) {
    final contactHint = commonContactNames.isEmpty
        ? _userProfileText(
            context,
            zhCN: '暂无共同联系人',
            zhTW: '暫無共同聯絡人',
            en: 'No mutual contacts',
          )
        : commonContactNames.take(2).join('、');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _userProfileText(
              context,
              zhCN: '共同信息',
              zhTW: '共同資訊',
              en: 'Relationship',
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.95,
            children: [
              _CommonInfoTile(
                icon: Icons.groups_2_outlined,
                color: Colors.green,
                title: _userProfileText(
                  context,
                  zhCN: '共同群聊',
                  zhTW: '共同群聊',
                  en: 'Groups',
                ),
                value: isLoading ? '--' : '$commonGroupCount',
                hint: _userProfileText(
                  context,
                  zhCN: '个群聊',
                  zhTW: '個群聊',
                  en: 'in common',
                ),
                isDark: isDark,
                onTap: onCommonGroupsTap,
              ),
              _CommonInfoTile(
                icon: Icons.contacts_outlined,
                color: Colors.blue,
                title: _userProfileText(
                  context,
                  zhCN: '共同联系人',
                  zhTW: '共同聯絡人',
                  en: 'Contacts',
                ),
                value: isLoading ? '--' : '$commonContactCount',
                hint: contactHint,
                isDark: isDark,
                onTap: onCommonContactsTap,
              ),
              _CommonInfoTile(
                icon: Icons.schedule_rounded,
                color: Colors.orange,
                title: _userProfileText(
                  context,
                  zhCN: '最近互动',
                  zhTW: '最近互動',
                  en: 'Last Activity',
                ),
                value: recentInteraction,
                hint: _userProfileText(
                  context,
                  zhCN: '私聊消息',
                  zhTW: '私聊訊息',
                  en: 'Private chat',
                ),
                isDark: isDark,
              ),
              _CommonInfoTile(
                icon: Icons.perm_media_outlined,
                color: AppColors.primaryFor(context),
                title: _userProfileText(
                  context,
                  zhCN: '共享媒体',
                  zhTW: '共享媒體',
                  en: 'Shared Media',
                ),
                value: isLoading ? '--' : '$sharedMediaTotal',
                hint: _userProfileText(
                  context,
                  zhCN: '项内容',
                  zhTW: '項內容',
                  en: 'items',
                ),
                isDark: isDark,
                onTap: onSharedMediaTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommonInfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String hint;
  final bool isDark;
  final VoidCallback? onTap;

  const _CommonInfoTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.hint,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF6F7FB);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: value.length > 8 ? 14 : 18,
                      color: AppColors.textPrimaryFor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
  final Color? foregroundColor;
  final double buttonSize;

  const _TGActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.lightStyle = false,
    this.foregroundColor,
    this.buttonSize = 50,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveForeground = foregroundColor ??
        (lightStyle ? Colors.white : AppColors.primaryFor(context));
    final bgColor = lightStyle
        ? Colors.black.withOpacity(0.26)
        : AppColors.primaryWithOpacity(context, 0.1);
    final iconColor = effectiveForeground;
    final textColor = effectiveForeground;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        children: [
          Container(
            width: buttonSize,
            height: buttonSize,
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
                : Icon(
                    icon,
                    color: iconColor,
                    size: (buttonSize * 0.5).clamp(22.0, 26.0),
                  ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
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
                      color: AppColors.textPrimaryFor(context),
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

class _ProfileDetailsCard extends StatelessWidget {
  final Color cardColor;
  final bool isDark;
  final String bioLabel;
  final String bio;
  final String usernameLabel;
  final String? username;
  final VoidCallback? onUsernameTap;
  final VoidCallback onQrTap;

  const _ProfileDetailsCard({
    required this.cardColor,
    required this.isDark,
    required this.bioLabel,
    required this.bio,
    required this.usernameLabel,
    required this.username,
    required this.onUsernameTap,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedUsername = username?.trim() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileDetailsText(
              value: bio,
              label: bioLabel,
              isDark: isDark,
              maxLines: 3,
            ),
            if (trimmedUsername.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 17),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: AppColors.dividerFor(context),
                ),
              ),
              GestureDetector(
                onTap: onUsernameTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Expanded(
                      child: _ProfileDetailsText(
                        value: '@$trimmedUsername',
                        label: usernameLabel,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 14),
                    IconButton(
                      onPressed: onQrTap,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 42,
                        height: 42,
                      ),
                      icon: Icon(
                        Icons.qr_code_2_rounded,
                        color:
                            (isDark ? Colors.white : Colors.black).withOpacity(
                          0.48,
                        ),
                        size: 28,
                      ),
                      tooltip: _userProfileText(
                        context,
                        zhCN: '二维码名片',
                        zhTW: 'QR 名片',
                        en: 'QR Card',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileDetailsText extends StatelessWidget {
  final String value;
  final String label;
  final bool isDark;
  final int maxLines;

  const _ProfileDetailsText({
    required this.value,
    required this.label,
    required this.isDark,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondaryFor(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            height: 1.35,
            color: isDark ? Colors.white : const Color(0xFF111827),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TGProfileInfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final int maxLines;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _TGProfileInfoCell({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.valueColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark
        ? AppColors.primaryWithOpacity(context, 0.18)
        : const Color(0xFFF0F3FF);
    final valueColor = isDark ? Colors.white : const Color(0xFF111827);
    final labelColor = AppColors.textTertiaryFor(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.primaryFor(context)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: labelColor,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      color: this.valueColor ?? valueColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 13),
                child: trailing!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditContactInfoResult {
  final String remark;

  const _EditContactInfoResult({required this.remark});
}

class _EditContactInfoPage extends StatefulWidget {
  final String displayName;
  final String? username;
  final String userId;
  final String initialRemark;

  const _EditContactInfoPage({
    required this.displayName,
    required this.username,
    required this.userId,
    required this.initialRemark,
  });

  @override
  State<_EditContactInfoPage> createState() => _EditContactInfoPageState();
}

class _EditContactInfoPageState extends State<_EditContactInfoPage> {
  late final TextEditingController _remarkController;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController(text: widget.initialRemark);
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  void _finish() {
    Navigator.pop(
      context,
      _EditContactInfoResult(remark: _remarkController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = AppColors.backgroundFor(context);
    final cardColor = AppColors.cardFor(context);
    final separatorColor = AppColors.dividerFor(context);
    final valueColor = AppColors.textPrimaryFor(context);
    final labelColor = AppColors.textTertiaryFor(context);
    final username = widget.username?.trim();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bgColor,
        foregroundColor: AppColors.textPrimaryFor(context),
        centerTitle: true,
        title: Text(
          _userProfileText(
            context,
            zhCN: '编辑联系人信息',
            zhTW: '編輯聯絡人資訊',
            en: 'Edit Contact Info',
          ),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _finish,
            child: Text(
              _userProfileText(
                context,
                zhCN: '完成',
                zhTW: '完成',
                en: 'Done',
              ),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _TGSection(
              cardColor: cardColor,
              separatorColor: separatorColor,
              children: [
                _EditContactReadonlyRow(
                  icon: Icons.person_outline,
                  label: _userProfileText(
                    context,
                    zhCN: '昵称',
                    zhTW: '暱稱',
                    en: 'Nickname',
                  ),
                  value: widget.displayName,
                ),
                if (username != null && username.isNotEmpty)
                  _EditContactReadonlyRow(
                    icon: Icons.alternate_email_rounded,
                    label: _userProfileText(
                      context,
                      zhCN: '用户名',
                      zhTW: '使用者名稱',
                      en: 'Username',
                    ),
                    value: username,
                  ),
                _EditContactReadonlyRow(
                  icon: Icons.tag_outlined,
                  label: 'ID',
                  value: widget.userId,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 18,
                          color: AppColors.primaryFor(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _userProfileText(
                            context,
                            zhCN: '备注名',
                            zhTW: '備註名稱',
                            en: 'Remark Name',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: labelColor,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarkController,
                      autofocus: true,
                      maxLength: 30,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(30),
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _finish(),
                      style: TextStyle(fontSize: 16, color: valueColor),
                      decoration: InputDecoration(
                        hintText: _userProfileText(
                          context,
                          zhCN: '填写备注名，留空则显示昵称',
                          zhTW: '填寫備註名稱，留空則顯示暱稱',
                          en: 'Enter a remark name. Leave empty to show the nickname.',
                        ),
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        counterStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditContactReadonlyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _EditContactReadonlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark
        ? AppColors.primaryWithOpacity(context, 0.18)
        : const Color(0xFFF0F3FF);
    final valueColor = isDark ? Colors.white : const Color(0xFF111827);
    final labelColor = AppColors.textTertiaryFor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppColors.primaryFor(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: labelColor,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    color: valueColor,
                    fontWeight: FontWeight.w500,
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              action.title,
                              style: TextStyle(
                                fontSize: 20,
                                color: action.isDestructive
                                    ? Colors.red
                                    : AppColors.linkFor(context),
                              ),
                              textAlign: TextAlign.center,
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
                    color: AppColors.linkFor(context),
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
              isCircle: true,
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
    final l10n = AppLocalizations.of(context);

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
              _userProfileText(
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
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: urls
                .map(
                  (url) => ListTile(
                    leading:
                        Icon(Icons.link, color: AppColors.linkFor(context)),
                    title: Text(
                      url,
                      style: TextStyle(
                          color: AppColors.linkFor(context), fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context)),
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
              item.fileName ??
                  _userProfileText(
                    context,
                    zhCN: '未知文件',
                    zhTW: '未知檔案',
                    en: 'Unknown File',
                  ),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textPrimaryFor(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatFileSize(item.fileSize ?? 0)} · ${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textTertiaryFor(context)),
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
              '${_userProfileText(
                context,
                zhCN: '语音消息',
                zhTW: '語音訊息',
                en: 'Voice Message',
              )} ${_formatDuration(item.duration ?? 0)}',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
            subtitle: Text(
              '${item.senderName ?? ''} · ${_formatDate(item.createdAt)}',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textTertiaryFor(context)),
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
              _userProfileText(
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
          _userProfileText(
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
            _userProfileText(
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
  List<api.SearchMessageItem> _results = [];
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
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.searchMessages(_chatId!, query);

      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _isSearching = false;
          _results = response.data!.list;
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

  void _openMessage(api.SearchMessageItem result) {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }
    context.push(
      '/chat/$chatId?name=${Uri.encodeComponent(widget.userName)}&type=private&messageId=${Uri.encodeComponent(result.id)}&messageSeq=${result.seq}',
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
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.primaryFor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _userProfileText(
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
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _userProfileText(
                    context,
                    zhCN: '在与 ${widget.userName} 的对话中搜索',
                    zhTW: '在與 ${widget.userName} 的對話中搜尋',
                    en: 'Search in your chat with ${widget.userName}',
                  ),
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
                                  ? _userProfileText(
                                      context,
                                      zhCN: '输入关键词搜索消息',
                                      zhTW: '輸入關鍵字搜尋訊息',
                                      en: 'Enter keywords to search messages',
                                    )
                                  : _userProfileText(
                                      context,
                                      zhCN: '未找到相关消息',
                                      zhTW: '找不到相關訊息',
                                      en: 'No related messages found',
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
                              horizontal: 16,
                              vertical: 4,
                            ),
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
                              onTap: () => _openMessage(result),
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
    final l10n = AppLocalizations.of(context);

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
          '${l10n.commonGroups} · $userName',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
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
                    l10n.get('no_common_groups'),
                    style: TextStyle(fontSize: 17, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final groupName = _fallbackGroupName(
                  context,
                  group['name']?.toString(),
                );
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
                    color: AppColors.cardFor(context),
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
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                    subtitle: Text(
                      _groupMembersText(context, memberCount),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
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
    {'id': 'spam', 'icon': Icons.mail_outline},
    {'id': 'fake', 'icon': Icons.warning_amber_outlined},
    {'id': 'violence', 'icon': Icons.dangerous_outlined},
    {'id': 'porn', 'icon': Icons.block},
    {'id': 'harassment', 'icon': Icons.person_off_outlined},
    {'id': 'copyright', 'icon': Icons.copyright},
    {'id': 'other', 'icon': Icons.more_horiz},
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
      ).showSnackBar(
        SnackBar(
          content: Text(
            _userProfileText(
              context,
              zhCN: '请选择举报原因',
              zhTW: '請選擇檢舉原因',
              en: 'Please select a report reason',
            ),
          ),
        ),
      );
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
        ).showSnackBar(
          SnackBar(
            content: Text(
              _userProfileText(
                context,
                zhCN: '举报已提交，我们会尽快处理',
                zhTW: '檢舉已提交，我們會盡快處理',
                en: 'Report submitted. We will review it as soon as possible.',
              ),
            ),
          ),
        );
      } else {
        // 显示具体的错误信息
        final errorMsg = _userProfileServerMessage(
          response.message,
          zhCN: '提交失败，请重试',
          zhTW: '提交失敗，請重試',
          en: 'Submission failed. Please try again.',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      // 解析错误信息
      String errorMsg = _userProfileText(
        context,
        zhCN: '提交失败，请重试',
        zhTW: '提交失敗，請重試',
        en: 'Submission failed. Please try again.',
      );
      if (e.toString().contains('400')) {
        errorMsg = _userProfileText(
          context,
          zhCN: '您已举报过该内容，请等待处理',
          zhTW: '您已檢舉過此內容，請等待處理',
          en: 'You have already reported this content. Please wait for review.',
        );
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
    final bgColor = AppColors.backgroundFor(context);
    final cardColor = AppColors.cardFor(context);
    final separatorColor = AppColors.dividerFor(context);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.primaryFor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _userProfileText(
            context,
            zhCN: '举报',
            zhTW: '檢舉',
            en: 'Report',
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
            onPressed: _isSubmitting ? null : _submitReport,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _userProfileText(
                      context,
                      zhCN: '提交',
                      zhTW: '提交',
                      en: 'Submit',
                    ),
                    style: TextStyle(
                        color: AppColors.linkFor(context), fontSize: 17),
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
                          _userProfileText(
                            context,
                            zhCN: '举报对象',
                            zhTW: '檢舉對象',
                            en: 'Reported Target',
                          ),
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.targetName,
                          style: TextStyle(
                            fontSize: 17,
                            color: AppColors.textPrimaryFor(context),
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
                _userProfileText(
                  context,
                  zhCN: '选择举报原因',
                  zhTW: '選擇檢舉原因',
                  en: 'Select a Report Reason',
                ),
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
                                  _reportReasonTitle(
                                    context,
                                    reason['id'] as String,
                                  ),
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: AppColors.textPrimaryFor(context),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  color: AppColors.primaryFor(context),
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
                _userProfileText(
                  context,
                  zhCN: '补充说明（可选）',
                  zhTW: '補充說明（選填）',
                  en: 'Additional Details (Optional)',
                ),
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
                    hintText: _userProfileText(
                      context,
                      zhCN: '请详细描述问题，帮助我们更好地处理...',
                      zhTW: '請詳細描述問題，幫助我們更好地處理...',
                      en: 'Please describe the issue in detail to help us review it.',
                    ),
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
                    color: AppColors.textPrimaryFor(context),
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
                _userProfileText(
                  context,
                  zhCN: '我们会对举报内容进行审核，如确认违规将采取相应措施。感谢您帮助维护社区环境。',
                  zhTW: '我們會審核檢舉內容，如確認違規將採取相應措施。感謝您協助維護社群環境。',
                  en: 'We will review the reported content and take action if violations are confirmed. Thank you for helping keep the community safe.',
                ),
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
  final void Function(String friendId, String friendName, String? friendAvatar)
      onSelect;

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
      final id =
          (contact.uuid?.trim().isNotEmpty == true ? contact.uuid : contact.id)
              ?.trim();
      if (id == null || id.isEmpty) continue;
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
      final targetId = chat.targetUserUuid?.trim().isNotEmpty == true
          ? chat.targetUserUuid!.trim()
          : (chat.targetUserId ?? '').trim();
      if (chat.type == ChatItemType.private && targetId.isNotEmpty) {
        final id = targetId;
        final name = chat.name;
        if (!seenIds.contains(id) && !seenNames.contains(name)) {
          seenIds.add(id);
          seenNames.add(name);
          friends.add(_FriendItem(id: id, name: name, avatar: chat.avatar));
        }
      }
    }

    return Material(
      color: AppColors.surfaceFor(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
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
                    _userProfileText(
                      context,
                      zhCN: '选择好友',
                      zhTW: '選擇好友',
                      en: 'Select a friend',
                    ),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(contactListProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      _userProfileText(
                        context,
                        zhCN: '刷新',
                        zhTW: '重新整理',
                        en: 'Refresh',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
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
                            _userProfileText(
                              context,
                              zhCN: '暂无可发送的好友，请先添加好友或点刷新',
                              zhTW: '暫無可發送的好友，請先新增好友或點重新整理',
                              en: 'No friends available. Add friends or refresh.',
                            ),
                            textAlign: TextAlign.center,
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
                              color: AppColors.textPrimaryFor(context),
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
                          onTap: () =>
                              onSelect(friend.id, friend.name, friend.avatar),
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
        setState(() {
          _isInitialized = true;
        });
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
                              activeColor: AppColors.primaryFor(context),
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
