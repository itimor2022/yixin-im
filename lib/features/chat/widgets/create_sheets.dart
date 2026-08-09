// 文件用途：提供 CreateGroupSheet 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 CreateGroupSheet，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
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

String _createSheetText(
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

String _cleanCreateSheetError(Object error) {
  return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
}

bool _isVipCreateError(String message) {
  final lower = message.toLowerCase();
  return message.contains('VIP') ||
      message.contains('SVIP') ||
      message.contains('会员') ||
      lower.contains('vip');
}

void _showCreateSheetError(
  BuildContext context, {
  required Object error,
  required String fallback,
}) {
  final message = _cleanCreateSheetError(error);
  final isVipError = _isVipCreateError(message);
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(isVipError && message.isNotEmpty ? message : fallback),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      showCloseIcon: true,
      closeIconColor: Colors.white,
      action: isVipError
          ? SnackBarAction(
              label: _createSheetText(
                context,
                zhCN: '去开通',
                zhTW: '去開通',
                en: 'Open',
              ),
              textColor: Colors.white,
              onPressed: () {
                messenger.hideCurrentSnackBar();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                router.push('/vip');
              },
            )
          : null,
    ),
  );
}

/// 显示创建群组的底部弹窗
void showCreateGroupSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final usesFloatingNav = FloatingNavLayout.isEnabledForContext(context);
  if (usesFloatingNav) {
    container.read(floatingNavHiddenProvider.notifier).state = true;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const CreateGroupSheet(),
  ).whenComplete(() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    if (usesFloatingNav) {
      container.read(floatingNavHiddenProvider.notifier).state = false;
    }
  });
}

/// 显示创建频道的底部弹窗
void showCreateChannelSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final usesFloatingNav = FloatingNavLayout.isEnabledForContext(context);
  if (usesFloatingNav) {
    container.read(floatingNavHiddenProvider.notifier).state = true;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const CreateChannelSheet(),
  ).whenComplete(() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    if (usesFloatingNav) {
      container.read(floatingNavHiddenProvider.notifier).state = false;
    }
  });
}

// ==================== 创建群组 ====================

// 关键声明：create sheets 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
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

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
        if (PlatformUtils.useDesktopLayout(context)) {
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
      _showCreateSheetError(
        context,
        error: e,
        fallback: l10n.createGroupFailed,
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
    final floatingBottomSpace = FloatingNavLayout.isEnabledForContext(context)
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
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
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
                                  ? AppColors.linkFor(context)
                                  : AppColors.textTertiaryFor(context),
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
                          color: AppColors.primaryWithOpacity(context, 0.15),
                        ),
                        child: _avatarPath != null
                            ? Image.file(
                                File(_avatarPath!),
                                fit: BoxFit.cover,
                                width: 60,
                                height: 60,
                              )
                            : Icon(
                                Icons.camera_alt,
                                color: AppColors.linkFor(context),
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
                        hintText: l10n.groupName,
                        hintStyle: TextStyle(
                          color: AppColors.inputHintFor(context),
                        ),
                        border: InputBorder.none,
                      ),
                      style: TextStyle(
                        fontSize: 18,
                        color: AppColors.textPrimaryFor(context),
                      ),
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
                    hintText: _createSheetText(
                      context,
                      zhCN: '搜索好友',
                      zhTW: '搜尋好友',
                      en: 'Search Friends',
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintStyle: TextStyle(
                      color: AppColors.inputHintFor(context),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: TextStyle(color: AppColors.textPrimaryFor(context)),
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
                          ? _createSheetText(
                              context,
                              zhCN: '后台已开启“非好友不可拉群”，这里只显示好友联系人',
                              zhTW: '後台已開啟「非好友不可拉群」，這裡只顯示好友聯絡人',
                              en: 'The admin has enabled "Friends only for group invites", so only friends are shown here',
                            )
                          : _createSheetText(
                              context,
                              zhCN: '按昵称、备注或用户名搜索好友并邀请入群',
                              zhTW: '按暱稱、備註或用戶名搜尋好友並邀請入群',
                              en: 'Search friends by nickname, remark, or username and invite them to the group',
                            ),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ),
                  if (!_isLoadingContacts)
                    TextButton(
                      onPressed: _reloadContacts,
                      child: Text(
                        _createSheetText(
                          context,
                          zhCN: '刷新好友',
                          zhTW: '重新整理好友',
                          en: 'Refresh Friends',
                        ),
                      ),
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
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryFor(context),
                              ),
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
                      color: AppColors.linkFor(context),
                    ),
                  ),
                  if (_selectedContactUuids.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${l10n.selectedCount} ${_selectedContactUuids.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
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
                                  color: AppColors.textTertiaryFor(context),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  searchQuery.isNotEmpty
                                      ? _createSheetText(
                                          context,
                                          zhCN: '未找到匹配的好友',
                                          zhTW: '找不到符合的好友',
                                          en: 'No matching friends found',
                                        )
                                      : _createSheetText(
                                          context,
                                          zhCN: '暂无可邀请的好友成员',
                                          zhTW: '暫無可邀請的好友成員',
                                          en: 'No friends available to invite',
                                        ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.textSecondaryFor(context),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  requireFriendOnly
                                      ? _createSheetText(
                                          context,
                                          zhCN: '当前后台限制为仅可邀请好友入群，请先添加好友后再创建群聊',
                                          zhTW: '目前後台限制為僅可邀請好友入群，請先新增好友後再建立群聊',
                                          en: 'The current admin policy only allows inviting friends to groups. Add friends first before creating the group',
                                        )
                                      : _createSheetText(
                                          context,
                                          zhCN: '请先添加好友，或下拉刷新联系人列表后重试',
                                          zhTW: '請先新增好友，或下拉重新整理聯絡人列表後再試',
                                          en: 'Add friends first, or pull down to refresh the contact list and try again',
                                        ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondaryFor(context),
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
                              titleTextStyle: TextStyle(
                                fontSize: 16,
                                color: AppColors.textPrimaryFor(context),
                              ),
                              subtitle: Text(
                                contact.isOnline
                                    ? l10n.online
                                    : l10n.recentlyOnline,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: contact.isOnline
                                      ? AppColors.online
                                      : AppColors.textSecondaryFor(context),
                                ),
                              ),
                              trailing: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryFor(context)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primaryFor(context)
                                        : AppColors.textTertiaryFor(context),
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
        if (PlatformUtils.useDesktopLayout(context)) {
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
      _showCreateSheetError(
        context,
        error: e,
        fallback: l10n.createChannelFailed,
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final floatingBottomSpace = FloatingNavLayout.isEnabledForContext(context)
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
                                  ? AppColors.linkFor(context)
                                  : AppColors.textTertiaryFor(context),
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
                          color: AppColors.primaryWithOpacity(context, 0.15),
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
                                color: AppColors.linkFor(context),
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
                        hintStyle: TextStyle(
                          color: AppColors.inputHintFor(context),
                        ),
                        border: InputBorder.none,
                      ),
                      style: TextStyle(
                        fontSize: 18,
                        color: AppColors.textPrimaryFor(context),
                      ),
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
                  hintStyle: TextStyle(
                    color: AppColors.inputHintFor(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: TextStyle(color: AppColors.textPrimaryFor(context)),
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
                      ? AppColors.primaryWithOpacity(context, 0.15)
                      : AppColors.inputBackgroundFor(context),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? AppColors.linkFor(context)
                      : AppColors.textTertiaryFor(context),
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
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
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
                    color: isSelected
                        ? AppColors.primaryFor(context)
                        : AppColors.textTertiaryFor(context),
                    width: 2,
                  ),
                  color: isSelected
                      ? AppColors.primaryFor(context)
                      : Colors.transparent,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: AppColors.onPrimaryFor(context),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
