// 文件用途：实现 _ChatDetailGroupMuteActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailGroupMuteActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail group mute actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailGroupMuteActions on _GroupInfoSheet {
  // 流程逻辑：`_showMuteOptions` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _showMuteOptions(
    BuildContext context,
    WidgetRef ref,
    String chatId,
    api.ChatMember member,
    int myRole,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageContext = context;

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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  member.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              if (member.isMuted) ...[
                // 已禁言，显示解禁选项
                ListTile(
                  leading: const Icon(
                    Icons.volume_up,
                    color: AppColors.success,
                  ),
                  title: Text(
                    _chatDetailText(
                      context,
                      zhCN: '解除禁言',
                      zhTW: '解除禁言',
                      en: 'Unmute',
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final chatService = ref.read(api.chatServiceProvider);
                      final result = await chatService.unmuteMember(
                        chatId,
                        member.userId,
                      );
                      if (result.isSuccess) {
                        ref.invalidate(chatMembersProvider(chatId));
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                _chatDetailText(
                                  pageContext,
                                  zhCN: '已解除禁言',
                                  zhTW: '已解除禁言',
                                  en: 'Member unmuted',
                                ),
                              ),
                            ),
                          );
                        }
                      } else if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.message ??
                                  _chatDetailText(
                                    pageContext,
                                    zhCN: '操作失败',
                                    zhTW: '操作失敗',
                                    en: 'Action failed',
                                  ),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              _chatDetailText(
                                pageContext,
                                zhCN: '操作失败，请重试',
                                zhTW: '操作失敗，請重試',
                                en: 'Action failed. Please try again.',
                              ),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ] else ...[
                // 未禁言，显示禁言选项
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.orange),
                  title: Text(
                    _chatDetailText(
                      context,
                      zhCN: '禁言 10 分钟',
                      zhTW: '禁言 10 分鐘',
                      en: 'Mute 10 minutes',
                    ),
                  ),
                  onTap: () => this._muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    10,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.orange),
                  title: Text(
                    _chatDetailText(
                      context,
                      zhCN: '禁言 1 小时',
                      zhTW: '禁言 1 小時',
                      en: 'Mute 1 hour',
                    ),
                  ),
                  onTap: () => this._muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    60,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.orange),
                  title: Text(
                    _chatDetailText(
                      context,
                      zhCN: '禁言 1 天',
                      zhTW: '禁言 1 天',
                      en: 'Mute 1 day',
                    ),
                  ),
                  onTap: () => this._muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    1440,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.red),
                  title: Text(
                    _chatDetailText(
                      context,
                      zhCN: '永久禁言',
                      zhTW: '永久禁言',
                      en: 'Mute permanently',
                    ),
                  ),
                  onTap: () => this._muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    0,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.close,
                  color: AppColors.textSecondaryFor(context),
                ),
                title: Text(
                  _chatDetailText(
                    context,
                    zhCN: '取消',
                    zhTW: '取消',
                    en: 'Cancel',
                  ),
                ),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _muteMember(
    BuildContext pageContext,
    BuildContext sheetContext,
    WidgetRef ref,
    String chatId,
    String userId,
    int duration,
  ) async {
    Navigator.pop(sheetContext);
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final result = await chatService.muteMember(
        chatId,
        userId,
        duration: duration,
      );
      if (result.isSuccess) {
        ref.invalidate(chatMembersProvider(chatId));
        if (pageContext.mounted) {
          final durationText = duration == 0
              ? _chatDetailText(
                  pageContext,
                  zhCN: '永久',
                  zhTW: '永久',
                  en: 'permanently',
                )
              : duration >= 1440
                  ? _chatDetailText(
                      pageContext,
                      zhCN: '${duration ~/ 1440} 天',
                      zhTW: '${duration ~/ 1440} 天',
                      en: '${duration ~/ 1440} day(s)',
                    )
                  : duration >= 60
                      ? _chatDetailText(
                          pageContext,
                          zhCN: '${duration ~/ 60} 小时',
                          zhTW: '${duration ~/ 60} 小時',
                          en: '${duration ~/ 60} hour(s)',
                        )
                      : _chatDetailText(
                          pageContext,
                          zhCN: '$duration 分钟',
                          zhTW: '$duration 分鐘',
                          en: '$duration minute(s)',
                        );
          ScaffoldMessenger.of(
            pageContext,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _chatDetailText(
                  pageContext,
                  zhCN: '已禁言 $durationText',
                  zhTW: '已禁言 $durationText',
                  en: 'Muted for $durationText',
                ),
              ),
            ),
          );
        }
      } else if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              result.message ??
                  _chatDetailText(
                    pageContext,
                    zhCN: '操作失败',
                    zhTW: '操作失敗',
                    en: 'Action failed',
                  ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              _chatDetailText(
                pageContext,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Action failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
