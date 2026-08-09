// 文件用途：提供 ChatInputSendCallback 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 ChatInputSendCallback，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';
import 'emoji_picker.dart';

// 关键声明：chat input bar 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
typedef ChatInputSendCallback = void Function(String text,
    {bool? refocusInput});

/// TG 风格输入栏（带表情选择器）
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatInputSendCallback onSend;
  final VoidCallback? onAttachment;
  final VoidCallback? onVoice;
  final VoidCallback? onBurnAfterReadToggle;
  final VoidCallback? onAnonymousToggle;
  final bool showEmojiPicker;
  final bool showAttachmentPicker;
  final VoidCallback? onEmojiToggle;
  final VoidCallback? onInputTap;
  final bool burnAfterReadEnabled;
  final bool allowBurnAfterRead;
  final bool anonymousEnabled;
  final bool allowAnonymous;
  final bool allowVoice;
  final double fontSize;

  /// 有待发附件（图片等）时强制显示发送按钮
  final bool hasPendingAttachments;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onAttachment,
    this.onVoice,
    this.onBurnAfterReadToggle,
    this.onAnonymousToggle,
    this.showEmojiPicker = false,
    this.showAttachmentPicker = false,
    this.onEmojiToggle,
    this.onInputTap,
    this.burnAfterReadEnabled = false,
    this.allowBurnAfterRead = true,
    this.anonymousEnabled = false,
    this.allowAnonymous = false,
    this.allowVoice = true,
    this.fontSize = 16,
    this.hasPendingAttachments = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasText = false;
  final GlobalKey _emojiButtonKey = GlobalKey();
  OverlayEntry? _emojiOverlay;

  bool get _isDesktop => PlatformUtils.isPhysicalDesktop;

  String _labelText({
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    switch (AppLocalizations.currentLanguage) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _removeEmojiOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _removeEmojiOverlay() {
    _emojiOverlay?.remove();
    _emojiOverlay = null;
  }

  void _showDesktopEmojiPicker() {
    if (_emojiOverlay != null) {
      _removeEmojiOverlay();
      widget.onEmojiToggle?.call();
      return;
    }

    final renderBox =
        _emojiButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _emojiOverlay = OverlayEntry(
      builder: (context) => _DesktopEmojiOverlay(
        anchorPosition: position,
        anchorSize: size,
        onEmojiSelected: _handleEmojiSelected,
        onDismiss: () {
          _removeEmojiOverlay();
          widget.onEmojiToggle?.call();
        },
      ),
    );

    Overlay.of(context).insert(_emojiOverlay!);
    widget.onEmojiToggle?.call();
  }

  void _handleEmojiSelected(String emoji, {bool isAnimated = false}) {
    if (emoji == 'BACKSPACE') {
      // 删除一个字符
      final text = widget.controller.text;
      final selection = widget.controller.selection;
      if (text.isNotEmpty && selection.isValid && selection.baseOffset > 0) {
        // 处理emoji删除（可能是多个字符）
        final beforeCursor = text.substring(0, selection.baseOffset);
        final afterCursor = text.substring(selection.baseOffset);

        // 检查是否是emoji（通常是2-4个代码单元）
        int deleteCount = 1;
        if (beforeCursor.isNotEmpty) {
          final lastChar = beforeCursor.characters.last;
          deleteCount = lastChar.length;
        }

        final newText =
            beforeCursor.substring(0, beforeCursor.length - deleteCount) +
                afterCursor;
        widget.controller.text = newText;
        widget.controller.selection = TextSelection.collapsed(
          offset: selection.baseOffset - deleteCount,
        );
      }
    } else {
      // 直接发送表情
      HapticFeedback.lightImpact();
      widget.onSend(emoji, refocusInput: false);
    }
  }

  void _toggleMobileEmojiPicker() {
    HapticFeedback.selectionClick();
    if (widget.showEmojiPicker) {
      widget.onEmojiToggle?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.focusNode.requestFocus();
        }
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onEmojiToggle?.call();
      }
    });
  }

  Widget _buildTrailingActionButton(bool isDark) {
    if (_hasText || widget.hasPendingAttachments) {
      return _SendButton(
        key: const Key('chat_send_button'),
        onPressed: () {
          HapticFeedback.lightImpact();
          widget.onSend(widget.controller.text);
        },
      );
    }

    if (!widget.allowVoice) {
      return SizedBox(
        key: const Key('chat_voice_hidden_spacer'),
        width: _isDesktop ? 44 : 40,
        height: _isDesktop ? 44 : 40,
      );
    }

    return _CircleIconButton(
      key: const Key('chat_voice_button'),
      icon: Icons.mic,
      onPressed: widget.onVoice,
      backgroundColor: isDark
          ? AppColors.darkControlBackgroundStrong
          : AppColors.lightSurface,
      iconColor: isDark
          ? AppColors.primaryFor(context)
          : AppColors.textSecondaryFor(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isAttachmentOpen = widget.showAttachmentPicker;
    final panelColor = isDark ? AppColors.darkSurface : const Color(0xFFF7F7F7);
    final bottomPadding = _isDesktop
        ? 12.0
        : (widget.showEmojiPicker || widget.showAttachmentPicker
            ? 8.0
            : MediaQuery.of(context).padding.bottom + 8);
    final horizontalPadding = _isDesktop ? 16.0 : 8.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入区域（毛玻璃效果）
        ClipRect(
          child: _InputBarBackdrop(
            enabled: !isAttachmentOpen,
            child: Container(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: _isDesktop ? 12 : 8,
                bottom: bottomPadding,
              ),
              decoration: BoxDecoration(
                color: isAttachmentOpen
                    ? panelColor
                    : (isDark ? AppColors.darkSurface : Colors.white)
                        .withOpacity(_isDesktop ? 0.94 : 0.90),
                border: isAttachmentOpen || _isDesktop
                    ? Border(
                        top: BorderSide(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : const Color(0xFFE8E8E8),
                          width: 0.5,
                        ),
                      )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.onAttachment != null) ...[
                    // 附件按钮 - 微信式加号入口
                    _CircleIconButton(
                      key: const Key('chat_attachment_button'),
                      icon: Icons.add_circle_outline_rounded,
                      onPressed: widget.onAttachment,
                      backgroundColor: Colors.transparent,
                      iconColor: isDark ? AppColors.darkTextSecondary : null,
                      iconSize: _isDesktop ? 32 : 30,
                      showBorder: false,
                    ),
                    SizedBox(width: _isDesktop ? 12 : 8),
                  ],

                  // 输入框
                  Expanded(
                    child: Container(
                      constraints: BoxConstraints(
                          maxHeight: 120, minHeight: _isDesktop ? 44 : 40),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkInputBackground
                            : AppColors.lightInputBackground,
                        borderRadius:
                            BorderRadius.circular(_isDesktop ? 22 : 20),
                        border: _isDesktop
                            ? Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.black.withOpacity(0.06),
                                width: 1,
                              )
                            : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // 文本输入
                          Expanded(
                            child: Focus(
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter &&
                                    (widget.controller.text.trim().isNotEmpty ||
                                        widget.hasPendingAttachments)) {
                                  HapticFeedback.lightImpact();
                                  widget.onSend(widget.controller.text);
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                key: const Key('chat_message_input'),
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                maxLines: 5,
                                minLines: 1,
                                textInputAction: TextInputAction.send,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: l10n.typeMessage,
                                  hintStyle: TextStyle(
                                    fontSize: widget.fontSize,
                                    color: AppColors.textTertiaryFor(context),
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  hoverColor: Colors.transparent,
                                  fillColor: Colors.transparent,
                                  filled: false,
                                  contentPadding: EdgeInsets.only(
                                    left: _isDesktop ? 20 : 14,
                                    right: _isDesktop ? 20 : 0, // 移动端右边由表情按钮占用
                                    top: _isDesktop ? 12 : 10,
                                    bottom: _isDesktop ? 12 : 10,
                                  ),
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  fontSize: widget.fontSize,
                                  color: AppColors.textPrimaryFor(context),
                                ),
                                onTap: () {
                                  // 点击输入框时隐藏表情选择器
                                  if (widget.showEmojiPicker) {
                                    widget.onEmojiToggle?.call();
                                  }
                                  widget.onInputTap?.call();
                                },
                                onSubmitted: (text) {
                                  if (text.trim().isNotEmpty ||
                                      widget.hasPendingAttachments) {
                                    HapticFeedback.lightImpact();
                                    widget.onSend(text);
                                  }
                                },
                                onChanged: (text) {
                                  // Android 真机的物理/自动化 Enter 有时不会触发
                                  // TextInputAction.send，而是向多行输入框插入换行。
                                  // 对移动端的行尾 Enter 做发送兜底；粘贴的中间换行不受影响。
                                  if (!_isDesktop &&
                                      text.endsWith('\n') &&
                                      text.trim().isNotEmpty) {
                                    final message =
                                        text.substring(0, text.length - 1);
                                    widget.controller.value = TextEditingValue(
                                      text: message,
                                      selection: TextSelection.collapsed(
                                        offset: message.length,
                                      ),
                                    );
                                    HapticFeedback.lightImpact();
                                    widget.onSend(message);
                                  }
                                },
                              ),
                            ),
                          ),

                          // 表情按钮 - 移动端在输入框内，桌面端在输入框外
                          if (!_isDesktop)
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: 8, bottom: 4),
                              child: GestureDetector(
                                key: _emojiButtonKey,
                                onTap: _toggleMobileEmojiPicker,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      widget.showEmojiPicker
                                          ? Icons.keyboard_rounded
                                          : Icons.emoji_emotions_outlined,
                                      key: ValueKey(widget.showEmojiPicker),
                                      size: 22,
                                      color: widget.showEmojiPicker
                                          ? AppColors.primaryFor(context)
                                          : (AppColors.textSecondaryFor(
                                              context)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(width: _isDesktop ? 12 : 8),

                  // 桌面端：表情按钮在输入框外部
                  if (widget.onAnonymousToggle != null &&
                      widget.allowAnonymous) ...[
                    Tooltip(
                      message: _labelText(
                        zhCN: widget.anonymousEnabled ? '关闭匿名发言' : '匿名发言',
                        zhTW: widget.anonymousEnabled ? '關閉匿名發言' : '匿名發言',
                        en: widget.anonymousEnabled
                            ? 'Turn off anonymous messages'
                            : 'Anonymous messages',
                      ),
                      child: _CircleIconButton(
                        key: const Key('chat_anonymous_button'),
                        icon: Icons.badge_outlined,
                        onPressed: widget.onAnonymousToggle,
                        backgroundColor: widget.anonymousEnabled
                            ? AppColors.primaryFor(context)
                            : Colors.transparent,
                        iconColor: widget.anonymousEnabled
                            ? Colors.white
                            : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondaryFor(context)),
                        iconSize: _isDesktop ? 23 : 21,
                        showBorder: false,
                      ),
                    ),
                    SizedBox(width: _isDesktop ? 8 : 4),
                  ],

                  if (_isDesktop)
                    _CircleIconButton(
                      key: _emojiButtonKey,
                      icon: widget.showEmojiPicker
                          ? Icons.keyboard_rounded
                          : Icons.emoji_emotions_outlined,
                      onPressed: _showDesktopEmojiPicker,
                      backgroundColor: isDark
                          ? AppColors.darkControlBackgroundStrong
                          : AppColors.lightSurface,
                      iconColor: isDark
                          ? AppColors.primaryFor(context)
                          : AppColors.textSecondaryFor(context),
                    ),

                  if (_isDesktop) const SizedBox(width: 8),

                  // 发送/语音按钮
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: _buildTrailingActionButton(isDark),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 表情选择器（仅移动端显示）
        if (!_isDesktop)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: widget.showEmojiPicker ? 280 : 0,
            child: TickerMode(
              // Animated emoji tiles remain mounted so the selected tab and
              // scroll position survive closing the panel. They must not keep
              // scheduling invisible frames while the panel height is zero.
              enabled: widget.showEmojiPicker,
              child: IgnorePointer(
                ignoring: !widget.showEmojiPicker,
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 280,
                  maxHeight: 280,
                  child: TGEmojiPicker(
                    height: 280,
                    onEmojiSelected: _handleEmojiSelected,
                    onStickerTap: () {
                      // 跳转到贴纸页面
                    },
                    onGifTap: () {
                      // 跳转到GIF页面
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 圆形图标按钮
class _InputBarBackdrop extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const _InputBarBackdrop({required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled || PlatformUtils.isAndroid) {
      return child;
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: child,
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double rotate;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final bool showBorder;

  const _CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.rotate = 0,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
    this.showBorder = true,
  });

  bool get _isDesktop => PlatformUtils.isPhysicalDesktop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = _isDesktop ? 44.0 : 40.0;
    final resolvedIconSize = iconSize ?? (_isDesktop ? 24.0 : 22.0);

    return GestureDetector(
      onTap: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!.call();
            },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor ??
              (isDark
                  ? AppColors.darkControlBackgroundStrong
                  : AppColors.lightSurface),
          shape: BoxShape.circle,
          border: _isDesktop && showBorder
              ? Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                  width: 1,
                )
              : null,
        ),
        child: Transform.rotate(
          angle: rotate * 3.14159 / 180,
          child: Icon(
            icon,
            size: resolvedIconSize,
            color: iconColor ??
                (isDark
                    ? AppColors.primaryFor(context)
                    : AppColors.textSecondaryFor(context)),
          ),
        ),
      ),
    );
  }
}

/// TG 风格发送按钮 - 蓝色纸飞机
class _SendButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SendButton({
    super.key,
    required this.onPressed,
  });

  bool get _isDesktop => PlatformUtils.isPhysicalDesktop;

  @override
  Widget build(BuildContext context) {
    final size = _isDesktop ? 44.0 : 40.0;
    final iconSize = _isDesktop ? 22.0 : 20.0;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6C9EFF),
              Color(0xFF5B7FFF),
            ],
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.send,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }
}

/// 桌面端表情选择器弹出层
class _DesktopEmojiOverlay extends StatelessWidget {
  final Offset anchorPosition;
  final Size anchorSize;
  final Function(String emoji, {bool isAnimated}) onEmojiSelected;
  final VoidCallback onDismiss;

  const _DesktopEmojiOverlay({
    required this.anchorPosition,
    required this.anchorSize,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    // 计算弹出位置 - 在按钮上方
    const pickerWidth = 380.0;
    const pickerHeight = 360.0;

    // 计算水平位置，确保不超出屏幕
    double left = anchorPosition.dx - pickerWidth + anchorSize.width + 20;
    if (left < 10) left = 10;
    if (left + pickerWidth > screenSize.width - 10) {
      left = screenSize.width - pickerWidth - 10;
    }

    // 计算垂直位置 - 在按钮上方
    double bottom = screenSize.height - anchorPosition.dy + 10;

    return Stack(
      children: [
        // 点击外部关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),

        // 表情选择器面板
        Positioned(
          left: left,
          bottom: bottom,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: pickerWidth,
              height: pickerHeight,
              decoration: BoxDecoration(
                color: AppColors.cardFor(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: TGEmojiPicker(
                  height: pickerHeight,
                  onEmojiSelected: onEmojiSelected,
                  onStickerTap: () {},
                  onGifTap: () {},
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
