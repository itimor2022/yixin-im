// 文件用途：实现 _UserInfoSheet 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _UserInfoSheet 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail info sheets 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _UserInfoSheet extends StatelessWidget {
  final String name;
  final String? avatar;
  final String userId;

  const _UserInfoSheet({required this.name, this.avatar, required this.userId});

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              child: AvatarWidget(
                name: name,
                avatar: avatar,
                userId: userId,
                size: 80,
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
                _chatDetailText(
                  context,
                  zhCN: '在线',
                  zhTW: '在線',
                  en: 'Online',
                ),
                style: TextStyle(fontSize: 14, color: AppColors.online),
              ),
            ),
            const SizedBox(height: 24),
            _InfoRow(icon: Icons.phone, title: '+86 138****8888'),
            _InfoRow(icon: Icons.alternate_email, title: '@$userId'),
            _InfoRow(
              icon: Icons.info_outline,
              title: _chatDetailText(
                context,
                zhCN: '这个人很懒，什么都没写',
                zhTW: '這個人很懶，什麼都沒寫',
                en: 'This user has not added a bio',
              ),
            ),
            const Divider(height: 32),
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
              icon: Icons.block_outlined,
              title: _chatDetailText(
                context,
                zhCN: '屏蔽用户',
                zhTW: '封鎖使用者',
                en: 'Block User',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shared info sheet rows

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;

  const _InfoRow({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryFor(context)),
      title: Text(title),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trailingColor = AppColors.textSecondaryFor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151D2D) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    AppColors.primaryWithOpacity(context, isDark ? 0.18 : 0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryWithOpacity(
                      context, isDark ? 0.10 : 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryWithOpacity(
                        context,
                        isDark ? 0.16 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: AppColors.primaryFor(context), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Flexible(
                      child: Text(
                        trailing!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: trailingColor,
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: trailingColor,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
