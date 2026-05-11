import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/upload_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/avatar_crop_page.dart';
import '../providers/chat_provider.dart';
import '../../home/pages/home_desktop_page.dart';

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
  bool _memberProtection = false;
  
  // 公开/私密设置
  bool _isPublic = false;
  bool _joinApproval = false; // 加入需要管理员审批
  
  // 头像
  String? _newAvatarUrl;
  
  api.Chat? _chatDetail;
  ChatItem? _chat;
  bool _dataLoaded = false;

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
      _memberProtection = chatDetail.memberProtection;
      
      // 加载公开/私密设置
      _isPublic = chatDetail.isPublic;
      _joinApproval = chatDetail.joinApproval;
      
      _dataLoaded = true;
    } else if (_chat != null && !_dataLoaded) {
      _nameController.text = _chat!.name;
      _descController.text = _chat!.description ?? '';
      _dataLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.chatId));
    
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
        appBar: AppBar(title: const Text('加载中...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_chat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑')),
        body: const Center(child: Text('聊天不存在')),
      );
    }

    final isChannel = _chat!.type == ChatItemType.channel;
    final title = isChannel ? '编辑频道' : '编辑群组';

    // 桌面端面板模式：只返回内容
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, isChannel);
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: Text('完成', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _buildBody(isDark, isChannel),
    );
  }

  Widget _buildBody(bool isDark, bool isChannel) {
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
                          '保存更改',
                          style: TextStyle(
                            color: AppColors.primary,
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
              _buildTypeSection(isDark, isChannel),
              
              const SizedBox(height: 24),
              
              // 链接设置
              _buildLinkSection(isDark, isChannel),
              
              const SizedBox(height: 24),
              
              // 加入/订阅设置 - 需要管理员审批
              _buildJoinSettingsSection(isDark, isChannel),
              
              const SizedBox(height: 24),
              
              // 权限设置（群组）
              if (!isChannel) _buildPermissionSection(isDark),
              
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
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
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
                hintText: _chat!.type == ChatItemType.channel ? '频道名称' : '群组名称',
                border: InputBorder.none,
                hintStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
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
            '简介',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
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
                hintText: '添加简介...',
                hintStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
                counterStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSection(bool isDark, bool isChannel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChannel ? '频道类型' : '群组类型',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
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
                  onChanged: (v) => setState(() => _isPublic = v ?? false),
                  title: Text(
                    isChannel ? '公开频道' : '公开群组',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isChannel 
                        ? '任何人都可以搜索并订阅此频道'
                        : '任何人都可以搜索并加入此群组',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                const Divider(height: 1),
                // 私密频道/群组
                RadioListTile<bool>(
                  value: false,
                  groupValue: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v ?? false),
                  title: Text(
                    isChannel ? '私密频道' : '私密群组',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isChannel 
                        ? '只有被邀请才能订阅，不可被搜索'
                        : '只有被邀请才能加入，不可被搜索',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  activeColor: AppColors.primary,
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
            isChannel ? '订阅设置' : '加入设置',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
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
                isChannel ? '订阅需要审批' : '加入需要审批',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                isChannel 
                    ? '新订阅者需要管理员批准才能订阅此频道'
                    : '新成员需要管理员或群主批准才能加入',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
              activeColor: AppColors.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkSection(bool isDark, bool isChannel) {
    final hasUsername = _usernameController.text.isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChannel ? '频道号' : '群组号',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          
          // 说明
          Text(
            isChannel 
                ? '设置频道号后，其他人可以通过搜索频道号找到您的频道。'
                : '设置群组号后，其他人可以通过搜索群组号找到您的群组。',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    onChanged: _checkUsername,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                      LengthLimitingTextInputFormatter(32),
                    ],
                    decoration: InputDecoration(
                      hintText: isChannel ? '频道号' : '群组号',
                      hintStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      suffixIcon: _isCheckingUsername
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _usernameController.text.isNotEmpty
                              ? Icon(
                                  _isUsernameAvailable ? Icons.check_circle : Icons.error,
                                  color: _isUsernameAvailable ? AppColors.success : AppColors.error,
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
              '长度为 5-32 个字符，只能包含字母、数字和下划线。',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ),
          ),
          
          // 显示设置的用户名
          if (hasUsername && _isUsernameAvailable) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.alternate_email, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '@${_usernameController.text}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, color: AppColors.primary, size: 20),
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

  Widget _buildPermissionSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '权限设置',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
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
                  title: '全员禁言',
                  subtitle: '开启后仅管理员和创建者可发言',
                  value: !_canSendMessage,
                  onChanged: (v) => setState(() => _canSendMessage = !v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.photo_outlined,
                  title: '发送媒体',
                  subtitle: '成员可以发送图片、视频和文件',
                  value: _canSendMedia,
                  onChanged: (v) => setState(() => _canSendMedia = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.link,
                  title: '发送链接',
                  subtitle: '成员可以发送链接预览',
                  value: _canSendLinks,
                  onChanged: (v) => setState(() => _canSendLinks = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.person_add_outlined,
                  title: '添加成员',
                  subtitle: '成员可以邀请其他人加入',
                  value: _canAddMembers,
                  onChanged: (v) => setState(() => _canAddMembers = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.push_pin_outlined,
                  title: '置顶消息',
                  subtitle: '允许普通成员置顶消息',
                  value: _canPinMessages,
                  onChanged: (v) => setState(() => _canPinMessages = v),
                ),
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: '群成员保护',
                  subtitle: '开启后普通成员只能看到管理员和群主，且无法点开成员资料',
                  value: _memberProtection,
                  onChanged: (v) => setState(() => _memberProtection = v),
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
                    isChannel ? '删除频道' : '删除群组',
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
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
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
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              _buildSheetItem(
                title: '拍照', 
                icon: Icons.camera_alt_rounded, 
                isDark: isDark, 
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromCamera();
                },
              ),
              _buildSheetItem(
                title: '相册', 
                icon: Icons.photo_rounded, 
                isDark: isDark, 
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromGallery();
                },
              ),
              if (_chat?.avatar != null || _newAvatarUrl != null)
                _buildSheetItem(
                  title: '删除照片', 
                  icon: Icons.delete_rounded, 
                  isDark: isDark, 
                  isDestructive: true, 
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _newAvatarUrl = '');
                  },
                ),
              Container(height: 8, color: isDark ? Colors.black26 : const Color(0xFFF2F2F7)),
              _buildSheetItem(title: '取消', isDark: isDark, onTap: () => Navigator.pop(context), isBold: true),
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
                color: isDestructive ? Colors.red : AppColors.primary,
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
      title: isChannel ? '裁剪频道头像' : '裁剪群组头像',
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
              content: const Text('头像已上传，请保存以生效'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('上传头像失败'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        _usernameError = '用户名至少需要 5 个字符';
        _isUsernameAvailable = false;
        _isCheckingUsername = false;
      });
      return;
    }

    if (!RegExp(r'^[a-zA-Z]').hasMatch(value)) {
      setState(() {
        _usernameError = '用户名必须以字母开头';
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
        _usernameError = isAvailable ? null : '此用户名已被占用';
      });
    }
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('链接已复制'),
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
        title: const Text('二维码', textAlign: TextAlign.center),
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
                  color: AppColors.lightTextPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              id,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 保存二维码
            },
            child: const Text('保存'),
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
        title: Text(isChannel ? '删除频道' : '删除群组'),
        content: Text(
          isChannel 
              ? '确定要删除此频道吗？所有消息和成员将被清除，此操作不可撤销。'
              : '确定要删除此群组吗？所有消息和成员将被清除，此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatListProvider.notifier).deleteChat(_chat!.id);
              // 返回聊天列表
              context.go('/home');
            },
            child: Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('名称不能为空'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // 调用 API 保存
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.updateChat(
        widget.chatId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        avatar: _newAvatarUrl,
        username: _usernameController.text.trim().isNotEmpty ? _usernameController.text.trim() : null,
        isPublic: _isPublic,
        joinApproval: _joinApproval,
        canSendMessage: _canSendMessage,
        canSendMedia: _canSendMedia,
        canSendLinks: _canSendLinks,
        canAddMembers: _canAddMembers,
        canPinMessages: _canPinMessages,
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
          description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
          avatar: fullAvatarUrl ?? _chat!.avatar,
        );
        ref.read(chatListProvider.notifier).updateChat(updatedChat);
        
        // 刷新 chatDetailProvider 缓存
        ref.invalidate(chatDetailProvider(widget.chatId));
        
        HapticFeedback.mediumImpact();
        if (mounted) {
          // 桌面端关闭面板，移动端 pop
          if (widget.isDesktopPanel) {
            ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
          } else {
            Navigator.pop(context);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('已保存'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? '保存失败'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      secondary: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
    );
  }
}
