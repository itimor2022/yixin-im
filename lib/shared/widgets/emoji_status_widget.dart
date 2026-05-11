import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/constants/emoji_animations.dart';

/// 表情状态显示组件（支持动态表情）
class EmojiStatusWidget extends StatelessWidget {
  final String emoji;
  final double size;

  const EmojiStatusWidget({
    super.key,
    required this.emoji,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (emoji.isEmpty) return const SizedBox.shrink();

    final animatedEmoji = EmojiAnimations.findByEmoji(emoji);
    
    if (animatedEmoji != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(
          animatedEmoji.path,
          repeat: true,
          animate: true,
          fit: BoxFit.contain,
        ),
      );
    }
    
    return Text(
      emoji,
      style: TextStyle(fontSize: size * 0.85),
    );
  }
}
