// 文件用途：实现 _ChatDetailInputMentions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailInputMentions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail input mentions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailInputMentions on _ChatDetailPageState {
  // 流程逻辑：`_onInputChanged` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _onInputChanged() {
    if (!mounted) return;

    final text = _inputController.text;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(chatListProvider.notifier).updateDraft(widget.chatId, text);
    });

    if (_wsService == null) return;

    if (text.isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        _wsService!.sendTyping(widget.chatId, isTyping: false);
      }
      _typingTimer?.cancel();
      if (widget.chatType != ChatType.private) {
        _detectMentionQuery();
      }
      return;
    }

    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      _wsService!.sendTyping(widget.chatId, isTyping: true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 8), () {
      if (_isTyping && _wsService != null) {
        _isTyping = false;
        _wsService!.sendTyping(widget.chatId, isTyping: false);
      }
    });

    // 群聊/频道才检测 @ 提及
    if (widget.chatType != ChatType.private) {
      _detectMentionQuery();
    }
  }

  /// 检测光标前是否有未完成的 @mention 模式
  void _detectMentionQuery() {
    final text = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final textBeforeCursor = text.substring(0, cursor);
    final lastAt = textBeforeCursor.lastIndexOf('@');

    if (lastAt < 0) {
      if (_mentionQuery != null)
        _updateState(() {
          _mentionQuery = null;
          _atSignIndex = -1;
        });
      return;
    }

    // @ 后到光标之间不含空格才视为正在输入 mention
    final afterAt = textBeforeCursor.substring(lastAt + 1);
    if (afterAt.contains(' ') || afterAt.contains('\n')) {
      if (_mentionQuery != null)
        _updateState(() {
          _mentionQuery = null;
          _atSignIndex = -1;
        });
      return;
    }

    // 限制搜索词长度
    if (afterAt.length > 30) {
      if (_mentionQuery != null)
        _updateState(() {
          _mentionQuery = null;
          _atSignIndex = -1;
        });
      return;
    }

    _updateState(() {
      _atSignIndex = lastAt;
      _mentionQuery = afterAt;
    });
  }

  /// 插入 @ 提及并记录用户 ID
  void _insertMention(api.ChatMember member) {
    final text = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    final mentionText = '@${member.displayName} ';

    final safeCursor =
        (cursor >= 0 && cursor <= text.length) ? cursor : text.length;
    final newText = text.substring(0, _atSignIndex) +
        mentionText +
        text.substring(safeCursor);

    _inputController.text = newText;
    _inputController.selection = TextSelection.collapsed(
      offset: _atSignIndex + mentionText.length,
    );

    if (!_pendingMentionIds.contains(member.userId)) {
      _pendingMentionIds.add(member.userId);
    }

    _updateState(() {
      _mentionQuery = null;
      _atSignIndex = -1;
    });

    _inputFocusNode.requestFocus();
  }

  void _insertMentionAll() {
    final text = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    final mentionText = _localizedText(
      zhCN: '@全体成员 ',
      zhTW: '@全體成員 ',
      en: '@all ',
    );
    final safeCursor =
        (cursor >= 0 && cursor <= text.length) ? cursor : text.length;
    final newText = text.substring(0, _atSignIndex) +
        mentionText +
        text.substring(safeCursor);

    _inputController.text = newText;
    _inputController.selection = TextSelection.collapsed(
      offset: _atSignIndex + mentionText.length,
    );
    if (!_pendingMentionIds.contains('__all__')) {
      _pendingMentionIds.add('__all__');
    }
    _updateState(() {
      _mentionQuery = null;
      _atSignIndex = -1;
    });
    _inputFocusNode.requestFocus();
  }

  /// 发送消息时停止 typing 状态

  Widget _buildMentionPicker(bool isDark) {
    final query = _mentionQuery ?? '';
    final membersAsync = ref.watch(chatMembersProvider(widget.chatId));

    return membersAsync.when(
      data: (members) {
        final currentUserId = ref.read(authServiceProvider).user?.uuid;
        final detail = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
        final normalizedQuery = query.trim().toLowerCase();
        final canMentionAll = detail != null &&
            detail.status != 2 &&
            detail.myRole >= 2 &&
            (normalizedQuery.isEmpty ||
                '全体成员'.contains(normalizedQuery) ||
                '全體成員'.contains(normalizedQuery) ||
                'all'.contains(normalizedQuery));
        final filtered = members
            .where((m) {
              if (m.userId == currentUserId) return false; // 排除自己
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return m.displayName.toLowerCase().contains(q) ||
                  m.username.toLowerCase().contains(q);
            })
            .take(8)
            .toList();

        if (filtered.isEmpty && !canMentionAll) {
          return const SizedBox.shrink();
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 256),
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filtered.length + (canMentionAll ? 1 : 0),
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
                indent: 52,
              ),
              itemBuilder: (context, index) {
                if (canMentionAll && index == 0) {
                  return InkWell(
                    onTap: _insertMentionAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                AppColors.primaryWithOpacity(context, 0.12),
                            child: Icon(
                              Icons.campaign_outlined,
                              size: 19,
                              color: AppColors.primaryFor(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _localizedText(
                                zhCN: '全体成员',
                                zhTW: '全體成員',
                                en: 'Everyone',
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            _localizedText(
                              zhCN: '管理员可用',
                              zhTW: '管理員可用',
                              en: 'Admins',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final memberIndex = canMentionAll ? index - 1 : index;
                final member = filtered[memberIndex];
                return InkWell(
                  onTap: () => _insertMention(member),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        AvatarWidget(
                          avatar: member.avatar,
                          name: member.displayName,
                          size: 32,
                          userId: member.userId,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: ColoredNameWidget(
                                      name: member.displayName,
                                      nicknameColor: member.nicknameColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      defaultColor: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (member.vipVisible) ...[
                                    const SizedBox(width: 5),
                                    VipBadge(
                                      level: member.vipLevel,
                                      text: member.vipBadge,
                                      iconUrl: member.vipBadgeIcon,
                                      height: 18,
                                      compact: true,
                                    ),
                                  ],
                                ],
                              ),
                              if (member.username.isNotEmpty)
                                Text(
                                  '@${member.username}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (member.role >= 2)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primaryWithOpacity(context, 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              member.roleName,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primaryFor(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  /// TG 风格待发送图片预览面板

  void _mentionUser(String userId, String userName) {
    // 在输入框中插入@用户名
    final currentText = _inputController.text;
    final selection = _inputController.selection;
    final mention = '@$userName ';

    // 获取有效的光标位置（如果无效则插入到末尾）
    final cursorPos = (selection.baseOffset >= 0 &&
            selection.baseOffset <= currentText.length)
        ? selection.baseOffset
        : currentText.length;

    // 在光标位置插入@
    final newText = currentText.substring(0, cursorPos) +
        mention +
        currentText.substring(cursorPos);

    _inputController.text = newText;
    // 将光标移动到@后面
    _inputController.selection = TextSelection.collapsed(
      offset: cursorPos + mention.length,
    );

    // 记录被提及的用户 ID（用于发送消息时携带 mentions 字段）
    if (!_pendingMentionIds.contains(userId)) {
      _pendingMentionIds.add(userId);
    }

    // 聚焦输入框
    _inputFocusNode.requestFocus();
  }
}
