// 文件用途：实现 _ChatDetailMediaFileActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：从系统文件选择器取得文件，校验取消和大小状态后交给消息 Provider 上传并更新聊天列表预览。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media file actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaFileActions on _ChatDetailPageState {
  // 流程逻辑：`_pickVideo` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _pickVideo() async {
    if (!_ensureCanSendMedia()) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.video,
      withData: PlatformUtils.isWeb || PlatformUtils.isMobile,
    );

    if (result == null || result.files.isEmpty) return;

    final settings =
        await ref.read(systemSettingsServiceProvider).getSettings();
    final maxSize = settings.maxVideoSize * 1024 * 1024;
    var sentCount = 0;
    var unsupportedCount = 0;

    for (final file in result.files) {
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase().trim()
          : '';
      if (!this._isVideoExt(ext)) {
        unsupportedCount++;
        continue;
      }
      if (file.size > maxSize) {
        if (mounted) {
          _showFileSizeExceededDialog(
            file.size,
            maxSize,
            _localizedText(zhCN: '视频', zhTW: '影片', en: 'Video'),
          );
        }
        continue;
      }

      if (PlatformUtils.isWeb) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        await ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendVideoFromBytes(
              bytes,
              file.name,
              burnAfterRead: _activeBurnAfterRead,
              anonymous: _activeAnonymousSend,
            );
      } else {
        final path = file.path;
        if (path != null && path.isNotEmpty && await File(path).exists()) {
          await ref
              .read(messageListProvider(widget.chatId).notifier)
              .sendVideoMessage(
                path,
                burnAfterRead: _activeBurnAfterRead,
                anonymous: _activeAnonymousSend,
              );
        } else {
          final bytes = file.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          await ref
              .read(messageListProvider(widget.chatId).notifier)
              .sendVideoFromBytes(
                bytes,
                file.name,
                burnAfterRead: _activeBurnAfterRead,
                anonymous: _activeAnonymousSend,
              );
        }
      }

      sentCount++;
    }

    if (unsupportedCount > 0 && mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '有 $unsupportedCount 个视频格式暂不支持，请选择 mp4、mov、m4v、avi 或 webm',
          zhTW: '有 $unsupportedCount 個影片格式暫不支援，請選擇 mp4、mov、m4v、avi 或 webm',
          en: '$unsupportedCount videos were skipped. Use mp4, mov, m4v, avi, or webm.',
        ),
      );
    }

    if (sentCount > 0) {
      this._updateChatListPreview(
        sentCount > 1
            ? _localizedText(
                zhCN: '[$sentCount 个视频]',
                zhTW: '[$sentCount 個影片]',
                en: '[$sentCount videos]',
              )
            : _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
        type: MessageContentType.video,
      );
      this._scrollToBottom();
    }
  }

  Future<void> _pickFile() async {
    if (!_ensureCanSendMedia()) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: PlatformUtils.isWeb, // Web 必须读字节
    );

    if (result == null || result.files.isEmpty) return;

    final settings =
        await ref.read(systemSettingsServiceProvider).getSettings();
    final maxSize = settings.maxFileSize * 1024 * 1024;

    for (final file in result.files) {
      if (file.size > maxSize) {
        if (mounted) {
          _showFileSizeExceededDialog(
            file.size,
            maxSize,
            _localizedText(zhCN: '文件', zhTW: '檔案', en: 'File'),
          );
        }
        continue;
      }

      if (PlatformUtils.isWeb) {
        // Web：使用字节上传
        final bytes = file.bytes;
        if (bytes == null) continue;
        ref.read(messageListProvider(widget.chatId).notifier).sendFileFromBytes(
              bytes,
              file.name,
              burnAfterRead: _activeBurnAfterRead,
              anonymous: _activeAnonymousSend,
            );
      } else {
        if (file.path == null) continue;
        ref.read(messageListProvider(widget.chatId).notifier).sendFileMessage(
              file.path!,
              file.name,
              burnAfterRead: _activeBurnAfterRead,
              anonymous: _activeAnonymousSend,
            );
      }

      this._updateChatListPreview(
        _localizedText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]'),
        type: MessageContentType.file,
      );
    }
    this._scrollToBottom();
  }

  void _showFileSizeExceededDialog(
    int actualSize,
    int maxSize,
    String fileType,
  ) {
    final actualMB = (actualSize / 1024 / 1024).toStringAsFixed(1);
    final maxMB = (maxSize / 1024 / 1024).toStringAsFixed(0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayType = switch (fileType) {
      '视频' => _localizedText(zhCN: '视频', zhTW: '影片', en: 'video'),
      '圖片' => _localizedText(zhCN: '图片', zhTW: '圖片', en: 'image'),
      '图片' => _localizedText(zhCN: '图片', zhTW: '圖片', en: 'image'),
      '文件' => _localizedText(zhCN: '文件', zhTW: '檔案', en: 'file'),
      _ => fileType,
    };

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _localizedText(
                  zhCN: '$displayType过大',
                  zhTW: '$displayType過大',
                  en: 'This $displayType is too large',
                ),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _localizedText(
                  zhCN: '当前$displayType大小 ${actualMB}MB，超出限制 ${maxMB}MB',
                  zhTW: '目前$displayType大小 ${actualMB}MB，超出限制 ${maxMB}MB',
                  en: 'Current $displayType size is ${actualMB}MB, exceeding the ${maxMB}MB limit',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _localizedText(
                  zhCN: '请选择较小的$displayType或进行压缩后重试',
                  zhTW: '請選擇較小的$displayType或壓縮後重試',
                  en: 'Please choose a smaller $displayType or compress it and try again',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiaryFor(context),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryFor(context),
                    foregroundColor: AppColors.onPrimaryFor(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _localizedText(
                      zhCN: '我知道了',
                      zhTW: '我知道了',
                      en: 'Got it',
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
