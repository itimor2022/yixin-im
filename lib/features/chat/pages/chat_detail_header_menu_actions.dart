// 文件用途：实现 _ChatDetailHeaderMenuActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailHeaderMenuActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail header menu actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailHeaderMenuActions on _ChatDetailPageState {
  // 流程逻辑：`_showMoreOptions` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _showMoreOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGroup = widget.chatType == ChatType.group;
    final isChannel = widget.chatType == ChatType.channel;
    final isDesktop = PlatformUtils.isPhysicalDesktop;

    // 从 chatDetailProvider 获取用户角色
    final chatDetailAsync = ref.read(chatDetailProvider(widget.chatId));
    final isAdmin =
        chatDetailAsync.whenOrNull(data: (chat) => chat?.isAdmin) ?? false;

    // 桌面端使用弹出菜单
    if (isDesktop) {
      _showDesktopPopupMenu(context, isGroup, isChannel, isAdmin, isDark);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // 管理员或群主才显示管理选项
              if (isAdmin && (isGroup || isChannel))
                _OptionTile(
                  icon: Icons.settings_outlined,
                  title: isChannel
                      ? _localizedText(
                          zhCN: '管理频道',
                          zhTW: '管理頻道',
                          en: 'Manage Channel',
                        )
                      : _localizedText(
                          zhCN: '管理群组',
                          zhTW: '管理群組',
                          en: 'Manage Group',
                        ),
                  onTap: () {
                    Navigator.pop(context);
                    _openEditPage(context);
                  },
                ),

              // 所有用户都能搜索
              _OptionTile(
                icon: Icons.search,
                title: _localizedText(
                  zhCN: '搜索',
                  zhTW: '搜尋',
                  en: 'Search',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openSearchMessages();
                },
              ),
              _OptionTile(
                icon: Icons.bookmark_outline,
                title: _localizedText(
                  zhCN: '收藏',
                  zhTW: '收藏',
                  en: 'Favorites',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openFavoriteMessages();
                },
              ),

              // 退出/取消订阅
              if (isGroup)
                _OptionTile(
                  icon: Icons.exit_to_app,
                  title: _localizedText(
                    zhCN: '退出群组',
                    zhTW: '退出群組',
                    en: 'Leave Group',
                  ),
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showLeaveConfirmDialog(context, isChannel: false);
                  },
                ),
              if (isChannel)
                _OptionTile(
                  icon: Icons.exit_to_app,
                  title: _localizedText(
                    zhCN: '取消订阅',
                    zhTW: '取消訂閱',
                    en: 'Unsubscribe',
                  ),
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showLeaveConfirmDialog(context, isChannel: true);
                  },
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDesktopPopupMenu(
    BuildContext context,
    bool isGroup,
    bool isChannel,
    bool isAdmin,
    bool isDark,
  ) {
    final l10n = AppLocalizations.of(context);
    final buttonObj = context.findRenderObject();
    if (buttonObj is! RenderBox) return;
    final RenderBox button = buttonObj;
    final overlayState = Navigator.of(context).overlay;
    if (overlayState == null) return;
    final overlayObj = overlayState.context.findRenderObject();
    if (overlayObj is! RenderBox) return;
    final RenderBox overlay = overlayObj;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          Offset(button.size.width - 200, 50),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkSurface : Colors.white,
      items: [
        if (isAdmin && (isGroup || isChannel))
          PopupMenuItem(
            value: 'manage',
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                const SizedBox(width: 12),
                Text(
                  isChannel
                      ? _translate(
                          context,
                          'manage_channel',
                          _localizedText(
                            zhCN: '管理频道',
                            zhTW: '管理頻道',
                            en: 'Manage Channel',
                          ),
                        )
                      : _translate(
                          context,
                          'manage_group',
                          _localizedText(
                            zhCN: '管理群组',
                            zhTW: '管理群組',
                            en: 'Manage Group',
                          ),
                        ),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'search',
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 12),
              Text(l10n.search),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favorites',
          child: Row(
            children: [
              Icon(
                Icons.bookmark_outline,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 12),
              Text(l10n.get('favorite')),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              Icon(Icons.exit_to_app, size: 20, color: AppColors.error),
              const SizedBox(width: 12),
              Text(
                isChannel ? l10n.get('unsubscribe') : l10n.leaveGroup,
                style: TextStyle(color: AppColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'manage':
          _openEditPage(context);
          break;
        case 'search':
          _openSearchMessages();
          break;
        case 'favorites':
          _openFavoriteMessages();
          break;
        case 'leave':
          _showLeaveConfirmDialog(context, isChannel: isChannel);
          break;
      }
    });
  }

  Future<void> _openSearchMessages() async {
    final result = await Navigator.of(context).push<api.SearchMessageItem>(
      MaterialPageRoute(
        builder: (context) => MessageSearchPage(
          chatId: widget.chatId,
          chatName: widget.chatName,
          chatType: widget.chatType == ChatType.channel ? 'channel' : 'group',
          returnSelection: true,
        ),
      ),
    );
    if (!mounted || result == null || result.id.isEmpty) {
      return;
    }
    await _scrollToMessage(result.id, targetSeq: result.seq);
  }

  void _openEditPage(BuildContext context) {
    final isDesktop = PlatformUtils.isPhysicalDesktop;
    final isChannel = widget.chatType == ChatType.channel;

    if (isDesktop) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
        type: isChannel
            ? DesktopPanelType.channelEdit
            : DesktopPanelType.groupEdit,
        id: widget.chatId,
      );
    } else {
      context.push('/group/edit/${widget.chatId}');
    }
  }
}
