// 文件用途：实现 _ChatDetailEditDeleteActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailEditDeleteActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail edit delete actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailEditDeleteActions on _ChatDetailPageState {
  // 流程逻辑：`_handleEdit` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  /// 处理编辑消息
  void _handleEdit(MessageItem message) {
    if (!_ensureChatWritable()) return;
    if (message.type == MessageItemType.image && !message.burnAfterRead) {
      unawaited(_handleEditImage(message));
      return;
    }

    if (message.type != MessageItemType.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'only_text_messages_can_be_edited',
              _localizedText(
                zhCN: '只能编辑文本消息',
                zhTW: '只能編輯文字消息',
                en: 'Only text messages can be edited',
              ),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final diff = DateTime.now().difference(message.createdAt);
    if (diff.inHours > 48) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'edit_time_limit_exceeded',
              _localizedText(
                zhCN: '超过48小时的消息无法编辑',
                zhTW: '超過 48 小時的消息無法編輯',
                en: 'Messages older than 48 hours cannot be edited',
              ),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    GlobalHaptics.selection();
    _updateState(() {
      _editingMessage = message;
      _originalEditContent = message.content;
      _replyToMessage = null;
      _inputController.text = message.content;
    });
    _inputFocusNode.requestFocus();
  }

  /// 取消编辑
  Future<void> _handleEditImage(MessageItem message) async {
    if (!_ensureCanSendMedia()) return;
    if (message.isDeleted || !message.isOutgoing) return;

    try {
      if (PlatformUtils.isPhysicalDesktop) {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.custom,
          allowedExtensions: const [
            'jpg',
            'jpeg',
            'png',
            'gif',
            'webp',
            'heic',
            'heif',
          ],
        );
        final picked =
            result?.files.isNotEmpty == true ? result!.files.first : null;
        final path = picked?.path;
        if (path == null || path.isEmpty) return;

        final dimensions = await _decodeImageDimensionsFromFile(path);
        final ok = await ref
            .read(messageListProvider(widget.chatId).notifier)
            .editImageMessageFromPath(
              message.id,
              path,
              width: dimensions?.width,
              height: dimensions?.height,
            );
        if (!mounted) return;
        _showEditImageResult(ok);
        return;
      }

      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image == null) return;

      final path = image.path;
      var canUsePath = false;
      if (path.isNotEmpty) {
        final file = File(path);
        canUsePath = await file.exists();
      }

      final bytes = canUsePath
          ? await File(path).readAsBytes()
          : await image.readAsBytes();
      final dimensions = await _decodeImageDimensions(bytes);
      final notifier = ref.read(messageListProvider(widget.chatId).notifier);
      final ok = canUsePath
          ? await notifier.editImageMessageFromPath(
              message.id,
              path,
              width: dimensions?.width,
              height: dimensions?.height,
            )
          : await notifier.editImageMessageFromBytes(
              message.id,
              bytes,
              ext: image.name.split('.').last,
              width: dimensions?.width,
              height: dimensions?.height,
            );
      if (!mounted) return;
      _showEditImageResult(ok);
    } catch (e, st) {
      debugPrint('[ImageEdit] Pick/edit image failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 8);
      if (!mounted) return;
      _showEditImageResult(false);
    }
  }

  Future<({int width, int height})?> _decodeImageDimensionsFromFile(
    String path,
  ) async {
    try {
      return _decodeImageDimensions(await File(path).readAsBytes());
    } catch (e) {
      debugPrint('[ImageEdit] Read selected image failed: $e');
      return null;
    }
  }

  Future<({int width, int height})?> _decodeImageDimensions(
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return null;
    try {
      final decoded = await decodeImageFromList(bytes);
      return (width: decoded.width, height: decoded.height);
    } catch (e) {
      debugPrint('[ImageEdit] Decode selected image failed: $e');
      return null;
    }
  }

  void _showEditImageResult(bool ok) {
    if (ok) {
      AppSnackBar.success(
        context,
        _localizedText(zhCN: '图片已编辑', zhTW: '圖片已編輯', en: 'Image edited'),
      );
      return;
    }
    AppSnackBar.error(
      context,
      _localizedText(
          zhCN: '图片编辑失败', zhTW: '圖片編輯失敗', en: 'Failed to edit image'),
    );
  }

  void _cancelEdit() {
    _updateState(() {
      _editingMessage = null;
      _originalEditContent = null;
      _inputController.clear();
    });
  }

  /// 处理删除消息 - 直接删除并播放破碎动画
  void _handleDelete(MessageItem message) {
    _playDeleteAnimation(message);
  }

  /// 播放删除破碎动画
  void _playDeleteAnimation(MessageItem message) {
    GlobalHaptics.medium();

    final screenSize = MediaQuery.of(context).size;
    final center = Offset(screenSize.width / 2, screenSize.height / 2);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => _MessageDeleteAnimation(
        screenCenter: center,
        onComplete: () {
          overlayEntry.remove();
          _activeOverlays.remove(overlayEntry);
        },
      ),
    );

    _activeOverlays.add(overlayEntry);
    Overlay.of(context).insert(overlayEntry);

    _deleteMessageLocally(message);
  }

  /// 本地删除消息（持久化删除）
  Future<void> _deleteMessageLocally(MessageItem message) async {
    GlobalHaptics.medium();
    await ref
        .read(messageListProvider(widget.chatId).notifier)
        .deleteMessage(message.id);
  }

  /// 进入多选模式
  void _enterSelectionMode(MessageItem message) {
    GlobalHaptics.selection();
    _updateState(() {
      _isSelectionMode = true;
      _selectedMessageIds.add(message.id);
    });
  }

  /// 退出多选模式
  void _exitSelectionMode() {
    GlobalHaptics.selection();
    _updateState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  /// 切换消息选中状态
  void _toggleMessageSelection(String messageId) {
    GlobalHaptics.selection();
    _updateState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  /// 删除选中的消息
  void _deleteSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _selectedMessageIds.length;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * anim1.value,
                    sigmaY: 8 * anim1.value,
                  ),
                  child: Container(
                    color: Colors.black.withOpacity(0.3 * anim1.value),
                  ),
                ),
              ),
            ),
            Center(
              child: Transform.scale(
                scale: Curves.easeOutBack.transform(anim1.value),
                child: Opacity(
                  opacity: anim1.value,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.12)
                                : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.5),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.delete_sweep_rounded,
                                  color: AppColors.error,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _translate(
                                  context,
                                  'delete_selected_messages',
                                  _localizedText(
                                    zhCN: '删除 {count} 条消息',
                                    zhTW: '刪除 {count} 條消息',
                                    en: 'Delete {count} messages',
                                  ),
                                  {'count': '$count'},
                                ),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _translate(
                                  context,
                                  'delete_selected_messages_desc',
                                  _localizedText(
                                    zhCN: '这些消息将从您的聊天记录中删除，且无法恢复',
                                    zhTW: '這些消息將從你的聊天記錄中刪除，且無法恢復',
                                    en: 'These messages will be deleted from your chat history and cannot be recovered',
                                  ),
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        backgroundColor: isDark
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.black.withOpacity(0.05),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context).cancel,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () async {
                                        Navigator.pop(context);
                                        GlobalHaptics.medium();
                                        final idsToDelete =
                                            _selectedMessageIds.toList();
                                        _exitSelectionMode();
                                        for (final id in idsToDelete) {
                                          if (!mounted) break;
                                          await ref
                                              .read(
                                                messageListProvider(
                                                  widget.chatId,
                                                ).notifier,
                                              )
                                              .deleteMessage(id);
                                        }
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        backgroundColor: AppColors.error,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context).delete,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
