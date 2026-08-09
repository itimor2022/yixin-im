// 文件用途：实现 _ChatDetailBuild 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailBuild 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail build 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailBuild on _ChatDetailPageState {
  Widget _buildChatDetailPage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref.listen<AsyncValue<SystemSettings>>(systemSettingsProvider, (
      previous,
      next,
    ) {
      final settings = next.valueOrNull ?? const SystemSettings();
      final allowed = settings.burnAfterReadEnabled;
      if (!allowed && _burnAfterReadEnabled && mounted) {
        _updateState(() => _burnAfterReadEnabled = false);
      }
      if (!this._hasAvailableAttachmentAction(settings) &&
          _showAttachmentPickerState &&
          mounted) {
        _updateState(() => _showAttachmentPickerState = false);
      }
    });
    ref.listen<AsyncValue<api.Chat?>>(chatDetailProvider(widget.chatId), (
      previous,
      next,
    ) {
      if (!_anonymousSendAllowed && _anonymousSendEnabled && mounted) {
        _updateState(() => _anonymousSendEnabled = false);
      }
    });
    // 换号后 messageListProvider 会重建，但本页 initState 不会再次执行，需补一次加载与订阅
    ref.listen<String>(authServiceProvider.select((s) => s.user?.uuid ?? ''), (
      previous,
      next,
    ) {
      final p = previous ?? '';
      final n = next ?? '';
      if (p.isNotEmpty && n.isNotEmpty && p != n) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(chatListProvider.notifier).setActiveChatId(widget.chatId);
          ref.read(webSocketServiceProvider.notifier).subscribeChats([
            widget.chatId,
          ]);
          unawaited(ref.read(contactListProvider.notifier).initialize());
          ref.read(messageListProvider(widget.chatId).notifier).initialize();
          unawaited(this._persistReadState());
        });
      }
    });
    // 不在顶层 watch messageList，避免每条消息触发整页 rebuild
    // messages 只在 _buildMessageList 的 Consumer 内 watch
    final chatBackground = ref.watch(chatBackgroundProvider);

    final isDesktop = PlatformUtils.isPhysicalDesktop;

    Widget content = PopScope(
      canPop: true, // 允许左滑返回
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // 返回时执行清理逻辑（不再调用 pop，因为系统已经 pop 了）
          this._cleanupOnExit();
        }
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            // 聊天背景 - 全屏显示（使用 RepaintBoundary 避免重绘）
            Positioned.fill(
              child: RepaintBoundary(
                child: ChatBackgroundWidget(
                  background: chatBackground,
                  isDark: isDark,
                ),
              ),
            ),

            // 主内容
            SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  // 根据类型显示不同顶部栏（带毛玻璃效果）
                  this._buildTopBar(isDark),

                  // TG 风格统一置顶栈：普通置顶消息 + 群/频道公告
                  if (_currentPinnedEntry != null && !_pinnedStackDismissed)
                    Builder(
                      builder: (context) {
                        final entries = _pinnedEntries;
                        final currentEntry = _currentPinnedEntry!;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => this._openPinnedEntry(currentEntry),
                              child: Container(
                                height: 64,
                                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCard
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: isDark
                                      ? Border.all(color: AppColors.darkDivider)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(
                                        isDark ? 0.28 : 0.08,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    _AnnouncementStackIndicator(
                                      count: entries.length,
                                      activeIndex: _pinnedEntryIndex,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _localizedText(
                                              zhCN: '置顶消息',
                                              zhTW: '置頂消息',
                                              en: 'Pinned Message',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1.1,
                                              color:
                                                  AppColors.primaryFor(context),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            currentEntry.content,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1.15,
                                              color: isDark
                                                  ? const Color(0xFFD8DCE2)
                                                  : const Color(0xFF4B5563),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    _AnnouncementIconButton(
                                      icon: Icons.close_rounded,
                                      isDark: isDark,
                                      onTap: () {
                                        _updateState(
                                            () => _pinnedStackDismissed = true);
                                      },
                                    ),
                                    if (entries.length > 1)
                                      _AnnouncementIconButton(
                                        icon: Icons.menu_rounded,
                                        isDark: isDark,
                                        onTap: () =>
                                            this._showPinnedEntryListSheet(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  // 消息列表（点击收起键盘和表情选择器）
                  if (widget.chatType == ChatType.group &&
                      _activeMeetingInfo != null)
                    this._buildActiveMeetingBannerCompact(isDark),
                  Expanded(
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => this._dismissKeyboardAndEmoji(),
                        behavior: HitTestBehavior.translucent,
                        // Consumer 隔离：只有消息列表区域随消息变化 rebuild
                        child: Consumer(
                          builder: (context, ref, _) {
                            final messages = ref.watch(
                              messageListProvider(widget.chatId),
                            );
                            final messageNotifier = ref.read(
                              messageListProvider(widget.chatId).notifier,
                            );
                            if (messages.isEmpty &&
                                !messageNotifier.hasLoadedInitial) {
                              return const SizedBox.expand();
                            }
                            return messages.isEmpty
                                ? this._buildEmptyChat()
                                : this._buildMessageList(messages, isDark);
                          },
                        ),
                      ),
                    ),
                  ),

                  // 输入区域 或 选择模式操作栏
                  if (_isSelectionMode)
                    this._buildSelectionActionBar(isDark)
                  else if (_isRecordingVoice)
                    VoiceRecordOverlay(
                      onSend: this._stopVoiceRecord,
                      onCancel: this._cancelVoiceRecord,
                    )
                  else
                    this._buildInputArea(isDark),
                ],
              ),
            ),

            // 回到底部按钮
            if (_showScrollToBottom)
              Positioned(
                right: 16,
                bottom: 100,
                child: _ScrollToBottomButton(onTap: this._scrollToBottom),
              ),

            // 桌面端拖拽提示遮罩
            if (_isDragging && isDesktop)
              Positioned.fill(
                child: Container(
                  color: AppColors.primaryWithOpacity(context, 0.15),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardFor(context),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_upload_outlined,
                            size: 48,
                            color: AppColors.primaryFor(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _localizedText(
                              zhCN: '松开发送文件',
                              zhTW: '鬆開傳送檔案',
                              en: 'Release to send files',
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryFor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _localizedText(
                              zhCN: '支持图片、视频、文档等',
                              zhTW: '支援圖片、影片、文件等',
                              en: 'Supports images, videos, documents, and more',
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
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

    // 桌面端包装拖拽功能
    if (isDesktop) {
      return DropTarget(
        onDragEntered: (details) {
          _updateState(() => _isDragging = true);
        },
        onDragExited: (details) {
          _updateState(() => _isDragging = false);
        },
        onDragDone: (details) {
          _updateState(() => _isDragging = false);
          this._handleDroppedFiles(details.files);
        },
        child: content,
      );
    }

    return content;
  }
}

class _AnnouncementStackIndicator extends StatelessWidget {
  final int count;
  final int activeIndex;

  const _AnnouncementStackIndicator({
    required this.count,
    required this.activeIndex,
  });

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleCount = count.clamp(1, 4);
    final active = activeIndex.clamp(0, visibleCount - 1);
    return SizedBox(
      width: 12,
      height: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(visibleCount, (index) {
          final isActive = index == active;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: isActive ? 4 : 3,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primaryFor(context)
                        : (isDark
                            ? AppColors.darkDivider
                            : const Color(0xFFB8DFF8)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _AnnouncementIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _AnnouncementIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 21,
            color:
                isDark ? AppColors.darkTextSecondary : const Color(0xFF667085),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementSheetTile extends StatelessWidget {
  final String text;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _AnnouncementSheetTile({
    required this.text,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryFor(context)
                    : (isDark
                        ? AppColors.darkDivider
                        : const Color(0xFFD0D5DD)),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: isDark ? Colors.white70 : const Color(0xFF344054),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
