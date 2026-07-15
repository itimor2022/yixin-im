import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ===== Auth 页面通用 UI Tokens =====
///
/// 登录 / 注册页共用的配色与视觉样式。
/// 主色跟全站 [AppColors.primary] 一致 (#009CFF)。
const Color kAuthPrimary = Color(0xFFFF6B6B);
const Color kAuthGradStart = Color(0xFFFF6B6B);
const Color kAuthGradEnd = Color(0xFFFF9E9E);
const Color kAuthCardLight = Color(0xFFF3F5F8);
const Color kAuthTextPrimary = Color(0xFF111827);
const Color kAuthTextSecondary = Color(0xFF6B7280);
const Color kAuthTextHint = Color(0xFF9CA3AF);
const Color kAuthDivider = Color(0xFFECEEF1);

/// 现代极简输入框
///
/// 视觉：**无背景卡**，只有一条底部细线；左侧主色小图标；高度 54。
/// 用于登录 / 注册页，配合"我的"风格保持极简清爽。
class AuthInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isDark;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;

  const AuthInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isDark,
    this.keyboardType,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onChanged,
    this.inputFormatters,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final Color underlineColor = isDark
        ? Colors.white.withOpacity(0.14)
        : const Color(0xFFE5E7EB);

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: underlineColor, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(icon, color: kAuthPrimary, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscureText,
              autocorrect: autocorrect,
              enableSuggestions: enableSuggestions,
              onChanged: onChanged,
              inputFormatters: inputFormatters,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : kAuthTextPrimary,
              ),
              cursorColor: kAuthPrimary,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 14.5,
                  color: isDark ? Colors.white38 : kAuthTextHint,
                ),
                // 关键：显式关闭全局 InputDecorationTheme 的 filled 灰底，
                // 否则输入框内部还会自动填一层灰色。
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (suffix != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: suffix,
            ),
        ],
      ),
    );
  }
}

/// 表单下的小文字链接 (图标 + 文字，主色 + 透明底)
class AuthTextLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AuthTextLink({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: kAuthPrimary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kAuthPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主色渐变 CTA 大按钮（54 高，圆角 16，带阴影）
class AuthPrimaryButton extends StatelessWidget {
  final String text;
  final bool loading;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = !loading && onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enabled
                    ? const [kAuthGradStart, kAuthGradEnd]
                    : const [Color(0xFFB4B9C2), Color(0xFFCDD2DA)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: kAuthPrimary.withOpacity(0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主色描边空心按钮（用于次要 CTA，如"立即注册 / 立即登录"）
class AuthOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const AuthOutlineButton({
    super.key,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54, // 与 AuthPrimaryButton 一致，方便与主色按钮并排一行
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kAuthPrimary, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          foregroundColor: kAuthPrimary,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: kAuthPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// 步骤指示器（数字圆圈 + 连线，主色高亮）
class AuthStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final bool isDark;

  const AuthStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          final leftStep = i ~/ 2;
          return Container(
            width: 40,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: currentStep > leftStep
                  ? kAuthPrimary
                  : (isDark ? Colors.white24 : const Color(0xFFDEE2E7)),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }
        final step = i ~/ 2;
        final done = currentStep > step;
        final active = currentStep >= step;
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? kAuthPrimary : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? kAuthPrimary
                  : (isDark ? Colors.white24 : const Color(0xFFDEE2E7)),
              width: 1.6,
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 16)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white
                          : (isDark ? Colors.white54 : kAuthTextSecondary),
                    ),
                  ),
          ),
        );
      }),
    );
  }
}

/// Auth 页面通用 hero 头部（主色渐变 + Logo + 标题 + 副标题）
///
/// [title] / [subtitle] 用于欢迎语。
/// [logo] 通常传远程/本地图片。
/// [rightAction] 用于右上角悬浮按钮（如客服）。
class AuthHeroHeader extends StatelessWidget {
  final Widget logo;
  final String? title;
  final String? subtitle;
  final Widget? rightAction;
  final VoidCallback? onBack;
  final EdgeInsets padding;

  const AuthHeroHeader({
    super.key,
    required this.logo,
    this.title,
    this.subtitle,
    this.rightAction,
    this.onBack,
    this.padding = const EdgeInsets.only(top: 44, bottom: 60, left: 24, right: 24),
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).viewPadding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: topPad + padding.top,
        bottom: padding.bottom,
        left: padding.left,
        right: padding.right,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kAuthGradStart, kAuthGradEnd],
        ),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onBack != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Material(
                    color: Colors.white.withOpacity(0.18),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onBack,
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              logo,
              if (title != null && title!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.4,
                    height: 1.1,
                  ),
                ),
              ],
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ],
          ),
          if (rightAction != null)
            Positioned(top: 0, right: 0, child: rightAction!),
        ],
      ),
    );
  }
}

/// Auth 页面 Logo —— 极简版：仅展示图片，无背景 / 边框 / 阴影
class AuthLogoBadge extends StatelessWidget {
  final String? remoteUrl;
  final String fallbackAsset;
  final double size;

  const AuthLogoBadge({
    super.key,
    this.remoteUrl,
    this.fallbackAsset = 'assets/logo.png',
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final hasRemote = (remoteUrl ?? '').isNotEmpty;
    // 加一个粗时间戳，避免频繁刷新 CDN 但仍能感知 logo 变更
    final finalUrl = hasRemote
        ? '$remoteUrl${remoteUrl!.contains('?') ? '&' : '?'}_t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'
        : null;
    return SizedBox(
      width: size,
      height: size,
      child: hasRemote
          ? Image.network(
              finalUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                // 加载中：显示本地 asset 作为占位
                return Image.asset(fallbackAsset, fit: BoxFit.contain);
              },
              errorBuilder: (_, __, ___) =>
                  Image.asset(fallbackAsset, fit: BoxFit.contain),
            )
          : Image.asset(fallbackAsset, fit: BoxFit.contain),
    );
  }
}
