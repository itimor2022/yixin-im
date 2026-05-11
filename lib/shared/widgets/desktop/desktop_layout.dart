import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';

/// Telegram 风格的桌面端布局
/// 左侧边栏 + 右侧内容区域
class DesktopLayout extends StatefulWidget {
  /// 左侧边栏内容（聊天列表等）
  final Widget sidebar;
  
  /// 右侧主内容区域（聊天详情等）
  final Widget? content;
  
  /// 无内容时的占位 Widget
  final Widget? emptyPlaceholder;
  
  /// 侧边栏初始宽度
  final double initialSidebarWidth;
  
  /// 侧边栏宽度变化回调
  final ValueChanged<double>? onSidebarWidthChanged;
  
  const DesktopLayout({
    super.key,
    required this.sidebar,
    this.content,
    this.emptyPlaceholder,
    this.initialSidebarWidth = 320,
    this.onSidebarWidthChanged,
  });

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> {
  late double _sidebarWidth;
  bool _isDragging = false;
  
  @override
  void initState() {
    super.initState();
    _sidebarWidth = widget.initialSidebarWidth;
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasContent = widget.content != null;
    
    return Row(
      children: [
        // 左侧边栏
        SizedBox(
          width: _sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                right: BorderSide(
                  color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  width: 1,
                ),
              ),
            ),
            child: widget.sidebar,
          ),
        ),
        
        // 拖动分隔条
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _isDragging = true),
            onHorizontalDragEnd: (_) {
              setState(() => _isDragging = false);
              widget.onSidebarWidthChanged?.call(_sidebarWidth);
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _sidebarWidth += details.delta.dx;
                _sidebarWidth = _sidebarWidth.clamp(
                  PlatformUtils.desktopSidebarMinWidth,
                  PlatformUtils.desktopSidebarMaxWidth,
                );
              });
            },
            child: Container(
              width: 4,
              color: _isDragging 
                  ? AppColors.primary.withOpacity(0.5)
                  : Colors.transparent,
            ),
          ),
        ),
        
        // 右侧内容区域
        Expanded(
          child: hasContent 
              ? widget.content!
              : widget.emptyPlaceholder ?? _buildEmptyPlaceholder(isDark),
        ),
      ],
    );
  }
  
  /// 默认空占位 Widget
  Widget _buildEmptyPlaceholder(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              '选择一个聊天开始对话',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 8),
            if (PlatformUtils.isDesktop)
              Text(
                '按 ⌘N 创建新聊天',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// macOS 风格的自定义标题栏
class DesktopTitleBar extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final double height;
  
  const DesktopTitleBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      // 拖动窗口
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        if (PlatformUtils.isDesktop) {
          windowManager.startDragging();
        }
      },
      onDoubleTap: () {
        // 双击标题栏切换最大化
        if (PlatformUtils.isDesktop) {
          windowManager.isMaximized().then((isMaximized) {
            if (isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          });
        }
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // macOS 红绿灯按钮占位
            if (PlatformUtils.isApple) const SizedBox(width: 78),
            
            // 左侧内容
            if (leading != null) leading!,
            
            // 标题
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              const Spacer(),
            
            // 右侧操作按钮
            if (actions != null) ...actions!,
            
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// 桌面端悬停效果按钮
class DesktopHoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  
  const DesktopHoverButton({
    super.key,
    required this.child,
    this.onPressed,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<DesktopHoverButton> createState() => _DesktopHoverButtonState();
}

class _DesktopHoverButtonState extends State<DesktopHoverButton> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget button = MouseRegion(
      cursor: widget.onPressed != null 
          ? SystemMouseCursors.click 
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isHovered 
                ? (isDark ? Colors.white10 : Colors.black.withOpacity(0.05))
                : Colors.transparent,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
    
    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }
    
    return button;
  }
}
