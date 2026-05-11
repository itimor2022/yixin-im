import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/avatar_crop_page.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../home/pages/home_desktop_page.dart';
import '../pages/chat_detail_page.dart' show ChatType;
import '../providers/chat_provider.dart';

/// 显示创建群组的底部弹窗
void showCreateGroupSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const CreateGroupSheet(),
  );
}

/// 显示创建频道的底部弹窗
void showCreateChannelSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const CreateChannelSheet(),
  );
}

// ==================== 创建群组 ====================

class CreateGroupSheet extends ConsumerStatefulWidget {
  const CreateGroupSheet({super.key});

  @override
  ConsumerState<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<CreateGroupSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedContactUuids = {}; // 存储联系人的 UUID
  String? _avatarPath; // 本地头像路径
  Uint8List? _avatarBytes;
  String? _avatarUrl; // 上传后的URL
  bool _isPublic = false; // 公开/私密设置
  bool _isLoadingContacts = true;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _isLoadingContacts = ref.read(contactListProvider).isEmpty;
    _ensureContactsLoaded();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _nameController.text.trim().isNotEmpty &&
      _selectedContactUuids.isNotEmpty;
  bool _isCreating = false;

  Future<void> _ensureContactsLoaded() async {
    final notifier = ref.read(contactListProvider.notifier);
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

  Future<void> _reloadContacts() async {
    final notifier = ref.read(contactListProvider.notifier);
    setState(() => _isLoadingContacts = true);
    try {
      await notifier.loadFromServer(force: true);
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

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations(ref.read(languageProvider));
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (image != null && mounted) {
      // 使用裁剪器
      final croppedPath = await showAvatarCropDialog(
        context: context,
        imagePath: image.path,
        title: l10n.cropGroupAvatar,
      );

      if (croppedPath != null && mounted) {
        setState(() => _avatarPath = croppedPath);
      }
    }
  }

  Future<void> _createGroup() async {
    if (!_canCreate || _isCreating) return;

    setState(() => _isCreating = true);

    try {
      // 如果选择了头像，先上传
      String? uploadedAvatarUrl;
      if (_avatarPath != null) {
        final uploadService = ref.read(uploadServiceProvider);
        uploadedAvatarUrl = await uploadService.uploadAvatar(
          XFile(_avatarPath!),
        );
      }

      final chat =
          await ref.read(chatListProvider.notifier).createGroupFromServer(
                name: _nameController.text.trim(),
                memberIds: _selectedContactUuids.toList(),
                avatar: uploadedAvatarUrl,
                isPublic: _isPublic,
              );

      if (!mounted) return;
      Navigator.pop(context);

      if (chat != null) {
        if (PlatformUtils.isDesktop) {
          // 桌面/Web 端：通过 Provider 更新右侧面板，避免路由替换整个布局
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: chat.name,
            avatar: chat.avatar,
            chatType: ChatType.group,
          );
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
        } else {
          context.push(
            '/chat/${chat.id}?name=${Uri.encodeComponent(chat.name)}&type=group',
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations(ref.read(languageProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.createGroupFailed}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contacts = ref.watch(contactListProvider);
    final systemSettingsAsync = ref.watch(systemSettingsProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final requireFriendOnly = systemSettingsAsync.maybeWhen(
      data: (settings) => settings.groupInviteRequireFriend,
      orElse: () => false,
    );
    final searchQuery = _searchQuery.trim().toLowerCase();
    final floatingBottomSpace = FloatingNavLayout.isEnabled
        ? FloatingNavLayout.reservedSpace(context, extra: 8)
        : 100.0;
    final contactsByUuid = {
      for (final contact in contacts)
        if ((contact.uuid ?? '').trim().isNotEmpty)
          contact.uuid!.trim(): contact,
    };
    final selectedContacts = _selectedContactUuids
        .map((uuid) => contactsByUuid[uuid])
        .whereType<ContactItem>()
        .toList();
    final filteredContacts = contacts.where((contact) {
      final uuid = contact.uuid?.trim() ?? '';
      if (uuid.isEmpty) return false;
      return contact.matchesQuery(searchQuery);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // 顶部栏
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  Expanded(
                    child: Text(
                      l10n.createGroup,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        (_canCreate && !_isCreating) ? _createGroup : null,
                    child: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            l10n.create,
                            style: TextStyle(
                              color: _canCreate
                                  ? AppColors.primary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // 群名称输入
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                        ),
                        child: _avatarPath != null
                            ? Image.file(
                                File(_avatarPath!),
                                fit: BoxFit.cover,
                                width: 60,
                                height: 60,
                              )
                            : Icon(Icons.camera_alt, color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: l10n.groupName,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 群组类型选择 -
            _GroupTypeOption(
              icon: Icons.public,
              title: l10n.publicGroup,
              subtitle: l10n.anyoneCanJoin,
              isSelected: _isPublic,
              onTap: () => setState(() => _isPublic = true),
            ),
            _GroupTypeOption(
              icon: Icons.lock_outline,
              title: l10n.privateGroup,
              subtitle: l10n.inviteOnly,
              isSelected: !_isPublic,
              onTap: () => setState(() => _isPublic = false),
            ),

            const Divider(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkInputBackground
                      : AppColors.lightInputBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: '搜索好友',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      requireFriendOnly
                          ? '后台已开启“非好友不可拉群”，这里只显示好友联系人'
                          : '按昵称、备注或用户名搜索好友并邀请入群',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                  if (!_isLoadingContacts)
                    TextButton(
                      onPressed: _reloadContacts,
                      child: const Text('刷新好友'),
                    ),
                ],
              ),
            ),

            // 已选成员
            if (selectedContacts.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: selectedContacts.length,
                  itemBuilder: (context, index) {
                    final contact = selectedContacts[index];
                    final contactUuid = contact.uuid!.trim();
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              AvatarWidget(
                                avatar: contact.avatar,
                                name: contact.name,
                                userId: contact.id,
                                size: 50,
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _selectedContactUuids.remove(
                                      contactUuid,
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 50,
                            child: Text(
                              contact.name,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
            ],

            // 选择成员标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    l10n.selectMembers,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  if (_selectedContactUuids.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${l10n.selectedCount} ${_selectedContactUuids.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 联系人列表
            Expanded(
              child: _isLoadingContacts
                  ? const Center(child: CircularProgressIndicator())
                  : filteredContacts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.group_outlined,
                                  size: 56,
                                  color: AppColors.lightTextTertiary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  searchQuery.isNotEmpty
                                      ? '未找到匹配的好友'
                                      : '暂无可邀请的好友成员',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  requireFriendOnly
                                      ? '当前后台限制为仅可邀请好友入群，请先添加好友后再创建群聊'
                                      : '请先添加好友，或下拉刷新联系人列表后重试',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.only(bottom: floatingBottomSpace),
                          itemCount: filteredContacts.length,
                          itemBuilder: (context, index) {
                            final contact = filteredContacts[index];
                            final contactUuid = contact.uuid!.trim();
                            final isSelected = _selectedContactUuids.contains(
                              contactUuid,
                            );
                            return ListTile(
                              leading: AvatarWidget(
                                avatar: contact.avatar,
                                name: contact.name,
                                userId: contact.id,
                                size: 44,
                              ),
                              title: Text(contact.name),
                              subtitle: Text(
                                contact.isOnline
                                    ? l10n.online
                                    : l10n.recentlyOnline,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: contact.isOnline
                                      ? AppColors.online
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                              trailing: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.lightTextTertiary,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedContactUuids.remove(contactUuid);
                                  } else {
                                    _selectedContactUuids.add(contactUuid);
                                  }
                                });
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

// ==================== 创建频道 ====================

class CreateChannelSheet extends ConsumerStatefulWidget {
  const CreateChannelSheet({super.key});

  @override
  ConsumerState<CreateChannelSheet> createState() => _CreateChannelSheetState();
}

class _CreateChannelSheetState extends ConsumerState<CreateChannelSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _isPublic = true;
  String? _avatarPath; // 本地头像路径
  Uint8List? _avatarBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _canCreate => _nameController.text.trim().isNotEmpty;
  bool _isCreating = false;

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations(ref.read(languageProvider));
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (image != null && mounted) {
      // 使用裁剪器
      final croppedPath = await showAvatarCropDialog(
        context: context,
        imagePath: image.path,
        title: l10n.cropChannelAvatar,
      );

      if (croppedPath != null && mounted) {
        setState(() => _avatarPath = croppedPath);
      }
    }
  }

  Future<void> _createChannel() async {
    if (!_canCreate || _isCreating) return;

    setState(() => _isCreating = true);

    try {
      // 如果选择了头像，先上传
      String? uploadedAvatarUrl;
      if (_avatarPath != null) {
        final uploadService = ref.read(uploadServiceProvider);
        uploadedAvatarUrl = await uploadService.uploadAvatar(
          XFile(_avatarPath!),
        );
      }

      final chat =
          await ref.read(chatListProvider.notifier).createChannelFromServer(
                name: _nameController.text.trim(),
                description: _descController.text.trim().isNotEmpty
                    ? _descController.text.trim()
                    : null,
                isPublic: _isPublic,
                avatar: uploadedAvatarUrl,
              );

      if (!mounted) return;
      Navigator.pop(context);

      if (chat != null) {
        if (PlatformUtils.isDesktop) {
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: chat.name,
            avatar: chat.avatar,
            chatType: ChatType.channel,
          );
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
        } else {
          context.push(
            '/chat/${chat.id}?name=${Uri.encodeComponent(chat.name)}&type=channel',
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations(ref.read(languageProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.createChannelFailed}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final floatingBottomSpace = FloatingNavLayout.isEnabled
        ? FloatingNavLayout.reservedSpace(context, extra: 8)
        : 100.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: scrollController,
          children: [
            // 顶部栏
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  Expanded(
                    child: Text(
                      l10n.createChannel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        (_canCreate && !_isCreating) ? _createChannel : null,
                    child: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            l10n.create,
                            style: TextStyle(
                              color: _canCreate
                                  ? AppColors.primary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // 频道图标和名称
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: ClipOval(
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                        ),
                        child: _avatarPath != null
                            ? Image.file(
                                File(_avatarPath!),
                                fit: BoxFit.cover,
                                width: 70,
                                height: 70,
                              )
                            : Icon(
                                Icons.campaign,
                                color: AppColors.primary,
                                size: 32,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: l10n.channelName,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),

            // 频道描述
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _descController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: l10n.channelDescriptionOptional,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 频道类型 -
            _GroupTypeOption(
              icon: Icons.public,
              title: l10n.publicChannel,
              subtitle: l10n.anyoneCanSubscribe,
              isSelected: _isPublic,
              onTap: () => setState(() => _isPublic = true),
            ),
            _GroupTypeOption(
              icon: Icons.lock_outline,
              title: l10n.privateChannel,
              subtitle: l10n.inviteOnlySubscribe,
              isSelected: !_isPublic,
              onTap: () => setState(() => _isPublic = false),
            ),

            SizedBox(height: floatingBottomSpace),
          ],
        ),
      ),
    );
  }
}

///  的群组类型选项
class _GroupTypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _GroupTypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 图标
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isSelected ? AppColors.primary : Colors.grey,
                ),
              ),
              const SizedBox(width: 16),
              // 文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 选中圆圈
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isSelected ? AppColors.primary : Colors.grey.shade400,
                    width: 2,
                  ),
                  color: isSelected ? AppColors.primary : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
