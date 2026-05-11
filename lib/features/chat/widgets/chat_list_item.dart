import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../providers/chat_provider.dart';

/// 左滑操作类型
enum SwipeAction { pin, mute, read, delete }

class ChatListItem extends StatefulWidget {
  final ChatItem chat;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Function(SwipeAction)? onSwipeAction;
  final bool isOfficial; // 是否是官方用户/群组/频道
  final bool isSelected; // 是否被选中（桌面端用）
  final bool isDesktop; // 是否是桌面端（禁用滑动，启用右键菜单）
  final bool showPendingApprovalDot;
  final String? typingText;

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
  });

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _deleteController; // 删除确认动画控制器
  double _dragExtent = 0;
  bool _isOpen = false;
  bool _showDeleteConfirm = false; // 是否显示删除确认

  static const double _actionButtonWidth = 70.0;
  static const double _normalMaxDragExtent =
      _actionButtonWidth * 3; // 3个按钮（未读、静音、置顶）
  static const double _deleteMaxDragExtent = _actionButtonWidth * 4; // 加上删除按钮

  double get _maxDragExtent => _showDeleteConfirm
      ? _actionButtonWidth * 2.3 // 删除确认模式（更紧凑）
      : _deleteMaxDragExtent;

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

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_showDeleteConfirm) return; // 删除确认模式下不允许拖动

    setState(() {
      _dragExtent -= details.delta.dx;
      _dragExtent = _dragExtent.clamp(0.0, _deleteMaxDragExtent);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_showDeleteConfirm) return;

    if (_dragExtent > _deleteMaxDragExtent / 2) {
      // 打开
      _animateTo(_deleteMaxDragExtent);
      _isOpen = true;
    } else {
      // 关闭
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

  /// 显示删除确认（二次展开）
  void _showDeleteConfirmation() {
    HapticFeedback.mediumImpact();
    setState(() {
      _showDeleteConfirm = true;
    });
    // 动画展开到确认删除的宽度（更紧凑）
    _animateTo(_actionButtonWidth * 2.3);
  }

  void _handleAction(SwipeAction action) {
    HapticFeedback.mediumImpact();
    _close();
    widget.onSwipeAction?.call(action);
  }

  /// 构建普通操作按钮
  Widget _buildNormalButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 标记已读
        _ActionButton(
          icon: Icons.done_all,
          label: widget.chat.unreadCount > 0 ? '已读' : '未读',
          color: AppColors.primary,
          onTap: () => _handleAction(SwipeAction.read),
        ),
        // 静音/取消静音
        _ActionButton(
          icon: widget.chat.isMuted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: widget.chat.isMuted ? '取消静音' : '静音',
          color: const Color(0xFFFF9500),
          onTap: () => _handleAction(SwipeAction.mute),
        ),
        // 置顶/取消置顶
        _ActionButton(
          icon: widget.chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: widget.chat.isPinned ? '取消置顶' : '置顶',
          color: const Color(0xFF8E8E93),
          onTap: () => _handleAction(SwipeAction.pin),
        ),
        // 删除（点击后展开确认）
        _ActionButton(
          icon: Icons.delete_outline,
          label: '删除',
          color: const Color(0xFFFF3B30),
          onTap: _showDeleteConfirmation,
        ),
      ],
    );
  }

  /// 构建删除确认按钮（二次展开）
  Widget _buildDeleteConfirmButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 确认删除按钮
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 桌面端：使用右键菜单，无滑动
    if (widget.isDesktop) {
      return _buildDesktopItem(context, isDark);
    }

    // 移动端：使用滑动操作
    return _buildMobileItem(context, isDark);
  }

  /// 桌面端列表项（右键菜单）
  Widget _buildDesktopItem(BuildContext context, bool isDark) {
    return Column(
      children: [
        SizedBox(
          height: 76,
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTapUp: (details) =>
                _showContextMenu(context, details.globalPosition, isDark),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                color: widget.isSelected
                    ? (isDark
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.primary.withOpacity(0.1))
                    : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: _buildContent(isDark),
              ),
            ),
          ),
        ),
        // 分隔线
        Padding(
          padding: const EdgeInsets.only(left: 82),
          child: Divider(
            height: 1,
            thickness: 0.5,
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
        ),
      ],
    );
  }

  /// 显示右键菜单
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
                color: AppColors.primary,
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
            children: [
              const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              const SizedBox(width: 12),
              const Text('删除', style: TextStyle(color: Colors.red)),
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

  /// 移动端列表项（滑动操作）
  Widget _buildMobileItem(BuildContext context, bool isDark) {
    return Column(
      children: [
        SizedBox(
          height: 76, // 统一高度
          child: Stack(
            children: [
              // 背景操作按钮
              Positioned.fill(
                child: _showDeleteConfirm
                    ? _buildDeleteConfirmButtons()
                    : _buildNormalButtons(),
              ),
              // 前景内容
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
                        // 触觉反馈
                        HapticFeedback.heavyImpact();
                        widget.onLongPress?.call();
                      }
                    : null,
                child: Transform.translate(
                  offset: Offset(-_dragExtent, 0),
                  child: Container(
                    color: widget.isSelected
                        ? (isDark
                            ? AppColors.primary.withOpacity(0.15)
                            : AppColors.primary.withOpacity(0.1))
                        : (isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: _buildContent(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 分隔线
        Padding(
          padding: const EdgeInsets.only(left: 82),
          child: Divider(
            height: 1,
            thickness: 0.5,
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          ),
        ),
      ],
    );
  }

  /// 构建列表项内容（头像、名称、消息等）
  Widget _buildContent(bool isDark) {
    return Row(
      children: [
        // 头像
        Stack(
          children: [
            AvatarWidget(
              name: widget.chat.name,
              avatar: widget.chat.avatar,
              userId: widget.chat.type == ChatItemType.private
                  ? (widget.chat.targetUserId ?? widget.chat.id)
                  : widget.chat.id,
              size: 54,
              premiumType: widget.chat.premiumType,
            ),
            // 在线状态
            if (widget.chat.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBackground
                          : AppColors.lightBackground,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        // 内容
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 第一行：名称 + 表情状态 + 类型标签 + 静音图标 + 时间
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: ColoredNameWidget(
                            name: widget.chat.name,
                            nicknameColor: widget.chat.nicknameColor,
                            premiumType: widget.chat.premiumType,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            defaultColor: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 表情状态
                        if (widget.chat.emojiAvatar != null &&
                            widget.chat.emojiAvatar!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          EmojiStatusWidget(
                            emoji: widget.chat.emojiAvatar!,
                            size: 18,
                          ),
                        ],
                        // 官方认证标识（在名字/表情后面）
                        if (widget.isOfficial) ...[
                          const SizedBox(width: 4),
                          const OfficialBadge(size: 16),
                        ],
                        // 类型标签（放在名字后面）
                        if (widget.chat.type != ChatItemType.private)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getTagBackgroundColor(isDark),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getTypeLabel(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _getTagTextColor(isDark),
                              ),
                            ),
                          ),
                        if (widget.showPendingApprovalDot) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.25),
                                  blurRadius: 4,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ],
                        // 静音图标 - TG 风格
                        if (widget.chat.isMuted)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.volume_off_rounded,
                              size: 16,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        // 认证标志
                        if (widget.chat.isVerified)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.verified,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 时间
                  Text(
                    widget.chat.time,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 第二行：最后消息 + 置顶/未读
              Row(
                children: [
                  Expanded(child: _buildLastMessage(isDark)),
                  const SizedBox(width: 8),
                  // 置顶图标
                  if (widget.chat.isPinned && widget.chat.unreadCount == 0)
                    Icon(
                      Icons.push_pin,
                      size: 16,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    )
                  // 未读数 - TG 风格
                  else if (widget.chat.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.chat.isMuted
                            ? (isDark ? Colors.white24 : Colors.black26)
                            : AppColors.success,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.chat.unreadCount > 999
                            ? '${(widget.chat.unreadCount / 1000).toStringAsFixed(1)}K'
                            : widget.chat.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getTagBackgroundColor(bool isDark) {
    if (isDark) {
      return widget.chat.type == ChatItemType.channel
          ? const Color(0xFF1E3A4C)
          : const Color(0xFF1E3C2E);
    }
    return widget.chat.type == ChatItemType.channel
        ? AppColors.channelTagBackground
        : AppColors.groupTagBackground;
  }

  Color _getTagTextColor(bool isDark) {
    if (isDark) {
      return widget.chat.type == ChatItemType.channel
          ? const Color(0xFF65AADD)
          : const Color(0xFF7BC862);
    }
    return widget.chat.type == ChatItemType.channel
        ? AppColors.channelTagText
        : AppColors.groupTagText;
  }

  String _getTypeLabel() {
    switch (widget.chat.type) {
      case ChatItemType.group:
        return '群组';
      case ChatItemType.channel:
        return '频道';
      default:
        return '';
    }
  }

  Widget _buildLastMessage(bool isDark) {
    final textColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    if (widget.typingText != null && widget.typingText!.isNotEmpty) {
      return Text(
        widget.typingText!,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.blue,
          fontStyle: FontStyle.italic,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final senderText = widget.chat.type == ChatItemType.group &&
            widget.chat.lastMessageSender != null
        ? '${widget.chat.lastMessageSender}: '
        : '';

    // 草稿
    if (widget.chat.draft != null && widget.chat.draft!.isNotEmpty) {
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '草稿: ',
              style: TextStyle(color: AppColors.error, fontSize: 14),
            ),
            TextSpan(
              text: widget.chat.draft,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // 消息内容前缀图标
    Widget? prefixIcon;
    String? typeText; // 类型文本（用于替代空内容）
    final msgType = widget.chat.lastMessageType;
    if (msgType != null) {
      if (msgType == MessageContentType.photo) {
        prefixIcon = Icon(Icons.photo, size: 16, color: textColor);
        typeText = '[图片]';
      } else if (msgType == MessageContentType.video) {
        prefixIcon = Icon(Icons.videocam, size: 16, color: textColor);
        typeText = '[视频]';
      } else if (msgType == MessageContentType.voice) {
        prefixIcon = Icon(Icons.mic, size: 16, color: textColor);
        typeText = '[语音]';
      } else if (msgType == MessageContentType.file) {
        prefixIcon = Icon(Icons.insert_drive_file, size: 16, color: textColor);
        typeText = '[文件]';
      } else if (msgType == MessageContentType.sticker) {
        prefixIcon = Icon(Icons.emoji_emotions, size: 16, color: textColor);
        typeText = '[表情]';
      } else if (msgType == MessageContentType.location) {
        prefixIcon = Icon(Icons.location_on, size: 16, color: textColor);
        typeText = '[位置]';
      } else if (msgType == MessageContentType.contact) {
        prefixIcon = Icon(
          Icons.contact_page_outlined,
          size: 16,
          color: textColor,
        );
        typeText = '[联系人名片]';
      } else if (msgType == MessageContentType.call) {
        prefixIcon = Icon(Icons.call, size: 16, color: textColor);
        // 通话消息直接显示内容（如"语音通话 00:03"）
        typeText = '[通话]';
      }
    }

    // 如果消息内容为空但有类型，使用类型文本
    final displayMessage =
        (widget.chat.lastMessage == null || widget.chat.lastMessage!.isEmpty)
            ? typeText
            : widget.chat.lastMessage;

    return Row(
      children: [
        if (widget.showPendingApprovalDot) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.chat.pendingJoinRequestCount > 0
                  ? '待审批 ${widget.chat.pendingJoinRequestCount > 99 ? '99+' : widget.chat.pendingJoinRequestCount}'
                  : '待审批',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (prefixIcon != null) ...[prefixIcon, const SizedBox(width: 4)],
        Expanded(
          child: _buildMessageContent(senderText, textColor, displayMessage),
        ),
      ],
    );
  }

  /// 构建消息内容（支持动画表情）
  Widget _buildMessageContent(
    String senderText,
    Color textColor,
    String? displayMsg,
  ) {
    final message = displayMsg ?? widget.chat.lastMessage ?? '';
    if (message.isEmpty && senderText.isEmpty) {
      // 没有消息时显示提示文案
      return Text(
        '快来发送第一条消息吧～',
        style: TextStyle(
          fontSize: 14,
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

    // 检测是否是纯表情消息（1-3个表情）
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

      // 如果是纯表情消息，渲染动画
      if (allEmoji && animatedEmojis.isNotEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (senderText.isNotEmpty)
              Text(
                senderText,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            // 列表预览中禁用动画以节省 CPU/GPU
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

    // 普通消息或混合内容 - 渲染带内嵌小动画的富文本
    return _buildRichMessagePreview(senderText, message, textColor);
  }

  /// 构建富文本消息预览（文字+小动画表情）
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
        // 先添加累积的文本
        if (textBuffer.isNotEmpty) {
          widgets.add(
            Text(textBuffer, style: TextStyle(fontSize: 14, color: textColor)),
          );
          textBuffer = '';
        }
        // 添加动画表情（列表预览中禁用动画）
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

    // 添加剩余文本
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

    // 如果没有动画表情，使用普通文本
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

  /// 检测字符是否是emoji
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

/// 左滑操作按钮
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
