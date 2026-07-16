import '../../../shared/widgets/member_badge_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/chat_provider.dart';

/// ============================================================
/// 聊天列表项 —— **扁平** 版本 (v4)
/// ============================================================
///
/// 已彻底移除卡片风格（无背景 / 无边框 / 无阴影 / 无底部装饰条），
/// 让整个列表在纯白 Scaffold 上呈现"零框线"的极简样式。
///
/// 视觉变更：
///   · 单条会话是**没有任何 chrome 的平铺行**，直接坐在白色背景上
///   · 选中态：极淡主色底 (#F0F7FF) + 左侧 3px 主色 accent 竖条
///   · 未读徽标仍位于头像右上角
///   · 置顶 / 静音 / 待审批仍作为底部状态 chip 显示
///
/// 保留全部旧行为：
///   · SwipeAction 枚举 & onSwipeAction 回调
///   · 移动端左滑（3+1 按钮，二次展开删除确认）
///   · 桌面端 Secondary-tap 右键菜单
///   · 富文本消息预览 + Lottie 表情内联
///   · 草稿 / 输入中 / 语音/图片/视频/文件/位置/名片/通话 前缀
///   · isOfficial / isMember / badgeText / badgeColor 等所有 flag

/// ===== 视觉 Token =====
const Color _kListPrimary = AppColors.primary;

/// 在头像上叠加的"贴纸"（在线小点 / 未读徽标）需要一圈跟 Scaffold
/// 背景色一致的描边，形成"从背景里挖出来"的视觉。这里仅保留深色主题
/// 的 Scaffold 底色作为描边色（浅色主题直接用白色）。
const Color _kListStickerCutout = Color(0xFF0E1015);
const Color _kListTitleText = Color(0xFF111827);
const Color _kListSubText = Color(0xFF6B7280);
const Color _kListTimeText = Color(0xFF9CA3AF);
const Color _kListMutedTint = Color(0xFFB8BEC7);

/// 选中背景（浅色/深色主题各一）——非常淡，仅指示 active 项。
const Color _kListSelectedBgLight = Color(0xFFF0F7FF);
const Color _kListSelectedBgDark = Color(0x1F009CFF);

/// 每一行的水平内边距 & 垂直内边距（扁平样式，没有卡片外 margin）。
const double _kRowHPadding = 16;
const double _kRowVPadding = 10;
const double _kAvatarSize = 52;
const double _kAvatarGap = 12;

/// 左滑操作类型
enum SwipeAction { pin, mute, read, delete }

class ChatListItem extends StatefulWidget {
  final ChatItem chat;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Function(SwipeAction)? onSwipeAction;
  final bool isOfficial;
  final bool isSelected;
  final bool isDesktop;
  final bool showPendingApprovalDot;
  final String? typingText;
  final bool isMember;
  final String? badgeText;
  final String? badgeColor;

  /// 兼容旧参数——新版不再画整条 divider，改用留白，此 flag 现在被忽略。
  final bool showDivider;

  const ChatListItem({
    super.key,
    required this.chat,
    this.onTap,
    this.onLongPress,
    this.onSwipeAction,
    this.isOfficial = false,
    this.isSelected = false,
    this.isDesktop = false,
    this.showPendingApprovalDot = false,
    this.typingText,
    this.isMember = false,
    this.badgeText,
    this.badgeColor,
    this.showDivider = true,
  });

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _deleteController;
  double _dragExtent = 0;
  bool _isOpen = false;
  bool _showDeleteConfirm = false;

  static const double _actionButtonWidth = 70.0;
  static const double _deleteMaxDragExtent = _actionButtonWidth * 4;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _deleteController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _deleteController.dispose();
    super.dispose();
  }

  // ============ 拖动手势 ============

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_showDeleteConfirm) return;
    setState(() {
      _dragExtent -= details.delta.dx;
      _dragExtent = _dragExtent.clamp(0.0, _deleteMaxDragExtent);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_showDeleteConfirm) return;

    if (_dragExtent > _deleteMaxDragExtent / 2) {
      _animateTo(_deleteMaxDragExtent);
      _isOpen = true;
    } else {
      _close();
    }
  }

  void _animateTo(double target) {
    final start = _dragExtent;
    final animation = Tween<double>(
      begin: start,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    void listener() {
      setState(() {
        _dragExtent = animation.value;
      });
    }

    animation.addListener(listener);
    _controller.forward(from: 0).then((_) {
      animation.removeListener(listener);
    });
  }

  void _close() {
    if (_showDeleteConfirm) {
      setState(() {
        _showDeleteConfirm = false;
      });
    }
    _animateTo(0);
    _isOpen = false;
  }

  void _showDeleteConfirmation() {
    HapticFeedback.mediumImpact();
    setState(() {
      _showDeleteConfirm = true;
    });
    _animateTo(_actionButtonWidth * 2.3);
  }

  void _handleAction(SwipeAction action) {
    HapticFeedback.mediumImpact();
    _close();
    widget.onSwipeAction?.call(action);
  }

  // ============ 顶层入口 ============

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.isDesktop) {
      return _buildDesktopItem(context, isDark);
    }
    return _buildMobileItem(context, isDark);
  }

  // ============ 桌面端 ============

  Widget _buildDesktopItem(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, isDark),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: _buildCard(isDark),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, bool isDark) {
    showMenu<SwipeAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: SwipeAction.read,
          child: Row(
            children: [
              Icon(
                widget.chat.unreadCount > 0
                    ? Icons.mark_chat_read
                    : Icons.mark_chat_unread,
                size: 20,
                color: _kListPrimary,
              ),
              const SizedBox(width: 12),
              Text(widget.chat.unreadCount > 0 ? '标为已读' : '标为未读'),
            ],
          ),
        ),
        PopupMenuItem(
          value: SwipeAction.pin,
          child: Row(
            children: [
              Icon(
                widget.chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                size: 20,
                color: Colors.grey,
              ),
              const SizedBox(width: 12),
              Text(widget.chat.isPinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
        PopupMenuItem(
          value: SwipeAction.mute,
          child: Row(
            children: [
              Icon(
                widget.chat.isMuted
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                size: 20,
                color: Colors.orange,
              ),
              const SizedBox(width: 12),
              Text(widget.chat.isMuted ? '取消静音' : '静音'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: SwipeAction.delete,
          child: Row(
            children: const [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        widget.onSwipeAction?.call(value);
      }
    });
  }

  // ============ 移动端（带左滑） ============

  Widget _buildMobileItem(BuildContext context, bool isDark) {
    return ClipRect(
      // 用 ClipRect（矩形裁剪，无圆角）把左滑操作按钮限制在这一行内部，
      // 保证前景 translate 时不会越出行边界
      child: IntrinsicHeight(
        child: Stack(
          children: [
            // 底层：滑动操作按钮
            Positioned.fill(
              child: _showDeleteConfirm
                  ? _buildDeleteConfirmButtons()
                  : _buildNormalButtons(),
            ),
            // 前景行：跟随手指偏移
            GestureDetector(
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onTap: () {
                if (_isOpen) {
                  _close();
                } else {
                  HapticFeedback.selectionClick();
                  widget.onTap?.call();
                }
              },
              onLongPress: widget.onLongPress != null
                  ? () {
                      HapticFeedback.heavyImpact();
                      widget.onLongPress?.call();
                    }
                  : null,
              child: Transform.translate(
                offset: Offset(-_dragExtent, 0),
                child: _buildCard(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ActionButton(
          icon: Icons.done_all,
          label: widget.chat.unreadCount > 0 ? '已读' : '未读',
          color: _kListPrimary,
          onTap: () => _handleAction(SwipeAction.read),
        ),
        _ActionButton(
          icon: widget.chat.isMuted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: widget.chat.isMuted ? '取消静音' : '静音',
          color: const Color(0xFFFF9500),
          onTap: () => _handleAction(SwipeAction.mute),
        ),
        _ActionButton(
          icon: widget.chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: widget.chat.isPinned ? '取消置顶' : '置顶',
          color: const Color(0xFF8E8E93),
          onTap: () => _handleAction(SwipeAction.pin),
        ),
        _ActionButton(
          icon: Icons.delete_outline,
          label: '删除',
          color: const Color(0xFFFF3B30),
          onTap: _showDeleteConfirmation,
        ),
      ],
    );
  }

  Widget _buildDeleteConfirmButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.heavyImpact();
            _close();
            widget.onSwipeAction?.call(SwipeAction.delete);
          },
          child: Container(
            width: _actionButtonWidth * 2.3,
            color: const Color(0xFFFF3B30),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_forever, color: Colors.white, size: 24),
                SizedBox(height: 2),
                Text(
                  '删除',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============ 卡片主体（前景） ============

  /// 单行前景 —— **扁平样式**：
  ///   · 未选中：跟 Scaffold 一样的**不透明背景**（浅色为白色，深色为 #0E1015），
  ///     以确保能盖住底层的左滑操作按钮（未读/静音/置顶/删除）
  ///   · 选中：极淡主色底 (#F0F7FF) + 左侧 3px 主色 accent 竖条
  ///
  /// 已彻底移除卡片圆角、阴影、边框和底部装饰条。
  Widget _buildCard(bool isDark) {
    final selected = widget.isSelected;
    final Color bg = selected
        ? (isDark ? _kListSelectedBgDark : _kListSelectedBgLight)
        : (isDark ? const Color(0xFF0E1015) : Colors.white);

    return Container(
      color: bg,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选中态左侧主色 accent bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 3 : 0,
              color: _kListPrimary,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  selected ? _kRowHPadding - 3 : _kRowHPadding,
                  _kRowVPadding,
                  _kRowHPadding,
                  _kRowVPadding,
                ),
                child: _buildContent(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final Color titleColor =
        isDark ? AppColors.darkTextPrimary : _kListTitleText;
    final Color subColor =
        isDark ? AppColors.darkTextSecondary : _kListSubText;
    final Color timeColor =
        isDark ? AppColors.darkTextTertiary : _kListTimeText;

    // 判断底部是否需要 Chip 排
    final hasChips = widget.chat.isPinned ||
        widget.chat.isMuted ||
        (widget.showPendingApprovalDot);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ============ 左侧：头像 + 未读徽标 + 在线点 ============
        _AvatarBlock(
          chat: widget.chat,
          isDark: isDark,
        ),
        const SizedBox(width: _kAvatarGap),
        // ============ 右侧：名字 / 消息 / Chip 排 ============
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：名字 + 时间
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.chat.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.badgeText != null && widget.badgeText!.isNotEmpty)
                          MemberBadgeWidget(
                            isMember: true,
                            badgeText: widget.badgeText,
                            badgeColor: widget.badgeColor,
                            fontSize: 9,
                            margin: const EdgeInsets.only(left: 4),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.chat.time,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: timeColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 第二行：消息内容
              _buildLastMessage(isDark, subColor),
              // 第三行（可选）：Chip 排
              if (hasChips) ...[
                const SizedBox(height: 8),
                _buildStatusChips(isDark),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ============ 状态 Chip 排 ============

  Widget _buildStatusChips(bool isDark) {
    final chips = <Widget>[];

    if (widget.chat.isPinned) {
      chips.add(
        _StatusChip(
          icon: Icons.push_pin_rounded,
          label: '已置顶',
          fg: _kListPrimary,
          bg: _kListPrimary.withOpacity(isDark ? 0.20 : 0.12),
        ),
      );
    }
    if (widget.chat.isMuted) {
      chips.add(
        _StatusChip(
          icon: Icons.notifications_off_rounded,
          label: '免打扰',
          fg: isDark ? Colors.white70 : const Color(0xFF6B7280),
          bg: isDark
              ? Colors.white.withOpacity(0.08)
              : const Color(0xFFF1F2F4),
        ),
      );
    }
    if (widget.showPendingApprovalDot) {
      final pendingCount = widget.chat.pendingJoinRequestCount;
      chips.add(
        _StatusChip(
          icon: Icons.notification_important_rounded,
          label: pendingCount > 0
              ? (pendingCount > 99 ? '待审批 99+' : '待审批 $pendingCount')
              : '待审批',
          fg: const Color(0xFFDC2626),
          bg: const Color(0xFFFEE2E2),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  // ============ 消息行 =============

  Widget _buildLastMessage(bool isDark, Color subColor) {
    final Color textColor = subColor;

    // 优先级：typing > draft > 正文
    if (widget.typingText != null && widget.typingText!.isNotEmpty) {
      return Text(
        widget.typingText!,
        style: const TextStyle(
          fontSize: 14,
          color: _kListPrimary,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final senderText = widget.chat.type == ChatItemType.group &&
            widget.chat.lastMessageSender != null
        ? '${widget.chat.lastMessageSender}: '
        : '';

    if (widget.chat.draft != null && widget.chat.draft!.isNotEmpty) {
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '草稿: ',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: widget.chat.draft,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // 类型前缀图标
    Widget? prefixIcon;
    String? typeText;
    final msgType = widget.chat.lastMessageType;
    if (msgType != null) {
      if (msgType == MessageContentType.photo) {
        prefixIcon = Icon(Icons.photo, size: 15, color: textColor);
        typeText = '[图片]';
      } else if (msgType == MessageContentType.video) {
        prefixIcon = Icon(Icons.videocam, size: 15, color: textColor);
        typeText = '[视频]';
      } else if (msgType == MessageContentType.voice) {
        prefixIcon = Icon(Icons.mic, size: 15, color: textColor);
        typeText = '[语音]';
      } else if (msgType == MessageContentType.file) {
        prefixIcon = Icon(Icons.insert_drive_file, size: 15, color: textColor);
        typeText = '[文件]';
      } else if (msgType == MessageContentType.sticker) {
        prefixIcon = Icon(Icons.emoji_emotions, size: 15, color: textColor);
        typeText = '[表情]';
      } else if (msgType == MessageContentType.location) {
        prefixIcon = Icon(Icons.location_on, size: 15, color: textColor);
        typeText = '[位置]';
      } else if (msgType == MessageContentType.contact) {
        prefixIcon = Icon(
          Icons.contact_page_outlined,
          size: 15,
          color: textColor,
        );
        typeText = '[联系人名片]';
      } else if (msgType == MessageContentType.call) {
        prefixIcon = Icon(Icons.call, size: 15, color: textColor);
        typeText = '[通话]';
      }
    }

    final displayMessage =
        (widget.chat.lastMessage == null || widget.chat.lastMessage!.isEmpty)
            ? typeText
            : widget.chat.lastMessage;

    return Row(
      children: [
        if (prefixIcon != null) ...[prefixIcon, const SizedBox(width: 4)],
        Expanded(
          child: _buildMessageContent(senderText, textColor, displayMessage),
        ),
      ],
    );
  }

  Widget _buildMessageContent(
    String senderText,
    Color textColor,
    String? displayMsg,
  ) {
    final message = displayMsg ?? widget.chat.lastMessage ?? '';
    if (message.isEmpty && senderText.isEmpty) {
      return Text(
        '快来发送第一条消息吧~',
        style: TextStyle(
          fontSize: 13,
          color: textColor.withValues(alpha: 0.6),
          fontStyle: FontStyle.italic,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (message.isEmpty) {
      return Text(
        senderText,
        style: TextStyle(fontSize: 14, color: textColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // 检测是否是 1-3 个纯表情
    final chars = message.trim().characters.toList();
    if (chars.isNotEmpty && chars.length <= 3) {
      final animatedEmojis = <AnimatedEmoji>[];
      bool allEmoji = true;

      for (final char in chars) {
        final animated = EmojiAnimations.findByEmoji(char);
        if (animated != null) {
          animatedEmojis.add(animated);
        } else if (!_isEmoji(char)) {
          allEmoji = false;
          break;
        }
      }

      if (allEmoji && animatedEmojis.isNotEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (senderText.isNotEmpty)
              Text(
                senderText,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ...animatedEmojis.map(
              (emoji) => SizedBox(
                width: 20,
                height: 20,
                child: Lottie.asset(
                  emoji.path,
                  repeat: false,
                  animate: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        );
      }
    }

    return _buildRichMessagePreview(senderText, message, textColor);
  }

  Widget _buildRichMessagePreview(
    String senderText,
    String message,
    Color textColor,
  ) {
    final chars = message.characters.toList();
    final widgets = <Widget>[];

    if (senderText.isNotEmpty) {
      widgets.add(
        Text(senderText, style: TextStyle(fontSize: 14, color: textColor)),
      );
    }

    String textBuffer = '';
    for (final char in chars) {
      final animated = EmojiAnimations.findByEmoji(char);
      if (animated != null) {
        if (textBuffer.isNotEmpty) {
          widgets.add(
            Text(textBuffer,
                style: TextStyle(fontSize: 14, color: textColor)),
          );
          textBuffer = '';
        }
        widgets.add(
          SizedBox(
            width: 18,
            height: 18,
            child: Lottie.asset(
              animated.path,
              repeat: false,
              animate: false,
              fit: BoxFit.contain,
            ),
          ),
        );
      } else {
        textBuffer += char;
      }
    }

    if (textBuffer.isNotEmpty) {
      widgets.add(
        Flexible(
          child: Text(
            textBuffer,
            style: TextStyle(fontSize: 14, color: textColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    if (widgets.length == (senderText.isNotEmpty ? 2 : 1) &&
        widgets.last is Flexible) {
      return Text(
        senderText + message,
        style: TextStyle(fontSize: 14, color: textColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }

  bool _isEmoji(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    return (rune >= 0x1F300 && rune <= 0x1F9FF) ||
        (rune >= 0x2600 && rune <= 0x26FF) ||
        (rune >= 0x2700 && rune <= 0x27BF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        (rune >= 0x1F600 && rune <= 0x1F64F) ||
        (rune >= 0x1F680 && rune <= 0x1F6FF) ||
        (rune >= 0x1F1E0 && rune <= 0x1F1FF);
  }
}

// ============================================================
// 头像块（含右上未读徽标 + 右下在线绿点）
// ============================================================

class _AvatarBlock extends StatelessWidget {
  final ChatItem chat;
  final bool isDark;

  const _AvatarBlock({
    required this.chat,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final unread = chat.unreadCount;
    final showUnread = unread > 0;

    return SizedBox(
      width: _kAvatarSize,
      height: _kAvatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarWidget(
            name: chat.name,
            avatar: chat.avatar,
            userId: chat.type == ChatItemType.private
                ? (chat.targetUserId ?? chat.id)
                : chat.id,
            size: _kAvatarSize,
            borderRadius: _kAvatarSize / 2,
          ),
          // 右下：在线绿点
          if (chat.isOnline)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? _kListStickerCutout : Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
          // 右上：未读数徽标（贴在头像上）
          if (showUnread)
            Positioned(
              right: -6,
              top: -6,
              child: _UnreadStickerBadge(
                count: unread,
                muted: chat.isMuted,
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }
}

class _UnreadStickerBadge extends StatelessWidget {
  final int count;
  final bool muted;
  final bool isDark;

  const _UnreadStickerBadge({
    required this.count,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = muted ? _kListMutedTint : _kListPrimary;
    final label = count > 99 ? '99+' : count.toString();

    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? _kListStickerCutout : Colors.white,
          width: 2,
        ),
        boxShadow: muted
            ? null
            : [
                BoxShadow(
                  color: _kListPrimary.withOpacity(0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.0,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ============================================================
// 状态 Chip（置顶 / 免打扰 / 待审批）
// ============================================================

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 左滑操作按钮
// ============================================================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        color: color,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
