// 文件用途：实现 _GroupInfoSheet 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _GroupInfoSheet 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// Group info sheet

// 关键声明：chat detail group info sheet 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _GroupInfoSheet extends ConsumerWidget {
  final String name;
  final String? avatar;
  final String groupId;

  const _GroupInfoSheet({
    required this.name,
    this.avatar,
    required this.groupId,
  });

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatDetailAsync = ref.watch(chatDetailProvider(groupId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? const [Color(0xFF1B2333), Color(0xFF111827)]
                        : const [Color(0xFFF8FAFF), Color(0xFFEEF4FF)],
                  ),
                ),
                child: chatDetailAsync.when(
                  data: (chat) {
                    final memberCount = chat?.memberCount ?? 0;
                    final onlineCount = chat?.onlineCount ?? 0;
                    final username = chat?.username;
                    final description = chat?.description;
                    return Column(
                      children: [
                        AvatarWidget(
                          name: name,
                          avatar: avatar,
                          userId: groupId,
                          size: 84,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            this._buildInfoChip(
                              icon: Icons.group_outlined,
                              label: _chatDetailText(
                                context,
                                zhCN: '$memberCount 位成员',
                                zhTW: '$memberCount 位成員',
                                en: '$memberCount members',
                              ),
                              isDark: isDark,
                            ),
                            if (onlineCount > 0)
                              this._buildInfoChip(
                                icon: Icons.wifi_tethering,
                                label: _chatDetailText(
                                  context,
                                  zhCN: '$onlineCount 位在线',
                                  zhTW: '$onlineCount 位在線',
                                  en: '$onlineCount online',
                                ),
                                isDark: isDark,
                                accentColor: AppColors.success,
                              ),
                            if (username != null && username.isNotEmpty)
                              this._buildInfoChip(
                                icon: Icons.alternate_email,
                                label: '@$username',
                                isDark: isDark,
                              ),
                          ],
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.04)
                                  : Colors.white.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(16),
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
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryFor(context),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.88)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () => Column(
                    children: [
                      AvatarWidget(
                        name: name,
                        avatar: avatar,
                        userId: groupId,
                        size: 84,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      this._buildInfoChip(
                        icon: Icons.hourglass_empty,
                        label: _chatDetailText(
                          context,
                          zhCN: '加载中...',
                          zhTW: '載入中...',
                          en: 'Loading...',
                        ),
                        isDark: isDark,
                      ),
                    ],
                  ),
                  error: (_, __) => Column(
                    children: [
                      AvatarWidget(
                        name: name,
                        avatar: avatar,
                        userId: groupId,
                        size: 84,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: this._buildStatCard(
                      title: _chatDetailText(
                        context,
                        zhCN: '成员',
                        zhTW: '成員',
                        en: 'Members',
                      ),
                      value: '${chatDetailAsync.value?.memberCount ?? 0}',
                      subtitle: _chatDetailText(
                        context,
                        zhCN: '群组规模',
                        zhTW: '群組規模',
                        en: 'Group size',
                      ),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: this._buildStatCard(
                      title: _chatDetailText(
                        context,
                        zhCN: '在线',
                        zhTW: '在線',
                        en: 'Online',
                      ),
                      value: '${chatDetailAsync.value?.onlineCount ?? 0}',
                      subtitle: _chatDetailText(
                        context,
                        zhCN: '实时活跃',
                        zhTW: '即時活躍',
                        en: 'Active now',
                      ),
                      isDark: isDark,
                      accentColor: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ActionRow(
              icon: Icons.person_add_outlined,
              title: _chatDetailText(
                context,
                zhCN: '添加成员',
                zhTW: '新增成員',
                en: 'Add Members',
              ),
            ),

            // 显示群组号
            chatDetailAsync.when(
              data: (chat) {
                if (chat != null &&
                    chat.username != null &&
                    chat.username!.isNotEmpty) {
                  return _ActionRow(
                    icon: Icons.alternate_email,
                    title: _chatDetailText(
                      context,
                      zhCN: '群组号',
                      zhTW: '群組號',
                      en: 'Group ID',
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
                              zhCN: '群组号已复制',
                              zhTW: '群組號已複製',
                              en: 'Group ID copied',
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
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFor(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _chatDetailText(
                      context,
                      zhCN: '成员',
                      zhTW: '成員',
                      en: 'Members',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryFor(context),
                    ),
                  ),
                ],
              ),
            ),

            // 显示真实成员列表
            this._buildGroupMemberList(context, ref, isDark, chatDetailAsync),
          ],
        ),
      ),
    );
  }

  // 禁言操作菜单
}
