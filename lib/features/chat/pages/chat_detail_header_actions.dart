// 文件用途：实现 _ChatDetailHeaderActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailHeaderActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail header actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailHeaderActions on _ChatDetailPageState {
  // 流程逻辑：`_buildTopBar` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Widget _buildTopBar(bool isDark) {
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.chatId));
    final contacts = ref.watch(contactListProvider);
    final chatListState = ref.watch(chatListProvider);
    final listChat = this._findCurrentChatItem(chatListState);
    final detailChat = chatDetailAsync.valueOrNull;
    final privateContact =
        this._findPrivateContact(contacts, detailChat, listChat);
    final displayName = this._resolveChatDisplayName(
      detailChat,
      listChat,
      privateContact,
    );
    final displayAvatar = privateContact?.avatar ??
        detailChat?.avatar ??
        listChat?.avatar ??
        widget.avatar;
    final displayUserId = widget.chatType == ChatType.private
        ? (privateContact?.uuid ??
            privateContact?.id ??
            detailChat?.targetUserId ??
            listChat?.targetUserUuid ??
            listChat?.targetUserId ??
            widget.chatId)
        : widget.chatId;
    final displayNicknameColor = privateContact?.nicknameColor ??
        detailChat?.nicknameColor ??
        listChat?.nicknameColor;
    final displayEmojiAvatar = privateContact?.emojiAvatar ??
        detailChat?.emojiAvatar ??
        listChat?.emojiAvatar;
    final contactVip = privateContact?.vip;
    final detailVipVisible = detailChat?.vipVisible ?? false;
    final listVipVisible = listChat?.vipVisible ?? false;
    final displayVipLevel = contactVip?.visible == true
        ? contactVip!.level
        : detailVipVisible
            ? detailChat!.vipLevel
            : listVipVisible
                ? listChat!.vipLevel
                : 0;
    final displayVipBadge = contactVip?.visible == true
        ? contactVip!.badge
        : detailVipVisible
            ? detailChat!.vipBadge
            : listVipVisible
                ? listChat!.vipBadge
                : '';
    final displayVipBadgeIcon = contactVip?.visible == true
        ? contactVip!.badgeIcon
        : detailVipVisible
            ? detailChat!.vipBadgeIcon
            : listVipVisible
                ? listChat!.vipBadgeIcon
                : '';
    final headerAvatar = displayVipLevel > 0
        ? VipAvatarFrame(
            level: displayVipLevel,
            size: 36,
            frameWidth: 2,
            child: AvatarWidget(
              avatar: displayAvatar,
              name: displayName,
              userId: displayUserId,
              size: 36,
            ),
          )
        : AvatarWidget(
            avatar: displayAvatar,
            name: displayName,
            userId: displayUserId,
            size: 40,
          );

    final useSolidHeader = PlatformUtils.isAndroid || widget.isDesktopMode;
    final bgColor = useSolidHeader
        ? (isDark ? AppColors.darkSurface : AppColors.lightBackground)
        : (isDark ? Colors.black : Colors.white).withOpacity(0.5);

    final topPadding =
        widget.isDesktopMode ? 0.0 : MediaQuery.of(context).padding.top;

    Widget content = Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF94A3B8))
                .withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _buildBackButton(ref),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showChatInfo(context),
                child: Row(
                  children: [
                    headerAvatar,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: ColoredNameWidget(
                                    name: displayName,
                                    nicknameColor: displayNicknameColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    defaultColor:
                                        AppColors.textPrimaryFor(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (displayEmojiAvatar != null &&
                                    displayEmojiAvatar.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: EmojiStatusWidget(
                                      emoji: displayEmojiAvatar,
                                      size: 18,
                                    ),
                                  ),
                                if (displayVipLevel > 0) ...[
                                  const SizedBox(width: 5),
                                  VipBadge(
                                    level: displayVipLevel,
                                    text: displayVipBadge,
                                    iconUrl: displayVipBadgeIcon,
                                    height: 18,
                                    compact: true,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            _buildSubtitle(
                              chatDetailAsync,
                              isDark,
                              listChat: listChat,
                              privateContact: privateContact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.chatType != ChatType.private) ...[
              IconButton(
                icon: Icon(Icons.search, color: AppColors.primaryFor(context)),
                onPressed: () {},
              ),
              Builder(
                builder: (moreCtx) => IconButton(
                  icon: Icon(
                    Icons.more_vert,
                    color: AppColors.primaryFor(context),
                  ),
                  onPressed: () => _showMoreOptions(moreCtx),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (useSolidHeader) {
      return content;
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: content,
      ),
    );
  }

  Widget _buildSubtitle(
    AsyncValue<dynamic> chatDetailAsync,
    bool isDark, {
    ChatItem? listChat,
    ContactItem? privateContact,
  }) {
    final l10n = AppLocalizations.of(context);
    final defaultStyle = TextStyle(
      fontSize: 13,
      color: AppColors.textSecondaryFor(context),
    );
    final onlineStyle = const TextStyle(fontSize: 13, color: Colors.green);
    final typingStyle = const TextStyle(
      fontSize: 13,
      color: Colors.blue,
      fontStyle: FontStyle.italic,
    );

    // 如果有人正在输入，优先显示
    if (_typingUsers.isNotEmpty) {
      final typingText = widget.chatType == ChatType.private
          ? l10n.typing
          : '${_typingUsers.values.last} ${l10n.typing}';
      return Text(typingText, style: typingStyle);
    }

    switch (widget.chatType) {
      case ChatType.private:
        // 私聊显示在线状态
        return chatDetailAsync.when(
          data: (chat) {
            final isOnline = (chat?.onlineCount ?? 0) > 0 ||
                (listChat?.isOnline ?? false) ||
                (privateContact?.isOnline ?? false);
            return Text(
              isOnline ? l10n.online : l10n.offline,
              style: isOnline ? onlineStyle : defaultStyle,
            );
          },
          loading: () => Text('...', style: defaultStyle),
          error: (_, __) => const SizedBox.shrink(),
        );
      case ChatType.group:
        return chatDetailAsync.when(
          data: (chat) {
            if (chat != null) {
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${chat.memberCount} ${l10n.members}',
                      style: defaultStyle,
                    ),
                    if (chat.onlineCount > 0) ...[
                      TextSpan(text: ', ', style: defaultStyle),
                      TextSpan(
                        text: '${chat.onlineCount} ${l10n.online}',
                        style: onlineStyle,
                      ),
                    ],
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
          loading: () => Text(l10n.loading, style: defaultStyle),
          error: (_, __) => const SizedBox.shrink(),
        );
      case ChatType.channel:
        return chatDetailAsync.when(
          data: (chat) {
            if (chat != null) {
              final count = chat.memberCount;
              final text = '$count ${l10n.get('subscribers')}';
              return Text(text, style: defaultStyle);
            }
            return const SizedBox.shrink();
          },
          loading: () => Text(l10n.loading, style: defaultStyle),
          error: (_, __) => const SizedBox.shrink(),
        );
    }
  }

  Widget _buildBackButton(WidgetRef ref) {
    // 桌面端不显示返回按钮（分栏布局）
    if (widget.isDesktopMode) {
      return const SizedBox(width: 12);
    }

    // 使用 select 只监听未读数变化，避免整个 chatState 变化时重建
    final unreadCount = ref.watch(
      chatListProvider.select((state) {
        return state.pinnedChats
                .where((c) => c.id != widget.chatId && c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount) +
            state.regularChats
                .where((c) => c.id != widget.chatId && c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount);
      }),
    );

    return IconButton(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: AppColors.primaryFor(context),
          ),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primaryFor(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      onPressed: _handleBackButton,
    );
  }

  void _showChatInfo(BuildContext context) async {
    final latestChat = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    final currentName = latestChat?.name ?? widget.chatName;
    final currentAvatar = latestChat?.avatar ?? widget.avatar;
    final avatarParam = currentAvatar != null
        ? '&avatar=${Uri.encodeComponent(currentAvatar)}'
        : '';
    final nameParam = 'name=${Uri.encodeComponent(currentName)}';

    // 桌面端：在右侧面板显示资料页
    if (widget.isDesktopMode) {
      if (widget.chatType == ChatType.group) {
        ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
          type: DesktopProfileType.group,
          id: widget.chatId,
          name: currentName,
          avatar: currentAvatar,
        );
      } else if (widget.chatType == ChatType.channel) {
        ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
          type: DesktopProfileType.channel,
          id: widget.chatId,
          name: currentName,
          avatar: currentAvatar,
        );
      } else {
        // 私聊：获取对方用户 ID
        final chatDetail = ref.read(chatDetailProvider(widget.chatId));
        final targetUserId = chatDetail.value?.targetUserId ?? widget.chatId;
        ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
          type: DesktopProfileType.user,
          id: targetUserId,
          name: currentName,
          avatar: currentAvatar,
          chatId: widget.chatId,
        );
      }
      return;
    }

    // 移动端：导航到资料页
    if (widget.chatType == ChatType.group) {
      // 跳转到群组资料页
      context.push('/group/${widget.chatId}/profile?$nameParam$avatarParam');
    } else if (widget.chatType == ChatType.channel) {
      // 跳转到频道资料页
      context.push('/channel/${widget.chatId}/profile?$nameParam$avatarParam');
    } else {
      // 私聊：获取对方用户 ID
      final chatDetail = ref.read(chatDetailProvider(widget.chatId));
      final targetUserId = chatDetail.value?.targetUserId ?? widget.chatId;
      // 跳转到用户资料页，传入 chatId 以便加载媒体
      context.push(
        '/user/$targetUserId?$nameParam$avatarParam&chat_id=${widget.chatId}',
      );
    }
  }

  // 保留底部弹窗方法用于其他地方调用
  void _showUserInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserInfoSheet(
        name: widget.chatName,
        avatar: widget.avatar,
        userId: widget.chatId,
      ),
    );
  }

  void _showGroupInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GroupInfoSheet(
        name: widget.chatName,
        avatar: widget.avatar,
        groupId: widget.chatId,
      ),
    );
  }

  void _showChannelInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChannelInfoSheet(
        name: widget.chatName,
        avatar: widget.avatar,
        channelId: widget.chatId,
      ),
    );
  }
}
