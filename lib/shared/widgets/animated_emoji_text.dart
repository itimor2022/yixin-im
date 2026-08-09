// 文件用途：提供 AnimatedEmojiText 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 AnimatedEmojiText，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'web_safe_lottie.dart';

import '../../core/constants/emoji_animations.dart';

// 关键声明：animated emoji text 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 支持动态表情的文本组件
class AnimatedEmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double emojiSize;
  final int? maxLines;
  final TextOverflow? overflow;

  const AnimatedEmojiText({
    super.key,
    required this.text,
    this.style,
    this.emojiSize = 24,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final hasLimit = maxLines != null || overflow != null;
    final inlineSpans = _parseToInlineSpans();

    if (inlineSpans.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    // 有 maxLines/overflow 时用 Text.rich，避免瀑布流等场景文字溢出
    if (hasLimit) {
      return Text.rich(
        TextSpan(children: inlineSpans),
        style: style,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.ellipsis,
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: _parseText(text),
    );
  }

  static final _emojiPattern = RegExp(
    r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{231A}-\u{231B}]|[\u{23E9}-\u{23F3}]|[\u{23F8}-\u{23FA}]|[\u{25AA}-\u{25AB}]|[\u{25B6}]|[\u{25C0}]|[\u{25FB}-\u{25FE}]|[\u{2614}-\u{2615}]|[\u{2648}-\u{2653}]|[\u{267F}]|[\u{2693}]|[\u{26A1}]|[\u{26AA}-\u{26AB}]|[\u{26BD}-\u{26BE}]|[\u{26C4}-\u{26C5}]|[\u{26CE}]|[\u{26D4}]|[\u{26EA}]|[\u{26F2}-\u{26F3}]|[\u{26F5}]|[\u{26FA}]|[\u{26FD}]|[\u{2702}]|[\u{2705}]|[\u{2708}-\u{270D}]|[\u{270F}]|[\u{2712}]|[\u{2714}]|[\u{2716}]|[\u{271D}]|[\u{2721}]|[\u{2728}]|[\u{2733}-\u{2734}]|[\u{2744}]|[\u{2747}]|[\u{274C}]|[\u{274E}]|[\u{2753}-\u{2755}]|[\u{2757}]|[\u{2763}-\u{2764}]|[\u{2795}-\u{2797}]|[\u{27A1}]|[\u{27B0}]|[\u{27BF}]|[\u{2934}-\u{2935}]|[\u{2B05}-\u{2B07}]|[\u{2B1B}-\u{2B1C}]|[\u{2B50}]|[\u{2B55}]|[\u{3030}]|[\u{303D}]|[\u{3297}]|[\u{3299}]|[\u{1F004}]|[\u{1F0CF}]|[\u{1F170}-\u{1F171}]|[\u{1F17E}-\u{1F17F}]|[\u{1F18E}]|[\u{1F191}-\u{1F19A}]|[\u{1F1E6}-\u{1F1FF}]|[\u{1F201}-\u{1F202}]|[\u{1F21A}]|[\u{1F22F}]|[\u{1F232}-\u{1F23A}]|[\u{1F250}-\u{1F251}]|[\u{1F300}-\u{1F321}]|[\u{1F324}-\u{1F393}]|[\u{1F396}-\u{1F397}]|[\u{1F399}-\u{1F39B}]|[\u{1F39E}-\u{1F3F0}]|[\u{1F3F3}-\u{1F3F5}]|[\u{1F3F7}-\u{1F4FD}]|[\u{1F4FF}-\u{1F53D}]|[\u{1F549}-\u{1F54E}]|[\u{1F550}-\u{1F567}]|[\u{1F56F}-\u{1F570}]|[\u{1F573}-\u{1F57A}]|[\u{1F587}]|[\u{1F58A}-\u{1F58D}]|[\u{1F590}]|[\u{1F595}-\u{1F596}]|[\u{1F5A4}-\u{1F5A5}]|[\u{1F5A8}]|[\u{1F5B1}-\u{1F5B2}]|[\u{1F5BC}]|[\u{1F5C2}-\u{1F5C4}]|[\u{1F5D1}-\u{1F5D3}]|[\u{1F5DC}-\u{1F5DE}]|[\u{1F5E1}]|[\u{1F5E3}]|[\u{1F5E8}]|[\u{1F5EF}]|[\u{1F5F3}]|[\u{1F5FA}-\u{1F64F}]|[\u{1F680}-\u{1F6C5}]|[\u{1F6CB}-\u{1F6D2}]|[\u{1F6D5}-\u{1F6D7}]|[\u{1F6E0}-\u{1F6E5}]|[\u{1F6E9}]|[\u{1F6EB}-\u{1F6EC}]|[\u{1F6F0}]|[\u{1F6F3}-\u{1F6FC}]|[\u{1F7E0}-\u{1F7EB}]|[\u{1F90C}-\u{1F93A}]|[\u{1F93C}-\u{1F945}]|[\u{1F947}-\u{1F978}]|[\u{1F97A}-\u{1F9CB}]|[\u{1F9CD}-\u{1F9FF}]|[\u{1FA70}-\u{1FA74}]|[\u{1FA78}-\u{1FA7A}]|[\u{1FA80}-\u{1FA86}]|[\u{1FA90}-\u{1FAA8}]|[\u{1FAB0}-\u{1FAB6}]|[\u{1FAC0}-\u{1FAC2}]|[\u{1FAD0}-\u{1FAD6}]',
    unicode: true,
  );

  /// 解析为 InlineSpan 列表，供 Text.rich 使用（支持 maxLines/overflow）
  List<InlineSpan> _parseToInlineSpans() {
    final List<InlineSpan> result = [];
    final emojiMap = EmojiAnimations.emojiToFile;

    int lastEnd = 0;
    for (final match in _emojiPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        result.add(
            TextSpan(text: text.substring(lastEnd, match.start), style: style));
      }
      final emoji = match.group(0)!;
      final lottieFile = emojiMap[emoji];
      if (lottieFile != null) {
        result.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(
            width: emojiSize,
            height: emojiSize,
            child: WebSafeLottie.asset(
              'assets/emoji/lottie/$lottieFile',
              fit: BoxFit.contain,
              repeat: true,
              errorBuilder: (_, __, ___) => Text(emoji,
                  style: style?.copyWith(fontSize: emojiSize * 0.8)),
            ),
          ),
        ));
      } else {
        result.add(TextSpan(
            text: emoji, style: style?.copyWith(fontSize: emojiSize * 0.8)));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      result.add(TextSpan(text: text.substring(lastEnd), style: style));
    }
    return result;
  }

  List<Widget> _parseText(String input) {
    final List<Widget> result = [];
    final emojiMap = EmojiAnimations.emojiToFile;

    int lastEnd = 0;
    for (final match in _emojiPattern.allMatches(input)) {
      if (match.start > lastEnd) {
        final textBefore = input.substring(lastEnd, match.start);
        result.add(Text(textBefore, style: style));
      }
      final emoji = match.group(0)!;
      final lottieFile = emojiMap[emoji];
      if (lottieFile != null) {
        result.add(
          SizedBox(
            width: emojiSize,
            height: emojiSize,
            child: WebSafeLottie.asset(
              'assets/emoji/lottie/$lottieFile',
              fit: BoxFit.contain,
              repeat: true,
              errorBuilder: (context, error, stackTrace) {
                return Text(emoji,
                    style: style?.copyWith(fontSize: emojiSize * 0.8));
              },
            ),
          ),
        );
      } else {
        result.add(
            Text(emoji, style: style?.copyWith(fontSize: emojiSize * 0.8)));
      }
      lastEnd = match.end;
    }
    if (lastEnd < input.length) {
      result.add(Text(input.substring(lastEnd), style: style));
    }
    return result;
  }
}

/// 动态表情输入框装饰器
class AnimatedEmojiInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool enabled;
  final int? maxLines;
  final double emojiSize;

  const AnimatedEmojiInputField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.style,
    this.hintStyle,
    this.decoration,
    this.onChanged,
    this.onTap,
    this.enabled = true,
    this.maxLines = 1,
    this.emojiSize = 20,
  });

  @override
  State<AnimatedEmojiInputField> createState() =>
      _AnimatedEmojiInputFieldState();
}

class _AnimatedEmojiInputFieldState extends State<AnimatedEmojiInputField> {
  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Stack 来叠加显示动态表情和输入框
    return Stack(
      children: [
        // 透明文本框用于输入
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: widget.style?.copyWith(color: Colors.transparent) ??
              const TextStyle(color: Colors.transparent),
          cursorColor: widget.style?.color ?? Colors.black,
          decoration: widget.decoration?.copyWith(
                hintText:
                    widget.controller.text.isEmpty ? widget.hintText : null,
                hintStyle: widget.hintStyle,
              ) ??
              InputDecoration(
                hintText:
                    widget.controller.text.isEmpty ? widget.hintText : null,
                hintStyle: widget.hintStyle,
                border: InputBorder.none,
              ),
          onChanged: widget.onChanged,
          onTap: widget.onTap,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
        ),

        // 上层显示动态表情
        if (widget.controller.text.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                padding: widget.decoration?.contentPadding ??
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                alignment: Alignment.centerLeft,
                child: AnimatedEmojiText(
                  text: widget.controller.text,
                  style: widget.style,
                  emojiSize: widget.emojiSize,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 单个动态表情组件
class AnimatedEmoji extends StatelessWidget {
  final String emoji;
  final double size;
  final bool animate;

  const AnimatedEmoji({
    super.key,
    required this.emoji,
    this.size = 24,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final lottieFile = EmojiAnimations.emojiToFile[emoji];

    if (lottieFile != null && animate) {
      return SizedBox(
        width: size,
        height: size,
        child: WebSafeLottie.asset(
          'assets/emoji/lottie/$lottieFile',
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (context, error, stackTrace) {
            return Text(emoji, style: TextStyle(fontSize: size * 0.8));
          },
        ),
      );
    }

    return Text(emoji, style: TextStyle(fontSize: size * 0.8));
  }
}
