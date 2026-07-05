import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/api/api_client.dart'
    show ApiClient, ApiConfig, TokenStorage;
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/visible_lottie.dart';
import '../../../core/utils/link_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/message_provider.dart';
import '../pages/user_profile_page.dart';
import '../../wallet/services/wallet_service.dart';
import '../../wallet/widgets/red_packet_bubble.dart';
import '../../wallet/widgets/transfer_bubble.dart';

///  消息气泡
class MessageBubble extends StatelessWidget {
  final MessageItem message;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showSenderName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Function(LongPressStartDetails)? onLongPressStart;
  final Function(TapDownDetails)? onSecondaryTapDown; // 右键点击（桌面端）
  final VoidCallback? onDoubleTap;
  final VoidCallback? onReplyTap; // 点击回复预览跳转到原消息
  final Color? customOutgoingColor;
  final Color? customIncomingColor;
  final Function(String userId, String userName)? onMentionUser; // 长按头像@用户
  final bool isGroupChat;
  final bool canOpenMemberProfile;

  const MessageBubble({
    super.key,
    required this.message,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.showSenderName = false,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.onDoubleTap,
    this.onReplyTap,
    this.customOutgoingColor,
    this.customIncomingColor,
    this.onMentionUser,
    this.isGroupChat = false,
    this.canOpenMemberProfile = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOutgoing = message.isOutgoing;

    // 气泡颜色（支持自定义）
    final bubbleColor = isOutgoing
        ? (customOutgoingColor ??
            (isDark
                ? AppColors.darkBubbleOutgoing
                : AppColors.lightBubbleOutgoing))
        : (customIncomingColor ??
            (isDark
                ? AppColors.darkBubbleIncoming
                : AppColors.lightBubbleIncoming));

    // 文字颜色 - 根据气泡颜色亮度智能选择
    // 计算气泡颜色的亮度，决定使用黑色还是白色文字
    final bubbleLuminance = bubbleColor.computeLuminance();
    final textColor = bubbleLuminance > 0.5 ? Colors.black : Colors.white;

    // 时间颜色 - 同样根据气泡亮度调整
    final Color timeColor;
    if (bubbleLuminance > 0.5) {
      // 浅色气泡：使用深色时间
      timeColor =
          isOutgoing ? const Color(0xFF5D9B5D) : const Color(0xFF888888);
    } else {
      // 深色气泡：使用浅色时间
      timeColor = Colors.white60;
    }

    // 是否显示头像（群组/频道的接收消息）
    final showAvatar = showSenderName && !isOutgoing;

    return Padding(
      padding: EdgeInsets.only(
        top: isFirstInGroup ? 8 : 2,
        bottom: isLastInGroup ? 8 : 2,
        left: 8,
        right: 8,
      ),
      child: Row(
        mainAxisAlignment:
            isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 左侧头像（群组/频道消息）
          if (showAvatar) ...[
            if (isLastInGroup)
              GestureDetector(
                onTap: canOpenMemberProfile
                    ? () => _openSenderProfile(context)
                    : null,
                onLongPress: onMentionUser != null
                    ? () {
                        // 长按头像@用户
                        GlobalHaptics.medium();
                        onMentionUser!(message.senderId, message.senderName);
                      }
                    : null,
                child: AvatarWidget(
                  avatar: message.senderAvatar,
                  name: message.senderName,
                  userId: message.senderId,
                  size: 32,
                ),
              )
            else
              const SizedBox(width: 32), // 占位
            const SizedBox(width: 8),
          ],

          // 消息气泡
          Flexible(
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPressStart == null ? onLongPress : null,
              onLongPressStart: onLongPressStart,
              onSecondaryTapDown: onSecondaryTapDown, // 右键点击（桌面端）
              onDoubleTap: onDoubleTap,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width *
                      (showAvatar ? 0.7 : 0.75),
                ),
                child: Column(
                  crossAxisAlignment: isOutgoing
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _buildBubble(
                      context,
                      bubbleColor,
                      textColor,
                      timeColor,
                      isOutgoing,
                      isDark,
                    ),
                    // 表情回复
                    if (message.reactions.isNotEmpty)
                      _buildReactionsRow(isDark, isOutgoing),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
    bool isDark,
  ) {
    if (message.shouldHideBurnContent) {
      return _buildBurnLockedBubble(
        bubbleColor,
        textColor,
        timeColor,
        isOutgoing,
        isDark,
      );
    }

    late final Widget bubble;
    // 根据消息类型构建不同内容
    switch (message.type) {
      case MessageItemType.image:
        bubble = _buildImageBubble(bubbleColor, timeColor, isOutgoing);
        break;
      case MessageItemType.video:
        bubble = _buildVideoBubble(bubbleColor, timeColor, isOutgoing);
        break;
      case MessageItemType.voice:
        bubble = _buildVoiceBubble(
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      case MessageItemType.file:
        bubble = _buildFileBubble(
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      case MessageItemType.location:
        bubble = _buildLocationBubble(
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      case MessageItemType.sticker:
        bubble = _buildStickerBubble(timeColor);
        break;
      case MessageItemType.contact:
        bubble = _buildContactCardBubble(
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      case MessageItemType.call:
        bubble = _buildCallBubble(
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      case MessageItemType.redPacket:
        bubble = _buildRedPacketBubble(context, isOutgoing, isGroupChat);
        break;
      case MessageItemType.transfer:
        bubble = _buildTransferBubble(context, isOutgoing, isDark);
        break;
      default:
        bubble = _buildTextBubble(
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
    }

    return _wrapBurnCountdown(bubble, isOutgoing, isDark);
  }

  Widget _buildBurnLockedBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
    bool isDark,
  ) {
    final lockedBurnSeconds =
        message.burnAfterSeconds > 0 ? message.burnAfterSeconds : 10;
    final lockedHintColor = isDark ? Colors.white70 : Colors.black87;
    final lockedSubColor = isDark ? Colors.white54 : Colors.black54;

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: Color(0xFFFF7A00),
                ),
                const SizedBox(width: 6),
                Text(
                  '阅后即焚消息',
                  style: TextStyle(
                    color: lockedHintColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '点击查看，查看后 $lockedBurnSeconds 秒自动销毁',
              style: TextStyle(
                color: lockedSubColor,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.max,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 3),
                  _buildStatusIcon(timeColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    /*
    final seconds = message.burnAfterSeconds > 0
        ? message.burnAfterSeconds
        : 10;
    final hintColor = isDark ? Colors.white70 : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black54;

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: Color(0xFFFF7A00),
                ),
                const SizedBox(width: 6),
                Text(
                  '阅后即焚消息',
                  style: TextStyle(
                    color: hintColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '点击查看，查看后 $seconds 秒自动销毁',
              style: TextStyle(color: subColor, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.max,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 3),
                  _buildStatusIcon(timeColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    */
  }

  Widget _wrapBurnCountdown(Widget child, bool isOutgoing, bool isDark) {
    final countdownSeconds = message.burnCountdownSeconds;
    if (!message.burnAfterRead ||
        countdownSeconds == null ||
        countdownSeconds <= 0) {
      return child;
    }

    final countdownBadgeColor =
        isDark ? const Color(0xFF2A1B12) : const Color(0xFFFFF3E8);
    final countdownBorderColor =
        isDark ? const Color(0x66FF8A50) : const Color(0xFFFFC7A7);
    final countdownLabelColor =
        isDark ? Colors.white70 : const Color(0xFF9A3412);

    return Column(
      crossAxisAlignment:
          isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: countdownBadgeColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: countdownBorderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 14,
                color: Color(0xFFFF7A00),
              ),
              const SizedBox(width: 4),
              Text(
                '$countdownSeconds 秒后销毁',
                style: TextStyle(
                  color: countdownLabelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    /*
    final seconds = message.burnCountdownSeconds;
    if (!message.burnAfterRead || seconds == null || seconds <= 0) {
      return child;
    }

    final badgeColor = isDark
        ? const Color(0xFF2A1B12)
        : const Color(0xFFFFF3E8);
    final borderColor = isDark
        ? const Color(0x66FF8A50)
        : const Color(0xFFFFC7A7);
    final labelColor = isDark ? Colors.white70 : const Color(0xFF9A3412);

    return Column(
      crossAxisAlignment: isOutgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 14,
                color: Color(0xFFFF7A00),
              ),
              const SizedBox(width: 4),
              Text(
                '$seconds 秒后销毁',
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    */
  }

  /// 构建表情回复行
  /// 性能优化建议：考虑使用 visibility_detector 包，只在消息可见时播放动画
  /// 当前实现：所有动画持续播放，可能影响性能（特别是多个消息同时显示时）
  Widget _buildReactionsRow(bool isDark, bool isOutgoing) {
    // 按表情分组统计
    final reactionCounts = <String, List<String>>{};
    for (final reaction in message.reactions) {
      reactionCounts.putIfAbsent(reaction.emoji, () => []);
      reactionCounts[reaction.emoji]!.add(reaction.userName);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactionCounts.entries.map((entry) {
          final emoji = entry.key;
          final users = entry.value;
          final count = users.length;
          final animatedEmoji = EmojiAnimations.findByEmoji(emoji);

          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: animatedEmoji != null ? 4 : 8,
              vertical: animatedEmoji != null ? 2 : 4,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 动态表情或静态表情
                // TODO: 性能优化 - 考虑添加动画播放控制（如使用 visibility_detector）
                // 当前所有动画持续播放，可能影响性能
                if (animatedEmoji != null)
                  VisibleLottie(
                    path: animatedEmoji.path,
                    width: 22,
                    height: 22,
                    repeat: true,
                  )
                else
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                if (count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    // 检测是否是纯表情消息
    final emojiInfo = _detectPureEmoji(message.content);

    if (emojiInfo != null) {
      // 渲染动画表情
      return _buildEmojiBubble(emojiInfo, timeColor, isOutgoing);
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
                // 发送者名称（群聊中显示）+ 动态表情
                if (showSenderName && isFirstInGroup)
                  Builder(
                    builder: (context) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GestureDetector(
                        onTap: canOpenMemberProfile
                            ? () => _openSenderProfile(context)
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 使用用户设置的昵称颜色，如果没有则使用默认颜色
                            if (message.senderNicknameColor != null &&
                                message.senderNicknameColor!.isNotEmpty)
                              ColoredNameWidget(
                                name: message.senderName,
                                nicknameColor: message.senderNicknameColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              )
                            else
                              Text(
                                message.senderName,
                                style: AppTextStyles.caption.copyWith(
                                  color: _getSenderColor(message.senderId),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            // 动态表情状态
                            if (message.senderEmojiAvatar != null &&
                                message.senderEmojiAvatar!.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              EmojiStatusWidget(
                                emoji: message.senderEmojiAvatar!,
                                size: 14,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                // 回复预览
                if (message.replyTo != null) _buildReplyPreview(textColor),

                // 消息内容 - 富文本渲染（支持内嵌表情）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: _buildRichTextContent(textColor)),
                    // 时间和状态占位（已编辑+发送状态需要更多空间）
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

          // 时间和状态
          Positioned(
            right: 8,
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 已编辑标记
                if (message.isEdited)
                  Text(
                    '已编辑 ',
                    style: TextStyle(
                      color: timeColor.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                // 时间
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                // 发送状态
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

  /// 检测是否是纯表情消息（1-3个表情，无其他文字）
  _EmojiInfo? _detectPureEmoji(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    // 提取所有字符（按grapheme cluster）
    final chars = trimmed.characters.toList();
    if (chars.isEmpty || chars.length > 3) return null;

    // 检查每个字符是否都是emoji
    final emojis = <AnimatedEmoji>[];
    for (final char in chars) {
      final animated = EmojiAnimations.findByEmoji(char);
      if (animated != null) {
        emojis.add(animated);
      } else if (_isEmoji(char)) {
        // 普通emoji（没有动画）
        emojis.add(
          AnimatedEmoji(
            emoji: char,
            name: '',
            file: '',
            category: EmojiCategory.faces,
          ),
        );
      } else {
        // 包含非emoji字符
        return null;
      }
    }

    return _EmojiInfo(emojis: emojis, count: emojis.length);
  }

  /// 检测字符是否是emoji
  bool _isEmoji(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    // 检测常见emoji范围
    return (rune >= 0x1F300 && rune <= 0x1F9FF) || // 杂项符号和象形文字
        (rune >= 0x2600 && rune <= 0x26FF) || // 杂项符号
        (rune >= 0x2700 && rune <= 0x27BF) || // 装饰符号
        (rune >= 0xFE00 && rune <= 0xFE0F) || // 变体选择符
        (rune >= 0x1F600 && rune <= 0x1F64F) || // 表情
        (rune >= 0x1F680 && rune <= 0x1F6FF) || // 交通符号
        (rune >= 0x1F1E0 && rune <= 0x1F1FF); // 旗帜
  }

  /// 构建纯表情消息气泡（大动图）
  Widget _buildEmojiBubble(_EmojiInfo info, Color timeColor, bool isOutgoing) {
    // 根据表情数量确定大小
    final size = info.count == 1 ? 100.0 : (info.count == 2 ? 80.0 : 64.0);

    return Column(
      crossAxisAlignment:
          isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 发送者名称 + 动态表情
        if (showSenderName && isFirstInGroup && !isOutgoing)
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: GestureDetector(
                onTap: canOpenMemberProfile
                    ? () => _openSenderProfile(context)
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.senderNicknameColor != null &&
                        message.senderNicknameColor!.isNotEmpty)
                      ColoredNameWidget(
                        name: message.senderName,
                        nicknameColor: message.senderNicknameColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )
                    else
                      Text(
                        message.senderName,
                        style: AppTextStyles.caption.copyWith(
                          color: _getSenderColor(message.senderId),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (message.senderEmojiAvatar != null &&
                        message.senderEmojiAvatar!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      EmojiStatusWidget(
                        emoji: message.senderEmojiAvatar!,
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        // 表情动画
        Row(
          mainAxisSize: MainAxisSize.min,
          children: info.emojis.map((emoji) {
            if (emoji.file.isNotEmpty) {
              // 有动画的表情（使用可见性控制）
              return VisibleLottie(
                path: emoji.path,
                width: size,
                height: size,
                fit: BoxFit.contain,
                repeat: true,
              );
            } else {
              // 普通emoji（无动画）
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

        // 时间和状态
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isEdited)
                Text(
                  '已编辑 ',
                  style: TextStyle(
                    color: timeColor.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              Text(
                DateFormat('HH:mm').format(message.createdAt),
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

  /// 构建富文本内容（文字+内嵌小表情+链接）
  /// 优化：先快速检查是否包含动画表情，避免不必要的遍历
  Widget _buildRichTextContent(Color textColor) {
    final content = message.content;
    final defaultStyle = AppTextStyles.bodyMedium.copyWith(color: textColor);
    final isGroup = true;

    // 快速路径：如果消息较短或不包含 emoji 范围的字符，检查链接并返回
    if (content.length < 2 || !_mightContainAnimatedEmoji(content)) {
      // 检查是否包含链接
      if (!isGroup &&LinkUtils.containsLink(content)) {
        return Builder(
          builder: (context) => RichText(
            text: LinkUtils.buildLinkText(
              text: content,
              defaultStyle: defaultStyle,
              linkStyle: defaultStyle.copyWith(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                decorationColor: Colors.blue,
              ),
              context: context,
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
        // 先添加前面的文本
        if (currentIndex < i) {
          spans.add(
            TextSpan(
              text: chars.sublist(currentIndex, i).join(),
              style: defaultStyle,
            ),
          );
        }
        // 添加内嵌动画表情
        // 性能优化建议：考虑限制同时播放的动画数量，或使用 visibility_detector 控制播放
        // 使用可见性控制的 Lottie，优化性能
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

    // 如果没有找到动画表情，检查链接并返回
    if (!hasAnimatedEmoji) {
      if (LinkUtils.containsLink(content)) {
        return Builder(
          builder: (context) => RichText(
            text: LinkUtils.buildLinkText(
              text: content,
              defaultStyle: defaultStyle,
              linkStyle: defaultStyle.copyWith(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                decorationColor: Colors.blue,
              ),
              context: context,
            ),
          ),
        );
      }
      return Text(content, style: defaultStyle);
    }

    // 添加剩余文本
    if (currentIndex < chars.length) {
      spans.add(
        TextSpan(text: chars.sublist(currentIndex).join(), style: defaultStyle),
      );
    }

    return Text.rich(TextSpan(children: spans));
  }

  /// 快速检查字符串是否可能包含动画表情
  /// 只检查是否包含 emoji 范围的字符，避免完整遍历
  bool _mightContainAnimatedEmoji(String text) {
    for (final rune in text.runes) {
      // 只检查常见 emoji 范围
      if ((rune >= 0x1F600 && rune <= 0x1F64F) || // 表情符号
          (rune >= 0x1F300 && rune <= 0x1F5FF) || // 杂项符号和象形文字
          (rune >= 0x1F680 && rune <= 0x1F6FF) || // 交通和地图符号
          (rune >= 0x1F900 && rune <= 0x1F9FF) || // 补充符号
          (rune >= 0x2600 && rune <= 0x26FF)) {
        // 杂项符号
        return true;
      }
    }
    return false;
  }

Widget _buildImageBubble(
    Color bubbleColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    // 🌟 新增：检查是否有附带的文字说明
    final hasText = message.content.trim().isNotEmpty;

    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          final imageUrl = _getImageUrl();
          if (imageUrl == null) return;

          Navigator.of(context).push(
            PageRouteBuilder(
              opaque: false,
              barrierColor: Colors.black87,
              pageBuilder: (ctx, animation, secondaryAnimation) {
                return _ImagePreviewPage(
                  imageUrl: imageUrl,
                  isLocalFile: message.mediaUrl?.startsWith('/') == true &&
                      !(message.mediaUrl?.startsWith('/uploads') ?? false),
                );
              },
              transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            // 🌟 如果有文字，我们需要给整个气泡加上背景颜色，让文字好识别
            color: hasText ? bubbleColor : null,
            borderRadius: _getBubbleRadius(isOutgoing),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _getBubbleRadius(isOutgoing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 上层：图片部分
                Stack(
                  children: [
                    // 图片 - 使用已知尺寸预占位，避免加载后闪烁
                    _buildSizedMedia(280, 400),

                    // 🌟 如果没有附加文字，时间和状态依旧作为底层半透明遮罩覆盖在图片上（保持原逻辑）
                    if (!hasText)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        left: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.35),
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 12, 8, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                DateFormat('HH:mm').format(message.createdAt),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                              if (isOutgoing) ...[
                                const SizedBox(width: 3),
                                _buildStatusIcon(Colors.white70),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // 2. 🌟 下层：文字说明部分（仅在有关联文字时渲染）
                if (hasText)
                  Padding(
                    // 左右和下方留出间距，顶部与图片错开
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Stack(
                      children: [
                        // 富文本渲染：支持小表情、链接等
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: 4,
                            right: message.isEdited
                                ? (isOutgoing ? 88 : 66)
                                : (isOutgoing ? 54 : 42), // 留出右下角时间状态的空间
                          ),
                          child: _buildRichTextContent(
                            bubbleColor.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                        // 右下角的时间和状态
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.isEdited)
                                Text(
                                  '已编辑 ',
                                  style: TextStyle(
                                    color: timeColor.withOpacity(0.8),
                                    fontSize: 11,
                                  ),
                                ),
                              Text(
                                DateFormat('HH:mm').format(message.createdAt),
                                style: AppTextStyles.timestamp
                                    .copyWith(color: timeColor),
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
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _getImageUrl() {
    if (message.mediaUrl == null) return null;

    final url = message.mediaUrl!;

    // 本地文件路径
    if (url.startsWith('/') && !url.startsWith('/uploads')) {
      return url;
    }

    // 网络URL
    if (url.startsWith('/uploads')) {
      return '${ApiConfig.serverUrl}$url';
    } else if (!url.startsWith('http')) {
      return '${ApiConfig.serverUrl}/$url';
    }

    return url;
  }

  Widget _buildVideoBubble(
    Color bubbleColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    return _VideoBubbleWidget(
      message: message,
      isOutgoing: isOutgoing,
      getBubbleRadius: _getBubbleRadius,
      buildStatusIcon: _buildStatusIcon,
    );
  }

  Widget _buildVoiceBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    return _VoiceBubbleWidget(
      message: message,
      bubbleColor: bubbleColor,
      textColor: textColor,
      timeColor: timeColor,
      isOutgoing: isOutgoing,
      bubbleRadius: _getBubbleRadius(isOutgoing),
      buildStatusIcon: () => _buildStatusIcon(timeColor),
    );
  }

  Widget _buildFileBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    return _FileBubbleWidget(
      message: message,
      bubbleColor: bubbleColor,
      textColor: textColor,
      timeColor: timeColor,
      isOutgoing: isOutgoing,
      bubbleRadius: _getBubbleRadius(isOutgoing),
      buildStatusIcon: () => _buildStatusIcon(timeColor),
    );
  }

  Widget _buildLocationBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    final latitude = message.locationLatitude;
    final longitude = message.locationLongitude;
    final title = message.locationTitle?.trim().isNotEmpty == true
        ? message.locationTitle!.trim()
        : message.content;
    final address = message.locationAddress?.trim();
    final coordinates = (latitude != null && longitude != null)
        ? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
        : '';

    Future<void> openMap() async {
      if (latitude == null || longitude == null) return;
      final url = Uri.parse(
        'https://maps.google.com/?q=${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }

    String buildStaticMapUrl(double lat, double lng) {
      final latText = lat.toStringAsFixed(6);
      final lngText = lng.toStringAsFixed(6);
      return 'https://staticmap.openstreetmap.de/staticmap.php?center=$latText,$lngText&zoom=15&size=800x360&maptype=mapnik&markers=$latText,$lngText,red-pushpin';
    }

    return GestureDetector(
      onTap: (latitude != null && longitude != null) ? openMap : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: _getBubbleRadius(isOutgoing),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (latitude != null && longitude != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1.9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: buildStaticMapUrl(latitude, longitude),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: Colors.black.withOpacity(0.05),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.black.withOpacity(0.05),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.map_outlined,
                                size: 30,
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                coordinates,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: textColor.withOpacity(0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.46),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '地图位置',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title.isNotEmpty ? title : '位置',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (address != null && address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                address,
                style: AppTextStyles.bodySmall.copyWith(
                  color: textColor.withOpacity(0.75),
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ] else if (coordinates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                coordinates,
                style: AppTextStyles.bodySmall.copyWith(
                  color: textColor.withOpacity(0.75),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 3),
                  _buildStatusIcon(timeColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerBubble(Color timeColor) {
    return Column(
      crossAxisAlignment: message.isOutgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        // 贴纸图片
        SizedBox(width: 150, height: 150, child: _buildMediaImage()),

        // 时间
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('HH:mm').format(message.createdAt),
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

  /// 构建名片气泡
  Widget _buildContactCardBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    final contactName = message.contactName ?? '用户';
    final contactUsername = message.contactUsername;
    final contactAvatar = message.contactAvatar;
    final contactUserId = message.contactUserId;
    final contactNicknameColor = message.contactNicknameColor;
    final contactEmojiAvatar = message.contactEmojiAvatar;

    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          // 点击名片跳转到用户资料页
          if (contactUserId != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfilePage(
                  userId: contactUserId,
                  name: contactName,
                  avatar: contactAvatar,
                ),
              ),
            );
          }
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: _getBubbleRadius(isOutgoing),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名片内容
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 头像（使用 AvatarWidget 支持颜色）
                    AvatarWidget(
                      name: contactName,
                      avatar: contactAvatar,
                      userId: contactUserId ?? '',
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    // 名称和用户名
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 名字（带颜色）和表情
                          Row(
                            children: [
                              Flexible(
                                child: ColoredNameWidget(
                                  name: contactName,
                                  nicknameColor: contactNicknameColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  defaultColor: textColor,
                                ),
                              ),
                              if (contactEmojiAvatar != null &&
                                  contactEmojiAvatar.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                EmojiStatusWidget(
                                  emoji: contactEmojiAvatar,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                          if (contactUsername != null &&
                              contactUsername.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '@$contactUsername',
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 右侧箭头
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: textColor.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
              // 分隔线
              Container(height: 0.5, color: textColor.withOpacity(0.1)),
              // 底部：名片标签和时间
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.contact_page_outlined,
                      size: 14,
                      color: textColor.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '联系人名片',
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withOpacity(0.5),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('HH:mm').format(message.createdAt),
                      style: TextStyle(fontSize: 11, color: timeColor),
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
        ),
      ),
    );
  }

  /// 构建通话记录气泡
  Widget _buildCallBubble(
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    // 解析通话信息
    final content = message.content;
    final isVideoCall = content.contains('视频');

    // 解析通话状态和时长
    final callInfo = _parseCallContent(content, isOutgoing);
    final displayText = callInfo.displayText;
    final isMissed = callInfo.isMissed;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: _getBubbleRadius(isOutgoing),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 通话图标
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMissed
                  ? Colors.red.withOpacity(0.15)
                  : AppColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isVideoCall
                  ? (isMissed ? Icons.videocam_off : Icons.videocam)
                  : (isMissed ? Icons.phone_missed : Icons.phone),
              size: 20,
              color: isMissed ? Colors.red : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          // 通话信息
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: TextStyle(fontSize: 11, color: timeColor),
                ),
              ],
            ),
          ),
          if (isOutgoing) ...[
            const SizedBox(width: 4),
            _buildStatusIcon(timeColor),
          ],
        ],
      ),
    );
  }

  /// 解析通话内容，返回显示文本和是否未接
  ({String displayText, bool isMissed}) _parseCallContent(
    String content,
    bool isOutgoing,
  ) {
    // 已有明确状态的消息直接返回
    if (content.contains('已取消') ||
        content.contains('对方忙') ||
        content.contains('未接') ||
        content.contains('拒绝') ||
        content.contains('未接通') ||
        content.contains('无应答')) {
      return (displayText: content, isMissed: true);
    }

    // 检查是否是 "语音/视频通话 00:00" 格式（未接通的通话）
    final timePattern = RegExp(r'(\d+):(\d+)$');
    final match = timePattern.firstMatch(content);

    if (match != null) {
      final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
      final totalSeconds = minutes * 60 + seconds;

      // 如果时长为0，说明通话未接通
      if (totalSeconds == 0) {
        final callType = content.contains('视频') ? '视频通话' : '语音通话';
        // 根据是否为发送方判断状态
        if (isOutgoing) {
          return (displayText: '$callType 未接通', isMissed: true);
        } else {
          return (displayText: '$callType 未接听', isMissed: true);
        }
      }
    }

    // 有时长的通话，正常显示
    return (displayText: content, isMissed: false);
  }

  /// 构建红包消息气泡（带实时状态）
  Widget _buildRedPacketBubble(
    BuildContext context,
    bool isOutgoing,
    bool isGroupChat,
  ) {
    RedPacketInfo? redPacket;
    try {
      final content = message.content;
      if (content.startsWith('{')) {
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        redPacket = RedPacketInfo.fromJson(jsonData);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RedPacket] Parse error: $e');
    }

    redPacket ??= RedPacketInfo(
      id: message.id,
      senderId: message.senderId,
      senderName: '',
      chatId: '',
      type: RedPacketType.normal,
      totalAmount: 0,
      totalCount: 1,
      remainingAmount: 0,
      remainingCount: 0,
      message: '恭喜发财，大吉大利',
      status: RedPacketStatus.active,
      isClaimed: false,
      createdAt: message.createdAt,
    );

    return _LiveRedPacketBubble(
      messageId: message.id,
      redPacket: redPacket,
      isOutgoing: isOutgoing,
      senderAvatar: message.senderAvatar,
      isGroupChat: isGroupChat,
    );
  }

  /// 构建转账消息气泡（带实时状态）
  Widget _buildTransferBubble(
    BuildContext context,
    bool isOutgoing,
    bool isDark,
  ) {
    TransferInfo? transfer;
    try {
      final content = message.content;
      if (content.startsWith('{')) {
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        transfer = TransferInfo.fromJson(jsonData);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Transfer] Parse error: $e');
    }

    transfer ??= TransferInfo(
      id: message.id,
      senderId: message.senderId,
      senderName: '',
      receiverId: '',
      receiverName: '',
      amount: 0,
      status: TransferStatus.pending,
      createdAt: message.createdAt,
    );

    return _LiveTransferBubble(
      messageId: message.id,
      transfer: transfer,
      isOutgoing: isOutgoing,
      senderAvatar: message.senderAvatar,
    );
  }

  Widget _buildReplyPreview(Color textColor) {
    // TG 风格回复预览 - 带背景的卡片样式
    final replyAccentColor = message.isOutgoing
        ? const Color(0xFF4CAF50) // 绿色调和发送气泡
        : AppColors.primary;

    return GestureDetector(
      onTap: onReplyTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: textColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 左侧彩色竖条
              Container(width: 3, height: 36, color: replyAccentColor),
              const SizedBox(width: 8),
              // 内容
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 发送者名字
                      Text(
                        message.replyTo!.senderName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: replyAccentColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      // 消息内容预览
                      Text(
                        message.replyTo!.content,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Color color) {
    IconData icon;

    switch (message.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        );
      case MessageStatus.sent:
        icon = Icons.check_rounded;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all_rounded;
        break;
      case MessageStatus.read:
        return Icon(
          Icons.done_all_rounded,
          size: 16,
          color: AppColors.messageRead,
        );
      case MessageStatus.failed:
        return Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: AppColors.error,
        );
    }

    return Icon(icon, size: 16, color: color);
  }

  BorderRadius _getBubbleRadius(bool isOutgoing) {
    const radius = Radius.circular(18);
    const smallRadius = Radius.circular(4);

    if (isOutgoing) {
      return BorderRadius.only(
        topLeft: radius,
        topRight: isFirstInGroup ? radius : smallRadius,
        bottomLeft: radius,
        bottomRight: isLastInGroup ? radius : smallRadius,
      );
    } else {
      return BorderRadius.only(
        topLeft: isFirstInGroup ? radius : smallRadius,
        topRight: radius,
        bottomLeft: isLastInGroup ? radius : smallRadius,
        bottomRight: radius,
      );
    }
  }

  /// 根据发送者ID生成颜色（群聊中不同人不同颜色）
  Color _getSenderColor(String senderId) {
    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
      const Color(0xFFFF5722),
      const Color(0xFF795548),
    ];
    final index = senderId.hashCode.abs() % colors.length;
    return colors[index];
  }

  void _openSenderProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userId: message.senderId,
          name: message.senderName,
          avatar: message.senderAvatar,
        ),
      ),
    );
  }

  /// 根据已知的 mediaWidth/mediaHeight 预计算显示尺寸，避免图片加载后闪烁
  Widget _buildSizedMedia(double maxW, double maxH) {
    final mw = message.mediaWidth;
    final mh = message.mediaHeight;

    if (mw != null && mh != null && mw > 0 && mh > 0) {
      double w = mw.toDouble();
      double h = mh.toDouble();

      // 始终使用统一缩放因子，保证外层缩略图容器与图片真实比例一致，
      // 这样在 BoxFit.cover 下也不会出现明显裁边或留白。
      final shrinkScale = math.min(maxW / w, maxH / h);
      if (shrinkScale < 1) {
        w *= shrinkScale;
        h *= shrinkScale;
      }

      // 仅在图片整体都太小时才按比例整体放大，避免分别 clamp 宽高导致比例失真。
      if (w < 100 && h < 80) {
        final growScale = math.min(maxW / w, maxH / h);
        final desiredScale = math.max(100 / w, 80 / h);
        final finalScale = math.min(growScale, desiredScale);
        if (finalScale > 1) {
          w *= finalScale;
          h *= finalScale;
        }
      }

      return SizedBox(width: w, height: h, child: _buildMediaImage());
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxW,
        maxHeight: maxH,
        minWidth: 100,
        minHeight: 80,
      ),
      child: _buildMediaImage(),
    );
  }

  /// 构建媒体图片（处理本地文件和网络URL）
  Widget _buildMediaImage() {
    if (message.mediaUrl == null || message.mediaUrl!.isEmpty) {
      return Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.image, size: 40, color: Colors.grey[400]),
      );
    }

    final url = message.mediaUrl!;

    // 本地文件路径（以 / 开头但不是 /uploads）
    if (url.startsWith('/') && !url.startsWith('/uploads')) {
      final file = File(url);
      return Image.file(
        file,
        fit: BoxFit.fill,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
          );
        },
      );
    }

    // 网络URL（相对路径或完整URL）
    String imageUrl = url;
    if (url.startsWith('/uploads')) {
      imageUrl = '${ApiConfig.serverUrl}$url';
    } else if (!url.startsWith('http')) {
      imageUrl = '${ApiConfig.serverUrl}/$url';
    }

    // 性能优化：使用 LayoutBuilder 检测实际显示尺寸，动态调整缓存大小
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据实际约束计算缓存尺寸（最大不超过显示尺寸的 2 倍，最小 200）
        final maxWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? (constraints.maxWidth * 2).round().clamp(200, 560)
                : 280;
        final maxHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? (constraints.maxHeight * 2).round().clamp(200, 560)
                : 280;

        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.fill,
          // 性能优化：根据实际显示尺寸动态调整内存缓存大小
          memCacheWidth: maxWidth,
          memCacheHeight: maxHeight,
          // 磁盘缓存限制，避免占用过多存储空间
          maxWidthDiskCache: 800,
          maxHeightDiskCache: 800,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: const Duration(milliseconds: 150),
          placeholder: (context, url) => Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
          ),
        );
      },
    );
  }
}

/// 纯表情消息信息
class _EmojiInfo {
  final List<AnimatedEmoji> emojis;
  final int count;

  const _EmojiInfo({required this.emojis, required this.count});
}

/// 图片预览页面 - TG风格丝滑下滑关闭
class _ImagePreviewPage extends StatefulWidget {
  final String imageUrl;
  final bool isLocalFile;

  const _ImagePreviewPage({required this.imageUrl, required this.isLocalFile});

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  double _scale = 1.0;
  double _opacity = 1.0;
  bool _isDragging = false;

  late AnimationController _animController;
  late Animation<double> _resetAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      // 根据拖动距离计算缩放和透明度
      final progress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
      _scale = 1.0 - (progress * 0.3);
      _opacity = 1.0 - (progress * 0.5);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;

    // 如果拖动距离够大或速度够快，则关闭
    if (_dragOffset.abs() > 100 || velocity.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      // 回弹动画
      _resetAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
        CurvedAnimation(
          parent: _animController,
          curve: Curves.easeOutCubic,
        ),
      )..addListener(() {
          setState(() {
            _dragOffset = _resetAnimation.value;
            final progress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
            _scale = 1.0 - (progress * 0.3);
            _opacity = 1.0 - (progress * 0.5);
          });
        });
      _animController.forward(from: 0);
    }
    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(_opacity * 0.9),
      body: Stack(
        children: [
          // 背景点击区域
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 图片 - 支持下滑关闭
          Center(
            child: GestureDetector(
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Transform.scale(
                  scale: _scale,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: widget.isLocalFile
                        ? Image.file(
                            File(widget.imageUrl),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.broken_image,
                                size: 100,
                                color: Colors.white,
                              );
                            },
                          )
                        : CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              return const Icon(
                                Icons.broken_image,
                                size: 100,
                                color: Colors.white,
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
          // 顶部操作栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _isDragging ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 关闭按钮
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      // 下载按钮
                      IconButton(
                        icon: const Icon(
                          Icons.download,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => _saveImage(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage(BuildContext context) async {
    try {
      // 显示保存中提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('正在保存...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      String savePath;

      if (widget.isLocalFile) {
        // 本地文件直接保存
        savePath = widget.imageUrl;
      } else {
        // 网络图片先下载到临时目录
        final tempDir = await getTemporaryDirectory();
        final fileName = 'RanChat_${DateTime.now().millisecondsSinceEpoch}.jpg';
        savePath = '${tempDir.path}/$fileName';

        await Dio().download(widget.imageUrl, savePath);
      }

      // 使用 gal 保存到相册
      await Gal.putImage(savePath);

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('已保存到相册'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('保存失败: $e')),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// 文件气泡组件 - 支持下载动画
class _FileBubbleWidget extends StatefulWidget {
  final MessageItem message;
  final Color bubbleColor;
  final Color textColor;
  final Color timeColor;
  final bool isOutgoing;
  final BorderRadius bubbleRadius;
  final Widget Function() buildStatusIcon;

  const _FileBubbleWidget({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.timeColor,
    required this.isOutgoing,
    required this.bubbleRadius,
    required this.buildStatusIcon,
  });

  @override
  State<_FileBubbleWidget> createState() => _FileBubbleWidgetState();
}

class _FileBubbleWidgetState extends State<_FileBubbleWidget>
    with SingleTickerProviderStateMixin {
  // 下载状态: 0=未下载, 1=下载中, 2=已下载
  int _downloadState = 0;
  double _progress = 0.0;
  String? _localPath;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _checkIfDownloaded();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkIfDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = widget.message.fileName ?? '';
    final filePath = '${dir.path}/$fileName';
    if (await File(filePath).exists()) {
      setState(() {
        _downloadState = 2;
        _localPath = filePath;
      });
    }
  }

  (IconData, Color) _getFileIconAndColor(String ext) {
    switch (ext) {
      case 'pdf':
        return (Icons.picture_as_pdf_rounded, const Color(0xFFE53935));
      case 'doc':
      case 'docx':
        return (Icons.description_rounded, const Color(0xFF2196F3));
      case 'xls':
      case 'xlsx':
        return (Icons.table_chart_rounded, const Color(0xFF4CAF50));
      case 'ppt':
      case 'pptx':
        return (Icons.slideshow_rounded, const Color(0xFFFF9800));
      case 'zip':
      case 'rar':
      case '7z':
        return (Icons.folder_zip_rounded, const Color(0xFF9C27B0));
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
        return (Icons.audio_file_rounded, const Color(0xFFE91E63));
      case 'mp4':
      case 'mov':
      case 'avi':
        return (Icons.video_file_rounded, const Color(0xFF00BCD4));
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return (Icons.image_rounded, const Color(0xFF8BC34A));
      case 'txt':
        return (Icons.text_snippet_rounded, const Color(0xFF607D8B));
      case 'apk':
        return (Icons.android_rounded, const Color(0xFF3DDC84));
      default:
        return (Icons.insert_drive_file_rounded, AppColors.primary);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _downloadFile() async {
    if (_downloadState == 1) return; // 正在下载中

    final url = widget.message.mediaUrl;
    if (url == null) return;

    String fileUrl = url;
    if (url.startsWith('/uploads')) {
      fileUrl = '${ApiConfig.serverUrl}$url';
    } else if (!url.startsWith('http')) {
      fileUrl = '${ApiConfig.serverUrl}/$url';
    }

    setState(() {
      _downloadState = 1;
      _progress = 0.0;
    });
    _pulseController.repeat(reverse: true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = widget.message.fileName ??
          'file_${DateTime.now().millisecondsSinceEpoch}';
      final savePath = '${dir.path}/$fileName';

      await Dio().download(
        fileUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      _pulseController.stop();
      if (mounted) {
        setState(() {
          _downloadState = 2;
          _localPath = savePath;
        });
      }
    } catch (e) {
      _pulseController.stop();
      if (mounted) {
        setState(() {
          _downloadState = 0;
          _progress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openFile() async {
    if (_localPath == null) return;

    final ext =
        (widget.message.fileName ?? '').split('.').lastOrNull?.toLowerCase() ??
            '';

    // 图片文件 - 打开预览
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (ctx, animation, secondaryAnimation) {
            return _LocalImagePreviewPage(
              imagePath: _localPath!,
              fileName: widget.message.fileName ?? 'image',
            );
          },
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      return;
    }

    // 其他文件 - 尝试使用系统应用打开
    try {
      final file = File(_localPath!);
      if (await file.exists()) {
        // 尝试用系统应用打开
        final uri = Uri.file(_localPath!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          // 如果无法打开，提供分享选项
          if (context.mounted) {
            _showFileOptions();
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFileOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Material(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('分享文件'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_localPath != null) {
                      Share.shareXFiles([XFile(_localPath!)]);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('文件位置'),
                  subtitle: Text(
                    _localPath ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: _localPath ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('路径已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext =
        (widget.message.fileName ?? '').split('.').lastOrNull?.toLowerCase() ??
            '';
    final (IconData icon, Color color) = _getFileIconAndColor(ext);

    return GestureDetector(
      onTap: _downloadState == 2 ? _openFile : _downloadFile,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: widget.bubbleColor,
          borderRadius: widget.bubbleRadius,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 文件图标/下载进度/完成图标
            _buildFileIcon(icon, color),
            const SizedBox(width: 12),

            // 文件信息
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.fileName ?? '文件',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: widget.textColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 下载中显示进度百分比
                      if (_downloadState == 1)
                        Text(
                          '${(_progress * 100).toInt()}%  ',
                          style: AppTextStyles.caption.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        _formatFileSize(widget.message.mediaSize ?? 0),
                        style: AppTextStyles.caption.copyWith(
                          color: widget.textColor.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm').format(widget.message.createdAt),
                        style: AppTextStyles.timestamp.copyWith(
                          color: widget.timeColor,
                        ),
                      ),
                      if (widget.isOutgoing) ...[
                        const SizedBox(width: 3),
                        widget.buildStatusIcon(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileIcon(IconData fileIcon, Color fileColor) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景圆角方块
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _downloadState == 1 ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: fileColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),

          // 下载进度圆环
          if (_downloadState == 1)
            Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 3,
                    backgroundColor: fileColor.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(fileColor),
                  ),
                ),
              ),
            ),

          // 文件类型图标 - 始终显示
          Positioned.fill(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _downloadState == 1
                    ? Icon(
                        Icons.downloading_rounded,
                        key: const ValueKey('downloading'),
                        color: fileColor,
                        size: 20,
                      )
                    : Icon(
                        fileIcon,
                        key: const ValueKey('file'),
                        color: fileColor,
                        size: 24,
                      ),
              ),
            ),
          ),

          // 右下角已下载标记
          if (_downloadState == 2)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// 语音气泡组件 - 支持播放
class _VoiceBubbleWidget extends StatefulWidget {
  final MessageItem message;
  final Color bubbleColor;
  final Color textColor;
  final Color timeColor;
  final bool isOutgoing;
  final BorderRadius bubbleRadius;
  final Widget Function() buildStatusIcon;

  const _VoiceBubbleWidget({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.timeColor,
    required this.isOutgoing,
    required this.bubbleRadius,
    required this.buildStatusIcon,
  });

  @override
  State<_VoiceBubbleWidget> createState() => _VoiceBubbleWidgetState();
}

class _VoiceBubbleWidgetState extends State<_VoiceBubbleWidget>
    with SingleTickerProviderStateMixin {
  static AudioPlayer? _currentPlayer;
  static String? _currentPlayingId;

  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  late AnimationController _waveController;
  // 存储订阅以避免泄漏
  final List<dynamic> _playerSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 初始化时长
    _duration = Duration(milliseconds: widget.message.mediaDuration ?? 0);
  }

  @override
  void dispose() {
    for (final sub in _playerSubscriptions) {
      sub.cancel();
    }
    _playerSubscriptions.clear();
    _positionNotifier.dispose();
    _waveController.dispose();
    if (_currentPlayingId == widget.message.id) {
      _player?.stop();
      _player?.dispose();
      _currentPlayer = null;
      _currentPlayingId = null;
    }
    super.dispose();
  }

  String _buildVoiceUrl() {
    final url = widget.message.mediaUrl ?? '';
    if (url.startsWith('http')) {
      return url;
    } else if (url.startsWith('/')) {
      return '${ApiConfig.serverUrl}$url';
    } else {
      return '${ApiConfig.serverUrl}/$url';
    }
  }

  Future<void> _togglePlay() async {
    GlobalHaptics.selection();

    // 如果其他语音正在播放，先停止它
    if (_currentPlayingId != null && _currentPlayingId != widget.message.id) {
      await _currentPlayer?.stop();
      _currentPlayer?.dispose();
      _currentPlayer = null;
      _currentPlayingId = null;
    }

    if (_isPlaying) {
      await _player?.pause();
      _waveController.stop();
      setState(() => _isPlaying = false);
    } else {
      // 创建新的播放器
      _player ??= AudioPlayer();
      _currentPlayer = _player;
      _currentPlayingId = widget.message.id;

      // 取消旧的订阅，避免重复监听导致泄漏
      for (final sub in _playerSubscriptions) {
        sub.cancel();
      }
      _playerSubscriptions.clear();

      _playerSubscriptions.add(
        _player!.onPlayerStateChanged.listen((state) {
          if (mounted) {
            final playing = state == PlayerState.playing;
            setState(() => _isPlaying = playing);
            if (playing) {
              _waveController.repeat();
            } else {
              _waveController.stop();
            }
          }
        }),
      );

      _playerSubscriptions.add(
        _player!.onPositionChanged.listen((pos) {
          if (mounted) {
            _positionNotifier.value = pos;
          }
        }),
      );

      _playerSubscriptions.add(
        _player!.onPlayerComplete.listen((_) {
          if (mounted) {
            _positionNotifier.value = Duration.zero;
            setState(() {
              _isPlaying = false;
            });
            _waveController.stop();
            _waveController.reset();
          }
        }),
      );

      // 开始播放
      final voiceUrl = _buildVoiceUrl();
      try {
        await _player!.play(UrlSource(voiceUrl));
        _waveController.repeat();
        setState(() => _isPlaying = true);
      } catch (e) {
        if (kDebugMode) debugPrint('[VoiceBubble] Play error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final waveColor =
        widget.isOutgoing ? const Color(0xFF5D9B5D) : AppColors.primary;

    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        constraints: const BoxConstraints(minWidth: 160),
        decoration: BoxDecoration(
          color: widget.bubbleColor,
          borderRadius: widget.bubbleRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放/暂停按钮
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _isPlaying ? waveColor : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // 波形图 + 时长（使用 ValueListenableBuilder 精准更新）
            ValueListenableBuilder<Duration>(
              valueListenable: _positionNotifier,
              builder: (context, position, child) {
                final progress = _duration.inMilliseconds > 0
                    ? position.inMilliseconds / _duration.inMilliseconds
                    : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 动态波形图
                    SizedBox(
                      width: 100,
                      height: 24,
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _VoiceWavePainter(
                              progress: progress,
                              isPlaying: _isPlaying,
                              animValue: _waveController.value,
                              activeColor: waveColor,
                              inactiveColor: waveColor.withValues(alpha: 0.3),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 显示当前进度或总时长
                        Text(
                          _isPlaying
                              ? _formatDuration(position)
                              : _formatDuration(_duration),
                          style: AppTextStyles.caption.copyWith(
                            color: widget.textColor.withValues(alpha: 0.7),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('HH:mm').format(widget.message.createdAt),
                          style: AppTextStyles.timestamp.copyWith(
                            color: widget.timeColor,
                          ),
                        ),
                        if (widget.isOutgoing) ...[
                          const SizedBox(width: 3),
                          widget.buildStatusIcon(),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 语音波形绘制器
class _VoiceWavePainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final double animValue;
  final Color activeColor;
  final Color inactiveColor;

  _VoiceWavePainter({
    required this.progress,
    required this.isPlaying,
    required this.animValue,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // 固定种子保证波形一致
    const barCount = 20;
    const barWidth = 3.0;
    final spacing = (size.width - barCount * barWidth) / (barCount - 1);

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final normalizedProgress = progress * barCount;
      final isActive = i < normalizedProgress;

      // 基础高度
      double baseHeight = size.height * (0.3 + random.nextDouble() * 0.7);

      // 播放时添加动画效果
      if (isPlaying && isActive) {
        final wave = math.sin((animValue * 2 * math.pi) + (i * 0.3));
        baseHeight = baseHeight * (0.7 + 0.3 * wave);
      }

      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      final y1 = (size.height - baseHeight) / 2;
      final y2 = y1 + baseHeight;

      canvas.drawLine(
        Offset(x + barWidth / 2, y1),
        Offset(x + barWidth / 2, y2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.animValue != animValue;
  }
}

/// 视频气泡组件 - Telegram 风格
class _VideoBubbleWidget extends StatefulWidget {
  final MessageItem message;
  final bool isOutgoing;
  final BorderRadius Function(bool) getBubbleRadius;
  final Widget Function(Color) buildStatusIcon;

  const _VideoBubbleWidget({
    required this.message,
    required this.isOutgoing,
    required this.getBubbleRadius,
    required this.buildStatusIcon,
  });

  @override
  State<_VideoBubbleWidget> createState() => _VideoBubbleWidgetState();
}

class _VideoBubbleWidgetState extends State<_VideoBubbleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null || milliseconds == 0) return '0:00';
    final seconds = (milliseconds / 1000).round();
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes == 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String? _getThumbnailUrl() {
    final thumbnail = widget.message.thumbnail;
    if (thumbnail == null || thumbnail.isEmpty) return null;

    // 如果已经是完整URL
    if (thumbnail.startsWith('http')) return thumbnail;

    // 如果是服务器相对路径 (/uploads/...)
    if (thumbnail.startsWith('/uploads/')) {
      return ApiConfig.getMediaUrl(thumbnail);
    }

    // 如果是本地文件路径 (iOS: /var/..., /Users/..., Android: /data/..., /storage/...)
    if (thumbnail.startsWith('/var/') ||
        thumbnail.startsWith('/Users/') ||
        thumbnail.startsWith('/data/') ||
        thumbnail.startsWith('/storage/') ||
        thumbnail.contains('/Library/') ||
        thumbnail.contains('/Caches/') ||
        thumbnail.contains('/tmp/')) {
      return thumbnail;
    }

    // 其他情况拼接服务器地址
    return ApiConfig.getMediaUrl(thumbnail);
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _scaleController.reverse();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _scaleController.forward();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _scaleController.forward();
  }

  void _playVideo() {
    final videoUrl = widget.message.mediaUrl;
    if (videoUrl == null || videoUrl.isEmpty) return;

    // 判断是本地文件还是网络 URL
    final isLocal =
        videoUrl.startsWith('/') && !videoUrl.startsWith('/uploads');
    final fullUrl = isLocal ? videoUrl : ApiConfig.getMediaUrl(videoUrl);
    final thumbnailUrl = _getThumbnailUrl();

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _VideoPlayerPage(
            videoUrl: fullUrl,
            isLocal: isLocal,
            thumbnailUrl: thumbnailUrl,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = _getThumbnailUrl();
    final duration = widget.message.mediaDuration;
    final fileSize = widget.message.mediaSize;

    // 计算宽高比
    double aspectRatio = 16 / 9;
    if (widget.message.mediaWidth != null &&
        widget.message.mediaHeight != null &&
        widget.message.mediaHeight! > 0) {
      aspectRatio = widget.message.mediaWidth! / widget.message.mediaHeight!;
    }

    // 限制宽高比范围
    aspectRatio = aspectRatio.clamp(0.5, 2.0);

    // 预计算视频显示尺寸
    double displayW = 280;
    double displayH = displayW / aspectRatio;
    if (widget.message.mediaWidth != null &&
        widget.message.mediaHeight != null &&
        widget.message.mediaWidth! > 0 &&
        widget.message.mediaHeight! > 0) {
      displayW = widget.message.mediaWidth!.toDouble();
      displayH = widget.message.mediaHeight!.toDouble();
      if (displayW > 280) {
        displayH = displayH * 280 / displayW;
        displayW = 280;
      }
      if (displayH > 400) {
        displayW = displayW * 400 / displayH;
        displayH = 400;
      }
      if (displayW < 180) {
        displayH = displayH * 180 / displayW;
        displayW = 180;
      }
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _playVideo,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) =>
            Transform.scale(scale: _scaleController.value, child: child),
        child: SizedBox(
          width: displayW.clamp(180, 280),
          height: displayH.clamp(100, 400),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: widget.getBubbleRadius(widget.isOutgoing),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: widget.getBubbleRadius(widget.isOutgoing),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(thumbnailUrl),
                    _buildGradientOverlay(),
                    if (widget.message.status == MessageStatus.sending &&
                        widget.message.uploadProgress != null &&
                        widget.message.uploadProgress! < 1.0)
                      _buildUploadProgress(widget.message.uploadProgress!)
                    else
                      _buildPlayButton(),
                    if (duration != null && duration > 0)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: _buildInfoChip(
                          icon: Icons.play_arrow_rounded,
                          text: _formatDuration(duration),
                        ),
                      ),
                    if (fileSize != null && fileSize > 0)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _buildInfoChip(text: _formatFileSize(fileSize)),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat(
                              'HH:mm',
                            ).format(widget.message.createdAt),
                            style: AppTextStyles.timestamp.copyWith(
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          if (widget.isOutgoing) ...[
                            const SizedBox(width: 3),
                            widget.buildStatusIcon(Colors.white),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建视频缩略图
  /// 性能优化：使用 LayoutBuilder 动态调整缓存尺寸
  Widget _buildThumbnail(String? thumbnailUrl) {
    if (thumbnailUrl == null) {
      return _buildPlaceholder();
    }

    // 本地文件路径 (不是 http:// 开头的)
    if (!thumbnailUrl.startsWith('http')) {
      return Image.file(
        File(thumbnailUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }

    // 网络图片 - 使用 LayoutBuilder 优化缓存
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据实际约束计算缓存尺寸
        final maxWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? (constraints.maxWidth * 2).round().clamp(200, 560)
                : 280;
        final maxHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? (constraints.maxHeight * 2).round().clamp(200, 560)
                : 280;

        return CachedNetworkImage(
          imageUrl: thumbnailUrl,
          fit: BoxFit.cover,
          // 性能优化：根据实际显示尺寸动态调整内存缓存大小
          memCacheWidth: maxWidth,
          memCacheHeight: maxHeight,
          // 磁盘缓存限制
          maxWidthDiskCache: 800,
          maxHeightDiskCache: 800,
          fadeInDuration: const Duration(milliseconds: 200),
          fadeOutDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => _buildPlaceholder(),
          errorWidget: (_, __, ___) => _buildPlaceholder(),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              '视频',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.4),
            ],
            stops: const [0.0, 0.2, 0.7, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadProgress(double progress) {
    final pct = (progress * 100).toInt();
    return Center(
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.3),
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _isPressed ? 54 : 60,
        height: _isPressed ? 54 : 60,
        decoration: BoxDecoration(
          color: _isPressed
              ? Colors.white.withOpacity(0.9)
              : Colors.white.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.black.withOpacity(0.8),
          size: _isPressed ? 32 : 36,
        ),
      ),
    );
  }

  Widget _buildInfoChip({IconData? icon, required String text}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 6 : 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram 风格视频播放页面
class _VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final bool isLocal;
  final String? thumbnailUrl;

  const _VideoPlayerPage({
    required this.videoUrl,
    this.isLocal = false,
    this.thumbnailUrl,
  });

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isBuffering = false;
  bool _hasError = false;
  double _currentPosition = 0;
  double _totalDuration = 0;
  bool _isDragging = false;
  bool _isSaving = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    // 隐藏状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initializeVideo() async {
    _controller = widget.isLocal
        ? VideoPlayerController.file(File(widget.videoUrl))
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));

    _controller.addListener(() {
      if (!mounted) return;

      setState(() {
        _isPlaying = _controller.value.isPlaying;
        _isBuffering = _controller.value.isBuffering;
        if (!_isDragging) {
          _currentPosition =
              _controller.value.position.inMilliseconds.toDouble();
        }
        _totalDuration = _controller.value.duration.inMilliseconds.toDouble();
      });
    });

    try {
      await _controller.initialize().timeout(const Duration(seconds: 30));
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _totalDuration = _controller.value.duration.inMilliseconds.toDouble();
        });
        await _controller.seekTo(Duration.zero);
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          _controller.play();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('视频初始化失败: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // 恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _saveVideo() async {
    if (_isSaving || _isSaved) return;

    setState(() => _isSaving = true);

    try {
      // 请求相册权限
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (mounted) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('需要相册权限才能保存视频'),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }

      // 下载视频到临时目录
      final tempDir = await getTemporaryDirectory();
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savePath = '${tempDir.path}/$fileName';

      final dio = Dio();
      await dio.download(widget.videoUrl, savePath);

      // 保存到相册
      await Gal.putVideo(savePath);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isSaved = true;
        });

        // 显示成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('视频已保存到相册'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 清理临时文件
      try {
        await File(savePath).delete();
      } catch (_) {}
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text('保存失败，请重启应用后重试'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          // 左滑返回
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 300) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面/视频
                Center(
                  child: _isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : _buildThumbnailCover(),
                ),

                if (_hasError)
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _hasError = false);
                        _initializeVideo();
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '加载失败，点击重试',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!_isInitialized || _isBuffering)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),

                // 控制层
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: const [0.0, 0.2, 0.8, 1.0],
                      ),
                    ),
                  ),
                ),

                // 顶部栏
                if (_showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_ios_rounded),
                              color: Colors.white,
                              iconSize: 24,
                            ),
                            const Spacer(),
                            // 保存按钮
                            IconButton(
                              onPressed: _isSaving ? null : _saveVideo,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _isSaved
                                          ? Icons.check_circle_rounded
                                          : Icons.download_rounded,
                                      color: _isSaved
                                          ? Colors.green
                                          : Colors.white,
                                    ),
                              iconSize: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 中央播放/暂停按钮
                if (_showControls && _isInitialized)
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ),

                // 底部控制栏
                if (_showControls && _isInitialized)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 进度条
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white.withOpacity(
                                  0.3,
                                ),
                                thumbColor: Colors.white,
                                overlayColor: Colors.white.withOpacity(0.2),
                              ),
                              child: Slider(
                                value: _currentPosition.clamp(
                                  0,
                                  _totalDuration,
                                ),
                                max: _totalDuration > 0 ? _totalDuration : 1,
                                onChangeStart: (_) {
                                  setState(() => _isDragging = true);
                                },
                                onChanged: (value) {
                                  setState(() => _currentPosition = value);
                                },
                                onChangeEnd: (value) {
                                  setState(() => _isDragging = false);
                                  _controller.seekTo(
                                    Duration(milliseconds: value.toInt()),
                                  );
                                },
                              ),
                            ),

                            // 时间显示
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(
                                      Duration(
                                        milliseconds: _currentPosition.toInt(),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(
                                      Duration(
                                        milliseconds: _totalDuration.toInt(),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建封面缩略图
  Widget _buildThumbnailCover() {
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      // 本地文件
      if (!widget.thumbnailUrl!.startsWith('http')) {
        return Image.file(
          File(widget.thumbnailUrl!),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      }
      // 网络图片
      return CachedNetworkImage(
        imageUrl: widget.thumbnailUrl!,
        fit: BoxFit.contain,
        placeholder: (_, __) => _buildPlaceholder(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  /// 封面占位 - 显示加载动画
  Widget _buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放按钮样式的加载指示器
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在加载视频...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地图片预览页面
class _LocalImagePreviewPage extends StatefulWidget {
  final String imagePath;
  final String fileName;

  const _LocalImagePreviewPage({
    required this.imagePath,
    required this.fileName,
  });

  @override
  State<_LocalImagePreviewPage> createState() => _LocalImagePreviewPageState();
}

class _LocalImagePreviewPageState extends State<_LocalImagePreviewPage> {
  double _dragOffset = 0.0;
  double _scale = 1.0;

  void _onVerticalDragStart(DragStartDetails details) {
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      // 根据拖拽距离调整缩放
      _scale = (1.0 - (_dragOffset.abs() / 500)).clamp(0.5, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100 ||
        details.velocity.pixelsPerSecond.dy.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0.0;
        _scale = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景点击区域
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 图片 - 支持下滑关闭
          Center(
            child: GestureDetector(
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Transform.scale(
                  scale: _scale,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 64,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '无法加载图片',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 顶部操作栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        widget.fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Share.shareXFiles([XFile(widget.imagePath)]);
                      },
                      icon: const Icon(
                        Icons.share_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 红包详情 Sheet
/// 红包气泡 — 自动拉取最新状态
/// 全局钱包气泡刷新通知器
/// 当收到系统消息（红包被领取、转账被接收等）时触发，
/// 所有可见的红包/转账气泡会重新拉取最新状态
/// 红包/转账状态独立缓存
/// 内存 Map 提供本次会话内秒级命中，SharedPreferences 提供跨会话持久化
/// 不依赖消息 content（服务器消息 content 永远是初始状态，会覆盖 Isar）
class WalletStatusCache {
  static final WalletStatusCache _instance = WalletStatusCache._();
  static WalletStatusCache get instance => _instance;
  WalletStatusCache._();

  // 内存缓存
  final Map<String, String> _rpCache = {}; // red_packet_id -> JSON
  final Map<String, String> _tfCache = {}; // transfer_id -> JSON

  /// 缓存红包状态
  void cacheRedPacket(RedPacketInfo data) {
    final json = jsonEncode(data.toJson());
    _rpCache[data.id] = json;
    // 异步写 SharedPreferences（不阻塞）
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('rp_status_${data.id}', json);
    });
  }

  /// 获取缓存的红包状态（内存优先，再查 SharedPreferences）
  RedPacketInfo? getCachedRedPacket(String rpId) {
    final mem = _rpCache[rpId];
    if (mem != null) {
      try {
        return RedPacketInfo.fromJson(jsonDecode(mem));
      } catch (_) {}
    }
    return null;
  }

  /// 异步获取（含 SharedPreferences）
  Future<RedPacketInfo?> getCachedRedPacketAsync(String rpId) async {
    // 先查内存
    final cached = getCachedRedPacket(rpId);
    if (cached != null) return cached;
    // 再查磁盘
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('rp_status_$rpId');
      if (json != null) {
        final data = RedPacketInfo.fromJson(jsonDecode(json));
        _rpCache[rpId] = json; // 回填内存
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// 缓存转账状态
  void cacheTransfer(TransferInfo data) {
    final json = jsonEncode(data.toJson());
    _tfCache[data.id] = json;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('tf_status_${data.id}', json);
    });
  }

  /// 获取缓存的转账状态
  TransferInfo? getCachedTransfer(String tfId) {
    final mem = _tfCache[tfId];
    if (mem != null) {
      try {
        return TransferInfo.fromJson(jsonDecode(mem));
      } catch (_) {}
    }
    return null;
  }

  Future<TransferInfo?> getCachedTransferAsync(String tfId) async {
    final cached = getCachedTransfer(tfId);
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('tf_status_$tfId');
      if (json != null) {
        final data = TransferInfo.fromJson(jsonDecode(json));
        _tfCache[tfId] = json;
        return data;
      }
    } catch (_) {}
    return null;
  }
}

class WalletBubbleRefreshNotifier extends ChangeNotifier {
  static final WalletBubbleRefreshNotifier _instance =
      WalletBubbleRefreshNotifier._();
  static WalletBubbleRefreshNotifier get instance => _instance;
  WalletBubbleRefreshNotifier._();

  /// 触发所有可见气泡刷新
  void refresh() {
    notifyListeners();
  }
}

class _LiveRedPacketBubble extends StatefulWidget {
  final String messageId;
  final RedPacketInfo redPacket;
  final bool isOutgoing;
  final String? senderAvatar;
  final bool isGroupChat;

  const _LiveRedPacketBubble({
    required this.messageId,
    required this.redPacket,
    required this.isOutgoing,
    this.senderAvatar,
    this.isGroupChat = false,
  });

  @override
  State<_LiveRedPacketBubble> createState() => _LiveRedPacketBubbleState();
}

class _LiveRedPacketBubbleState extends State<_LiveRedPacketBubble> {
  RedPacketInfo? _liveData;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _loadCachedThenFetch();
    WalletBubbleRefreshNotifier.instance.addListener(_onGlobalRefresh);
  }

  @override
  void dispose() {
    WalletBubbleRefreshNotifier.instance.removeListener(_onGlobalRefresh);
    super.dispose();
  }

  /// 先从缓存加载（秒级命中），再决定是否需要网络请求
  Future<void> _loadCachedThenFetch() async {
    // 1. 同步读内存缓存
    final memCached = WalletStatusCache.instance.getCachedRedPacket(
      widget.redPacket.id,
    );
    if (memCached != null && mounted) {
      setState(() => _liveData = memCached);
      // 已终态（finished/expired），不再发 API
      if (memCached.status != RedPacketStatus.active) return;
    }
    // 2. 异步读 SharedPreferences
    if (_liveData == null) {
      final diskCached = await WalletStatusCache.instance
          .getCachedRedPacketAsync(widget.redPacket.id);
      if (diskCached != null && mounted) {
        setState(() => _liveData = diskCached);
        if (diskCached.status != RedPacketStatus.active) return;
      }
    }
    // 3. 仍是 active（或无缓存），延迟拉取最新状态
    final current = _liveData ?? widget.redPacket;
    if (current.status == RedPacketStatus.active) {
      final delay = 200 + (widget.redPacket.id.hashCode % 800).abs();
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _fetchStatus();
      });
    }
  }

  void _onGlobalRefresh() {
    final current = _liveData ?? widget.redPacket;
    if (current.status == RedPacketStatus.active) {
      _fetchStatus();
    }
  }

  Future<void> _fetchStatus() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final apiClient = ApiClient();
      final token = await TokenStorage.getToken();
      if (token != null) apiClient.setToken(token);
      final svc = WalletService(apiClient);
      final resp = await svc.getRedPacket(widget.redPacket.id);
      if (resp.isSuccess && resp.data != null && mounted) {
        final newData = resp.data!;
        setState(() => _liveData = newData);
        // 持久化到独立缓存（不写 Isar 消息 content，因为会被服务器数据覆盖）
        WalletStatusCache.instance.cacheRedPacket(newData);
      }
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  void _showDetail() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedPacketDetailSheet(
        redPacket: _liveData ?? widget.redPacket,
        isOutgoing: widget.isOutgoing,
        senderAvatar: widget.senderAvatar,
        isGroupChat: widget.isGroupChat,
      ),
    );
    _fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    final rp = _liveData ?? widget.redPacket;
    return RedPacketBubble(
      redPacket: rp,
      isOutgoing: widget.isOutgoing,
      onTap: _showDetail,
    );
  }
}

/// 转账气泡 — 自动拉取最新状态 + 实时刷新 + 本地持久化
class _LiveTransferBubble extends StatefulWidget {
  final String messageId;
  final TransferInfo transfer;
  final bool isOutgoing;
  final String? senderAvatar;

  const _LiveTransferBubble({
    required this.messageId,
    required this.transfer,
    required this.isOutgoing,
    this.senderAvatar,
  });

  @override
  State<_LiveTransferBubble> createState() => _LiveTransferBubbleState();
}

class _LiveTransferBubbleState extends State<_LiveTransferBubble> {
  TransferInfo? _liveData;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _loadCachedThenFetch();
    WalletBubbleRefreshNotifier.instance.addListener(_onGlobalRefresh);
  }

  @override
  void dispose() {
    WalletBubbleRefreshNotifier.instance.removeListener(_onGlobalRefresh);
    super.dispose();
  }

  Future<void> _loadCachedThenFetch() async {
    final memCached = WalletStatusCache.instance.getCachedTransfer(
      widget.transfer.id,
    );
    if (memCached != null && mounted) {
      setState(() => _liveData = memCached);
      if (memCached.status != TransferStatus.pending) return;
    }
    if (_liveData == null) {
      final diskCached = await WalletStatusCache.instance
          .getCachedTransferAsync(widget.transfer.id);
      if (diskCached != null && mounted) {
        setState(() => _liveData = diskCached);
        if (diskCached.status != TransferStatus.pending) return;
      }
    }
    final current = _liveData ?? widget.transfer;
    if (current.status == TransferStatus.pending) {
      final delay = 200 + (widget.transfer.id.hashCode % 800).abs();
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _fetchStatus();
      });
    }
  }

  void _onGlobalRefresh() {
    final current = _liveData ?? widget.transfer;
    if (current.status == TransferStatus.pending) {
      _fetchStatus();
    }
  }

  Future<void> _fetchStatus() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final apiClient = ApiClient();
      final token = await TokenStorage.getToken();
      if (token != null) apiClient.setToken(token);
      final svc = WalletService(apiClient);
      final resp = await svc.getTransfer(widget.transfer.id);
      if (resp.isSuccess && resp.data != null && mounted) {
        final newData = resp.data!;
        setState(() => _liveData = newData);
        WalletStatusCache.instance.cacheTransfer(newData);
      }
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  void _showDetail() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransferDetailSheet(
        transfer: _liveData ?? widget.transfer,
        isOutgoing: widget.isOutgoing,
        senderAvatar: widget.senderAvatar,
      ),
    );
    _fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    final tf = _liveData ?? widget.transfer;
    return TransferBubble(
      transfer: tf,
      isOutgoing: widget.isOutgoing,
      onTap: _showDetail,
    );
  }
}

class _RedPacketDetailSheet extends StatefulWidget {
  final RedPacketInfo redPacket;
  final bool isOutgoing;
  final String? senderAvatar;
  final bool isGroupChat;

  const _RedPacketDetailSheet({
    required this.redPacket,
    required this.isOutgoing,
    this.senderAvatar,
    this.isGroupChat = false,
  });

  @override
  State<_RedPacketDetailSheet> createState() => _RedPacketDetailSheetState();
}

class _RedPacketDetailSheetState extends State<_RedPacketDetailSheet> {
  bool _isClaimed = false;
  bool _isClaiming = false;
  double _claimedAmount = 0;
  String? _errorMsg;
  RedPacketInfo? _latestRedPacket;

  @override
  void initState() {
    super.initState();
    // 先从服务器获取最新红包状态
    _fetchRedPacketDetail();
  }

  /// 创建已认证的 ApiClient
  Future<ApiClient> _createApiClient() async {
    final apiClient = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null) {
      apiClient.setToken(token);
    }
    return apiClient;
  }

  /// 从服务器获取红包最新状态
  Future<void> _fetchRedPacketDetail() async {
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.getRedPacket(widget.redPacket.id);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _latestRedPacket = response.data;
          _isClaimed = response.data!.isClaimed;
          _claimedAmount = response.data!.claimedAmount ?? 0;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RedPacket] Fetch detail error: $e');
    }
  }

  Future<void> _claimRedPacket() async {
    if (_isClaiming || _isClaimed) return;

    setState(() {
      _isClaiming = true;
      _errorMsg = null;
    });

    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.claimRedPacket(widget.redPacket.id);

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final amount = (response.data!['amount'] as num?)?.toDouble() ?? 0;
        setState(() {
          _isClaimed = true;
          _isClaiming = false;
          _claimedAmount = amount;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() {
          _isClaiming = false;
          _errorMsg = response.message ?? '领取失败';
        });
        // 如果是已领取或已领完，刷新状态
        if (response.message?.contains('已领取') == true ||
            response.message?.contains('已被领完') == true) {
          _fetchRedPacketDetail();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RedPacket] Claim error: $e');
      if (mounted) {
        setState(() {
          _isClaiming = false;
          _errorMsg = '领取失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF6B6B), Color(0xFFEE5A5A)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 顶部拖动条
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 关闭按钮
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 发送者头像
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 34,
              backgroundColor: Colors.white.withOpacity(0.2),
              backgroundImage: (widget.senderAvatar?.isNotEmpty == true ||
                      widget.redPacket.senderAvatar?.isNotEmpty == true)
                  ? CachedNetworkImageProvider(
                      ApiConfig.getMediaUrl(
                        widget.senderAvatar ?? widget.redPacket.senderAvatar!,
                      ),
                    )
                  : null,
              child: (widget.senderAvatar?.isNotEmpty != true &&
                      widget.redPacket.senderAvatar?.isNotEmpty != true)
                  ? Text(
                      widget.redPacket.senderName.isNotEmpty
                          ? widget.redPacket.senderName[0]
                          : '我',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // 发送者名称
          Text(
            widget.isOutgoing
                ? (widget.isGroupChat ? '我发出的群红包' : '我发出的红包')
                : '${widget.redPacket.senderName.isNotEmpty ? widget.redPacket.senderName : "好友"}的红包',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 12),

          // 祝福语
          Text(
            widget.redPacket.message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
            ),
          ),

          const SizedBox(height: 40),

          // 已领取显示金额，未领取显示开按钮
          // 群聊红包发送者可以抢，私聊红包发送者只看"已发出"
          if (_isClaimed) ...[
            Text(
              '¥${_claimedAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已存入余额',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ] else if (widget.isOutgoing && !widget.isGroupChat) ...[
            Text(
              '¥${(_latestRedPacket ?? widget.redPacket).totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已发出',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ] else if ((_latestRedPacket ?? widget.redPacket).status ==
              RedPacketStatus.finished) ...[
            // 红包已领完
            Text(
              '红包已被领完',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ] else if ((_latestRedPacket ?? widget.redPacket).status ==
              RedPacketStatus.expired) ...[
            // 红包已过期
            Text(
              '红包已过期',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ] else ...[
            // 开红包按钮
            GestureDetector(
              onTap: _isClaiming ? null : _claimRedPacket,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD700),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: _isClaiming
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation(
                              Color(0xFFB8860B),
                            ),
                          ),
                        )
                      : const Text(
                          '開',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                ),
              ),
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMsg!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ],

          const Spacer(),

          // 底部信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '红包详情',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '红包金额',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                      Text(
                        '¥${(_latestRedPacket ?? widget.redPacket).totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '红包个数',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${(_latestRedPacket ?? widget.redPacket).totalCount}个',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  if ((_latestRedPacket ?? widget.redPacket).totalCount >
                      1) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '已领取',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                        Text(
                          '${(_latestRedPacket ?? widget.redPacket).totalCount - (_latestRedPacket ?? widget.redPacket).remainingCount}/${(_latestRedPacket ?? widget.redPacket).totalCount}个',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    if ((_latestRedPacket ?? widget.redPacket).type ==
                        RedPacketType.lucky) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '类型',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                          Text(
                            '拼手气红包',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 转账详情 Sheet — 微信风格
class _TransferDetailSheet extends StatefulWidget {
  final TransferInfo transfer;
  final bool isOutgoing;
  final String? senderAvatar;

  const _TransferDetailSheet({
    required this.transfer,
    required this.isOutgoing,
    this.senderAvatar,
  });

  @override
  State<_TransferDetailSheet> createState() => _TransferDetailSheetState();
}

class _TransferDetailSheetState extends State<_TransferDetailSheet> {
  bool _isAccepted = false;
  bool _isAccepting = false;
  bool _isRejected = false;
  String? _errorMsg;
  TransferInfo? _latestTransfer;

  @override
  void initState() {
    super.initState();
    _isAccepted = widget.transfer.status == TransferStatus.accepted;
    _isRejected = widget.transfer.status == TransferStatus.rejected;
    _fetchTransferDetail();
  }

  Future<ApiClient> _createApiClient() async {
    final apiClient = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null) apiClient.setToken(token);
    return apiClient;
  }

  Future<void> _fetchTransferDetail() async {
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.getTransfer(widget.transfer.id);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _latestTransfer = response.data;
          _isAccepted = response.data!.status == TransferStatus.accepted;
          _isRejected = response.data!.status == TransferStatus.rejected;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Transfer] Fetch detail error: $e');
    }
  }

  Future<void> _acceptTransfer() async {
    if (_isAccepting || _isAccepted) return;
    setState(() {
      _isAccepting = true;
      _errorMsg = null;
    });
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.acceptTransfer(widget.transfer.id);
      if (!mounted) return;
      if (response.isSuccess) {
        setState(() {
          _isAccepted = true;
          _isAccepting = false;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() {
          _isAccepting = false;
          _errorMsg = response.message ?? '收款失败';
        });
        if (response.message?.contains('已') == true) _fetchTransferDetail();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isAccepting = false;
          _errorMsg = '收款失败';
        });
    }
  }

  Future<void> _rejectTransfer() async {
    if (_isAccepting || _isAccepted || _isRejected) return;
    setState(() {
      _isAccepting = true;
      _errorMsg = null;
    });
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.rejectTransfer(widget.transfer.id);
      if (!mounted) return;
      if (response.isSuccess) {
        setState(() {
          _isRejected = true;
          _isAccepting = false;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() {
          _isAccepting = false;
          _errorMsg = response.message ?? '退还失败';
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isAccepting = false;
          _errorMsg = '退还失败';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final transfer = _latestTransfer ?? widget.transfer;
    final isPending = !_isAccepted &&
        !_isRejected &&
        transfer.status == TransferStatus.pending;
    final isExpired = transfer.status == TransferStatus.expired;

    const txOrange = Color(0xFFFFA940);
    const txGreen = Color(0xFF07C160);

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 顶部彩色头
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isAccepted
                    ? [txGreen, const Color(0xFF06AD56)]
                    : [txOrange, const Color(0xFFE69330)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // 拖拽条 + 关闭
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.7),
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 图标
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/stickers/zhuanzhang.png',
                      width: 36,
                      height: 36,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.currency_yuan_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 金额
                Text(
                  '¥${transfer.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                // 描述
                Text(
                  widget.isOutgoing
                      ? '转账给${transfer.receiverName.isNotEmpty ? transfer.receiverName : "好友"}'
                      : '来自${transfer.senderName.isNotEmpty ? transfer.senderName : "好友"}的转账',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          // 详情
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _row(
                    isDark,
                    '当前状态',
                    _isAccepted
                        ? '已收款'
                        : _isRejected
                            ? '已退还'
                            : isExpired
                                ? '已过期'
                                : '待收款',
                    color: _isAccepted
                        ? txGreen
                        : _isRejected
                            ? Colors.red
                            : isPending
                                ? txOrange
                                : Colors.grey,
                  ),
                  _div(isDark),
                  if (transfer.remark?.isNotEmpty == true) ...[
                    _row(isDark, '转账说明', transfer.remark!),
                    _div(isDark),
                  ],
                  _row(
                    isDark,
                    '转账时间',
                    DateFormat('yyyy-MM-dd HH:mm').format(transfer.createdAt),
                  ),
                  _div(isDark),
                  _row(
                    isDark,
                    '转账单号',
                    transfer.id.length > 16
                        ? '${transfer.id.substring(0, 16)}...'
                        : transfer.id,
                  ),
                  if (_errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  const Spacer(),
                  // 底部按钮
                  if (!widget.isOutgoing && isPending) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _isAccepting ? null : _rejectTransfer,
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    isDark ? Colors.white60 : Colors.grey[700],
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.grey[300]!,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: const Text(
                                '退还',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isAccepting ? null : _acceptTransfer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: txGreen,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: _isAccepting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      '确认收款',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_isAccepted) ...[
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: txGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: txGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '已收款 ¥${transfer.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: txGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(bool dark, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: dark ? Colors.white54 : Colors.grey[600],
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color ?? (dark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      );
  Widget _div(bool dark) =>
      Divider(height: 1, color: dark ? Colors.white10 : Colors.grey[200]);
}
