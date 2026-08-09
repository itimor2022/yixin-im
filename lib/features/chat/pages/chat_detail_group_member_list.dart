// 文件用途：实现 _ChatDetailGroupMemberList 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailGroupMemberList 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail group member list 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailGroupMemberList on _GroupInfoSheet {
  // 流程逻辑：`_buildGroupMemberList` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Widget _buildGroupMemberList(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    AsyncValue<dynamic> chatDetailAsync,
  ) {
    return ref.watch(chatMembersProvider(groupId)).when(
          data: (members) {
            final myRole = chatDetailAsync.value?.myRole ?? 0;
            final canOpenMemberProfile =
                !(chatDetailAsync.value?.memberProtection ?? false) ||
                    myRole >= 2;
            return Column(
              children: members
                  .map(
                    (member) => ListTile(
                      leading: Stack(
                        children: [
                          AvatarWidget(
                            name: member.displayName,
                            avatar: member.avatar,
                            userId: member.userId,
                            size: 40,
                          ),
                          if (member.isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBackground
                                        : AppColors.lightBackground,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: ColoredNameWidget(
                              name: member.displayName,
                              nicknameColor: member.nicknameColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              defaultColor:
                                  isDark ? Colors.white : Colors.black87,
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
                          if (member.vipVisible && member.isMuted)
                            const SizedBox(width: 5),
                          if (member.isMuted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                member.muteStatusText.isNotEmpty
                                    ? member.muteStatusText
                                    : _chatDetailText(
                                        context,
                                        zhCN: '禁言中',
                                        zhTW: '禁言中',
                                        en: 'Muted',
                                      ),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        member.roleName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: member.role >= 2
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: member.role >= 2
                              ? AppColors.primaryFor(context)
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                      // 管理员和群主可以对成员进行操作
                      trailing: myRole >= 1 && member.role < myRole
                          ? IconButton(
                              icon: Icon(
                                member.isMuted
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                                color: member.isMuted
                                    ? AppColors.success
                                    : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () => this._showMuteOptions(
                                context,
                                ref,
                                groupId,
                                member,
                                myRole,
                              ),
                            )
                          : null,
                      onLongPress: myRole >= 1 && member.role < myRole
                          ? () => this._showMuteOptions(
                                context,
                                ref,
                                groupId,
                                member,
                                myRole,
                              )
                          : null,
                      onTap: canOpenMemberProfile
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => UserProfilePage(
                                    userId: member.userId,
                                    name: member.displayName,
                                    avatar: member.avatar,
                                    chatId: groupId,
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                  )
                  .toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                _chatDetailText(
                  context,
                  zhCN: '加载失败',
                  zhTW: '載入失敗',
                  en: 'Load failed',
                ),
              ),
            ),
          ),
        );
  }
}
