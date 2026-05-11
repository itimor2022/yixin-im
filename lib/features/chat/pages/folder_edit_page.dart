import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/chat_provider.dart';
import '../providers/folder_provider.dart';

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
            color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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
                  color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
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
                      child: const Text('完成'),
                    ),
                    const Expanded(
                      child: Text(
                        '编辑文件夹',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showCreateFolder(context),
                      child: const Text('添加'),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // 提示文字
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '创建文件夹来整理聊天。长按并拖动来重新排序。',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
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
                    ref.read(folderProvider.notifier).reorderFolders(oldIndex, newIndex);
                  },
                  itemCount: folderState.folders.length,
                  itemBuilder: (context, index) {
                    final folder = folderState.folders[index];
                    return _FolderListItem(
                      key: ValueKey(folder.id),
                      folder: folder,
                      onEdit: () => _showEditFolder(context, folder),
                      onDelete: folder.isDefault ? null : () => _confirmDelete(context, folder),
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
        title: '新建文件夹',
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
        title: '编辑文件夹',
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
        title: const Text('删除文件夹'),
        content: Text('确定要删除"${folder.name}"文件夹吗？聊天不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(folderProvider.notifier).deleteFolder(folder.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
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
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.folder_outlined,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          folder.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        subtitle: Text(
          _getSubtitle(),
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
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
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                  onPressed: onDelete,
                ),
            ],
            const Icon(Icons.drag_handle),
          ],
        ),
      ),
    );
  }

  String _getSubtitle() {
    if (folder.isDefault) {
      return '所有聊天';
    }
    
    final parts = <String>[];
    
    if (folder.includeTypes?.isNotEmpty == true) {
      final typeNames = folder.includeTypes!.map((t) {
        switch (t) {
          case ChatItemType.private:
            return '私聊';
          case ChatItemType.group:
            return '群组';
          case ChatItemType.channel:
            return '频道';
        }
      }).join('、');
      parts.add(typeNames);
    }
    
    if (folder.showUnreadOnly) {
      parts.add('仅未读');
    }
    
    return parts.isEmpty ? '自定义' : parts.join(' · ');
  }
}

/// 创建/编辑文件夹对话框
class _FolderDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final Set<ChatItemType>? initialTypes;
  final bool initialShowUnreadOnly;
  final Function(String name, List<ChatItemType> types, bool showUnreadOnly) onSave;

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
              decoration: const InputDecoration(
                labelText: '文件夹名称',
                hintText: '输入名称',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            const Text('包含的聊天类型', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('私聊', ChatItemType.private),
                _buildTypeChip('群组', ChatItemType.group),
                _buildTypeChip('频道', ChatItemType.channel),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('只显示未读'),
              value: _showUnreadOnly,
              onChanged: (value) => setState(() => _showUnreadOnly = value),
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (_controller.text.isNotEmpty) {
              widget.onSave(_controller.text, _types.toList(), _showUnreadOnly);
              Navigator.pop(context);
            }
          },
          child: const Text('保存'),
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
      selectedColor: AppColors.primary.withOpacity(0.2),
      checkmarkColor: AppColors.primary,
    );
  }
}
