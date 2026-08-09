// 文件用途：实现 FolderEditSheet 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 FolderEditSheet 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/chat_provider.dart';
import '../providers/folder_provider.dart';

String _folderEditText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：folder edit page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 文件夹编辑弹窗
class FolderEditSheet extends ConsumerStatefulWidget {
  const FolderEditSheet({super.key});

  @override
  ConsumerState<FolderEditSheet> createState() => _FolderEditSheetState();
}

class _FolderEditSheetState extends ConsumerState<FolderEditSheet> {
  bool _isReordering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folderState = ref.watch(folderProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color:
                isDark ? AppColors.darkBackground : AppColors.lightBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 拖动条
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题栏
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        _folderEditText(
                          context,
                          zhCN: '完成',
                          zhTW: '完成',
                          en: 'Done',
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _folderEditText(
                          context,
                          zhCN: '编辑文件夹',
                          zhTW: '編輯資料夾',
                          en: 'Edit Folder',
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showCreateFolder(context),
                      child: Text(
                        _folderEditText(
                          context,
                          zhCN: '添加',
                          zhTW: '新增',
                          en: 'Add',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 提示文字
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _folderEditText(
                    context,
                    zhCN: '创建文件夹来整理聊天。长按并拖动来重新排序。',
                    zhTW: '建立資料夾來整理聊天。長按並拖動即可重新排序。',
                    en: 'Create folders to organize chats. Long press and drag to reorder.',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ),

              // 文件夹列表
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scrollController,
                  onReorder: (oldIndex, newIndex) {
                    HapticFeedback.mediumImpact();
                    if (newIndex > oldIndex) newIndex--;
                    ref
                        .read(folderProvider.notifier)
                        .reorderFolders(oldIndex, newIndex);
                  },
                  itemCount: folderState.folders.length,
                  itemBuilder: (context, index) {
                    final folder = folderState.folders[index];
                    return _FolderListItem(
                      key: ValueKey(folder.id),
                      folder: folder,
                      onEdit: () => _showEditFolder(context, folder),
                      onDelete: folder.isDefault
                          ? null
                          : () => _confirmDelete(context, folder),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateFolder(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _FolderDialog(
        title: _folderEditText(
          context,
          zhCN: '新建文件夹',
          zhTW: '新增資料夾',
          en: 'New Folder',
        ),
        onSave: (name, types, showUnreadOnly) {
          final folder = ChatFolder(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            includeTypes: types.isNotEmpty ? types : null,
            showUnreadOnly: showUnreadOnly,
          );
          ref.read(folderProvider.notifier).addFolder(folder);
        },
      ),
    );
  }

  void _showEditFolder(BuildContext context, ChatFolder folder) {
    showDialog(
      context: context,
      builder: (context) => _FolderDialog(
        title: _folderEditText(
          context,
          zhCN: '编辑文件夹',
          zhTW: '編輯資料夾',
          en: 'Edit Folder',
        ),
        initialName: folder.name,
        initialTypes: folder.includeTypes?.toSet() ?? {},
        initialShowUnreadOnly: folder.showUnreadOnly,
        onSave: (name, types, showUnreadOnly) {
          final updatedFolder = folder.copyWith(
            name: name,
            includeTypes: types.isNotEmpty ? types : null,
            showUnreadOnly: showUnreadOnly,
          );
          ref.read(folderProvider.notifier).updateFolder(updatedFolder);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, ChatFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _folderEditText(
            context,
            zhCN: '删除文件夹',
            zhTW: '刪除資料夾',
            en: 'Delete Folder',
          ),
        ),
        content: Text(
          _folderEditText(
            context,
            zhCN: '确定要删除"${folder.name}"文件夹吗？聊天不会被删除。',
            zhTW: '確定要刪除「${folder.name}」資料夾嗎？聊天不會被刪除。',
            en: 'Delete "${folder.name}"? Chats will not be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _folderEditText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              ref.read(folderProvider.notifier).deleteFolder(folder.id);
              Navigator.pop(context);
            },
            child: Text(
              _folderEditText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文件夹列表项
class _FolderListItem extends StatelessWidget {
  final ChatFolder folder;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _FolderListItem({
    super.key,
    required this.folder,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryWithOpacity(context, 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.folder_outlined,
            color: AppColors.primaryFor(context),
          ),
        ),
        title: Text(
          folder.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        subtitle: Text(
          _getSubtitle(context),
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondaryFor(context),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!folder.isDefault) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                  onPressed: onDelete,
                ),
            ],
            const Icon(Icons.drag_handle),
          ],
        ),
      ),
    );
  }

  String _getSubtitle(BuildContext context) {
    if (folder.isDefault) {
      return _folderEditText(
        context,
        zhCN: '所有聊天',
        zhTW: '所有聊天',
        en: 'All Chats',
      );
    }

    final parts = <String>[];

    if (folder.includeTypes?.isNotEmpty == true) {
      final typeNames = folder.includeTypes!.map((t) {
        switch (t) {
          case ChatItemType.private:
            return _folderEditText(
              context,
              zhCN: '私聊',
              zhTW: '私聊',
              en: 'Private',
            );
          case ChatItemType.group:
            return _folderEditText(
              context,
              zhCN: '群组',
              zhTW: '群組',
              en: 'Group',
            );
          case ChatItemType.channel:
            return _folderEditText(
              context,
              zhCN: '频道',
              zhTW: '頻道',
              en: 'Channel',
            );
        }
      }).join('、');
      parts.add(typeNames);
    }

    if (folder.showUnreadOnly) {
      parts.add(
        _folderEditText(
          context,
          zhCN: '仅未读',
          zhTW: '僅未讀',
          en: 'Unread Only',
        ),
      );
    }

    return parts.isEmpty
        ? _folderEditText(
            context,
            zhCN: '自定义',
            zhTW: '自訂',
            en: 'Custom',
          )
        : parts.join(' · ');
  }
}

/// 创建/编辑文件夹对话框
class _FolderDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final Set<ChatItemType>? initialTypes;
  final bool initialShowUnreadOnly;
  final Function(String name, List<ChatItemType> types, bool showUnreadOnly)
      onSave;

  const _FolderDialog({
    required this.title,
    this.initialName,
    this.initialTypes,
    this.initialShowUnreadOnly = false,
    required this.onSave,
  });

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late TextEditingController _controller;
  late Set<ChatItemType> _types;
  late bool _showUnreadOnly;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _types = widget.initialTypes?.toSet() ?? {};
    _showUnreadOnly = widget.initialShowUnreadOnly;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: _folderEditText(
                  context,
                  zhCN: '文件夹名称',
                  zhTW: '資料夾名稱',
                  en: 'Folder Name',
                ),
                hintText: _folderEditText(
                  context,
                  zhCN: '输入名称',
                  zhTW: '輸入名稱',
                  en: 'Enter a name',
                ),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Text(
              _folderEditText(
                context,
                zhCN: '包含的聊天类型',
                zhTW: '包含的聊天類型',
                en: 'Included Chat Types',
              ),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip(
                  _folderEditText(
                    context,
                    zhCN: '私聊',
                    zhTW: '私聊',
                    en: 'Private',
                  ),
                  ChatItemType.private,
                ),
                _buildTypeChip(
                  _folderEditText(
                    context,
                    zhCN: '群组',
                    zhTW: '群組',
                    en: 'Group',
                  ),
                  ChatItemType.group,
                ),
                _buildTypeChip(
                  _folderEditText(
                    context,
                    zhCN: '频道',
                    zhTW: '頻道',
                    en: 'Channel',
                  ),
                  ChatItemType.channel,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(
                _folderEditText(
                  context,
                  zhCN: '只显示未读',
                  zhTW: '只顯示未讀',
                  en: 'Show Unread Only',
                ),
              ),
              value: _showUnreadOnly,
              onChanged: (value) => setState(() => _showUnreadOnly = value),
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primaryFor(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _folderEditText(
              context,
              zhCN: '取消',
              zhTW: '取消',
              en: 'Cancel',
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            if (_controller.text.isNotEmpty) {
              widget.onSave(_controller.text, _types.toList(), _showUnreadOnly);
              Navigator.pop(context);
            }
          },
          child: Text(
            _folderEditText(
              context,
              zhCN: '保存',
              zhTW: '儲存',
              en: 'Save',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String label, ChatItemType type) {
    final selected = _types.contains(type);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        setState(() {
          if (value) {
            _types.add(type);
          } else {
            _types.remove(type);
          }
        });
      },
      selectedColor: AppColors.primaryWithOpacity(context, 0.2),
      checkmarkColor: AppColors.primaryFor(context),
    );
  }
}
