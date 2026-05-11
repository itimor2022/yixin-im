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
    final bottomPadding = _isDesktop ? 12.0 : (widget.showEmojiPicker ? 8.0 : MediaQuery.of(context).padding.bottom + 8);
    final horizontalPadding = _isDesktop ? 16.0 : 8.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入区域（毛玻璃效果）
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: _isDesktop ? 12 : 8,
                bottom: bottomPadding,
              ),
              decoration: BoxDecoration(
                // 更清透的毛玻璃效果
                color: (isDark ? Colors.black : Colors.white).withOpacity(_isDesktop ? 0.85 : 0.7),
                border: _isDesktop ? Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08),
                    width: 1,
                  ),
                ) : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 附件按钮 - TG 风格圆形
              _CircleIconButton(
                icon: Icons.attach_file,
                onPressed: widget.onAttachment,
                rotate: 45,
                backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              ),

              if (widget.allowBurnAfterRead) ...[
                SizedBox(width: _isDesktop ? 8 : 6),
                _CircleIconButton(
                  icon: widget.burnAfterReadEnabled
                      ? Icons.local_fire_department_rounded
                      : Icons.local_fire_department_outlined,
                  onPressed: widget.onBurnAfterReadToggle,
                  backgroundColor: widget.burnAfterReadEnabled
                      ? const Color(0xFFFFE7D6)
                      : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
                  iconColor: widget.burnAfterReadEnabled
                      ? const Color(0xFFE65100)
                      : null,
                ),
              ],

              SizedBox(width: _isDesktop ? 12 : 8),
              
              // 输入框
              Expanded(
                child: Container(
                  constraints: BoxConstraints(maxHeight: 120, minHeight: _isDesktop ? 44 : 40),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? AppColors.darkInputBackground 
                        : AppColors.lightInputBackground,
                    borderRadius: BorderRadius.circular(_isDesktop ? 22 : 20),
                    border: _isDesktop ? Border.all(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                      width: 1,
                    ) : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 文本输入
                      Expanded(
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
                            fontSize: 16,
                            color: isDark 
                                ? AppColors.darkTextPrimary 
                                : AppColors.lightTextPrimary,
                          ),
                          onTap: () {
                            // 点击输入框时隐藏表情选择器
                            if (widget.showEmojiPicker) {
                              widget.onEmojiToggle?.call();
                            }
                          },
                          onSubmitted: (text) {
                            if (text.trim().isNotEmpty || widget.hasPendingAttachments) {
                              HapticFeedback.lightImpact();
                              widget.onSend(text);
                            }
                          },
                        ),
                      ),
                      
                      // 表情按钮 - 移动端在输入框内，桌面端在输入框外
                      if (!_isDesktop)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 4),
                          child: GestureDetector(
                            key: _emojiButtonKey,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (!widget.showEmojiPicker) {
                                widget.focusNode.unfocus();
                              }
                              widget.onEmojiToggle?.call();
                            },
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
                                      ? AppColors.primary
                                      : (isDark 
                                          ? AppColors.darkTextSecondary 
                                          : AppColors.lightTextSecondary),
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
              if (_isDesktop)
                _CircleIconButton(
                  key: _emojiButtonKey,
                  icon: widget.showEmojiPicker 
                      ? Icons.keyboard_rounded 
                      : Icons.emoji_emotions_outlined,
                  onPressed: _showDesktopEmojiPicker,
                  backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                ),
              
              if (_isDesktop)
                const SizedBox(width: 8),
              
              // 发送/语音按钮 
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: (_hasText || widget.hasPendingAttachments)
                    ? _SendButton(
                        key: const ValueKey('send'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.onSend(widget.controller.text);
                        },
                      )
                    : _CircleIconButton(
                        key: const ValueKey('mic'),
                        icon: Icons.mic,
                        onPressed: widget.onVoice,
                        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                      ),
              ),
            ],
          ),
            ),
          ),
        ),
        
        // 表情选择器（仅移动端显示）
        if (!_isDesktop)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: widget.showEmojiPicker
                ? TGEmojiPicker(
                    height: 280,
                    onEmojiSelected: _handleEmojiSelected,
                    onStickerTap: () {
                      // 跳转到贴纸页面
                    },
                    onGifTap: () {
                      // 跳转到GIF页面
                    },
                  )
                : const SizedBox.shrink(),
          ),
      ],
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

/// TG 风格发送按钮 - 蓝色纸飞机
class _SendButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SendButton({
    super.key,
    required this.onPressed,
  });
  
  bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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
