// 文件用途：提供 _FileBubbleWidget 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _FileBubbleWidget，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble file 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 文件气泡组件 - 支持下载动画
class _FileBubbleWidget extends StatefulWidget {
  final MessageItem message;
  final Color bubbleColor;
  final Color textColor;
  final Color timeColor;
  final bool isOutgoing;
  final BorderRadius bubbleRadius;
  final Widget Function() buildStatusIcon;

  const _FileBubbleWidget({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.timeColor,
    required this.isOutgoing,
    required this.bubbleRadius,
    required this.buildStatusIcon,
  });

  @override
  State<_FileBubbleWidget> createState() => _FileBubbleWidgetState();
}

class _FileBubbleWidgetState extends State<_FileBubbleWidget>
    with SingleTickerProviderStateMixin {
  // 下载状态: 0=未下载, 1=下载中, 2=已下载
  int _downloadState = 0;
  double _progress = 0.0;
  String? _localPath;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _checkIfDownloaded();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkIfDownloaded() async {
    final accountId = await TokenStorage.getUserId();
    if (accountId == null || accountId.isEmpty) return;
    final dir = await ChatMediaCacheManager.accountPrivateDirectory(
      accountId,
      'downloads',
    );
    final fileName = widget.message.fileName ?? '';
    final filePath = '${dir.path}/$fileName';
    if (await File(filePath).exists()) {
      setState(() {
        _downloadState = 2;
        _localPath = filePath;
      });
    }
  }

  (IconData, Color) _getFileIconAndColor(String ext) {
    switch (ext) {
      case 'pdf':
        return (Icons.picture_as_pdf_rounded, const Color(0xFFE53935));
      case 'doc':
      case 'docx':
        return (Icons.description_rounded, const Color(0xFF2196F3));
      case 'xls':
      case 'xlsx':
        return (Icons.table_chart_rounded, const Color(0xFF4CAF50));
      case 'ppt':
      case 'pptx':
        return (Icons.slideshow_rounded, const Color(0xFFFF9800));
      case 'zip':
      case 'rar':
      case '7z':
        return (Icons.folder_zip_rounded, const Color(0xFF9C27B0));
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
        return (Icons.audio_file_rounded, const Color(0xFFE91E63));
      case 'mp4':
      case 'mov':
      case 'avi':
        return (Icons.video_file_rounded, const Color(0xFF00BCD4));
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return (Icons.image_rounded, const Color(0xFF8BC34A));
      case 'txt':
        return (Icons.text_snippet_rounded, const Color(0xFF607D8B));
      case 'apk':
        return (Icons.android_rounded, const Color(0xFF3DDC84));
      default:
        return (Icons.insert_drive_file_rounded, AppColors.primaryFor(context));
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _downloadFile() async {
    if (_downloadState == 1) return; // 正在下载中

    final url = widget.message.mediaUrl;
    if (url == null) return;

    String fileUrl = url;
    if (url.startsWith('/uploads')) {
      fileUrl = '${ApiConfig.serverUrl}$url';
    } else if (!url.startsWith('http')) {
      fileUrl = '${ApiConfig.serverUrl}/$url';
    }

    setState(() {
      _downloadState = 1;
      _progress = 0.0;
    });
    _pulseController.repeat(reverse: true);

    try {
      final accountId = await TokenStorage.getUserId();
      if (accountId == null || accountId.isEmpty) {
        throw StateError('Cannot download a file without an active account');
      }
      final dir = await ChatMediaCacheManager.accountPrivateDirectory(
        accountId,
        'downloads',
      );
      final fileName = widget.message.fileName ??
          'file_${DateTime.now().millisecondsSinceEpoch}';
      final savePath = '${dir.path}/$fileName';

      await Dio().download(
        fileUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      _pulseController.stop();
      if (mounted) {
        setState(() {
          _downloadState = 2;
          _localPath = savePath;
        });
      }
    } catch (e) {
      _pulseController.stop();
      if (mounted) {
        setState(() {
          _downloadState = 0;
          _progress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizedUiText(
                context,
                zhCN: '下载失败，请重试',
                zhTW: '下載失敗，請重試',
                en: 'Download failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openFile() async {
    if (_localPath == null) return;

    final ext =
        (widget.message.fileName ?? '').split('.').lastOrNull?.toLowerCase() ??
            '';

    // 图片文件 - 打开预览
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (ctx, animation, secondaryAnimation) {
            return _LocalImagePreviewPage(
              imagePath: _localPath!,
              fileName: widget.message.fileName ?? 'image',
            );
          },
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      return;
    }

    // 其他文件 - 尝试使用系统应用打开
    try {
      final file = File(_localPath!);
      if (await file.exists()) {
        if (PlatformUtils.isAndroid) {
          final result = await AndroidFileOpenService.openFile(
            path: _localPath!,
            fileName: widget.message.fileName ?? file.path.split('/').last,
          );
          if (!result.opened && context.mounted) {
            _showFileOpenFallback(result.reason);
          }
          return;
        }

        final uri = Uri.file(_localPath!);
        if (await canLaunchUrl(uri) && await launchUrl(uri)) {
          return;
        }
        if (context.mounted) {
          _showFileOpenFallback('no_handler');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizedUiText(
                context,
                zhCN: '无法打开文件，请重试',
                zhTW: '無法開啟檔案，請重試',
                en: 'Unable to open file. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showFileOpenFallback(String reason) {
    final missingHandler = reason == 'no_handler';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedUiText(
            context,
            zhCN:
                missingHandler ? '未找到可打开该文件的应用，可先分享到其他应用' : '无法打开文件，可尝试分享到其他应用',
            zhTW:
                missingHandler ? '未找到可開啟該檔案的應用，可先分享到其他應用' : '無法開啟檔案，可嘗試分享到其他應用',
            en: missingHandler
                ? 'No app can open this file. Try sharing it to another app.'
                : 'Unable to open this file. Try sharing it to another app.',
          ),
        ),
      ),
    );
    _showFileOptions();
  }

  void _showFileOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Material(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: Text(
                    _localizedUiText(
                      ctx,
                      zhCN: '分享文件',
                      zhTW: '分享檔案',
                      en: 'Share File',
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_localPath != null) {
                      Share.shareXFiles([XFile(_localPath!)]);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: Text(
                    _localizedUiText(
                      ctx,
                      zhCN: '文件位置',
                      zhTW: '檔案位置',
                      en: 'File Location',
                    ),
                  ),
                  subtitle: Text(
                    _localPath ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: _localPath ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _localizedUiText(
                            context,
                            zhCN: '路径已复制',
                            zhTW: '路徑已複製',
                            en: 'Path copied',
                          ),
                        ),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext =
        (widget.message.fileName ?? '').split('.').lastOrNull?.toLowerCase() ??
            '';
    final (IconData icon, Color color) = _getFileIconAndColor(ext);

    return GestureDetector(
      onTap: _downloadState == 2 ? _openFile : _downloadFile,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: widget.bubbleColor,
          borderRadius: widget.bubbleRadius,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 文件图标/下载进度/完成图标
            _buildFileIcon(icon, color),
            const SizedBox(width: 12),

            // 文件信息
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.fileName ??
                        AppLocalizations.of(context).file,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: widget.textColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 下载中显示进度百分比
                      if (_downloadState == 1)
                        Text(
                          '${(_progress * 100).toInt()}%  ',
                          style: AppTextStyles.caption.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        _formatFileSize(widget.message.mediaSize ?? 0),
                        style: AppTextStyles.caption.copyWith(
                          color: widget.textColor.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm').format(
                          toCurrentLocalTime(widget.message.createdAt),
                        ),
                        style: AppTextStyles.timestamp.copyWith(
                          color: widget.timeColor,
                        ),
                      ),
                      if (widget.isOutgoing) ...[
                        const SizedBox(width: 3),
                        widget.buildStatusIcon(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileIcon(IconData fileIcon, Color fileColor) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景圆角方块
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _downloadState == 1 ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: fileColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),

          // 下载进度圆环
          if (_downloadState == 1)
            Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 3,
                    backgroundColor: fileColor.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(fileColor),
                  ),
                ),
              ),
            ),

          // 文件类型图标 - 始终显示
          Positioned.fill(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _downloadState == 1
                    ? Icon(
                        Icons.downloading_rounded,
                        key: const ValueKey('downloading'),
                        color: fileColor,
                        size: 20,
                      )
                    : Icon(
                        fileIcon,
                        key: const ValueKey('file'),
                        color: fileColor,
                        size: 24,
                      ),
              ),
            ),
          ),

          // 右下角已下载标记
          if (_downloadState == 2)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}
