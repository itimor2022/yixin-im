// 文件用途：实现 GroupEditPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 GroupEditPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/upload_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/avatar_crop_page.dart';
import '../providers/chat_provider.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../vip/providers/vip_provider.dart';
import '../../vip/services/vip_service.dart';

String _groupEditText(
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

String _groupEditServerMessage(
  String? raw, {
  required String fallbackEn,
}) {
  return localizeServerMessage(raw, fallbackEn: fallbackEn);
}

// 关键声明：group edit page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 群组/频道编辑页面
class GroupEditPage extends ConsumerStatefulWidget {
  final String chatId;
  final bool isDesktopPanel;

  const GroupEditPage({
    super.key,
    required this.chatId,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<GroupEditPage> createState() => _GroupEditPageState();
}

class _GroupEditPageState extends ConsumerState<GroupEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _usernameController;

  bool _isUsernameAvailable = true;
  bool _isCheckingUsername = false;
  String? _usernameError;
  bool _isSaving = false;

  // 权限设置状态
  bool _canSendMessage = true;
  bool _canSendMedia = true;
  bool _canSendLinks = true;
  bool _canAddMembers = false;
  bool _canPinMessages = false;
  bool _allowAnonymous = false;
  bool _allowForward = true;
  bool _allowViewHistory = true;
  bool _memberProtection = false;

  // 公开/私密设置
  bool _isPublic = false;
  bool _joinApproval = false; // 加入需要管理员审批
  bool _initialIsPublic = false;
  bool _initialMemberProtection = false;
  String _initialUsername = '';

  // 头像
  String? _newAvatarUrl;

  api.Chat? _chatDetail;
  ChatItem? _chat;
  bool _dataLoaded = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descController = TextEditingController();
    _usernameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _loadChatData(api.Chat? chatDetail) {
    if (_dataLoaded) return;

    // 本地聊天列表用于补齐名称和头像；可编辑权限必须来自服务端详情。
    final chats = ref.read(chatListProvider);
    _chat = chats.pinnedChats.firstWhere(
      (c) => c.id == widget.chatId,
      orElse: () => chats.regularChats.firstWhere(
        (c) => c.id == widget.chatId,
        orElse: () => throw Exception('Chat not found'),
      ),
    );

    if (chatDetail != null) {
      _chatDetail = chatDetail;
      _nameController.text = chatDetail.name ?? _chat?.name ?? '';
      _descController.text = chatDetail.description ?? '';
      _usernameController.text = chatDetail.username ?? '';

      // 加载权限设置
      _canSendMessage = chatDetail.canSendMessage;
      _canSendMedia = chatDetail.canSendMedia;
      _canSendLinks = chatDetail.canSendLinks;
      _canAddMembers = chatDetail.canAddMembers;
      _canPinMessages = chatDetail.canPinMessages;
      _allowAnonymous = chatDetail.allowAnonymous;
      _allowForward = chatDetail.allowForward;
      _allowViewHistory = chatDetail.allowViewHistory;
      _memberProtection = chatDetail.memberProtection;

      // 加载公开/私密设置
      _isPublic = chatDetail.isPublic;
      _joinApproval = chatDetail.joinApproval;
      _initialIsPublic = chatDetail.isPublic;
      _initialMemberProtection = chatDetail.memberProtection;
      _initialUsername = chatDetail.username?.trim() ?? '';

      _dataLoaded = true;
    } else if (_chat != null && !_dataLoaded) {
      _nameController.text = _chat!.name;
      _descController.text = _chat!.description ?? '';
      _dataLoaded = true;
    }
  }

  bool _canSetPublicIdentity(VipStatus status) {
    return status.isActive && status.entitlements.canSetPublicUsername;
  }

  bool _canEnableMemberProtection(VipStatus status) {
    return status.isActive && status.entitlements.canEnableMemberProtection;
  }

  bool get _isEnablingPublicIdentity {
    final nextUsername = _usernameController.text.trim();
    return (_isPublic && !_initialIsPublic) ||
        (nextUsername.isNotEmpty && nextUsername != _initialUsername);
  }

  bool get _isEnablingMemberProtection {
    return _memberProtection && !_initialMemberProtection;
  }

  Future<bool> _ensureVipFeature(
    bool Function(VipStatus status) isAllowed, {
    required String message,
  }) async {
    // 客户端权益判断只控制功能入口，保存时服务端仍会做最终资格校验。
    var status = ref.read(vipStatusProvider).valueOrNull;
    if (status != null && isAllowed(status)) return true;

    if (status == null) {
      try {
        final loadedStatus = await ref.read(vipStatusProvider.future);
        status = loadedStatus;
        if (isAllowed(loadedStatus)) return true;
      } catch (_) {
        return true;
      }
    }

    if (mounted) _showVipFeaturePrompt(message);
    return false;
  }

  void _showVipFeaturePrompt(String message) {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        showCloseIcon: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: _groupEditText(
            context,
            zhCN: '去开通',
            zhTW: '去開通',
            en: 'Open',
          ),
          onPressed: () {
            messenger.hideCurrentSnackBar();
            router.push('/vip');
          },
        ),
      ),
    );
  }

  Future<void> _setPublicType(bool value, bool isChannel) async {
    if (!value) {
      setState(() => _isPublic = false);
      return;
    }
    if (_initialIsPublic) {
      setState(() => _isPublic = true);
      return;
    }
    final allowed = await _ensureVipFeature(
      _canSetPublicIdentity,
      message: isChannel
          ? _groupEditText(
              context,
              zhCN: '开通 SVIP 后可设置公开频道',
              zhTW: '開通 SVIP 後可設定公開頻道',
              en: 'Activate SVIP to make channels public.',
            )
          : _groupEditText(
              context,
              zhCN: '开通 SVIP 后可设置公开群组',
              zhTW: '開通 SVIP 後可設定公開群組',
              en: 'Activate SVIP to make groups public.',
            ),
    );
    if (allowed && mounted) {
      setState(() => _isPublic = true);
    }
  }

  Future<void> _setMemberProtection(bool value) async {
    if (!value) {
      setState(() => _memberProtection = false);
      return;
    }
    if (_initialMemberProtection) {
      setState(() => _memberProtection = true);
      return;
    }
    final allowed = await _ensureVipFeature(
      _canEnableMemberProtection,
      message: _groupEditText(
        context,
        zhCN: '开通 SVIP 后可开启群成员保护',
        zhTW: '開通 SVIP 後可開啟群成員保護',
        en: 'Activate SVIP to protect the member list.',
      ),
    );
    if (allowed && mounted) {
      setState(() => _memberProtection = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.chatId));
    final vipStatusAsync = ref.watch(vipStatusProvider);
    final entitlements = vipStatusAsync.valueOrNull?.entitlements;
    final canUsePublicSettings = entitlements?.canSetPublicUsername == true;
    final canUseMemberProtection =
        entitlements?.canEnableMemberProtection == true;

    // 加载聊天数据
    chatDetailAsync.whenData((chatDetail) {
      _loadChatData(chatDetail);
    });

    if (_chat == null && !chatDetailAsync.isLoading) {
      // 尝试从本地列表加载
      _loadChatData(null);
    }

    if (_chat == null && chatDetailAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _groupEditText(
              context,
              zhCN: '加载中...',
              zhTW: '載入中...',
              en: 'Loading...',
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_chat == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _groupEditText(
              context,
              zhCN: '编辑',
              zhTW: '編輯',
              en: 'Edit',
            ),
          ),
        ),
        body: Center(
          child: Text(
            _groupEditText(
              context,
              zhCN: '聊天不存在',
              zhTW: '聊天不存在',
              en: 'Chat not found',
            ),
          ),
        ),
      );
    }

    final isChannel = _chat!.type == ChatItemType.channel;
    final title = isChannel
        ? _groupEditText(
            context,
            zhCN: '编辑频道',
            zhTW: '編輯頻道',
            en: 'Edit Channel',
          )
        : _groupEditText(
            context,
            zhCN: '编辑群组',
            zhTW: '編輯群組',
            en: 'Edit Group',
          );

    // 桌面端面板模式：只返回内容
    if (widget.isDesktopPanel) {
      return _buildBody(
        isDark,
        isChannel,
        canUsePublicSettings: canUsePublicSettings,
        canUseMemberProtection: canUseMemberProtection,
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: Text(
              _groupEditText(
                context,
                zhCN: '完成',
                zhTW: '完成',
                en: 'Done',
              ),
              style: TextStyle(
                  color: AppColors.linkFor(context),
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: _buildBody(
        isDark,
        isChannel,
        canUsePublicSettings: canUsePublicSettings,
        canUseMemberProtection: canUseMemberProtection,
      ),
    );
  }

  Widget _buildBody(
    bool isDark,
    bool isChannel, {
    required bool canUsePublicSettings,
    required bool canUseMemberProtection,
  }) {
    return Column(
      children: [
        // 桌面端面板模式时显示保存按钮
        if (widget.isDesktopPanel)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _groupEditText(
                            context,
                            zhCN: '保存更改',
                            zhTW: '儲存變更',
                            en: 'Save Changes',
                          ),
                          style: TextStyle(
                            color: AppColors.linkFor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              const SizedBox(height: 20),

              // 头像和名称
              _buildHeaderSection(isDark),

              const SizedBox(height: 24),

              // 描述
              _buildDescriptionSection(isDark),

              const SizedBox(height: 24),

              // 类型设置（公开/私密）
              _buildTypeSection(
                isDark,
                isChannel,
                canUsePublicSettings: canUsePublicSettings,
              ),

              const SizedBox(height: 24),

              // 链接设置
              _buildLinkSection(
                isDark,
                isChannel,
                canUsePublicSettings: canUsePublicSettings,
              ),

              const SizedBox(height: 24),

              // 加入/订阅设置 - 需要管理员审批
              _buildJoinSettingsSection(isDark, isChannel),

              const SizedBox(height: 24),

              // 权限设置（群组）
              if (!isChannel)
                _buildPermissionSection(
                  isDark,
                  canUseMemberProtection: canUseMemberProtection,
                ),

              if (!isChannel) const SizedBox(height: 24),

              // 危险操作
              _buildDangerSection(isDark, isChannel),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 头像
          GestureDetector(
            onTap: _changeAvatar,
            child: Stack(
              children: [
                AvatarWidget(
                  name: _chat!.name,
                  avatar: (_newAvatarUrl != null && _newAvatarUrl!.isNotEmpty)
                      ? ApiConfig.getMediaUrl(_newAvatarUrl!)
                      : _chat!.avatar,
                  userId: _chat!.id,
                  size: 70,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryFor(context),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBackground
                            : AppColors.lightBackground,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.camera_alt,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // 名称输入
          Expanded(
            child: TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: _chat!.type == ChatItemType.channel
                    ? _groupEditText(
                        context,
                        zhCN: '频道名称',
                        zhTW: '頻道名稱',
                        en: 'Channel Name',
                      )
                    : _groupEditText(
                        context,
                        zhCN: '群组名称',
                        zhTW: '群組名稱',
                        en: 'Group Name',
                      ),
                border: InputBorder.none,
                hintStyle: TextStyle(color: AppColors.textTertiaryFor(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _groupEditText(
              context,
              zhCN: '简介',
              zhTW: '簡介',
              en: 'Description',
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _descController,
              maxLines: 4,
              maxLength: 255,
              decoration: InputDecoration(
                hintText: _groupEditText(
                  context,
                  zhCN: '添加简介...',
                  zhTW: '新增簡介...',
                  en: 'Add a description...',
                ),
                hintStyle: TextStyle(color: AppColors.textTertiaryFor(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
                counterStyle:
                    TextStyle(color: AppColors.textTertiaryFor(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSection(
    bool isDark,
    bool isChannel, {
    required bool canUsePublicSettings,
  }) {
    final showPublicVipHint = !canUsePublicSettings && !_initialIsPublic;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChannel
                ? _groupEditText(
                    context,
                    zhCN: '频道类型',
                    zhTW: '頻道類型',
                    en: 'Channel Type',
                  )
                : _groupEditText(
                    context,
                    zhCN: '群组类型',
                    zhTW: '群組類型',
                    en: 'Group Type',
                  ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // 公开频道/群组
                RadioListTile<bool>(
                  value: true,
                  groupValue: _isPublic,
                  onChanged: (v) => _setPublicType(v ?? false, isChannel),
                  secondary: showPublicVipHint
                      ? Icon(
                          Icons.workspace_premium_outlined,
                          color: AppColors.warning,
                          size: 22,
                        )
                      : null,
                  title: Text(
                    isChannel
                        ? _groupEditText(
                            context,
                            zhCN: '公开频道',
                            zhTW: '公開頻道',
                            en: 'Public Channel',
                          )
                        : _groupEditText(
                            context,
                            zhCN: '公开群组',
                            zhTW: '公開群組',
                            en: 'Public Group',
                          ),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    showPublicVipHint
                        ? _groupEditText(
                            context,
                            zhCN: 'SVIP 可开启公开搜索',
                            zhTW: 'SVIP 可開啟公開搜尋',
                            en: 'SVIP unlocks public discovery.',
                          )
                        : isChannel
                            ? _groupEditText(
                                context,
                                zhCN: '任何人都可以搜索并订阅此频道',
                                zhTW: '任何人都可以搜尋並訂閱此頻道',
                                en: 'Anyone can search and subscribe to this channel.',
                              )
                            : _groupEditText(
                                context,
                                zhCN: '任何人都可以搜索并加入此群组',
                                zhTW: '任何人都可以搜尋並加入此群組',
                                en: 'Anyone can search and join this group.',
                              ),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                  activeColor: AppColors.primaryFor(context),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                const Divider(height: 1),
                // 私密频道/群组
                RadioListTile<bool>(
                  value: false,
                  groupValue: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v ?? false),
                  title: Text(
                    isChannel
                        ? _groupEditText(
                            context,
                            zhCN: '私密频道',
                            zhTW: '私密頻道',
                            en: 'Private Channel',
                          )
                        : _groupEditText(
                            context,
                            zhCN: '私密群组',
                            zhTW: '私密群組',
                            en: 'Private Group',
                          ),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isChannel
                        ? _groupEditText(
                            context,
                            zhCN: '只有被邀请才能订阅，不可被搜索',
                            zhTW: '只有被邀請才能訂閱，無法被搜尋',
                            en: 'Only invited users can subscribe, and it cannot be searched.',
                          )
                        : _groupEditText(
                            context,
                            zhCN: '只有被邀请才能加入，不可被搜索',
                            zhTW: '只有被邀請才能加入，無法被搜尋',
                            en: 'Only invited users can join, and it cannot be searched.',
                          ),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                  activeColor: AppColors.primaryFor(context),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinSettingsSection(bool isDark, bool isChannel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChannel
                ? _groupEditText(
                    context,
                    zhCN: '订阅设置',
                    zhTW: '訂閱設定',
                    en: 'Subscription Settings',
                  )
                : _groupEditText(
                    context,
                    zhCN: '加入设置',
                    zhTW: '加入設定',
                    en: 'Join Settings',
                  ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              value: _joinApproval,
              onChanged: (v) => setState(() => _joinApproval = v),
              title: Text(
                isChannel
                    ? _groupEditText(
                        context,
                        zhCN: '订阅需要审批',
                        zhTW: '訂閱需要審批',
                        en: 'Subscription requires approval',
                      )
                    : _groupEditText(
                        context,
                        zhCN: '加入需要审批',
                        zhTW: '加入需要審批',
                        en: 'Join requests require approval',
                      ),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                isChannel
                    ? _groupEditText(
                        context,
                        zhCN: '新订阅者需要管理员批准才能订阅此频道',
                        zhTW: '新訂閱者需要管理員批准才能訂閱此頻道',
                        en: 'New subscribers need admin approval to subscribe.',
                      )
                    : _groupEditText(
                        context,
                        zhCN: '新成员需要管理员或群主批准才能加入',
                        zhTW: '新成員需要管理員或群主批准才能加入',
                        en: 'New members need approval from an admin or the owner to join.',
                      ),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
              activeColor: AppColors.primaryFor(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkSection(
    bool isDark,
    bool isChannel, {
    required bool canUsePublicSettings,
  }) {
    final hasUsername = _usernameController.text.isNotEmpty;
    final showUsernameVipHint =
        !canUsePublicSettings && _initialUsername.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChannel
                ? _groupEditText(
                    context,
                    zhCN: '频道号',
                    zhTW: '頻道號',
                    en: 'Channel ID',
                  )
                : _groupEditText(
                    context,
                    zhCN: '群组号',
                    zhTW: '群組號',
                    en: 'Group ID',
                  ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryFor(context),
            ),
          ),
          const SizedBox(height: 8),

          // 说明
          Text(
            isChannel
                ? _groupEditText(
                    context,
                    zhCN: '设置频道号后，其他人可以通过搜索频道号找到您的频道。',
                    zhTW: '設定頻道號後，其他人可以透過搜尋頻道號找到您的頻道。',
                    en: 'After setting a channel ID, others can find your channel by searching it.',
                  )
                : _groupEditText(
                    context,
                    zhCN: '设置群组号后，其他人可以通过搜索群组号找到您的群组。',
                    zhTW: '設定群組號後，其他人可以透過搜尋群組號找到您的群組。',
                    en: 'After setting a group ID, others can find your group by searching it.',
                  ),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 12),

          // 用户名输入
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: _usernameError != null
                  ? Border.all(color: AppColors.error, width: 1)
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    '@',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    readOnly: showUsernameVipHint,
                    onTap: showUsernameVipHint
                        ? () => _showVipFeaturePrompt(
                              _groupEditText(
                                context,
                                zhCN: '开通 SVIP 后可设置公开群号和公开频道',
                                zhTW: '開通 SVIP 後可設定公開群號和公開頻道',
                                en: 'Activate SVIP to set public IDs.',
                              ),
                            )
                        : null,
                    onChanged: _checkUsername,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_]')),
                      LengthLimitingTextInputFormatter(32),
                    ],
                    decoration: InputDecoration(
                      hintText: isChannel
                          ? _groupEditText(
                              context,
                              zhCN: '频道号',
                              zhTW: '頻道號',
                              en: 'Channel ID',
                            )
                          : _groupEditText(
                              context,
                              zhCN: '群组号',
                              zhTW: '群組號',
                              en: 'Group ID',
                            ),
                      hintStyle:
                          TextStyle(color: AppColors.textTertiaryFor(context)),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      suffixIcon: _isCheckingUsername
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _usernameController.text.isNotEmpty
                              ? Icon(
                                  _isUsernameAvailable
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _isUsernameAvailable
                                      ? AppColors.success
                                      : AppColors.error,
                                )
                              : null,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 错误提示
          if (_usernameError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _usernameError!,
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),

          // 用户名规则说明
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _groupEditText(
                context,
                zhCN: showUsernameVipHint
                    ? 'SVIP 可设置公开群号和频道号。'
                    : '长度为 5-32 个字符，只能包含字母、数字和下划线。',
                zhTW: showUsernameVipHint
                    ? 'SVIP 可設定公開群號和頻道號。'
                    : '長度為 5-32 個字元，只能包含字母、數字和底線。',
                en: showUsernameVipHint
                    ? 'SVIP unlocks public group and channel IDs.'
                    : 'Use 5-32 characters. Letters, numbers, and underscores only.',
              ),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
          ),

          // 显示设置的用户名
          if (hasUsername && _isUsernameAvailable) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryWithOpacity(context, 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.alternate_email,
                      color: AppColors.primaryFor(context), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '@${_usernameController.text}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.linkFor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy,
                        color: AppColors.primaryFor(context), size: 20),
                    onPressed: () => _copyLink('@${_usernameController.text}'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionSection(
    bool isDark, {
    required bool canUseMemberProtection,
  }) {
    final showProtectionVipHint =
        !canUseMemberProtection && !_initialMemberProtection;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _groupEditText(
              context,
              zhCN: '权限设置',
              zhTW: '權限設定',
              en: 'Permissions',
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _PermissionTile(
                  icon: Icons.volume_off_outlined,
                  title: _groupEditText(
                    context,
                    zhCN: '全员禁言',
                    zhTW: '全員禁言',
                    en: 'Only admins can send messages',
                  ),
                  subtitle: _groupEditText(
                    context,
                    zhCN: '开启后仅管理员和创建者可发言',
                    zhTW: '開啟後僅管理員和建立者可發言',
                    en: 'Only admins and the owner can send messages.',
                  ),
                  value: !_canSendMessage,
                  onChanged: (v) => setState(() => _canSendMessage = !v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.photo_outlined,
                  title: _groupEditText(
                    context,
                    zhCN: '发送媒体',
                    zhTW: '傳送媒體',
                    en: 'Send Media',
                  ),
                  subtitle: _groupEditText(
                    context,
                    zhCN: '成员可以发送图片、视频和文件',
                    zhTW: '成員可以傳送圖片、影片和檔案',
                    en: 'Members can send images, videos, and files.',
                  ),
                  value: _canSendMedia,
                  onChanged: (v) => setState(() => _canSendMedia = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.link,
                  title: _groupEditText(
                    context,
                    zhCN: '发送链接',
                    zhTW: '傳送連結',
                    en: 'Send Links',
                  ),
                  subtitle: _groupEditText(
                    context,
                    zhCN: '成员可以发送链接预览',
                    zhTW: '成員可以傳送連結預覽',
                    en: 'Members can send link previews.',
                  ),
                  value: _canSendLinks,
                  onChanged: (v) => setState(() => _canSendLinks = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.person_add_outlined,
                  title: _groupEditText(
                    context,
                    zhCN: '添加成员',
                    zhTW: '新增成員',
                    en: 'Add Members',
                  ),
                  subtitle: _groupEditText(
                    context,
                    zhCN: '成员可以邀请其他人加入',
                    zhTW: '成員可以邀請其他人加入',
                    en: 'Members can invite other people to join.',
                  ),
                  value: _canAddMembers,
                  onChanged: (v) => setState(() => _canAddMembers = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.push_pin_outlined,
                  title: _groupEditText(
                    context,
                    zhCN: '置顶消息',
                    zhTW: '置頂訊息',
                    en: 'Pin Messages',
                  ),
                  subtitle: _groupEditText(
                    context,
                    zhCN: '允许普通成员置顶消息',
                    zhTW: '允許普通成員置頂訊息',
                    en: 'Allow regular members to pin messages.',
                  ),
                  value: _canPinMessages,
                  onChanged: (v) => setState(() => _canPinMessages = v),
                ),
                const Divider(height: 1),
                if (_chatDetail?.isOwner == true) ...[
                  _PermissionTile(
                    icon: Icons.badge_outlined,
                    title: _groupEditText(
                      context,
                      zhCN: '允许匿名发言',
                      zhTW: '允許匿名發言',
                      en: 'Allow anonymous messages',
                    ),
                    subtitle: _groupEditText(
                      context,
                      zhCN: '开启后成员可以用匿名身份在群里发消息',
                      zhTW: '開啟後成員可以用匿名身份在群裡發消息',
                      en: 'Members can send messages anonymously in this group.',
                    ),
                    value: _allowAnonymous,
                    onChanged: (v) => setState(() => _allowAnonymous = v),
                  ),
                  const Divider(height: 1),
                  _PermissionTile(
                    icon: Icons.forward_outlined,
                    title: _groupEditText(
                      context,
                      zhCN: '允许转发本群消息',
                      zhTW: '允許轉發本群訊息',
                      en: 'Allow forwarding group messages',
                    ),
                    subtitle: _groupEditText(
                      context,
                      zhCN: '关闭后普通成员不能把本群消息转发到其他会话',
                      zhTW: '關閉後普通成員不能把本群訊息轉發到其他會話',
                      en: 'When off, regular members cannot forward messages from this group.',
                    ),
                    value: _allowForward,
                    onChanged: (v) => setState(() => _allowForward = v),
                  ),
                  const Divider(height: 1),
                  _PermissionTile(
                    icon: Icons.history_outlined,
                    title: _groupEditText(
                      context,
                      zhCN: '历史消息',
                      zhTW: '歷史訊息',
                      en: 'History',
                    ),
                    subtitle: _groupEditText(
                      context,
                      zhCN: '关闭后，新进群的普通成员只能查看入群后的消息',
                      zhTW: '關閉後，新進群的普通成員只能查看入群後的訊息',
                      en: 'When off, new regular members only see messages sent after they joined.',
                    ),
                    value: _allowViewHistory,
                    onChanged: (v) => setState(() => _allowViewHistory = v),
                  ),
                  const Divider(height: 1),
                ],
                _PermissionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: _groupEditText(
                    context,
                    zhCN: '群成员保护',
                    zhTW: '群成員保護',
                    en: 'Protect Member List',
                  ),
                  subtitle: _groupEditText(
                    context,
                    zhCN: showProtectionVipHint
                        ? 'SVIP 可隐藏普通成员列表'
                        : '开启后普通成员只能看到管理员和群主，且无法点开成员资料',
                    zhTW: showProtectionVipHint
                        ? 'SVIP 可隱藏普通成員列表'
                        : '開啟後普通成員只能看到管理員和群主，且無法打開成員資料',
                    en: showProtectionVipHint
                        ? 'SVIP can hide the regular member list.'
                        : 'Regular members can only see admins and the owner, and cannot open member profiles.',
                  ),
                  value: _memberProtection,
                  onChanged: _setMemberProtection,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerSection(bool isDark, bool isChannel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text(
                    isChannel
                        ? _groupEditText(
                            context,
                            zhCN: '删除频道',
                            zhTW: '刪除頻道',
                            en: 'Delete Channel',
                          )
                        : _groupEditText(
                            context,
                            zhCN: '删除群组',
                            zhTW: '刪除群組',
                            en: 'Delete Group',
                          ),
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () => _showDeleteConfirmation(isChannel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _changeAvatar() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              _buildSheetItem(
                title: _groupEditText(
                  context,
                  zhCN: '拍照',
                  zhTW: '拍照',
                  en: 'Camera',
                ),
                icon: Icons.camera_alt_rounded,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromCamera();
                },
              ),
              _buildSheetItem(
                title: _groupEditText(
                  context,
                  zhCN: '相册',
                  zhTW: '相簿',
                  en: 'Album',
                ),
                icon: Icons.photo_rounded,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromGallery();
                },
              ),
              if (_chat?.avatar != null || _newAvatarUrl != null)
                _buildSheetItem(
                  title: _groupEditText(
                    context,
                    zhCN: '删除照片',
                    zhTW: '刪除照片',
                    en: 'Remove Photo',
                  ),
                  icon: Icons.delete_rounded,
                  isDark: isDark,
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _newAvatarUrl = '');
                  },
                ),
              Container(
                  height: 8,
                  color: isDark ? Colors.black26 : const Color(0xFFF2F2F7)),
              _buildSheetItem(
                title: _groupEditText(
                  context,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
                isDark: isDark,
                onTap: () => Navigator.pop(context),
                isBold: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetItem({
    required String title,
    IconData? icon,
    required bool isDark,
    VoidCallback? onTap,
    bool isDestructive = false,
    bool isBold = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 24,
                color:
                    isDestructive ? Colors.red : AppColors.primaryFor(context),
              ),
              const SizedBox(width: 16),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                color: isDestructive
                    ? Colors.red
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatarFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (image != null) {
      await _cropAndUploadAvatar(image.path);
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (image != null) {
      await _cropAndUploadAvatar(image.path);
    }
  }

  Future<void> _cropAndUploadAvatar(String imagePath) async {
    final isChannel = _chat?.type == ChatItemType.channel;

    // 使用纯 Flutter 裁剪器对话框
    final croppedPath = await showAvatarCropDialog(
      context: context,
      imagePath: imagePath,
      title: isChannel
          ? _groupEditText(
              context,
              zhCN: '裁剪频道头像',
              zhTW: '裁剪頻道頭像',
              en: 'Crop Channel Avatar',
            )
          : _groupEditText(
              context,
              zhCN: '裁剪群组头像',
              zhTW: '裁剪群組頭像',
              en: 'Crop Group Avatar',
            ),
    );

    if (croppedPath != null) {
      await _uploadGroupAvatar(XFile(croppedPath));
    }
  }

  Future<void> _uploadGroupAvatar(XFile image) async {
    setState(() => _isSaving = true);

    try {
      final uploadService = ref.read(uploadServiceProvider);
      final avatarUrl = await uploadService.uploadAvatar(image);

      if (avatarUrl != null) {
        setState(() => _newAvatarUrl = avatarUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _groupEditText(
                  context,
                  zhCN: '头像已上传，请保存以生效',
                  zhTW: '頭像已上傳，請儲存後生效',
                  en: 'Avatar uploaded. Save to apply the change.',
                ),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _groupEditText(
                  context,
                  zhCN: '上传头像失败',
                  zhTW: '上傳頭像失敗',
                  en: 'Failed to upload avatar',
                ),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_groupEditText(
                context,
                zhCN: '上传失败',
                zhTW: '上傳失敗',
                en: 'Upload failed',
              )}: $e',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _checkUsername(String value) async {
    if (value.isEmpty) {
      setState(() {
        _usernameError = null;
        _isUsernameAvailable = true;
        _isCheckingUsername = false;
      });
      return;
    }

    if (value.length < 5) {
      setState(() {
        _usernameError = _groupEditText(
          context,
          zhCN: '用户名至少需要 5 个字符',
          zhTW: '使用者名稱至少需要 5 個字元',
          en: 'Username must be at least 5 characters',
        );
        _isUsernameAvailable = false;
        _isCheckingUsername = false;
      });
      return;
    }

    if (!RegExp(r'^[a-zA-Z]').hasMatch(value)) {
      setState(() {
        _usernameError = _groupEditText(
          context,
          zhCN: '用户名必须以字母开头',
          zhTW: '使用者名稱必須以字母開頭',
          en: 'Username must start with a letter',
        );
        _isUsernameAvailable = false;
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    // 模拟检查用户名是否可用
    await Future.delayed(const Duration(milliseconds: 500));

    // 模拟一些已被占用的用户名
    final takenUsernames = ['admin', 'test', 'official', 'telegram'];
    final isAvailable = !takenUsernames.contains(value.toLowerCase());

    if (mounted) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = isAvailable;
        _usernameError = isAvailable
            ? null
            : _groupEditText(
                context,
                zhCN: '此用户名已被占用',
                zhTW: '此使用者名稱已被佔用',
                en: 'This username is already taken',
              );
      });
    }
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _groupEditText(
            context,
            zhCN: '链接已复制',
            zhTW: '連結已複製',
            en: 'Link copied',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showQRCode(String id) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _groupEditText(
            context,
            zhCN: '二维码',
            zhTW: '二維碼',
            en: 'QR Code',
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 模拟二维码
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  Icons.qr_code_2,
                  size: 150,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              id,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryFor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _groupEditText(
                context,
                zhCN: '关闭',
                zhTW: '關閉',
                en: 'Close',
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 保存二维码
            },
            child: Text(
              _groupEditText(
                context,
                zhCN: '保存',
                zhTW: '儲存',
                en: 'Save',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(bool isChannel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isChannel
              ? _groupEditText(
                  context,
                  zhCN: '删除频道',
                  zhTW: '刪除頻道',
                  en: 'Delete Channel',
                )
              : _groupEditText(
                  context,
                  zhCN: '删除群组',
                  zhTW: '刪除群組',
                  en: 'Delete Group',
                ),
        ),
        content: Text(
          isChannel
              ? _groupEditText(
                  context,
                  zhCN: '确定要删除此频道吗？所有消息和成员将被清除，此操作不可撤销。',
                  zhTW: '確定要刪除此頻道嗎？所有訊息和成員將被清除，此操作無法撤銷。',
                  en: 'Delete this channel? All messages and members will be removed. This cannot be undone.',
                )
              : _groupEditText(
                  context,
                  zhCN: '确定要删除此群组吗？所有消息和成员将被清除，此操作不可撤销。',
                  zhTW: '確定要刪除此群組嗎？所有訊息和成員將被清除，此操作無法撤銷。',
                  en: 'Delete this group? All messages and members will be removed. This cannot be undone.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _groupEditText(
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
              ref.read(chatListProvider.notifier).deleteChat(_chat!.id);
              // 返回聊天列表
              context.go('/home');
            },
            child: Text(
              _groupEditText(
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

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _groupEditText(
              context,
              zhCN: '名称不能为空',
              zhTW: '名稱不能為空',
              en: 'Name cannot be empty',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_isSaving) return;
    // 公开身份和成员保护只在“本次开启”时校验，避免阻断已有配置的正常编辑。
    if (_isEnablingPublicIdentity) {
      final allowed = await _ensureVipFeature(
        _canSetPublicIdentity,
        message: _groupEditText(
          context,
          zhCN: '开通 SVIP 后可设置公开群号和公开频道',
          zhTW: '開通 SVIP 後可設定公開群號和公開頻道',
          en: 'Activate SVIP to set public IDs.',
        ),
      );
      if (!allowed) return;
    }
    if (_isEnablingMemberProtection) {
      final allowed = await _ensureVipFeature(
        _canEnableMemberProtection,
        message: _groupEditText(
          context,
          zhCN: '开通 SVIP 后可开启群成员保护',
          zhTW: '開通 SVIP 後可開啟群成員保護',
          en: 'Activate SVIP to protect the member list.',
        ),
      );
      if (!allowed) return;
    }
    setState(() => _isSaving = true);

    try {
      // 调用 API 保存
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.updateChat(
        widget.chatId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        avatar: _newAvatarUrl,
        username: _usernameController.text.trim().isNotEmpty
            ? _usernameController.text.trim()
            : null,
        isPublic: _isPublic,
        joinApproval: _joinApproval,
        canSendMessage: _canSendMessage,
        canSendMedia: _canSendMedia,
        canSendLinks: _canSendLinks,
        canAddMembers: _canAddMembers,
        canPinMessages: _canPinMessages,
        allowAnonymous: _chatDetail?.isOwner == true ? _allowAnonymous : null,
        allowForward: _chatDetail?.isOwner == true ? _allowForward : null,
        allowViewHistory:
            _chatDetail?.isOwner == true ? _allowViewHistory : null,
        memberProtection: _memberProtection,
      );

      if (response.isSuccess) {
        // 更新本地状态，转换头像为完整 URL
        String? fullAvatarUrl = _newAvatarUrl;
        if (fullAvatarUrl != null && fullAvatarUrl.isNotEmpty) {
          fullAvatarUrl = ApiConfig.getMediaUrl(fullAvatarUrl);
        }

        final updatedChat = _chat!.copyWith(
          name: _nameController.text.trim(),
          description: _descController.text.trim().isNotEmpty
              ? _descController.text.trim()
              : null,
          avatar: fullAvatarUrl ?? _chat!.avatar,
        );
        ref.read(chatListProvider.notifier).updateChat(updatedChat);

        // 本地列表只更新基础展示字段，完整权限和公开配置重新从详情接口获取。
        ref.invalidate(chatDetailProvider(widget.chatId));

        HapticFeedback.mediumImpact();
        if (mounted) {
          // 桌面端关闭面板，移动端 pop
          if (widget.isDesktopPanel) {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          } else {
            Navigator.pop(context);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _groupEditText(
                  context,
                  zhCN: '已保存',
                  zhTW: '已儲存',
                  en: 'Saved',
                ),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _groupEditServerMessage(
                  response.message,
                  fallbackEn: 'Failed to save',
                ),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_groupEditText(
                context,
                zhCN: '保存失败',
                zhTW: '儲存失敗',
                en: 'Failed to save',
              )}: $e',
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

/// 权限开关组件
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
      secondary: Icon(icon, color: AppColors.primaryFor(context)),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primaryFor(context),
    );
  }
}
