import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/avatar_crop_page.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../home/pages/home_desktop_page.dart';
import '../pages/chat_detail_page.dart' show ChatType;
import '../providers/chat_provider.dart';

// ================== 视觉 Token（与"我的"/"网络线路"页对齐） ==================
const Color _kPrimary = AppColors.primary;
const Color _kBgLight = Color(0xFFF7F8FA);
const Color _kBgDark = Color(0xFF0E1015);
const Color _kSurfaceLight = Colors.white;
const Color _kSurfaceDark = Color(0xFF161821);
const Color _kTitleLight = Color(0xFF111827);
const Color _kSubLight = Color(0xFF6B7280);
const Color _kMutedLight = Color(0xFF9CA3AF);
const Color _kDividerLight = Color(0xFFEDEFF2);
const Color _kSegTrackLight = Color(0xFFF0F1F4);

/// 显示"新建群组"底部弹窗
void showCreateGroupSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const CreateGroupSheet(),
  );
}

// ==================== 创建群组（全新极简 UI，v3） ====================
//
// 布局思路（与之前完全不同）：
//   1) 顶部：只留一个左上 ✕，没有标题也没有右上"完成"
//   2) Hero 区居中排布：
//        · 72px 大圆头像 + 相机小徽标
//        · 无图标/无边框、居中巨字号的群名输入（headline 感）
//        · 一条会动的下划线（focus 时变主色）
//        · 分段胶囊控件：公开 | 私密（无图标、无副标题）
//   3) 中段：内联无框搜索栏 + 已选成员横向 chip 条
//   4) 联系人列表：勾选圆点在**左侧**（不是右侧），选中行整行淡蓝底
//   5) 底部：sticky 主色大按钮"创建群聊 (N 人)"
//
// 与旧版明显不同的地方：
//   · 旧版顶部有标题栏 + 右上完成；新版顶部仅一个 ✕
//   · 旧版头像+群名是左右平铺；新版是垂直居中大字
//   · 旧版公开/私密是两大行 + 副标题 + 图标；新版是一个胶囊
//   · 旧版联系人 check 在右侧；新版在左侧
//   · 旧版没有 sticky 底部主按钮；新版有

class CreateGroupSheet extends ConsumerStatefulWidget {
  const CreateGroupSheet({super.key});

  @override
  ConsumerState<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<CreateGroupSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final Set<String> _selectedContactUuids = {};
  String? _avatarPath;
  bool _isPublic = false;
  bool _isLoadingContacts = true;
  bool _isCreating = false;
  Timer? _searchDebounce;
  String _searchQuery = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isLoadingContacts = ref.read(contactListProvider).isEmpty;
    _ensureContactsLoaded();
    _nameFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _nameController.text.trim().isNotEmpty &&
      _selectedContactUuids.isNotEmpty;

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
    HapticFeedback.selectionClick();
    final l10n = AppLocalizations(ref.read(languageProvider));
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (image != null && mounted) {
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

  /// 清掉当前错误横幅（用户重新交互后自动清）
  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// 把 exception 拆成可读的短消息，去掉冗余堆栈
  String _prettyError(Object e) {
    final raw = e.toString();
    if (raw.startsWith('Exception: ')) return raw.substring(11);
    // AppCleanException 通常带有 message 字段，toString 会打印它
    return raw;
  }

  Future<void> _createGroup() async {
    if (!_canCreate || _isCreating) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final l10n = AppLocalizations(ref.read(languageProvider));

    try {
      String? uploadedAvatarUrl;
      if (_avatarPath != null) {
        final uploadService = ref.read(uploadServiceProvider);
        try {
          uploadedAvatarUrl = await uploadService.uploadAvatar(
            XFile(_avatarPath!),
          );
        } catch (e) {
          // 头像上传失败不阻塞流程，但需要提醒用户；把错误通过 banner 展示
          if (mounted) {
            setState(() {
              _isCreating = false;
              _errorMessage = '群头像上传失败：${_prettyError(e)}';
            });
          }
          return;
        }
      }

      final chat =
          await ref.read(chatListProvider.notifier).createGroupFromServer(
                name: _nameController.text.trim(),
                memberIds: _selectedContactUuids.toList(),
                avatar: uploadedAvatarUrl,
                isPublic: _isPublic,
              );

      if (!mounted) return;

      if (chat == null) {
        setState(() {
          _isCreating = false;
          _errorMessage = l10n.createGroupFailed;
        });
        return;
      }

      // 成功：先 pop sheet，再跳详情
      Navigator.pop(context);

      if (PlatformUtils.isDesktop) {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _errorMessage = '${l10n.createGroupFailed}：${_prettyError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg = isDark ? _kBgDark : _kBgLight;
    final Color surface = isDark ? _kSurfaceDark : _kSurfaceLight;
    final Color title = isDark ? Colors.white : _kTitleLight;
    final Color sub = isDark ? Colors.white70 : _kSubLight;
    final Color muted = isDark ? Colors.white38 : _kMutedLight;
    final Color divider =
        isDark ? Colors.white.withOpacity(0.06) : _kDividerLight;
    final Color segTrack =
        isDark ? Colors.white.withOpacity(0.08) : _kSegTrackLight;

    final contacts = ref.watch(contactListProvider);
    final systemSettingsAsync = ref.watch(systemSettingsProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final requireFriendOnly = systemSettingsAsync.maybeWhen(
      data: (settings) => settings.groupInviteRequireFriend,
      orElse: () => false,
    );
    final searchQuery = _searchQuery.trim().toLowerCase();

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

    final selectedCount = _selectedContactUuids.length;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        // 新版布局：
        //   · 顶部（拖动条 + ✕ + 错误横幅 + Hero + 搜索/已选 chip）**固定不滚**
        //   · 中间联系人列表用 Expanded + ListView，独立滚动
        //   · 底部按钮通过 SafeArea + viewInsets 贴到屏幕最下面（不再和
        //     floating 导航之间留缝，因为 modal 是覆盖在 nav 之上的）
        child: Column(
          children: [
            // ==================== 固定顶部区域 ====================
            _buildTopStrip(title: title, muted: muted),
            _ErrorBanner(
              message: _errorMessage,
              onDismiss: _clearError,
            ),
            _buildHero(
              title: title,
              sub: sub,
              muted: muted,
              surface: surface,
              segTrack: segTrack,
              divider: divider,
              isDark: isDark,
            ),
            _buildMidSection(
              title: title,
              sub: sub,
              muted: muted,
              surface: surface,
              divider: divider,
              isDark: isDark,
              selectedContacts: selectedContacts,
            ),

            // ==================== 可滚动联系人列表（占据剩余空间） ====================
            //
            // ListView 用 DraggableScrollableSheet 的 scrollController，
            // 这样在列表顶部继续下拉时可以自然把 sheet 拖低 / 关闭。
            Expanded(
              child: _buildContactsList(
                scrollController: scrollController,
                filteredContacts: filteredContacts,
                title: title,
                sub: sub,
                muted: muted,
                divider: divider,
                requireFriendOnly: requireFriendOnly,
                searchQuery: searchQuery,
                l10n: l10n,
              ),
            ),

            // ==================== 底部 sticky 主按钮（贴到最底） ====================
            //
            // ─ viewInsets.bottom 是键盘弹起的高度：键盘弹起时把按钮顶上去
            // ─ SafeArea(top:false) 处理 iOS Home Indicator / Android 手势条
            Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: _buildStickyFooter(
                  bg: bg,
                  muted: muted,
                  selectedCount: selectedCount,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ 顶部：拖动条 + ✕ ============
  Widget _buildTopStrip({required Color title, required Color muted}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4, bottom: 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            splashRadius: 20,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.close_rounded, color: title, size: 22),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  // ============ Hero 区：头像 + 大字群名 + 分段胶囊 ============
  Widget _buildHero({
    required Color title,
    required Color sub,
    required Color muted,
    required Color surface,
    required Color segTrack,
    required Color divider,
    required bool isDark,
  }) {
    final hasFocus = _nameFocus.hasFocus;
    final hasText = _nameController.text.trim().isNotEmpty;
    final Color underline = (hasFocus || hasText)
        ? _kPrimary
        : (isDark ? Colors.white24 : const Color(0xFFDDE1E6));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: Column(
        children: [
          // 大头像
          GestureDetector(
            onTap: _pickAvatar,
            behavior: HitTestBehavior.opaque,
            child: _HeroAvatar(
              avatarPath: _avatarPath,
              muted: muted,
              isDark: isDark,
            ),
          ),

          const SizedBox(height: 14),

          // 群名输入（无 icon、无 label、无边框卡片；仅一条底部会动的线）
          Focus(
            child: TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              onChanged: (_) {
                _clearError();
                setState(() {});
              },
              cursorColor: _kPrimary,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: title,
                letterSpacing: 0.4,
              ),
              decoration: InputDecoration(
                hintText: '输入群名',
                hintStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: muted.withOpacity(0.7),
                ),
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: (hasFocus || hasText) ? 2 : 1,
            width: (hasFocus || hasText) ? 160 : 84,
            decoration: BoxDecoration(
              color: underline,
              borderRadius: BorderRadius.circular(1),
            ),
          ),

          const SizedBox(height: 14),

          // 分段胶囊：公开 / 私密
          _SegmentedPill(
            trackColor: segTrack,
            titleColor: title,
            leftLabel: '公开',
            rightLabel: '私密',
            isLeftSelected: _isPublic,
            onTap: (isLeft) {
              _clearError();
              setState(() => _isPublic = isLeft);
            },
          ),
        ],
      ),
    );
  }

  // ============ 中段：搜索 + 已选 chip ============
  Widget _buildMidSection({
    required Color title,
    required Color sub,
    required Color muted,
    required Color surface,
    required Color divider,
    required bool isDark,
    required List<ContactItem> selectedContacts,
  }) {
    return Column(
      children: [
        // 顶部 hairline
        Container(height: 0.5, color: divider),

        // 无框内联搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  cursorColor: _kPrimary,
                  style: TextStyle(fontSize: 15, color: title),
                  decoration: InputDecoration(
                    hintText: '搜索联系人',
                    hintStyle: TextStyle(fontSize: 15, color: muted),
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                  child: Icon(Icons.cancel_rounded, size: 18, color: muted),
                ),
            ],
          ),
        ),

        Container(height: 0.5, color: divider),

        // 已选 chip 内联条
        if (selectedContacts.isNotEmpty)
          _SelectedChipsRow(
            selectedContacts: selectedContacts,
            title: title,
            muted: muted,
            surface: surface,
            onRemove: (uuid) =>
                setState(() => _selectedContactUuids.remove(uuid)),
          ),
        if (selectedContacts.isNotEmpty)
          Container(height: 0.5, color: divider),
      ],
    );
  }

  // ============ 联系人列表段（独立滚动区）============
  //
  // 使用 [DraggableScrollableSheet] 提供的 [scrollController]，
  // 这样列表顶部继续下拉可以把整个 sheet 平滑收起 / 关闭。
  Widget _buildContactsList({
    required ScrollController scrollController,
    required List<ContactItem> filteredContacts,
    required Color title,
    required Color sub,
    required Color muted,
    required Color divider,
    required bool requireFriendOnly,
    required String searchQuery,
    required AppLocalizations l10n,
  }) {
    if (_isLoadingContacts) {
      // 加载中也用 SingleChildScrollView 包一下，保证 scrollController 有效
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _kPrimary,
              ),
            ),
          ),
        ),
      );
    }

    if (filteredContacts.isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 32),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.groups_2_outlined, size: 30, color: muted),
              ),
              const SizedBox(height: 14),
              Text(
                searchQuery.isNotEmpty ? '未找到匹配的好友' : '暂无可邀请的好友',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: title,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                requireFriendOnly
                    ? '后台限制为仅可邀请好友，请先添加好友'
                    : '请先添加好友后再来这里创建群聊',
                style: TextStyle(
                  fontSize: 12.5,
                  color: muted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _reloadContacts,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('刷新联系人'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: BorderSide(color: _kPrimary.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      // 首行 (index 0) 是「联系人 N」段落头，其余是联系人条目
      itemCount: filteredContacts.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
            child: Row(
              children: [
                Text(
                  '联系人',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: muted.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${filteredContacts.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _reloadContacts,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final contact = filteredContacts[index - 1];
        final uuid = contact.uuid!.trim();
        final isSelected = _selectedContactUuids.contains(uuid);

        return _ContactRowLeftCheck(
          contact: contact,
          selected: isSelected,
          title: title,
          sub: sub,
          muted: muted,
          l10n: l10n,
          onTap: () {
            HapticFeedback.selectionClick();
            _clearError();
            setState(() {
              if (isSelected) {
                _selectedContactUuids.remove(uuid);
              } else {
                _selectedContactUuids.add(uuid);
              }
            });
          },
        );
      },
    );
  }

  // ============ 底部 sticky 主按钮 ============
  //
  // 现在只负责画按钮本身 —— 底部的 keyboard inset / SafeArea 由外层的
  // Padding + SafeArea 处理，让按钮尽可能贴到屏幕最下面。
  Widget _buildStickyFooter({
    required Color bg,
    required Color muted,
    required int selectedCount,
  }) {
    final canFinish = _canCreate && !_isCreating;
    final String btnLabel;
    if (_nameController.text.trim().isEmpty) {
      btnLabel = '请填写群名';
    } else if (selectedCount == 0) {
      btnLabel = '至少选择一位联系人';
    } else {
      btnLabel = '创建群聊 ($selectedCount 人)';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: bg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: Material(
          color: canFinish ? _kPrimary : muted.withOpacity(0.30),
          borderRadius: BorderRadius.circular(999),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canFinish ? _createGroup : null,
            child: Center(
              child: _isCreating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      btnLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Hero 头像 ====================

class _HeroAvatar extends StatelessWidget {
  final String? avatarPath;
  final Color muted;
  final bool isDark;

  const _HeroAvatar({
    required this.avatarPath,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarPath != null;
    const double size = 60;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasAvatar
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _kPrimary.withOpacity(0.16),
                        _kPrimary.withOpacity(0.06),
                      ],
                    ),
              boxShadow: [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: hasAvatar
                ? ClipOval(
                    child: Image.file(
                      File(avatarPath!),
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.add_rounded,
                      size: 26,
                      color: _kPrimary,
                    ),
                  ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _kPrimary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? _kSurfaceDark : Colors.white,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 分段胶囊控件 ====================

class _SegmentedPill extends StatelessWidget {
  final Color trackColor;
  final Color titleColor;
  final String leftLabel;
  final String rightLabel;
  final bool isLeftSelected;
  final ValueChanged<bool> onTap;

  const _SegmentedPill({
    required this.trackColor,
    required this.titleColor,
    required this.leftLabel,
    required this.rightLabel,
    required this.isLeftSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegBtn(
            label: leftLabel,
            selected: isLeftSelected,
            titleColor: titleColor,
            onTap: () => onTap(true),
          ),
          _SegBtn(
            label: rightLabel,
            selected: !isLeftSelected,
            titleColor: titleColor,
            onTap: () => onTap(false),
          ),
        ],
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color titleColor;
  final VoidCallback onTap;

  const _SegBtn({
    required this.label,
    required this.selected,
    required this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? _kPrimary : titleColor.withOpacity(0.65),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ==================== 已选 chip 内联条 ====================

class _SelectedChipsRow extends StatelessWidget {
  final List<ContactItem> selectedContacts;
  final Color title;
  final Color muted;
  final Color surface;
  final ValueChanged<String> onRemove;

  const _SelectedChipsRow({
    required this.selectedContacts,
    required this.title,
    required this.muted,
    required this.surface,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: selectedContacts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final c = selectedContacts[i];
            final uuid = c.uuid!.trim();
            return GestureDetector(
              onTap: () => onRemove(uuid),
              child: Container(
                padding:
                    const EdgeInsets.fromLTRB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _kPrimary.withOpacity(0.20),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AvatarWidget(
                      avatar: c.avatar,
                      name: c.name,
                      userId: c.id,
                      size: 28,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: title,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close_rounded,
                        size: 14, color: title.withOpacity(0.55)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== 联系人行（勾选在左侧） ====================

class _ContactRowLeftCheck extends StatelessWidget {
  final ContactItem contact;
  final bool selected;
  final Color title;
  final Color sub;
  final Color muted;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  const _ContactRowLeftCheck({
    required this.contact,
    required this.selected,
    required this.title,
    required this.sub,
    required this.muted,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kPrimary.withOpacity(0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              _LeftCheck(selected: selected, muted: muted),
              const SizedBox(width: 14),
              AvatarWidget(
                avatar: contact.avatar,
                name: contact.name,
                userId: contact.id,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.isOnline ? l10n.online : l10n.recentlyOnline,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: contact.isOnline
                            ? AppColors.online
                            : muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeftCheck extends StatelessWidget {
  final bool selected;
  final Color muted;

  const _LeftCheck({required this.selected, required this.muted});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _kPrimary : Colors.transparent,
        border: Border.all(
          color: selected ? _kPrimary : muted.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

// ==================== 内联错误横幅 ====================
//
// modal sheet 打开时 `ScaffoldMessenger.showSnackBar` 会被 sheet 挡住看不见，
// 所以创建失败要用一个内嵌在 sheet 顶部的横幅显示。
// 视觉上采用柔和红底 + 深红图标/文字，与全局 AppSnackBar 的"深色卡片+彩色小圆点"
// 一样避免了以前"充盈红底"的刺眼感。

class _ErrorBanner extends StatelessWidget {
  final String? message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: (message == null || message!.isEmpty)
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2), // 柔和玫瑰色底
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFECDD3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message!,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: const Color(0xFF991B1B).withOpacity(0.7),
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
