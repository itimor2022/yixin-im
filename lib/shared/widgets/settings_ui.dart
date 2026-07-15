/// 设置类页面共享 UI 语言 v4 —— **"个人资料页"级极简：无卡片 · 无图标 · 无粗标题**
///
/// v4 目标：让 6 个设置子页在结构上跟 `个人资料页 / 群组资料页 / 编辑资料页`
/// 完全同频 —— 顶部一段蓝色渐变 + 左对齐白字页标题，页面主体是**直接铺在
/// 浅灰底色上**的一段段扁平文字行，**没有分组卡、没有图标、没有粗体分组
/// 标题**。分组只靠"很小的一撮浅灰大写文字 + 上下留白"来暗示，视觉密度
/// 大幅降低，看起来跟 v2 (浮岛小卡片) / v3 (合并大卡片) 都 100% 不同。
///
/// 用法示例：
/// ```dart
/// SettingsScaffold(
///   title: '通知和声音',
///   children: [
///     const SettingsSection('消息通知'),
///     SettingsSwitchIsland(label: '私聊消息', value: v, onChanged: fn),
///     SettingsSwitchIsland(label: '群消息', value: v, onChanged: fn),
///     const SettingsSection('铃声'),
///     SettingsChoiceIsland(label: '默认铃声', value: '经典', onTap: fn),
///   ],
/// );
/// ```
///
/// **无需**手动分组 —— `SettingsScaffold` 只做背景 + Header + 直接把 children
/// 铺到一个纵向 ListView 里，行与行之间没有分隔线也没有卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'top_gradient_backdrop.dart';

// ============================================================================
// 设计令牌 —— 与"个人资料页"一致
// ============================================================================

/// 页面底色（对齐 `_kProfileBg` / `_kUpBg` / `_kGpBg`）
const Color _kSettingsBgLight = Color(0xFFF7F8FA);
const Color _kSettingsBgDark = Color(0xFF0B0C10);

/// 行文字色
const Color _kLabelLight = Color(0xFF111827);
const Color _kLabelDark = Colors.white;
const Color _kSubLight = Color(0xFF6B7280);
const Color _kSubDark = Color(0xB3FFFFFF); // white70
const Color _kValueLight = Color(0xFF6B7280);
const Color _kValueDark = Color(0x8AFFFFFF); // white54

/// 分组标题（弱化到几乎看不见）
const Color _kSectionLight = Color(0xFF9CA3AF);
const Color _kSectionDark = Color(0x7AFFFFFF); // white48

/// 主色（Switch active、chevron 等）
const Color _kPrimary = Color(0xFFFF6B6B);

/// 顶部渐变区结构（与 MePage 同频）
const double _kHeaderContentHeight = 60;
const double _kHeaderGradientBuffer = 12;
const double _kHeaderGradientFadeTail = 80;

// ============================================================================
// SettingsScaffold —— 蓝色渐变顶部 + 左对齐白字标题 + 扁平内容区
// ============================================================================

class SettingsScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool isDesktopPanel;
  final EdgeInsetsGeometry contentPadding;

  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.isDesktopPanel = false,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? _kSettingsBgDark : _kSettingsBgLight;

    // 桌面面板模式：只输出内容
    if (isDesktopPanel) {
      return Container(
        color: bgColor,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 20).add(contentPadding),
          children: children,
        ),
      );
    }

    final double topPad = MediaQuery.of(context).padding.top;
    final double gradientOpaqueHeight =
        topPad + _kHeaderContentHeight + _kHeaderGradientBuffer;
    final double gradientTotalHeight =
        gradientOpaqueHeight + _kHeaderGradientFadeTail;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ==================== 底层：滚动内容（扁平行、无分组卡） ====================
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.only(
                top: gradientOpaqueHeight,
                bottom: 60,
              ).add(contentPadding),
              physics: const AlwaysScrollableScrollPhysics(),
              children: children,
            ),
          ),

          // ==================== 中层：装饰渐变 ====================
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: gradientTotalHeight,
            child: const IgnorePointer(
              child: TopGradientBackdrop(),
            ),
          ),

          // ==================== 顶层：返回按钮 + 左对齐标题 ====================
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: _kHeaderContentHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        _BackButton(
                          onTap: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.pop(context);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (trailing != null) trailing!,
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: const Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SettingsSection —— 只输出一段"顶部大留白 + 极小灰字大写标签"
//
// 例：`      MESSAGES`  或纯 padding —— 视觉上比之前"竖条+粗黑标题"弱很多。
// ============================================================================

class SettingsSection extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  const SettingsSection(
    this.title, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(0, 26, 0, 8),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (title.trim().isEmpty) {
      return const SizedBox(height: 26);
    }
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: isDark ? _kSectionDark : _kSectionLight,
        ),
      ),
    );
  }
}

// ============================================================================
// SettingsNote —— 段末小提示
// ============================================================================

class SettingsNote extends StatelessWidget {
  final String text;
  const SettingsNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: isDark ? Colors.white38 : const Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}

// ============================================================================
// _FlatRowShell —— 扁平行外壳（Padding + InkWell，无背景、无 border）
// ============================================================================

class _FlatRowShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const _FlatRowShell({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

// ============================================================================
// SettingsSwitchIsland —— 扁平开关行（左：标签，右：Switch）
//
// 注意：新版**不再展示 `icon` 参数**（保持 API 兼容但会被忽略）。
// ============================================================================

class SettingsSwitchIsland extends StatelessWidget {
  // ignore: unused_field
  final IconData? icon;
  // ignore: unused_field
  final Color? iconColor;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchIsland({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _FlatRowShell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? _kLabelDark : _kLabelLight,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? _kSubDark : _kSubLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 用 Transform.scale 让 Switch 显得更精致
          Transform.scale(
            scale: 0.85,
            child: Switch.adaptive(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              activeColor: _kPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SettingsChoiceIsland —— 扁平跳转 / 选择行（左：标签，右：值 + chevron）
//
// 注意：新版**不再展示 `icon` 参数**（保持 API 兼容但会被忽略）。
// ============================================================================

class SettingsChoiceIsland extends StatelessWidget {
  // ignore: unused_field
  final IconData? icon;
  // ignore: unused_field
  final Color? iconColor;
  final String label;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? labelColor;
  final Widget? trailing;
  final bool loading;

  const SettingsChoiceIsland({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.value,
    this.subtitle,
    this.onTap,
    this.labelColor,
    this.trailing,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveLabelColor =
        labelColor ?? (isDark ? _kLabelDark : _kLabelLight);

    return _FlatRowShell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: effectiveLabelColor,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? _kSubDark : _kSubLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null && value!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? _kValueDark : _kValueLight,
                ),
              ),
            ),
          ],
          if (loading) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          if (onTap != null && trailing == null && !loading) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? Colors.white24 : const Color(0xFFC0C4CC),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// SettingsCustomIsland —— 自定义内容扁平行
// ============================================================================

/// 需要塞入自定义内容（缩略图 / 滑块 / 复合布局）时使用，行为跟其他 island
/// 一致：直接铺在页面底色上，没有卡片。
class SettingsCustomIsland extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const SettingsCustomIsland({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    return _FlatRowShell(
      onTap: onTap,
      padding: padding,
      child: child,
    );
  }
}

// ============================================================================
// SettingsLooseCard —— 保留 API 但不再画卡片背景
//
// 语义变化：v3 里它是一张带 shadow 的独立圆角卡片；v4 里改为透明块，
// 只保留内边距。这样调用方（比如 devices_page 的当前设备 hero）无需改动，
// 但视觉上不再有卡片轮廓。
// ============================================================================

class SettingsLooseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SettingsLooseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}

// ============================================================================
// SettingsCircleIcon —— 为兼容旧代码保留，但已不推荐使用
// ============================================================================

class SettingsCircleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const SettingsCircleIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Icon(icon, color: color, size: size * 0.6),
    );
  }
}
