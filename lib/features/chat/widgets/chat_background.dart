// 文件用途：提供 ChatBackgroundWidget 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 ChatBackgroundWidget，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';

// 关键声明：chat background 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 聊天背景组件
class ChatBackgroundWidget extends StatelessWidget {
  final ChatBackground background;
  final bool isDark;

  const ChatBackgroundWidget({
    super.key,
    required this.background,
    required this.isDark,
  });

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    switch (background.type) {
      case ChatBackgroundType.solid:
        return _buildSolidBackground();
      case ChatBackgroundType.gradient:
        return _buildGradientBackground();
      case ChatBackgroundType.image:
        return _buildImageBackground();
      case ChatBackgroundType.pattern:
        return _buildPatternBackground();
    }
  }

  Widget _buildSolidBackground() {
    return Container(
      color: background.solidColor ??
          (isDark
              ? AppColors.darkChatBackground
              : AppColors.lightChatBackground),
    );
  }

  Widget _buildGradientBackground() {
    return Stack(
      children: [
        // 渐变背景
        Container(
          decoration: BoxDecoration(
            gradient: background.gradient ?? _defaultGradient,
          ),
        ),
        // SVG 图案叠加
        Positioned.fill(
          child: Opacity(
            opacity: isDark ? 0.08 : 0.15,
            child: SvgPicture.asset(
              'assets/images/backgrounds/bg5.svg',
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                isDark ? Colors.white : Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        if (isDark)
          Positioned.fill(
            child: Container(
              color: AppColors.darkChatBackground.withOpacity(0.62),
            ),
          ),
      ],
    );
  }

  LinearGradient get _defaultGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E),
              ]
            : [
                const Color(0xFFE8D5E0),
                const Color(0xFFD4C5E0),
                const Color(0xFFC5D0E8),
              ],
      );

  Widget _buildImageBackground() {
    if (background.imagePath == null) {
      return _buildGradientBackground();
    }

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: background.imagePath!.startsWith('http')
                  ? NetworkImage(background.imagePath!)
                  : AssetImage(background.imagePath!) as ImageProvider,
              fit: BoxFit.cover,
              opacity: isDark ? 0.3 : 0.8,
            ),
          ),
        ),
        // SVG 图案叠加（可选）
        if (background.showPattern)
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: SvgPicture.asset(
                'assets/images/backgrounds/bg5.svg',
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  isDark ? Colors.white : Colors.black,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        if (isDark)
          Positioned.fill(
            child: Container(
              color: AppColors.darkChatBackground.withOpacity(0.58),
            ),
          ),
      ],
    );
  }

  Widget _buildPatternBackground() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: _defaultGradient,
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: isDark ? 0.08 : 0.15,
            child: SvgPicture.asset(
              'assets/images/backgrounds/bg5.svg',
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        if (isDark)
          Positioned.fill(
            child: Container(
              color: AppColors.darkChatBackground.withOpacity(0.50),
            ),
          ),
      ],
    );
  }
}

/// 聊天背景选择器（简化版，用于设置页面内嵌）
class ChatBackgroundPicker extends StatelessWidget {
  final ChatBackground currentBackground;
  final Function(ChatBackground) onSelect;

  const ChatBackgroundPicker({
    super.key,
    required this.currentBackground,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // TG 风格的背景渐变选项
    final gradientOptions = [
      // 紫粉渐变（默认）
      const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE8D5E0), Color(0xFFD4C5E0), Color(0xFFC5D0E8)],
      ),
      // 蓝绿渐变
      const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFB8E6CF), Color(0xFFA8D8EA), Color(0xFFB8D4E3)],
      ),
      // 橙粉渐变
      const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFDE2C8), Color(0xFFFAD0C4), Color(0xFFF5C4D4)],
      ),
      // 蓝紫渐变
      const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFC9D6FF), Color(0xFFD4C5E0), Color(0xFFE2B0FF)],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: gradientOptions.length,
            itemBuilder: (context, index) {
              final gradient = gradientOptions[index];
              final isSelected =
                  currentBackground.type == ChatBackgroundType.gradient &&
                      index == 0;

              return GestureDetector(
                onTap: () => onSelect(ChatBackground(
                  type: ChatBackgroundType.gradient,
                  gradient: gradient,
                )),
                child: Container(
                  width: 70,
                  height: 80,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(
                            color: AppColors.primaryFor(context), width: 2.5)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isSelected ? 9.5 : 12),
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(gradient: gradient),
                        ),
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.2,
                            child: SvgPicture.asset(
                              'assets/images/backgrounds/bg5.svg',
                              fit: BoxFit.cover,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: AppColors.primaryFor(context),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
