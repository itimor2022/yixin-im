import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/api/api_client.dart' show ApiConfig;
import '../../../core/services/notification_sound_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/message_provider.dart';

///  消息长按菜单
class MessageContextMenu extends StatefulWidget {
  final MessageItem message;
  final bool isOutgoing;
  final bool showSenderName;
  final Offset tapPosition;
  final VoidCallback onDismiss;
  final Function(String emoji)? onReaction;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onForward;
  final VoidCallback? onFavorite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRevoke;
  final VoidCallback? onSelect;
  final VoidCallback? onPin;
  // 桌面端文件操作
  final VoidCallback? onDownload;
  final VoidCallback? onSaveAs;
  final VoidCallback? onShowInFolder;
  final VoidCallback? onOpenFile;

  const MessageContextMenu({
    super.key,
    required this.message,
    required this.isOutgoing,
    required this.tapPosition,
    required this.onDismiss,
    this.showSenderName = false,
    this.onReaction,
    this.onReply,
    this.onCopy,
    this.onForward,
    this.onFavorite,
    this.onEdit,
    this.onDelete,
    this.onRevoke,
    this.onSelect,
    this.onPin,
    this.onDownload,
    this.onSaveAs,
    this.onShowInFolder,
    this.onOpenFile,
  });

  @override
  State<MessageContextMenu> createState() => _MessageContextMenuState();
}

class _MessageContextMenuState extends State<MessageContextMenu>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _panelAnimController;
  late AnimationController _deleteConfirmController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _blurAnimation;
  late Animation<double> _panelExpandAnimation;
  late Animation<double> _deleteSlideAnimation;

  bool _showEmojiPanel = false;
  bool _showDeleteConfirm = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _panelAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _deleteConfirmController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _blurAnimation = Tween<double>(
      begin: 0.0,
      end: 15.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _panelExpandAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _panelAnimController, curve: Curves.easeOutCubic),
    );

    _deleteSlideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _deleteConfirmController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward();
    GlobalHaptics.medium();
  }

  @override
  void dispose() {
    _animController.dispose();
    _panelAnimController.dispose();
    _deleteConfirmController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_showEmojiPanel) {
      await _panelAnimController.reverse();
    }
    await _animController.reverse();
    widget.onDismiss();
  }

  void _handleReaction(String emoji) {
    GlobalHaptics.selection();
    widget.onReaction?.call(emoji);
    _dismiss();
  }

  void _handleAction(VoidCallback? action) {
    if (action != null) {
      GlobalHaptics.selection();
      _dismiss().then((_) => action());
    }
  }

  void _toggleEmojiPanel() {
    GlobalHaptics.selection();
    setState(() {
      _showEmojiPanel = !_showEmojiPanel;
    });
    if (_showEmojiPanel) {
      _panelAnimController.forward();
    } else {
      _panelAnimController.reverse();
    }
  }

  void _toggleDeleteConfirm() {
    GlobalHaptics.selection();
    setState(() {
      _showDeleteConfirm = !_showDeleteConfirm;
    });
    if (_showDeleteConfirm) {
      _deleteConfirmController.forward();
    } else {
      _deleteConfirmController.reverse();
    }
  }

  void _confirmDelete() {
    GlobalHaptics.medium();
    _dismiss().then((_) => widget.onDelete?.call());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _animController,
          _panelAnimController,
          _deleteConfirmController,
        ]),
        builder: (context, child) {
          return Stack(
            children: [
              // 全屏模糊背景
              Positioned.fill(
                child: GestureDetector(
                  onTap: _dismiss,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _blurAnimation.value,
                      sigmaY: _blurAnimation.value,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(
                        0.3 * _fadeAnimation.value,
                      ),
                    ),
                  ),
                ),
              ),

              // 内容
              Positioned.fill(
                child: SafeArea(
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: _buildContent(
                        context,
                        isDark,
                        screenSize,
                        padding,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool isDark,
    Size screenSize,
    EdgeInsets padding,
  ) {
    final isDesktop = PlatformUtils.isDesktop;

    // 桌面端：紧凑的右键菜单，定位在点击位置附近
    if (isDesktop) {
      return _buildDesktopContent(context, isDark, screenSize, padding);
    }

    // 移动端：原有的全屏模糊菜单
    final isTopHalf = widget.tapPosition.dy < screenSize.height / 2;
    final menuWidth = screenSize.width * 0.65;

    return Column(
      mainAxisAlignment: isTopHalf
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        if (!isTopHalf) const Spacer(),

        if (isTopHalf) ...[
          SizedBox(height: padding.top + 60),
          // 表情反应栏 + 展开面板
          _buildReactionSection(isDark, screenSize),
          const SizedBox(height: 12),
        ],

        // 消息预览
        _buildMessagePreview(context, isDark, screenSize),

        const SizedBox(height: 12),

        if (!isTopHalf) ...[
          // 表情反应栏 + 展开面板
          _buildReactionSection(isDark, screenSize),
          const SizedBox(height: 12),
        ],

        // 操作菜单（只在未展开表情面板时显示）
        AnimatedOpacity(
          opacity: _showEmojiPanel ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedSlide(
            offset: _showEmojiPanel ? const Offset(0, 0.2) : Offset.zero,
            duration: const Duration(milliseconds: 150),
            child: _buildActionMenu(isDark, menuWidth),
          ),
        ),

        if (isTopHalf) const Spacer(),
        if (!isTopHalf) SizedBox(height: padding.bottom + 20),
      ],
    );
  }

  /// 桌面端菜单布局 - 紧凑的右键菜单
  Widget _buildDesktopContent(
    BuildContext context,
    bool isDark,
    Size screenSize,
    EdgeInsets padding,
  ) {
    final menuWidth = 220.0;
    final menuHeight = 320.0; // 预估菜单高度

    // 计算菜单位置，确保不超出屏幕
    double left = widget.tapPosition.dx;
    double top = widget.tapPosition.dy;

    // 如果右边空间不够，往左移
    if (left + menuWidth > screenSize.width - 20) {
      left = screenSize.width - menuWidth - 20;
    }
    // 如果左边超出，靠左
    if (left < 20) left = 20;

    // 如果下边空间不够，往上移
    if (top + menuHeight > screenSize.height - 20) {
      top = screenSize.height - menuHeight - 20;
    }
    // 如果上边超出，靠上
    if (top < 20) top = 20;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 表情反应栏
              _buildDesktopReactionBar(isDark),
              const SizedBox(height: 6),
              // 操作菜单
              _buildDesktopActionMenu(isDark, menuWidth),
            ],
          ),
        ),
      ],
    );
  }

  /// 桌面端表情反应栏 - 更紧凑
  Widget _buildDesktopReactionBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...EmojiAnimations.quickReactions.map(
            (emoji) => _buildDesktopReactionItem(emoji, isDark),
          ),
          _buildDesktopMoreReactionsButton(isDark),
        ],
      ),
    );
  }

  Widget _buildDesktopReactionItem(AnimatedEmoji emoji, bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleReaction(emoji.emoji),
        child: Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(2),
          child: Lottie.asset(emoji.path, repeat: true, animate: true),
        ),
      ),
    );
  }

  Widget _buildDesktopMoreReactionsButton(bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleEmojiPanel,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add,
              size: 16,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  /// 桌面端操作菜单 - 紧凑样式
  Widget _buildDesktopActionMenu(bool isDark, double menuWidth) {
    final message = widget.message;

    // 判断是否是媒体/文件类型消息
    final isMediaMessage =
        message.type == MessageItemType.image ||
        message.type == MessageItemType.video ||
        message.type == MessageItemType.file ||
        message.type == MessageItemType.voice;

    return Container(
      width: menuWidth,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDesktopMenuItem(
            icon: Icons.reply_rounded,
            title: '回复',
            isDark: isDark,
            onTap: () => _handleAction(widget.onReply),
          ),
          _buildDesktopDivider(isDark),

          if (message.type != MessageItemType.redPacket &&
              message.type != MessageItemType.transfer &&
              message.type != MessageItemType.system) ...[
            _buildDesktopMenuItem(
              icon: Icons.copy_rounded,
              title: '复制',
              isDark: isDark,
              onTap: () => _handleAction(widget.onCopy),
            ),
            _buildDesktopDivider(isDark),
          ],

          if (widget.onForward != null)
            _buildDesktopMenuItem(
              icon: Icons.shortcut_rounded,
              title: '转发',
              isDark: isDark,
              onTap: () => _handleAction(widget.onForward),
            ),

          if (widget.onFavorite != null) ...[
            _buildDesktopDivider(isDark),
            _buildDesktopMenuItem(
              icon: Icons.favorite_border_rounded,
              title: '收藏',
              isDark: isDark,
              onTap: () => _handleAction(widget.onFavorite),
            ),
          ],

          // 媒体/文件类型消息显示额外操作
          if (isMediaMessage) ...[
            if (widget.onDownload != null) ...[
              _buildDesktopDivider(isDark),
              _buildDesktopMenuItem(
                icon: Icons.download_rounded,
                title: '下载',
                isDark: isDark,
                onTap: () => _handleAction(widget.onDownload),
              ),
            ],
            if (widget.onSaveAs != null) ...[
              _buildDesktopDivider(isDark),
              _buildDesktopMenuItem(
                icon: Icons.save_alt_rounded,
                title: '存储到...',
                isDark: isDark,
                onTap: () => _handleAction(widget.onSaveAs),
              ),
            ],
            if (widget.onShowInFolder != null) ...[
              _buildDesktopDivider(isDark),
              _buildDesktopMenuItem(
                icon: Icons.folder_open_rounded,
                title: Platform.isMacOS
                    ? '在 Finder 中显示'
                    : Platform.isWindows
                    ? '在资源管理器中显示'
                    : '在文件管理器中显示',
                isDark: isDark,
                onTap: () => _handleAction(widget.onShowInFolder),
              ),
            ],
            if (widget.onOpenFile != null &&
                message.type == MessageItemType.file) ...[
              _buildDesktopDivider(isDark),
              _buildDesktopMenuItem(
                icon: Icons.open_in_new_rounded,
                title: '使用默认应用打开',
                isDark: isDark,
                onTap: () => _handleAction(widget.onOpenFile),
              ),
            ],
          ],

          if (message.isOutgoing &&
              message.type != MessageItemType.redPacket &&
              message.type != MessageItemType.transfer) ...[
            _buildDesktopDivider(isDark),
            _buildDesktopMenuItem(
              icon: Icons.edit_rounded,
              title: '编辑',
              isDark: isDark,
              onTap: () => _handleAction(widget.onEdit),
            ),
          ],

          if (widget.onRevoke != null) ...[
            _buildDesktopDivider(isDark),
            _buildDesktopMenuItem(
              icon: Icons.undo_rounded,
              title: '撤回',
              isDark: isDark,
              onTap: () => _handleAction(widget.onRevoke),
            ),
          ],

          if (widget.onPin != null) ...[
            _buildDesktopDivider(isDark),
            _buildDesktopMenuItem(
              icon: Icons.push_pin_rounded,
              title: '置顶',
              isDark: isDark,
              onTap: () => _handleAction(widget.onPin),
            ),
          ],

          _buildDesktopDivider(isDark),
          _buildDesktopMenuItem(
            icon: Icons.check_circle_outline_rounded,
            title: '选择',
            isDark: isDark,
            onTap: () => _handleAction(widget.onSelect),
          ),

          _buildDesktopDivider(isDark),
          _buildDesktopMenuItem(
            icon: Icons.delete_outline_rounded,
            title: '删除',
            isDark: isDark,
            onTap: () => _handleAction(widget.onDelete),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopMenuItem({
    required IconData icon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? AppColors.error
        : (isDark ? Colors.white : Colors.black87);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDivider(bool isDark) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
    );
  }

  /// 表情反应区域（反应栏 + 展开面板）- 全毛玻璃效果
  Widget _buildReactionSection(bool isDark, Size screenSize) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_showEmojiPanel ? 14 : 22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: _showEmojiPanel ? screenSize.width - 16 : null,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2C2C2E).withOpacity(0.85)
                  : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(_showEmojiPanel ? 14 : 22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 25,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部反应栏（始终显示）
                _buildReactionsBar(isDark),

                // 展开的表情面板
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: _showEmojiPanel
                      ? SizedBox(
                          height: 280,
                          child: _TGEmojiPanel(
                            onEmojiSelected: _handleReaction,
                            isDark: isDark,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 表情反应栏
  Widget _buildReactionsBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: _showEmojiPanel ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...EmojiAnimations.quickReactions.map(
            (emoji) => _buildReactionItem(emoji, isDark),
          ),
          _buildMoreReactionsButton(isDark),
        ],
      ),
    );
  }

  Widget _buildReactionItem(AnimatedEmoji emoji, bool isDark) {
    return GestureDetector(
      onTap: () => _handleReaction(emoji.emoji),
      child: Container(
        width: 38,
        height: 38,
        padding: const EdgeInsets.all(3),
        child: Lottie.asset(emoji.path, repeat: true, animate: true),
      ),
    );
  }

  Widget _buildMoreReactionsButton(bool isDark) {
    return GestureDetector(
      onTap: _toggleEmojiPanel,
      child: AnimatedRotation(
        turns: _showEmojiPanel ? 0.125 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _showEmojiPanel
                  ? AppColors.primary.withOpacity(0.15)
                  : (isDark ? Colors.white12 : Colors.black.withOpacity(0.05)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add,
              size: 18,
              color: _showEmojiPanel
                  ? AppColors.primary
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  /// 消息预览
  Widget _buildMessagePreview(
    BuildContext context,
    bool isDark,
    Size screenSize,
  ) {
    final message = widget.message;
    final isOutgoing = widget.isOutgoing;

    final bubbleColor = isOutgoing
        ? (isDark
              ? AppColors.darkBubbleOutgoing
              : AppColors.lightBubbleOutgoing)
        : (isDark
              ? AppColors.darkBubbleIncoming
              : AppColors.lightBubbleIncoming);

    final textColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final timeColor = isOutgoing
        ? (isDark ? Colors.white60 : const Color(0xFF5D9B5D))
        : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isOutgoing ? 40 : 16),
      child: Row(
        mainAxisAlignment: isOutgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOutgoing && widget.showSenderName) ...[
            AvatarWidget(
              avatar: message.senderAvatar,
              name: message.senderName,
              userId: message.senderId,
              size: 32,
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: screenSize.width * 0.7),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isOutgoing ? 18 : 4),
                  bottomRight: Radius.circular(isOutgoing ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isOutgoing && widget.showSenderName)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _getSenderColor(message.senderName),
                        ),
                      ),
                    ),

                  // 根据消息类型显示不同预览
                  _buildMessageContent(message, textColor, isDark),

                  const SizedBox(height: 4),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(message.createdAt),
                        style: TextStyle(fontSize: 11, color: timeColor),
                      ),
                      if (isOutgoing) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.status == MessageStatus.read
                              ? Icons.done_all
                              : Icons.done,
                          size: 14,
                          color: message.status == MessageStatus.read
                              ? AppColors.primary
                              : timeColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 根据消息类型构建内容
  Widget _buildMessageContent(
    MessageItem message,
    Color textColor,
    bool isDark,
  ) {
    switch (message.type) {
      case MessageItemType.image:
        // 显示图片缩略图
        final imageUrl = message.thumbnail ?? message.mediaUrl;
        final fullImageUrl = ApiConfig.getMediaUrl(imageUrl);
        if (fullImageUrl.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: fullImageUrl,
              width: 160,
              height: 160,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 160,
                height: 160,
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: 160,
                height: 160,
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                child: Icon(
                  Icons.image_rounded,
                  size: 40,
                  color: textColor.withOpacity(0.3),
                ),
              ),
            ),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_rounded,
              size: 20,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text('图片', style: TextStyle(fontSize: 16, color: textColor)),
          ],
        );
      case MessageItemType.video:
        // 显示视频缩略图
        final thumbUrl = message.thumbnail;
        final fullThumbUrl = ApiConfig.getMediaUrl(thumbUrl);
        if (fullThumbUrl.isNotEmpty) {
          return Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: fullThumbUrl,
                  width: 160,
                  height: 120,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 160,
                    height: 120,
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 160,
                    height: 120,
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                    child: Icon(
                      Icons.videocam_rounded,
                      size: 40,
                      color: textColor.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_rounded,
              size: 20,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text('视频', style: TextStyle(fontSize: 16, color: textColor)),
          ],
        );
      case MessageItemType.voice:
        // 语音消息 - 显示波形样式
        final durationMs = message.mediaDuration ?? 0;
        final durationSec = durationMs > 1000
            ? (durationMs / 1000).round()
            : durationMs;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            // 波形
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                8,
                (i) => Container(
                  width: 3,
                  height: 8 + (i % 3) * 6.0,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${durationSec}″',
              style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.7)),
            ),
          ],
        );
      case MessageItemType.file:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.insert_drive_file_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.fileName ?? '文件',
                    style: TextStyle(fontSize: 14, color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.mediaSize != null)
                    Text(
                      _formatFileSize(message.mediaSize!),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withOpacity(0.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      case MessageItemType.redPacket:
        String rpMessage = '恭喜发财，大吉大利';
        try {
          final json = message.content.isNotEmpty
              ? Map<String, dynamic>.from(
                  (message.content.startsWith('{'))
                      ? (const JsonDecoder().convert(message.content)
                            as Map<String, dynamic>)
                      : {'message': message.content},
                )
              : {};
          rpMessage = json['message'] as String? ?? '恭喜发财，大吉大利';
        } catch (_) {}
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFA5252), Color(0xFFE03131)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧧', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rpMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '红包',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case MessageItemType.transfer:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59F00),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              const Text(
                '转账',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      case MessageItemType.system:
        return Text(
          '系统消息',
          style: TextStyle(
            fontSize: 14,
            color: textColor.withOpacity(0.6),
            fontStyle: FontStyle.italic,
          ),
        );
      case MessageItemType.sticker:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.emoji_emotions_rounded,
              size: 20,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text('表情', style: TextStyle(fontSize: 16, color: textColor)),
          ],
        );
      case MessageItemType.call:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.call_rounded,
              size: 20,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text(
              message.content.isNotEmpty ? message.content : '通话',
              style: TextStyle(fontSize: 16, color: textColor),
            ),
          ],
        );
      case MessageItemType.contact:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              size: 20,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text('联系人名片', style: TextStyle(fontSize: 16, color: textColor)),
          ],
        );
      case MessageItemType.location:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 20,
              color: textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text('位置', style: TextStyle(fontSize: 16, color: textColor)),
          ],
        );
      default:
        return Text(
          message.content.isEmpty ? '消息' : message.content,
          style: TextStyle(fontSize: 16, height: 1.3, color: textColor),
        );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 操作菜单
  Widget _buildActionMenu(bool isDark, double menuWidth) {
    final message = widget.message;

    return Center(
      child: Container(
        width: menuWidth,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMenuItem(
              icon: Icons.reply_rounded,
              title: '回复',
              isDark: isDark,
              onTap: () => _handleAction(widget.onReply),
            ),
            _buildDivider(isDark),

            if (message.type != MessageItemType.redPacket &&
                message.type != MessageItemType.transfer &&
                message.type != MessageItemType.system) ...[
              _buildMenuItem(
                icon: Icons.copy_rounded,
                title: '复制',
                isDark: isDark,
                onTap: () => _handleAction(widget.onCopy),
              ),
              _buildDivider(isDark),
            ],

            if (widget.onForward != null)
              _buildMenuItem(
                icon: Icons.shortcut_rounded,
                title: '转发',
                isDark: isDark,
                onTap: () => _handleAction(widget.onForward),
              ),

            if (widget.onFavorite != null) ...[
              _buildDivider(isDark),
              _buildMenuItem(
                icon: Icons.favorite_border_rounded,
                title: '收藏',
                isDark: isDark,
                onTap: () => _handleAction(widget.onFavorite),
              ),
            ],

            if (message.isOutgoing &&
                message.type != MessageItemType.redPacket &&
                message.type != MessageItemType.transfer) ...[
              _buildDivider(isDark),
              _buildMenuItem(
                icon: Icons.edit_rounded,
                title: '编辑',
                isDark: isDark,
                onTap: () => _handleAction(widget.onEdit),
              ),
            ],

            if (widget.onRevoke != null) ...[
              _buildDivider(isDark),
              _buildMenuItem(
                icon: Icons.undo_rounded,
                title: '撤回',
                isDark: isDark,
                onTap: () => _handleAction(widget.onRevoke),
              ),
            ],

            if (widget.onPin != null) ...[
              _buildDivider(isDark),
              _buildMenuItem(
                icon: Icons.push_pin_rounded,
                title: '置顶',
                isDark: isDark,
                onTap: () => _handleAction(widget.onPin),
              ),
            ],

            _buildDivider(isDark),
            _buildMenuItem(
              icon: Icons.check_circle_outline_rounded,
              title: '选择',
              isDark: isDark,
              onTap: () => _handleAction(widget.onSelect),
            ),

            _buildDivider(isDark),
            // 删除按钮 - 侧滑确认
           // _buildDeleteMenuItem(isDark),
          ],
        ),
      ),
    );
  }

  /// 删除菜单项 - 带侧滑确认
  Widget _buildDeleteMenuItem(bool isDark) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      child: AnimatedBuilder(
        animation: _deleteSlideAnimation,
        builder: (context, _) {
          final progress = _deleteSlideAnimation.value;

          return SizedBox(
            height: 46,
            child: Stack(
              children: [
                // 确认删除按钮（红色背景，从右侧滑入）
                Positioned.fill(
                  child: Container(
                    color: AppColors.error,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: progress > 0.5 ? _confirmDelete : null,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_rounded,
                                size: 22,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '确认删除',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 删除按钮（滑出隐藏）
                Positioned(
                  left: -progress * 250,
                  right: progress * 250,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: progress > 0.5,
                    child: Container(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _toggleDeleteConfirm,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '删除',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 22,
                                  color: AppColors.error,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? AppColors.error
        : (isDark ? Colors.white : Colors.black87);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: color,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Icon(icon, size: 22, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
    );
  }

  Color _getSenderColor(String name) {
    final colors = [
      const Color(0xFFE17076),
      const Color(0xFF7BC862),
      const Color(0xFF65AADD),
      const Color(0xFFEE7AE9),
      const Color(0xFFFAA05A),
      const Color(0xFF6EC9CB),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// 表情面板（从反应栏展开）
class _TGEmojiPanel extends StatefulWidget {
  final Function(String emoji) onEmojiSelected;
  final bool isDark;

  const _TGEmojiPanel({required this.onEmojiSelected, required this.isDark});

  @override
  State<_TGEmojiPanel> createState() => _TGEmojiPanelState();
}

class _TGEmojiPanelState extends State<_TGEmojiPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  Set<String> _installedPackIds = {};
  List<String> _recentEmojis = [];
  int _currentIndex = 0;
  bool _isLoaded = false;

  List<StickerPack> get _installedPacks => BuiltInStickerPacks.all
      .where((p) => _installedPackIds.contains(p.id))
      .toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getStringList('installed_sticker_packs') ?? [];
    _installedPackIds = installed.toSet();

    if (_installedPackIds.isEmpty) {
      _installedPackIds = BuiltInStickerPacks.all.map((p) => p.id).toSet();
    }

    _recentEmojis =
        prefs.getStringList('recent_emojis') ??
        ['👋', '😂', '❤️', '😎', '🤔', '👍', '🔥', '🎉', '😍', '✨', '👏', '🙏'];

    _tabController = TabController(
      length: _installedPacks.length + 1,
      vsync: this,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentIndex = _tabController.index);
      _pageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });

    setState(() => _isLoaded = true);
  }

  void _selectEmoji(String emoji) {
    widget.onEmojiSelected(emoji);
    _updateRecent(emoji);
  }

  Future<void> _updateRecent(String emoji) async {
    final prefs = await SharedPreferences.getInstance();
    _recentEmojis.remove(emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 30) {
      _recentEmojis = _recentEmojis.sublist(0, 30);
    }
    await prefs.setStringList('recent_emojis', _recentEmojis);
  }

  @override
  void dispose() {
    if (_isLoaded) {
      _tabController.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // 分隔线
        Container(
          height: 0.5,
          color: widget.isDark
              ? Colors.white10
              : Colors.black.withOpacity(0.06),
        ),

        // 顶部导航 - 贴纸包图标
        _buildTopNav(),

        // 搜索栏和分类
        _buildSearchBar(),

        // 表情内容
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _tabController.animateTo(index);
            },
            itemCount: _installedPacks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildRecentGrid();
              }
              return _buildPackGrid(_installedPacks[index - 1]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTopNav() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        itemCount: _installedPacks.length + 1,
        itemBuilder: (context, index) {
          final isSelected = _currentIndex == index;

          return GestureDetector(
            onTap: () {
              GlobalHaptics.selection();
              _tabController.animateTo(index);
            },
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSelected
                    ? (widget.isDark
                          ? Colors.white12
                          : AppColors.primary.withOpacity(0.1))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: index == 0
                    ? Icon(
                        Icons.access_time_rounded,
                        size: 18,
                        color: isSelected
                            ? AppColors.primary
                            : (widget.isDark ? Colors.white38 : Colors.black26),
                      )
                    : SizedBox(
                        width: 22,
                        height: 22,
                        child: Lottie.asset(
                          _installedPacks[index - 1].previewPath,
                          repeat: isSelected,
                          animate: isSelected,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    // 分类图标（灰色轮廓）
    final categoryIcons = [
      Icons.favorite_border_rounded,
      Icons.thumb_up_outlined,
      Icons.chat_bubble_outline_rounded,
      Icons.people_outline_rounded,
      Icons.emoji_emotions_outlined,
      Icons.sentiment_satisfied_outlined,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          // 搜索
          Icon(
            Icons.search_rounded,
            size: 18,
            color: widget.isDark ? Colors.white30 : Colors.black26,
          ),
          const SizedBox(width: 4),
          Text(
            '搜索',
            style: TextStyle(
              fontSize: 13,
              color: widget.isDark ? Colors.white30 : Colors.black26,
            ),
          ),
          const Spacer(),
          // 分类图标
          ...categoryIcons.map(
            (icon) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                icon,
                size: 18,
                color: widget.isDark ? Colors.white30 : Colors.black26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _recentEmojis.length,
      itemBuilder: (context, index) {
        final emoji = _recentEmojis[index];
        final animated = EmojiAnimations.findByEmoji(emoji);

        return GestureDetector(
          onTap: () => _selectEmoji(emoji),
          child: animated != null
              ? Lottie.asset(animated.path, repeat: true)
              : Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
        );
      },
    );
  }

  Widget _buildPackGrid(StickerPack pack) {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: pack.stickerFiles.length,
      itemBuilder: (context, index) {
        final file = pack.stickerFiles[index];
        final emoji = EmojiAnimations.all.firstWhere(
          (e) => e.file == file,
          orElse: () => EmojiAnimations.all.first,
        );

        return GestureDetector(
          onTap: () => _selectEmoji(emoji.emoji),
          child: Lottie.asset(EmojiAnimations.getPath(file), repeat: true),
        );
      },
    );
  }
}

/// 显示消息上下文菜单
Future<void> showMessageContextMenu({
  required BuildContext context,
  required MessageItem message,
  required bool isOutgoing,
  required Offset tapPosition,
  bool showSenderName = false,
  Function(String emoji)? onReaction,
  VoidCallback? onReply,
  VoidCallback? onCopy,
  VoidCallback? onForward,
  VoidCallback? onFavorite,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  VoidCallback? onRevoke,
  VoidCallback? onSelect,
  VoidCallback? onPin,
  // 桌面端文件操作
  VoidCallback? onDownload,
  VoidCallback? onSaveAs,
  VoidCallback? onShowInFolder,
  VoidCallback? onOpenFile,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, __) => MessageContextMenu(
      message: message,
      isOutgoing: isOutgoing,
      tapPosition: tapPosition,
      showSenderName: showSenderName,
      onDismiss: () => Navigator.of(context).pop(),
      onReaction: onReaction,
      onReply: onReply,
      onCopy: onCopy,
      onForward: onForward,
      onFavorite: onFavorite,
      onEdit: onEdit,
      onDelete: onDelete,
      onRevoke: onRevoke,
      onSelect: onSelect,
      onPin: onPin,
      onDownload: onDownload,
      onSaveAs: onSaveAs,
      onShowInFolder: onShowInFolder,
      onOpenFile: onOpenFile,
    ),
  );
}
