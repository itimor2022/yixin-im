// 文件用途：实现 _ChatDetailDesktopFileActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailDesktopFileActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail desktop file actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailDesktopFileActions on _ChatDetailPageState {
  // 流程逻辑：`_handleSaveAs` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  /// 桌面端：另存为
  Future<void> _handleSaveAs(MessageItem message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar(
          _localizedText(
            zhCN: '无法保存：文件不存在',
            zhTW: '無法儲存：找不到檔案',
            en: 'Cannot save: file not found',
          ),
        );
        return;
      }

      String defaultFileName;
      switch (message.type) {
        case MessageItemType.image:
          defaultFileName =
              'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
          break;
        case MessageItemType.video:
          defaultFileName =
              'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
          break;
        case MessageItemType.voice:
          defaultFileName =
              'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
          break;
        case MessageItemType.file:
          defaultFileName = message.fileName ??
              'file_${DateTime.now().millisecondsSinceEpoch}';
          break;
        default:
          defaultFileName = 'file_${DateTime.now().millisecondsSinceEpoch}';
      }

      final result = await FilePicker.platform.saveFile(
        dialogTitle: _translate(context, 'save_file', 'Save File'),
        fileName: defaultFileName,
      );

      if (result == null) return;

      final fullUrl = _getFullMediaUrl(mediaUrl);
      final dio = Dio();
      await dio.download(fullUrl, result);

      _showSnackBar(AppLocalizations.of(context).fileSaved);
    } catch (e) {
      debugPrint('[ChatDetail] Save as error: $e');
      _showSnackBar(
        _localizedText(
          zhCN: '保存失败，请重试',
          zhTW: '儲存失敗，請重試',
          en: 'Save failed. Please try again.',
        ),
      );
    }
  }

  /// 桌面端：在 Finder/资源管理器中显示
  Future<void> _handleShowInFolder(MessageItem message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar(
          _translate(
            context,
            'file_not_found',
            _localizedText(
              zhCN: '文件不存在',
              zhTW: '檔案不存在',
              en: 'File not found',
            ),
          ),
        );
        return;
      }

      final cacheDir = await _getMediaCacheDir();
      final fileName = Uri.parse(mediaUrl).pathSegments.lastOrNull ?? 'file';
      final localFile = File('$cacheDir/$fileName');

      if (await localFile.exists()) {
        if (Platform.isMacOS) {
          await Process.run('open', ['-R', localFile.path]);
        } else if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', localFile.path]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [localFile.parent.path]);
        }
      } else {
        _showSnackBar(
          _translate(
            context,
            'downloading_file',
            _localizedText(
              zhCN: '正在下载文件...',
              zhTW: '正在下載檔案...',
              en: 'Downloading file...',
            ),
          ),
        );

        final fullUrl = _getFullMediaUrl(mediaUrl);
        final dio = Dio();
        await dio.download(fullUrl, localFile.path);

        if (Platform.isMacOS) {
          await Process.run('open', ['-R', localFile.path]);
        } else if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', localFile.path]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [localFile.parent.path]);
        }
      }
    } catch (e) {
      debugPrint('[ChatDetail] Show in folder error: $e');
      _showSnackBar(
        _localizedText(
          zhCN: '操作失败',
          zhTW: '操作失敗',
          en: 'Operation failed. Please try again.',
        ),
      );
    }
  }

  /// 桌面端：使用默认应用打开文件
  Future<void> _handleOpenFile(MessageItem message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar(_translate(context, 'file_not_found', 'File not found'));
        return;
      }

      final cacheDir = await _getMediaCacheDir();
      final fileName = message.fileName ??
          Uri.parse(mediaUrl).pathSegments.lastOrNull ??
          'file';
      final localFile = File('$cacheDir/$fileName');

      if (!await localFile.exists()) {
        _showSnackBar(
          _translate(context, 'downloading_file', 'Downloading file...'),
        );

        final fullUrl = _getFullMediaUrl(mediaUrl);
        final dio = Dio();
        await dio.download(fullUrl, localFile.path);
      }

      if (Platform.isMacOS) {
        await Process.run('open', [localFile.path]);
      } else if (Platform.isWindows) {
        await Process.run('start', ['', localFile.path], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [localFile.path]);
      }
    } catch (e) {
      debugPrint('[ChatDetail] Open file error: $e');
      _showSnackBar(
        _localizedText(
          zhCN: '打开失败，请重试',
          zhTW: '打開失敗，請重試',
          en: 'Open failed. Please try again.',
        ),
      );
    }
  }

  Future<String> _getMediaCacheDir() async {
    final accountId = ref.read(currentAccountIdProvider);
    if (accountId.isEmpty) {
      throw StateError('Cannot create a media cache without an active account');
    }
    final cacheDir = await ChatMediaCacheManager.accountPrivateDirectory(
      accountId,
      'desktop_downloads',
    );
    return cacheDir.path;
  }

  String _getFullMediaUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return ApiConfig.getMediaUrl(url);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
