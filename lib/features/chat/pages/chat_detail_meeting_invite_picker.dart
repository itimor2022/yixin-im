// 文件用途：实现 _ChatDetailMeetingInvitePicker 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMeetingInvitePicker 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail meeting invite picker 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMeetingInvitePicker on _ChatDetailPageState {
  // 流程逻辑：`_buildSheetTag` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Widget _buildSheetTag({required String text, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : const Color(0xFF3557C4),
        ),
      ),
    );
  }

  Future<List<String>?> _showMeetingInvitePickerCompact() async {
    List<api.ChatMember> members;
    try {
      members = await ref.read(chatMembersProvider(widget.chatId).future);
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              zhCN: '加载群成员失败',
              zhTW: '載入群成員失敗',
              en: 'Failed to load group members',
            ),
          ),
        ),
      );
      return null;
    }
    if (!mounted) return null;

    final currentUserId = ref.read(authServiceProvider).user?.uuid ?? '';
    final candidates = members
        .where((m) => m.userId.isNotEmpty && m.userId != currentUserId)
        .toList();
    if (candidates.isEmpty) {
      return <String>[];
    }

    final selectedIds = <String>{};
    final searchController = TextEditingController();
    String keyword = '';

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = keyword.trim().toLowerCase();
            final filtered = query.isEmpty
                ? candidates
                : candidates.where((m) {
                    final displayName = m.displayName.toLowerCase();
                    final username = m.username.toLowerCase();
                    final userId = m.userId.toLowerCase();
                    return displayName.contains(query) ||
                        username.contains(query) ||
                        userId.contains(query);
                  }).toList();

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.82,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedText(
                        zhCN: '邀请群成员',
                        zhTW: '邀請群成員',
                        en: 'Invite Group Members',
                      ),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _localizedText(
                        zhCN: '从群成员里选择需要加入的人',
                        zhTW: '從群成員中選擇需要加入的人',
                        en: 'Choose members to invite',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: _localizedText(
                          zhCN: '搜索昵称 / 用户名 / UUID',
                          zhTW: '搜尋暱稱 / 使用者名稱 / UUID',
                          en: 'Search nickname / username / UUID',
                        ),
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1F2937)
                            : const Color(0xFFF6F8FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          keyword = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSheetTag(
                          text: _localizedText(
                            zhCN: '可选 ${candidates.length} 人',
                            zhTW: '可選 ${candidates.length} 人',
                            en: '${candidates.length} available',
                          ),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildSheetTag(
                          text: _localizedText(
                            zhCN: '已选 ${selectedIds.length} 人',
                            zhTW: '已選 ${selectedIds.length} 人',
                            en: '${selectedIds.length} selected',
                          ),
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _localizedText(
                                  zhCN: '未找到可邀请成员',
                                  zhTW: '未找到可邀請成員',
                                  en: 'No members available to invite',
                                ),
                                style: TextStyle(
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final member = filtered[index];
                                final checked = selectedIds.contains(
                                  member.userId,
                                );
                                return InkWell(
                                  onTap: () {
                                    setSheetState(() {
                                      if (checked) {
                                        selectedIds.remove(member.userId);
                                      } else {
                                        selectedIds.add(member.userId);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: checked
                                          ? (isDark
                                              ? const Color(0xFF1E2A45)
                                              : const Color(0xFFEAF1FF))
                                          : (isDark
                                              ? const Color(0xFF1F2937)
                                              : const Color(0xFFF7F9FC)),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: checked
                                            ? const Color(0xFF2E5BFF)
                                            : (isDark
                                                ? const Color(0xFF334155)
                                                : const Color(0xFFE2E8F0)),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        AvatarWidget(
                                          avatar: member.avatar,
                                          name: member.displayName,
                                          size: 34,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName.isNotEmpty
                                                    ? member.displayName
                                                    : member.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                member.username.isNotEmpty
                                                    ? member.username
                                                    : member.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Checkbox(
                                          value: checked,
                                          onChanged: (value) {
                                            setSheetState(() {
                                              if (value == true) {
                                                selectedIds.add(member.userId);
                                              } else {
                                                selectedIds.remove(
                                                  member.userId,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(null),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF5A68C7),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(
                                _localizedText(
                                  zhCN: '取消',
                                  zhTW: '取消',
                                  en: 'Cancel',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(<String>[]),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF5A68C7),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(
                                _localizedText(
                                  zhCN: '跳过',
                                  zhTW: '跳過',
                                  en: 'Skip',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: () => Navigator.of(
                                sheetContext,
                              ).pop(selectedIds.toList()),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: Text(
                                _localizedText(
                                  zhCN: '发起',
                                  zhTW: '發起',
                                  en: 'Start',
                                ),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return result;
  }
}
