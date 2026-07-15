import 'package:universal_io/io.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import 'emoji_picker.dart';

/// TG 风格输入栏（带表情选择器）
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(String) onSend;
  final VoidCallback? onAttachment;
  final VoidCallback? onVoice;
  final VoidCallback? onBurnAfterReadToggle;
  final bool showEmojiPicker;
  final VoidCallback? onEmojiToggle;
  final bool burnAfterReadEnabled;
  final bool allowBurnAfterRead;
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
    this.showEmojiPicker = false,
    this.onEmojiToggle,
    this.burnAfterReadEnabled = false,
    this.allowBurnAfterRead = true,
    this.hasPendingAttachments = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasText = false;
  final GlobalKey _emojiButtonKey = GlobalKey();
  OverlayEntry? _emojiOverlay;
  
  bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _removeEmojiOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
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
    
    final renderBox = _emojiButtonKey.currentContext?.findRenderObject() as RenderBox?;
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
        
        final newText = beforeCursor.substring(0, beforeCursor.length - deleteCount) + afterCursor;
        widget.controller.text = newText;
        widget.controller.selection = TextSelection.collapsed(
          offset: selection.baseOffset - deleteCount,
        );
      }
    } else {
      // 直接发送表情
      HapticFeedback.lightImpact();
      widget.onSend(emoji);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isDesktop) {
      return _buildDesktop(isDark);
    }
    return _buildMobile(isDark);
  }

  Widget _buildMobile(bool isDark) {
    final bottomPadding = widget.showEmojiPicker
        ? 6.0
        : MediaQuery.of(context).padding.bottom + 6;

    // ==== 全新配色 ====
    // 底部整体使用浅蓝渐变卡片，中间输入区改为白色 + 主色外描边（focus 时更明显），
    // 左右两端使用"实心主色圆形按钮"作为视觉锚点。
    final Color barBg = isDark ? const Color(0xFF12141A) : Colors.white;
    final Color topShadowColor =
        isDark ? Colors.black.withOpacity(0.45) : Colors.black.withOpacity(0.06);
    final Color inputBg =
        isDark ? const Color(0xFF1B1E27) : const Color(0xFFF3F6FB);
    final Color inputBorderColor = widget.focusNode.hasFocus
        ? AppColors.primary.withOpacity(0.55)
        : (isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE1E6EF));
    final Color hintColor =
        isDark ? Colors.white38 : const Color(0xFF9AA3B2);
    final Color textColor =
        isDark ? Colors.white : const Color(0xFF111827);
    final Color subtleIcon =
        isDark ? Colors.white70 : const Color(0xFF6B7280);
    final bool showSend = _hasText || widget.hasPendingAttachments;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: barBg,
            boxShadow: [
              BoxShadow(
                color: topShadowColor,
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ============ 左：主色实心 "+" 按钮 ============
              _PrimaryRoundButton(
                icon: Icons.add_rounded,
                onPressed: widget.onAttachment,
              ),
              if (widget.allowBurnAfterRead) ...[
                const SizedBox(width: 8),
                _BurnAfterReadChip(
                  active: widget.burnAfterReadEnabled,
                  onPressed: widget.onBurnAfterReadToggle,
                ),
              ],
              const SizedBox(width: 10),

              // ============ 中：白色输入卡（带主色 focus 描边） ============
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints:
                      const BoxConstraints(maxHeight: 132, minHeight: 46),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: inputBorderColor,
                      width: widget.focusNode.hasFocus ? 1.4 : 0.8,
                    ),
                    boxShadow: widget.focusNode.hasFocus
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  padding: const EdgeInsets.only(left: 18, right: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          maxLines: 5,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          cursorColor: AppColors.primary,
                          cursorRadius: const Radius.circular(2),
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.4,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Aa',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: hintColor,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                          onTap: () {
                            if (widget.showEmojiPicker) {
                              widget.onEmojiToggle?.call();
                            }
                          },
                        ),
                      ),
                      // 表情图标（贴在输入区右侧）
                      GestureDetector(
                        key: _emojiButtonKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (!widget.showEmojiPicker) {
                            widget.focusNode.unfocus();
                          }
                          widget.onEmojiToggle?.call();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              widget.showEmojiPicker
                                  ? Icons.keyboard_hide_rounded
                                  : Icons.emoji_emotions_outlined,
                              key: ValueKey(widget.showEmojiPicker),
                              size: 24,
                              color: widget.showEmojiPicker
                                  ? AppColors.primary
                                  : subtleIcon,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ============ 右：语音 / 发送 主色实心按钮 ============
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: showSend
                    ? _PrimaryRoundButton(
                        key: const ValueKey('send'),
                        icon: Icons.arrow_upward_rounded,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.onSend(widget.controller.text);
                        },
                      )
                    : _PrimaryRoundButton(
                        key: const ValueKey('mic'),
                        icon: Icons.mic_rounded,
                        onPressed: widget.onVoice,
                      ),
              ),
            ],
          ),
        ),

        // 表情选择器
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: widget.showEmojiPicker
              ? TGEmojiPicker(
                  height: 280,
                  onEmojiSelected: _handleEmojiSelected,
                  onStickerTap: () {},
                  onGifTap: () {},
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildDesktop(bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08),
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _CircleIconButton(
                icon: Icons.attach_file,
                onPressed: widget.onAttachment,
                rotate: 45,
                backgroundColor:
                    isDark ? AppColors.darkSurface : AppColors.lightSurface,
              ),
              if (widget.allowBurnAfterRead) ...[
                const SizedBox(width: 8),
                _CircleIconButton(
                  icon: widget.burnAfterReadEnabled
                      ? Icons.local_fire_department_rounded
                      : Icons.local_fire_department_outlined,
                  onPressed: widget.onBurnAfterReadToggle,
                  backgroundColor: widget.burnAfterReadEnabled
                      ? const Color(0xFFFFE7D6)
                      : (isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface),
                  iconColor: widget.burnAfterReadEnabled
                      ? const Color(0xFFE65100)
                      : null,
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(maxHeight: 120, minHeight: 44),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkInputBackground
                        : AppColors.lightInputBackground,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.06),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: '输入消息',
                      hintStyle: TextStyle(
                        fontSize: 16,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty ||
                          widget.hasPendingAttachments) {
                        HapticFeedback.lightImpact();
                        widget.onSend(text);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _CircleIconButton(
                key: _emojiButtonKey,
                icon: widget.showEmojiPicker
                    ? Icons.keyboard_rounded
                    : Icons.emoji_emotions_outlined,
                onPressed: _showDesktopEmojiPicker,
                backgroundColor:
                    isDark ? AppColors.darkSurface : AppColors.lightSurface,
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: (_hasText || widget.hasPendingAttachments)
                    ? _PrimaryRoundButton(
                        key: const ValueKey('send'),
                        icon: Icons.arrow_upward_rounded,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.onSend(widget.controller.text);
                        },
                      )
                    : _CircleIconButton(
                        key: const ValueKey('mic'),
                        icon: Icons.mic,
                        onPressed: widget.onVoice,
                        backgroundColor: isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主色实心圆形按钮（用于输入栏左右两端 "+" / "🎤" / "↑"）
class _PrimaryRoundButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _PrimaryRoundButton({
    super.key,
    required this.icon,
    this.onPressed,
  });

  @override
  State<_PrimaryRoundButton> createState() => _PrimaryRoundButtonState();
}

class _PrimaryRoundButtonState extends State<_PrimaryRoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onPressed?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        transform: _pressed
            ? (Matrix4.identity()..scale(0.94))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              const Color(0xFFFF9E9E),
            ],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(_pressed ? 0.15 : 0.32),
              blurRadius: _pressed ? 8 : 14,
              offset: Offset(0, _pressed ? 2 : 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(widget.icon, color: Colors.white, size: 22),
      ),
    );
  }
}

/// "阅后即焚" 触发 chip —— 单独放在输入栏上方左侧
class _BurnAfterReadChip extends StatelessWidget {
  final bool active;
  final VoidCallback? onPressed;

  const _BurnAfterReadChip({
    required this.active,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = active
        ? const Color(0xFFFFE7D6)
        : (isDark ? const Color(0xFF23252E) : const Color(0xFFF1F3F6));
    final Color iconColor = active
        ? const Color(0xFFE65100)
        : (isDark ? Colors.white70 : const Color(0xFF6B7280));
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onPressed?.call();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(
          active
              ? Icons.local_fire_department_rounded
              : Icons.local_fire_department_outlined,
          color: iconColor,
          size: 22,
        ),
      ),
    );
  }
}

/// 圆形图标按钮
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double rotate;
  final Color? backgroundColor;
  final Color? iconColor;

  const _CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.rotate = 0,
    this.backgroundColor,
    this.iconColor,
  });
  
  bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = _isDesktop ? 44.0 : 40.0;
    final iconSize = _isDesktop ? 24.0 : 22.0;
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onPressed?.call();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor ?? (isDark ? AppColors.darkSurface : AppColors.lightSurface),
          shape: BoxShape.circle,
          border: _isDesktop ? Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
            width: 1,
          ) : null,
        ),
        child: Transform.rotate(
          angle: rotate * 3.14159 / 180,
          child: Icon(
            icon,
            size: iconSize,
            color:
                iconColor ??
                (isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary),
          ),
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
                color: isDark 
                    ? const Color(0xFF2C2C2E) 
                    : Colors.white,
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
