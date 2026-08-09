// 文件用途：提供 MessageBubble 可复用界面组件，服务于聊天与消息。
// 核心逻辑：按消息类型选择专用气泡组件，统一处理引用、反应、已读、播放队列和上下文菜单等跨类型交互。
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../core/services/api/api_client.dart'
    show ApiClient, ApiConfig, TokenStorage;
import '../../../core/services/media_cache_manager.dart';
import '../../../core/services/android_file_open_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/voice_playback_audio_context.dart';
import '../../../core/services/voice_playback_queue.dart';
import '../../../core/services/time_zone_refresh_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/image_file_format.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/animated_gif_image.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/sticker_image.dart';
import '../../../shared/widgets/visible_lottie.dart';
import '../../../core/utils/link_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/message_provider.dart';
import '../services/emoji_store_service.dart';
import '../pages/user_profile_page.dart';
import '../../vip/widgets/vip_avatar_frame.dart';
import '../../vip/widgets/vip_badge.dart';
import '../../wallet/services/wallet_service.dart';
import '../../wallet/providers/wallet_provider.dart';
import '../../wallet/widgets/red_packet_bubble.dart';
import '../../wallet/widgets/transfer_bubble.dart';
import '../utils/call_preview_formatter.dart';
import '../models/forward_bundle_snapshot.dart';
import '../pages/forward_bundle_preview_page.dart';

part 'message_bubble_file.dart';
part 'message_bubble_voice.dart';
part 'message_bubble_video.dart';
part 'message_bubble_video_player.dart';
part 'message_bubble_image.dart';
part 'message_bubble_album.dart';
part 'message_bubble_image_preview.dart';
part 'message_bubble_media.dart';
part 'message_bubble_helpers.dart';
part 'message_bubble_burn.dart';
part 'message_bubble_text.dart';
part 'message_bubble_call.dart';
part 'message_bubble_contact.dart';
part 'message_bubble_location.dart';
part 'message_bubble_sticker.dart';
part 'message_bubble_reply.dart';
part 'message_bubble_wallet.dart';
part 'message_bubble_wallet_red_packet_detail.dart';
part 'message_bubble_wallet_transfer_detail.dart';
part 'message_bubble_forward_bundle.dart';

String _localizedUiText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  final code = AppLocalizations.of(context).language.code;
  switch (code) {
    case 'en':
      return en;
    case 'zh_TW':
      return zhTW ?? zhCN;
    default:
      return zhCN;
  }
}

String _localizedServerUiMessage(
  BuildContext context, {
  required String? raw,
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  return localizeServerMessage(
    raw,
    fallbackZhCN: zhCN,
    fallbackZhTW: zhTW,
    fallbackEn: en,
  );
}

// 关键声明：message bubble 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
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
  final VoidCallback? onRetry;
  final Color? customOutgoingColor;
  final Color? customIncomingColor;
  final Function(String userId, String userName)? onMentionUser; // 长按头像@用户
  final bool isGroupChat;
  final bool canOpenMemberProfile;
  final double messageFontSize;
  final List<MessageItem> albumMessages;
  final List<MessageItem> voicePlaylist;

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
    this.onRetry,
    this.customOutgoingColor,
    this.customIncomingColor,
    this.onMentionUser,
    this.isGroupChat = false,
    this.canOpenMemberProfile = true,
    this.messageFontSize = 16,
    this.albumMessages = const [],
    this.voicePlaylist = const [],
  });

  String _localizedText(
    BuildContext context, {
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    final code = AppLocalizations.of(context).language.code;
    switch (code) {
      case 'en':
        return en;
      case 'zh_TW':
        return zhTW ?? zhCN;
      default:
        return zhCN;
    }
  }

  bool _containsAny(String source, Iterable<String> needles) {
    final lower = source.toLowerCase();
    for (final needle in needles) {
      if (needle.isEmpty) continue;
      if (lower.contains(needle.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  bool _isVideoCallContent(String content) {
    final legacyVideoCallMarker =
        String.fromCharCodes([0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d]);
    return _containsAny(content, ['视频', '視訊', 'video']) ||
        content.contains(legacyVideoCallMarker);
  }

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
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
    final senderVipLevel = message.senderVipActive && message.senderVipLevel > 0
        ? message.senderVipLevel
        : 0;
    const senderAvatarSlotSize = 38.0;
    const senderVipAvatarSize = 34.0;
    final senderAvatar = senderVipLevel > 0
        ? VipAvatarFrame(
            level: senderVipLevel,
            size: senderVipAvatarSize,
            frameWidth: 2,
            child: AvatarWidget(
              avatar: message.senderAvatar,
              name: message.senderName,
              userId: message.senderId,
              size: senderVipAvatarSize,
            ),
          )
        : AvatarWidget(
            avatar: message.senderAvatar,
            name: message.senderName,
            userId: message.senderId,
            size: senderAvatarSlotSize,
          );

    return SizedBox(
      width: double.infinity,
      child: Padding(
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
                  child: senderAvatar,
                )
              else
                const SizedBox(width: senderAvatarSlotSize), // 占位
              const SizedBox(width: 8),
            ],

            // 消息气泡
            Flexible(
              child: Align(
                alignment:
                    isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
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
                        if (showSenderName)
                          _buildSenderHeader(context, isOutgoing),
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
            ),
          ],
        ),
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
        context,
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
        bubble = albumMessages.length > 1
            ? _buildImageAlbumBubble(context, timeColor, isOutgoing)
            : _buildImageBubble(bubbleColor, timeColor, isOutgoing);
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
          context,
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
          context,
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      case MessageItemType.call:
        bubble = _buildCallBubble(
          context,
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
      case MessageItemType.forwardBundle:
        bubble = _buildForwardBundleBubble(
          context,
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
      default:
        bubble = _buildTextBubble(
          context,
          bubbleColor,
          textColor,
          timeColor,
          isOutgoing,
        );
        break;
    }

    return _wrapBurnCountdown(context, bubble, isOutgoing, isDark);
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
      voicePlaylist: voicePlaylist,
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
}
