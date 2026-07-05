import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/platform_utils.dart';

/// 手机 H5 优化的认证页面布局
/// 完全去除了桌面双栏侧边栏，聚焦于表单本身
class AuthDesktopLayout extends ConsumerWidget {
  /// 表单内容
  final Widget child;

  /// 是否显示返回按钮
  final bool showBackButton;

  /// 返回按钮回调
  final VoidCallback? onBack;

  /// 标题
  final String? title;

  const AuthDesktopLayout({
    super.key,
    required this.child,
    this.showBackButton = false,
    this.onBack,
    this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🌟 彻底干掉原先的 PC 双栏逻辑，无论是 PC 浏览器还是手机浏览器，统一走移动端表单内核
    return Scaffold(
      // 背景色跟随暗黑模式自适应
      backgroundColor: isDark ? const Color(0xFF0E0E0E) : Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // 🌟 核心控制：限制最大宽度为 420 像素。
            // 在手机 H5 上由于屏幕窄会直接铺满，在 PC 浏览器打开则会自动居中，完美符合 H5 规范。
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                // 顶部导航栏 / 返回按钮控制
                if (showBackButton || title != null)
                  _buildTopBar(context, isDark)
                else
                  // 为没有标题的页面保留适当的顶部留白
                  const SizedBox(height: 24),

                // 表单主内容区域
                Expanded(
                  child: SingleChildScrollView(
                    // 保持手指滑动的顺畅感
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建 H5 专用的顶部导航栏
  Widget _buildTopBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : Colors.black,
                size: 20,
              ),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              title ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}