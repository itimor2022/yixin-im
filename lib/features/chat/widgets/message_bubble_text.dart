// 文件用途：提供 _MessageBubbleText 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleText，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

final RegExp _mentionRegex = RegExp(r'@[A-Za-z0-9_]{3,32}');
final RegExp _mentionWordCharRegex = RegExp(r'[A-Za-z0-9_]');

// 关键声明：message bubble text 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleText on MessageBubble {
  // 流程逻辑：`_containsMention` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  bool _containsMention(String text) {
    for (final match in _mentionRegex.allMatches(text)) {
      if (_isValidMentionMatch(text, match)) return true;
    }
    return false;
  }

  bool _isValidMentionMatch(String text, RegExpMatch match) {
    final start = match.start;
    final end = match.end;
    if (start > 0 && _mentionWordCharRegex.hasMatch(text[start - 1])) {
      return false;
    }
    if (end < text.length && _mentionWordCharRegex.hasMatch(text[end])) {
      return false;
    }
    return true;
  }

  void _openMentionSearch(BuildContext context, String mention) {
    final query = Uri.encodeQueryComponent(mention);
    context.push('/search-users?query=$query');
  }

  List<InlineSpan> _buildInteractiveTextSpans(
    BuildContext context,
    String text,
    TextStyle defaultStyle,
  ) {
    final spans = <InlineSpan>[];
    final mentionStyle = defaultStyle.copyWith(
      color: AppColors.primaryFor(context),
      fontWeight: FontWeight.w600,
    );
    final linkStyle = defaultStyle.copyWith(
      color: Colors.blue,
      decoration: TextDecoration.underline,
      decorationColor: Colors.blue,
    );

    var cursor = 0;
    while (cursor < text.length) {
      final nextLink = LinkUtils.urlRegex
          .allMatches(text, cursor)
          .cast<RegExpMatch?>()
          .firstWhere((match) => match != null, orElse: () => null);
      final nextMention = _mentionRegex
          .allMatches(text, cursor)
          .where((match) => _isValidMentionMatch(text, match))
          .cast<RegExpMatch?>()
          .firstWhere((match) => match != null, orElse: () => null);

      RegExpMatch? next;
      var isLink = false;
      if (nextLink != null &&
          (nextMention == null || nextLink.start <= nextMention.start)) {
        next = nextLink;
        isLink = true;
      } else {
        next = nextMention;
      }

      if (next == null) {
        spans.add(TextSpan(text: text.substring(cursor), style: defaultStyle));
        break;
      }

      if (next.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, next.start),
            style: defaultStyle,
          ),
        );
      }

      final matchedText = next.group(0)!;
      spans.add(
        TextSpan(
          text: matchedText,
          style: isLink ? linkStyle : mentionStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (isLink) {
                LinkUtils.openLink(context, matchedText);
              } else {
                _openMentionSearch(context, matchedText);
              }
            },
        ),
      );
      cursor = next.end;
    }

    return spans;
  }

  Widget _buildTextBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    if (message.content
        .startsWith(EmojiStoreService.builtInStickerSendPrefix)) {
      return _buildBuiltInStickerBubble(timeColor, isOutgoing);
    }

    final emojiInfo = _detectPureEmoji(message.content);

    if (emojiInfo != null) {
      return _buildEmojiBubble(context, emojiInfo, timeColor, isOutgoing);
    }

    return Container(
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: _getBubbleRadius(isOutgoing),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.replyTo != null)
                  _buildReplyPreview(context, textColor),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: _buildRichTextContent(context, textColor)),
                    SizedBox(
                      width: message.isEdited
                          ? (isOutgoing ? 88 : 66)
                          : (isOutgoing ? 54 : 42),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isEdited)
                  Text(
                    '${AppLocalizations.of(context).get('edited')} ',
                    style: TextStyle(
                      color: timeColor.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                Text(
                  DateFormat('HH:mm')
                      .format(toCurrentLocalTime(message.createdAt)),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 3),
                  _buildStatusIcon(timeColor),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuiltInStickerBubble(Color timeColor, bool isOutgoing) {
    final assetPath = message.content
        .substring(EmojiStoreService.builtInStickerSendPrefix.length)
        .trim();
    if (assetPath.isEmpty || !assetPath.startsWith('assets/stickers/')) {
      return Text(message.content);
    }

    return Column(
      crossAxisAlignment:
          isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: assetPath.endsWith('.json')
              ? VisibleLottie(
                  path: assetPath,
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                  repeat: true,
                )
              : Image.asset(
                  assetPath,
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('HH:mm')
                    .format(toCurrentLocalTime(message.createdAt)),
                style: AppTextStyles.timestamp.copyWith(color: timeColor),
              ),
              if (message.isOutgoing) ...[
                const SizedBox(width: 3),
                _buildStatusIcon(timeColor),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 检测是否是纯表情消息（1-3个表情，无其他文字）
  _EmojiInfo? _detectPureEmoji(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    final chars = trimmed.characters.toList();
    if (chars.isEmpty || chars.length > 3) return null;

    final emojis = <AnimatedEmoji>[];
    for (final char in chars) {
      final animated = EmojiAnimations.findByEmoji(char);
      if (animated != null) {
        emojis.add(animated);
      } else if (_isEmoji(char)) {
        emojis.add(
          AnimatedEmoji(
            emoji: char,
            name: '',
            file: '',
            category: EmojiCategory.faces,
          ),
        );
      } else {
        return null;
      }
    }

    return _EmojiInfo(emojis: emojis, count: emojis.length);
  }

  bool _isEmoji(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    return (rune >= 0x1F300 && rune <= 0x1F9FF) ||
        (rune >= 0x2600 && rune <= 0x26FF) ||
        (rune >= 0x2700 && rune <= 0x27BF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        (rune >= 0x1F600 && rune <= 0x1F64F) ||
        (rune >= 0x1F680 && rune <= 0x1F6FF) ||
        (rune >= 0x1F1E0 && rune <= 0x1F1FF);
  }

  Widget _buildEmojiBubble(
    BuildContext context,
    _EmojiInfo info,
    Color timeColor,
    bool isOutgoing,
  ) {
    final size = info.count == 1 ? 100.0 : (info.count == 2 ? 80.0 : 64.0);

    return Column(
      crossAxisAlignment:
          isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: info.emojis.map((emoji) {
            if (emoji.file.isNotEmpty) {
              return VisibleLottie(
                path: emoji.path,
                width: size,
                height: size,
                fit: BoxFit.contain,
                repeat: true,
              );
            } else {
              return SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Text(
                    emoji.emoji,
                    style: TextStyle(fontSize: size * 0.8),
                  ),
                ),
              );
            }
          }).toList(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isEdited)
                Text(
                  '${AppLocalizations.of(context).get('edited')} ',
                  style: TextStyle(
                    color: timeColor.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              Text(
                DateFormat('HH:mm')
                    .format(toCurrentLocalTime(message.createdAt)),
                style: AppTextStyles.timestamp.copyWith(color: timeColor),
              ),
              if (isOutgoing) ...[
                const SizedBox(width: 3),
                _buildStatusIcon(timeColor),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRichTextContent(BuildContext context, Color textColor) {
    final content = message.content;
    final defaultStyle = AppTextStyles.bodyMedium.copyWith(
      color: textColor,
      fontSize: messageFontSize,
    );
    final hasInteractiveText =
        LinkUtils.containsLink(content) || _containsMention(content);

    if (content.length < 2 || !_mightContainAnimatedEmoji(content)) {
      if (hasInteractiveText) {
        return RichText(
          text: TextSpan(
            children: _buildInteractiveTextSpans(
              context,
              content,
              defaultStyle,
            ),
          ),
        );
      }
      return Text(content, style: defaultStyle);
    }

    final spans = <InlineSpan>[];
    int currentIndex = 0;
    final chars = content.characters.toList();
    bool hasAnimatedEmoji = false;

    for (int i = 0; i < chars.length; i++) {
      final char = chars[i];
      final animated = EmojiAnimations.findByEmoji(char);

      if (animated != null) {
        hasAnimatedEmoji = true;
        if (currentIndex < i) {
          spans.addAll(
            _buildInteractiveTextSpans(
              context,
              chars.sublist(currentIndex, i).join(),
              defaultStyle,
            ),
          );
        }
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: VisibleLottie(
              path: animated.path,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
        );
        currentIndex = i + 1;
      }
    }

    if (!hasAnimatedEmoji) {
      if (hasInteractiveText) {
        return RichText(
          text: TextSpan(
            children: _buildInteractiveTextSpans(
              context,
              content,
              defaultStyle,
            ),
          ),
        );
      }
      return Text(content, style: defaultStyle);
    }

    if (currentIndex < chars.length) {
      spans.addAll(
        _buildInteractiveTextSpans(
          context,
          chars.sublist(currentIndex).join(),
          defaultStyle,
        ),
      );
    }

    return Text.rich(TextSpan(children: spans));
  }

  bool _mightContainAnimatedEmoji(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x1F600 && rune <= 0x1F64F) ||
          (rune >= 0x1F300 && rune <= 0x1F5FF) ||
          (rune >= 0x1F680 && rune <= 0x1F6FF) ||
          (rune >= 0x1F900 && rune <= 0x1F9FF) ||
          (rune >= 0x2600 && rune <= 0x26FF)) {
        return true;
      }
    }
    return false;
  }
}

class _EmojiInfo {
  final List<AnimatedEmoji> emojis;
  final int count;

  const _EmojiInfo({required this.emojis, required this.count});
}
