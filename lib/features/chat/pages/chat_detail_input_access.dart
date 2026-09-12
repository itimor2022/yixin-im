// 文件用途：实现 _ChatDetailInputAccess 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailInputAccess 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail input access 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailInputAccess on _ChatDetailPageState {
  bool get _isChatDissolved {
    final chat = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    return chat?.status == 2;
  }

  // 流程逻辑：`_ensureChatWritable` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  bool _ensureChatWritable() {
    if (!_isChatDissolved) return true;
    if (mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '该群聊已解散，仅可查看历史消息',
          zhTW: '該群聊已解散，僅可查看歷史訊息',
          en: 'This group has been dissolved. Message history is read-only.',
        ),
      );
    }
    return false;
  }

  bool get _canCurrentUserSendMedia {
    final chat = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    if (chat == null) return true;
    if (chat.status == 2) return false;
    if ((widget.chatType == ChatType.group ||
            widget.chatType == ChatType.channel) &&
        !chat.canSendMedia &&
        chat.myRole < 2) {
      return false;
    }
    return true;
  }

  bool _ensureCanSendMedia() {
    if (!_ensureChatWritable()) return false;
    if (_canCurrentUserSendMedia) return true;
    if (mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '当前会话已禁止发送图片、视频、语音和文件',
          zhTW: '當前會話已禁止發送圖片、影片、語音和檔案',
          en: 'This chat does not allow photos, videos, voice messages, or files.',
        ),
      );
    }
    return false;
  }

  Widget _buildInputAreaForGroupChannel(bool isDark) {
    // 频道：检查是否已订阅
    if (widget.chatType == ChatType.channel) {
      final chatDetail = ref.watch(chatDetailProvider(widget.chatId));
      return chatDetail.when(
        data: (chat) {
          if (chat?.status == 2) {
            return _buildDissolvedBar(isDark);
          }
          // myRole == 0 表示未订阅
          if (chat == null || chat.myRole == 0) {
            // 检查是否已提交申请
            if (chat?.pendingRequest == true) {
              return _buildPendingRequestBar(isDark);
            }
            return _buildJoinButton(isDark, isChannel: true);
          }
          // 已订阅，检查禁言状态
          return _buildMuteStatusInputArea(isDark);
        },
        loading: () => _buildMuteStatusInputArea(isDark),
        error: (_, __) => _buildJoinButton(isDark, isChannel: true),
      );
    }

    // 群组：检查是否已加入
    if (widget.chatType == ChatType.group) {
      final chatDetail = ref.watch(chatDetailProvider(widget.chatId));
      return chatDetail.when(
        data: (chat) {
          if (chat?.status == 2) {
            return _buildDissolvedBar(isDark);
          }
          // myRole == 0 表示未加入
          if (chat == null || chat.myRole == 0) {
            // 检查是否已提交申请
            if (chat?.pendingRequest == true) {
              return _buildPendingRequestBar(isDark);
            }
            return _buildJoinButton(isDark, isChannel: false);
          }
          // 已加入，检查禁言状态
          return _buildMuteStatusInputArea(isDark);
        },
        loading: () => _buildMuteStatusInputArea(isDark),
        error: (_, __) => _buildJoinButton(isDark, isChannel: false),
      );
    }

    // 默认检查禁言状态
    return _buildMuteStatusInputArea(isDark);
  }

  // 已申请等待审批状态栏
  Widget _buildPendingRequestBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text(
                _translate(
                  context,
                  'pending_request_submitted',
                  _localizedText(
                    zhCN: '已提交申请，等待审批',
                    zhTW: '已提交申請，等待審批',
                    en: 'Request submitted, waiting for approval',
                  ),
                ),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建加入按钮 （支持频道和群组）
  Widget _buildJoinButton(bool isDark, {required bool isChannel}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _joinChat(isChannel),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: AppColors.primaryFor(context),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isChannel
                        ? _translate(
                            context,
                            'join_channel',
                            _localizedText(
                              zhCN: '加入频道',
                              zhTW: '加入頻道',
                              en: 'Join Channel',
                            ),
                          )
                        : _translate(
                            context,
                            'join_group',
                            _localizedText(
                              zhCN: '加入群组',
                              zhTW: '加入群組',
                              en: 'Join Group',
                            ),
                          ),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryFor(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 加入频道/群组
  Future<void> _joinChat(bool isChannel) async {
    final (success, errorMsg, requiresApproval, approvalMsg) = await ref
        .read(chatListProvider.notifier)
        .joinChatFromServer(widget.chatId);

    if (!mounted) return;

    if (success) {
      if (requiresApproval) {
        // 需要审批
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approvalMsg ??
                  (isChannel
                      ? _localizedText(
                          zhCN: '已提交订阅申请，请等待审批',
                          zhTW: '已提交訂閱申請，請等待審批',
                          en: 'Subscription request submitted. Please wait for approval.',
                        )
                      : _localizedText(
                          zhCN: '已提交加入申请，请等待审批',
                          zhTW: '已提交加入申請，請等待審批',
                          en: 'Join request submitted. Please wait for approval.',
                        )),
            ),
          ),
        );
        // 刷新详情以显示"等待审批"状态
        ref.invalidate(chatDetailProvider(widget.chatId));
      } else {
        // 直接加入成功，刷新详情
        ref.invalidate(chatDetailProvider(widget.chatId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              isChannel
                  ? _localizedText(
                      zhCN: '已订阅频道',
                      zhTW: '已訂閱頻道',
                      en: 'Channel joined',
                    )
                  : _localizedText(
                      zhCN: '已加入群组',
                      zhTW: '已加入群組',
                      en: 'Group joined',
                    ),
            ),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg ??
                (isChannel
                    ? _localizedText(
                        zhCN: '订阅失败',
                        zhTW: '訂閱失敗',
                        en: 'Join channel failed',
                      )
                    : _localizedText(
                        zhCN: '加入失败',
                        zhTW: '加入失敗',
                        en: 'Join group failed',
                      )),
          ),
        ),
      );
    }
  }

  // 构建禁言状态检查的输入区域
  Widget _buildMuteStatusInputArea(bool isDark) {
    final myUserId = ref.watch(
      authServiceProvider.select((s) => s.user?.uuid ?? ''),
    );

    if (myUserId.isEmpty) {
      return this._buildInputWithPreview(isDark);
    }

    // 检查群组全员禁言权限
    final chatDetail = ref.watch(chatDetailProvider(widget.chatId));
    final chat = chatDetail.valueOrNull;

    // 频道模式: 仅管理员和创建者可发言（类似 Telegram）
    // myRole: 1=普通成员, 2=管理员, 3=群主
    if (chat != null &&
        widget.chatType == ChatType.channel &&
        chat.myRole < 2) {
      return _buildMutedBar(
        isDark,
        _localizedText(
          zhCN: '仅管理员可发布内容',
          zhTW: '僅管理員可發布內容',
          en: 'Only admins can post',
        ),
      );
    }

    // 如果群组开启了全员禁言，且当前用户不是管理员/群主
    if (chat != null &&
        widget.chatType == ChatType.group &&
        !chat.canSendMessage &&
        chat.myRole < 2) {
      return _buildMutedBar(
        isDark,
        _localizedText(
          zhCN: '全员禁言中',
          zhTW: '全員禁言中',
          en: 'Group is muted for all members',
        ),
      );
    }

    final muteStatus = ref.watch(
      myMuteStatusProvider((widget.chatId, myUserId)),
    );

    return muteStatus.when(
      data: (status) {
        if (status != null && status.isMuted) {
          // 被禁言，显示提示
          String muteText = _localizedText(
            zhCN: '您已被禁言',
            zhTW: '您已被禁言',
            en: 'You have been muted',
          );
          if (status.muteEndTime != null) {
            final remaining = status.muteEndTime!.difference(DateTime.now());
            if (remaining.isNegative) {
              // 禁言已过期
              return this._buildInputWithPreview(isDark);
            }
            if (remaining.inDays > 0) {
              muteText = _localizedText(
                zhCN: '您已被禁言，剩余 ${remaining.inDays} 天',
                zhTW: '您已被禁言，剩餘 ${remaining.inDays} 天',
                en: 'You have been muted. ${remaining.inDays} day(s) remaining',
              );
            } else if (remaining.inHours > 0) {
              muteText = _localizedText(
                zhCN: '您已被禁言，剩余 ${remaining.inHours} 小时',
                zhTW: '您已被禁言，剩餘 ${remaining.inHours} 小時',
                en: 'You have been muted. ${remaining.inHours} hour(s) remaining',
              );
            } else {
              muteText = _localizedText(
                zhCN: '您已被禁言，剩余 ${remaining.inMinutes} 分钟',
                zhTW: '您已被禁言，剩餘 ${remaining.inMinutes} 分鐘',
                en: 'You have been muted. ${remaining.inMinutes} minute(s) remaining',
              );
            }
          }

          return _buildMutedBar(isDark, muteText);
        }

        // 未被禁言
        return this._buildInputWithPreview(isDark);
      },
      loading: () => this._buildInputWithPreview(isDark),
      error: (_, __) => this._buildInputWithPreview(isDark),
    );
  }

  // 构建禁言提示栏（TG风格 - 仿输入框样式）
  Widget _buildMutedBar(bool isDark, String text) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.volume_off_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDissolvedBar(bool isDark) {
    return _buildMutedBar(
      isDark,
      _localizedText(
        zhCN: '该群聊已解散，仅可查看历史消息',
        zhTW: '該群聊已解散，僅可查看歷史訊息',
        en: 'This group has been dissolved. History is read-only.',
      ),
    );
  }
}
