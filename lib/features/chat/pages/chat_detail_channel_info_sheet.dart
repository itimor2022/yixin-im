// 文件用途：实现 _ChannelInfoSheet 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChannelInfoSheet 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// Channel info sheet

// 关键声明：chat detail channel info sheet 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _ChannelInfoSheet extends ConsumerWidget {
  final String name;
  final String? avatar;
  final String channelId;

  const _ChannelInfoSheet({
    required this.name,
    this.avatar,
    required this.channelId,
  });

  String _formatSubscriberCount(BuildContext context, int count) {
    if (count >= 10000) {
      return AppLocalizations.of(context).language == AppLanguage.en
          ? '${(count / 1000).toStringAsFixed(1)}k'
          : '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '$count';
  }

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatDetailAsync = ref.watch(chatDetailProvider(channelId));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Stack(
                children: [
                  AvatarWidget(
                    name: name,
                    avatar: avatar,
                    userId: channelId,
                    size: 80,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkBackground
                            : AppColors.lightBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.verified,
                        size: 24,
                        color: AppColors.primaryFor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Center(
              child: Text(
                chatDetailAsync.when(
                  data: (chat) => chat != null
                      ? _chatDetailText(
                          context,
                          zhCN:
                              '${_formatSubscriberCount(context, chat.memberCount)} · 频道',
                          zhTW:
                              '${_formatSubscriberCount(context, chat.memberCount)} · 頻道',
                          en: '${_formatSubscriberCount(context, chat.memberCount)} subscribers · Channel',
                        )
                      : _chatDetailText(
                          context,
                          zhCN: '频道',
                          zhTW: '頻道',
                          en: 'Channel',
                        ),
                  loading: () => _chatDetailText(
                    context,
                    zhCN: '加载中...',
                    zhTW: '載入中...',
                    en: 'Loading...',
                  ),
                  error: (_, __) => _chatDetailText(
                    context,
                    zhCN: '频道',
                    zhTW: '頻道',
                    en: 'Channel',
                  ),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),

            // 显示简介
            chatDetailAsync.when(
              data: (chat) {
                if (chat != null &&
                    chat.description != null &&
                    chat.description!.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _chatDetailText(
                              context,
                              zhCN: '简介',
                              zhTW: '簡介',
                              en: 'About',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryFor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chat.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimaryFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 16);
              },
              loading: () => const SizedBox(height: 16),
              error: (_, __) => const SizedBox(height: 16),
            ),

            // 频道号
            chatDetailAsync.when(
              data: (chat) {
                if (chat != null &&
                    chat.username != null &&
                    chat.username!.isNotEmpty) {
                  return _ActionRow(
                    icon: Icons.alternate_email,
                    title: _chatDetailText(
                      context,
                      zhCN: '频道号',
                      zhTW: '頻道號',
                      en: 'Channel ID',
                    ),
                    trailing: '@${chat.username}',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: '@${chat.username}'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _chatDetailText(
                              context,
                              zhCN: '频道号已复制',
                              zhTW: '頻道號已複製',
                              en: 'Channel ID copied',
                            ),
                          ),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            _ActionRow(
              icon: Icons.notifications_outlined,
              title: _chatDetailText(
                context,
                zhCN: '通知',
                zhTW: '通知',
                en: 'Notifications',
              ),
              trailing: _chatDetailText(
                context,
                zhCN: '开启',
                zhTW: '開啟',
                en: 'On',
              ),
            ),
            _ActionRow(
              icon: Icons.share_outlined,
              title: _chatDetailText(
                context,
                zhCN: '分享频道',
                zhTW: '分享頻道',
                en: 'Share Channel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
