import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:http_parser/http_parser.dart';

import '../../core/theme/app_colors.dart';

/// 内置浏览器页面（Telegram 风格，支持下拉关闭）
class InAppBrowser extends StatefulWidget {
  final String url;
  final String? title;
  final bool hideAddressBar;

  const InAppBrowser({
    super.key,
    required this.url,
    this.title,
    this.hideAddressBar = false,
  });

  /// 打开内置浏览器
  static Future<void> open(BuildContext context, String url, {String? title, bool hideAddressBar = false}) async {
    // 确保 URL 有协议前缀
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }
    
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return InAppBrowser(url: finalUrl, title: title, hideAddressBar: hideAddressBar);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<InAppBrowser> createState() => _InAppBrowserState();
}

class _InAppBrowserState extends State<InAppBrowser> with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  final ImagePicker _imagePicker = ImagePicker();
  final Dio _downloadDio = Dio();
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentUrl = '';
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isSecure = false;
  
  // 下拉关闭相关
  double _dragOffset = 0;
  bool _isDragging = false;
  final double _dismissThreshold = 150; // 下拉超过这个距离就关闭

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _pageTitle = widget.title ?? '';
    _isSecure = widget.url.startsWith('https://');
    _initWebView();
  }

  void _initWebView() {
    // 仅对 https 页面启用 JS，http 页面禁用以防中间人注入
    final jsMode = widget.url.startsWith('https://')
        ? JavaScriptMode.unrestricted
        : JavaScriptMode.disabled;

    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(jsMode)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() {
              _loadingProgress = progress / 100;
              _isLoading = progress < 100;
            });
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _isSecure = url.startsWith('https://');
            });
            // 故意**不**在这里再调 setJavaScriptMode。
            // 详见 custom_portal_content_native.dart 里的注释：这样做会让
            // 某些 SPA 的初始化脚本跑第二遍，出现消息 / 事件被处理两次。
            // JS 模式在 controller 初始化时决定一次即可。
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            final title = await _controller.getTitle();
            if (title != null && title.isNotEmpty && mounted) {
              setState(() {
                _pageTitle = title;
              });
            }
            _updateNavigationState();
          },
          onWebResourceError: (error) {
            if (kDebugMode) debugPrint('[WebView] Error: ${error.description}');
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            if (_isDownloadRequest(uri)) {
              await _downloadFile(uri);
              return NavigationDecision.prevent;
            }

            if (_shouldOpenExternally(uri)) {
              await _launchExternalUri(uri);
              return NavigationDecision.prevent;
            }

            // 明确拒绝危险 scheme（javascript:、file:、data: 等）
            if (uri.scheme != 'http' && uri.scheme != 'https') {
              if (kDebugMode) debugPrint('[WebView] Blocked dangerous scheme: ${uri.scheme}');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setOnShowFileSelector(_handleAndroidFileSelection);
    }

    _controller = controller..loadRequest(Uri.parse(widget.url));
  }

  bool _shouldOpenExternally(Uri uri) {
    const externalSchemes = <String>{
      'tel',
      'mailto',
      'sms',
      'weixin',
      'alipays',
      'mqqapi',
      'iosamap',
      'androidamap',
      'baidumap',
      'intent',
      'market',
    };

    return externalSchemes.contains(uri.scheme);
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        if (kDebugMode) debugPrint('[WebView] Failed to launch external url: $uri');
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[WebView] External launch failed: $error');
    }
  }

  // 详见 CustomPortalContent._handleAndroidFileSelection 里的注释：
  // 关键坑是 FileType.custom + null/empty allowedExtensions 会抛
  // "Unsupported filter" 异常。任何时候都得给 FilePicker 一个合法组合。
  Future<List<String>> _handleAndroidFileSelection(
    FileSelectorParams params,
  ) async {
    try {
      final allowMultiple = params.mode == FileSelectorMode.openMultiple;
      final acceptedTypes = params.acceptTypes
          .map((type) => type.trim())
          .where((type) => type.isNotEmpty && type != '*/*')
          .toList();

      if (kDebugMode) {
        debugPrint(
          '[WebView] file select: multi=$allowMultiple '
          'capture=${params.isCaptureEnabled} accept=$acceptedTypes',
        );
      }

      final shouldUseCamera = params.isCaptureEnabled &&
          acceptedTypes.any((type) => type.startsWith('image/'));
      if (shouldUseCamera && !allowMultiple) {
        final capturedFile = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
          maxWidth: 1920,
          maxHeight: 1920,
        );
        if (capturedFile == null) {
          return <String>[];
        }
        return <String>[_pathToWebViewUri(capturedFile.path)];
      }

      const imageExtensions = <String>{
        '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif',
      };
      final isImageOnly = acceptedTypes.isNotEmpty &&
          acceptedTypes.every(
            (type) =>
                type.startsWith('image/') ||
                imageExtensions.contains(type.toLowerCase()),
          );
      if (isImageOnly) {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: allowMultiple,
          type: FileType.image,
        );
        return _mapFilePickerResult(result);
      }

      final extensions = _extractAllowedExtensions(acceptedTypes);
      if (extensions != null && extensions.isNotEmpty) {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: allowMultiple,
          type: FileType.custom,
          allowedExtensions: extensions,
        );
        return _mapFilePickerResult(result);
      }

      // 兜底：accept 空 / 只有 MIME / */* → FileType.any
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        type: FileType.any,
      );
      return _mapFilePickerResult(result);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[WebView] File selection failed: $error\n$stack');
      }
      return <String>[];
    }
  }

  // 详见 CustomPortalContent._mapFiles 里的注释：
  // 必须把文件路径转成 file:// URI，否则 Android WebView 会以
  // "invalid Uri" 拒绝接收。
  List<String> _mapFilePickerResult(FilePickerResult? result) {
    if (result == null || result.files.isEmpty) {
      return <String>[];
    }
    return result.files
        .map((file) => file.path)
        .whereType<String>()
        .map(_pathToWebViewUri)
        .toList();
  }

  String _pathToWebViewUri(String path) {
    if (path.startsWith('file://') ||
        path.startsWith('content://') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }
    return Uri.file(path).toString();
  }

  bool _isDownloadRequest(Uri uri) {
    const downloadExtensions = <String>{
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.zip',
      '.rar',
      '.7z',
      '.apk',
      '.txt',
      '.csv',
    };

    final path = uri.path.toLowerCase();
    if (downloadExtensions.any(path.endsWith)) {
      return true;
    }

    return uri.queryParameters.containsKey('download') ||
        uri.queryParameters['attachment'] == '1';
  }

  Future<void> _downloadFile(Uri uri) async {
    try {
      _showMessage('开始下载文件...');
      final directory = await _resolveDownloadDirectory();
      final response = await _downloadDio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      final filename = _resolveDownloadFilename(uri, response.headers);
      final savePath = '${directory.path}${Platform.pathSeparator}$filename';
      final file = File(savePath);
      await file.writeAsBytes(response.data ?? <int>[]);

      _showDownloadSuccess(file);
    } catch (error) {
      if (kDebugMode) debugPrint('[WebView] Download failed: $error');
      _showMessage('文件下载失败');
    }
  }

  Future<Directory> _resolveDownloadDirectory() async {
    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      if (!await downloadsDirectory.exists()) {
        await downloadsDirectory.create(recursive: true);
      }
      return downloadsDirectory;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    if (!await documentsDirectory.exists()) {
      await documentsDirectory.create(recursive: true);
    }
    return documentsDirectory;
  }

  String _resolveDownloadFilename(Uri uri, Headers headers) {
    final disposition = headers.value('content-disposition');
    if (disposition != null) {
      final filenameStarMatch = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
          .firstMatch(disposition);
      if (filenameStarMatch != null) {
        return Uri.decodeFull(filenameStarMatch.group(1)!);
      }

      final filenameMatch = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
          .firstMatch(disposition);
      if (filenameMatch != null) {
        return filenameMatch.group(1)!;
      }
    }

    final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (lastSegment.isNotEmpty) {
      return lastSegment;
    }

    final contentType = headers.value(Headers.contentTypeHeader);
    final extension = _extensionForContentType(contentType);
    return 'download_${DateTime.now().millisecondsSinceEpoch}$extension';
  }

  String _extensionForContentType(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return '';
    }

    final mediaType = MediaType.parse(contentType);
    final subtype = mediaType.subtype.toLowerCase();
    const mapping = <String, String>{
      'pdf': '.pdf',
      'zip': '.zip',
      'msword': '.doc',
      'vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
      'vnd.ms-excel': '.xls',
      'vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
      'plain': '.txt',
      'csv': '.csv',
      'json': '.json',
    };

    return mapping[subtype] ?? '';
  }

  void _showDownloadSuccess(File file) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('文件已保存：${file.path.split(Platform.pathSeparator).last}'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '分享',
          onPressed: () {
            Share.shareXFiles([XFile(file.path)]);
          },
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<String>? _extractAllowedExtensions(List<String> acceptTypes) {
    final extensions = acceptTypes
        .where((type) => type.startsWith('.'))
        .map((type) => type.substring(1).toLowerCase())
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList();

    if (extensions.isEmpty) {
      return null;
    }

    return extensions;
  }

  Future<void> _updateNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 400.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset > _dismissThreshold || details.velocity.pixelsPerSecond.dy > 500) {
      // 关闭浏览器
      Navigator.of(context).pop();
    } else {
      // 弹回原位
      setState(() {
        _dragOffset = 0;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    
    // 颜色配置
    final headerBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEFEFF4);
    final contentBg = isDark ? const Color(0xFF000000) : Colors.white;
    
    // 计算透明度（下拉时背景变暗）
    final double opacity = (1 - (_dragOffset / 300)).clamp(0.3, 1.0);
    final double scale = (1 - (_dragOffset / 2000)).clamp(0.95, 1.0);
    
    return GestureDetector(
      onTap: () {}, // 阻止点击穿透
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.5 * opacity),
        body: AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translate(0.0, _dragOffset)
            ..scale(scale),
          child: Container(
            margin: EdgeInsets.only(top: topPadding),
            decoration: BoxDecoration(
              color: contentBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 可拖动的顶部区域
                GestureDetector(
                  onVerticalDragStart: _onVerticalDragStart,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  behavior: HitTestBehavior.opaque,
                  child: _buildTelegramHeader(isDark, headerBg),
                ),
                // 加载进度条
                if (_isLoading)
                  LinearProgressIndicator(
                    value: _loadingProgress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 2,
                  )
                else
                  const SizedBox(height: 2),
                // WebView
                Expanded(
                  child: WebViewWidget(controller: _controller),
                ),
                // Telegram 风格底部栏
                _buildTelegramBottomBar(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Telegram 风格顶部导航栏（可下拉关闭）
  Widget _buildTelegramHeader(bool isDark, Color headerBg) {
    final buttonBg = isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06);
    final addressBarBg = isDark ? Colors.white.withOpacity(0.12) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    
    return Container(
      color: headerBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 下拉指示器
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          // 导航栏内容
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                // 关闭按钮 (X)
                _buildCircleButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                  backgroundColor: buttonBg,
                  iconColor: textColor,
                ),
                const SizedBox(width: 10),
                // 地址栏（hideAddressBar 为 true 时隐藏）
                if (!widget.hideAddressBar)
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: addressBarBg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: isDark ? null : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSecure)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.lock,
                                size: 14,
                                color: isDark ? Colors.white60 : Colors.black45,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              _getDomain(_currentUrl),
                              style: TextStyle(
                                fontSize: 15,
                                color: textColor,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isLoading) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDark ? Colors.white60 : Colors.black45,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 10),
                // 更多按钮（hideAddressBar 时一并隐藏）
                if (!widget.hideAddressBar)
                  _buildCircleButton(
                    icon: Icons.more_horiz,
                    onTap: () => _showMoreOptions(isDark),
                    backgroundColor: buttonBg,
                    iconColor: textColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Telegram 风格底部工具栏
  Widget _buildTelegramBottomBar(bool isDark) {
    final barBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final iconColor = AppColors.primary;
    final disabledColor = isDark ? Colors.white30 : Colors.grey.shade400;
    
    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 后退
              _buildBottomButton(
                icon: Icons.chevron_left,
                onTap: _canGoBack ? () => _controller.goBack() : null,
                color: _canGoBack ? iconColor : disabledColor,
                size: 32,
              ),
              // 前进
              _buildBottomButton(
                icon: Icons.chevron_right,
                onTap: _canGoForward ? () => _controller.goForward() : null,
                color: _canGoForward ? iconColor : disabledColor,
                size: 32,
              ),
              // 分享
              _buildBottomButton(
                icon: Icons.ios_share,
                onTap: () => Share.share(_currentUrl),
                color: iconColor,
                size: 26,
              ),
              // 刷新
              _buildBottomButton(
                icon: Icons.refresh,
                onTap: () => _controller.reload(),
                color: iconColor,
                size: 26,
              ),
              // 在浏览器中打开
              _buildBottomButton(
                icon: Icons.open_in_browser,
                onTap: () {
                  launchUrl(
                    Uri.parse(_currentUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                color: iconColor,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor,
        ),
      ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: color,
        ),
      ),
    );
  }

  void _showMoreOptions(bool isDark) {
    final bgColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              // 页面标题
              if (_pageTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _pageTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_pageTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: Text(
                    _currentUrl,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (_pageTitle.isEmpty)
                const SizedBox(height: 8),
              // 选项列表
              _buildOptionItem(
                icon: Icons.copy_rounded,
                title: '拷贝链接',
                isDark: isDark,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _currentUrl));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('链接已拷贝'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
              ),
              _buildOptionItem(
                icon: Icons.refresh_rounded,
                title: '刷新',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _controller.reload();
                },
              ),
              const SizedBox(height: 8),
              // 取消按钮
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: AppColors.primary,
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return url;
    }
  }
}
