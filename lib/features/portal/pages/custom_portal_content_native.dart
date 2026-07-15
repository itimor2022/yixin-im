import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';

/// 把 WebView 伪装成真实的 Chrome for Android。
///
/// 修 bug：内嵌客服系统里一条消息显示两条（服务器上其实只有一条，
/// 外部浏览器打开正常）。根因是很多客服系统 JS 里根据 User-Agent 判断：
/// 检测到 UA 里带 "; wv)"（Android WebView 的默认标记）时，就走
/// 一条不太一样的降级分支——常见是同时开 WebSocket + long-poll，
/// 结果服务器推送到达两次，本地去重失败就出现重复消息。
///
/// 把 UA 换成完全干净的 Chrome for Android，客服 JS 就会走跟外部
/// 浏览器一模一样的代码路径。UA 里的 Android 版本 / Chrome 版本
/// 可以过一段时间维护一次以保持"新鲜"，但只是为了避开某些站点
/// 对超旧浏览器的兼容降级，不换也不影响功能。
const String _kBrowserUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

class CustomPortalContent extends StatelessWidget {
  final String title;
  final String url;
  final bool isDesktopSidebar;

  const CustomPortalContent({
    super.key,
    required this.title,
    required this.url,
    required this.isDesktopSidebar,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.isWindows) {
      return _PortalWindowsWebView(
        title: title,
        url: url,
        isDesktopSidebar: isDesktopSidebar,
      );
    }

    if (PlatformUtils.isAndroid ||
        PlatformUtils.isIOS ||
        PlatformUtils.isMacOS) {
      return _PortalWebView(url: url);
    }

    return _PortalExternalFallback(
      title: title,
      url: url,
      isDesktopSidebar: isDesktopSidebar,
      message: '当前设备暂不支持内嵌网站，可直接打开',
    );
  }
}

class _PortalWebView extends StatefulWidget {
  final String url;

  const _PortalWebView({required this.url});

  @override
  State<_PortalWebView> createState() => _PortalWebViewState();
}

class _PortalWebViewState extends State<_PortalWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0;

  // 用于 Android WebView 的 <input type="file"> 处理：
  // 内嵌客服系统里的"发图"按钮本质是原生 HTML file input，Android
  // WebView 不注册 OnShowFileSelector 会静默丢弃点击。这里的 ImagePicker
  // 用于覆盖 accept="image/*" + capture 的相机快拍分支。
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = _createController(_normalizeUrl(widget.url));
  }

  @override
  void didUpdateWidget(covariant _PortalWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUrl = _normalizeUrl(widget.url);
    if (nextUrl != _normalizeUrl(oldWidget.url)) {
      _controller.loadRequest(Uri.parse(nextUrl));
    }
  }

  WebViewController _createController(String initialUrl) {
    final jsMode = initialUrl.startsWith('https://')
        ? JavaScriptMode.unrestricted
        : JavaScriptMode.disabled;

    late final PlatformWebViewControllerCreationParams params;
    if (PlatformUtils.isApple) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(jsMode)
      ..setBackgroundColor(Colors.white)
      // 伪装成 Chrome for Android，让客服 JS 走跟外部浏览器一样的分支，
      // 避免 WebView 特殊降级导致的消息重复渲染。详见 _kBrowserUserAgent 注释。
      ..setUserAgent(_kBrowserUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress / 100;
              _isLoading = progress < 100;
            });
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
            });
            // 故意**不**在这里再调 setJavaScriptMode。
            //
            // 修 bug：内嵌客服系统里发一条消息会出现两条（重进又只剩一条）。
            // 根因是 Android WebView 只要在 onPageStarted 里再次调用
            // setJavaScriptMode（哪怕值不变），WebSettings.setJavaScriptEnabled
            // 就会重新评估，在页面加载途中触发某些 SPA 的初始化脚本**跑第二遍**——
            // 注册两次 WebSocket 监听 / 两次 send 事件处理器，结果每条消息就
            // 会被本地渲染两遍。切走 tab 再回来时页面重新拉取服务器最新记录，
            // 覆盖掉本地错误状态，所以看到「重新进入又是一条」。
            //
            // JS 模式在 controller 初始化时（上面 setJavaScriptMode(jsMode)）
            // 按 initialUrl 的 scheme 决定一次就够了。真正跳到不同 scheme 的
            // 危险 URL 会在 onNavigationRequest 里被拒。
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            if (_shouldOpenExternally(uri)) {
              await _launchExternalUri(uri);
              return NavigationDecision.prevent;
            }

            if (uri.scheme != 'http' && uri.scheme != 'https') {
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
        // 关键：注册文件选择器回调。不注册的话内嵌网页里的图片上传按钮
        // （<input type="file">）在 Android WebView 上会**完全没反应**，
        // 用户只能打字，无法发图。iOS 的 WKWebView 内置支持不需要额外注册。
        ..setOnShowFileSelector(_handleAndroidFileSelection);
      // 仅在 debug 模式下把内嵌页面的 console.log/warn/error 打到 Flutter
      // 日志。方便以后定位客服 JS 里 dedup / WS 相关的坑，release 包不生效。
      if (kDebugMode) {
        androidController.setOnConsoleMessage((msg) {
          debugPrint(
            '[PortalWebView][console.${msg.level.name}] ${msg.message}',
          );
        });
      }
    }

    controller.loadRequest(Uri.parse(initialUrl));
    return controller;
  }

  /// 处理 Android WebView 里的 `<input type="file">` 点击。
  ///
  /// 分类逻辑（**任何分支都必须给 FilePicker 一个合法组合**——否则会抛
  /// "Unsupported filter" 异常，客服系统里就点了没反应）：
  ///   1. `accept="image/*" capture` → 直接拉相机（单选）
  ///   2. 只挑了图片（image/* / image/xxx / .jpg / .png / ...）
  ///      → `FileType.image`
  ///   3. 明确列了扩展名（`.pdf,.docx,...`）→ `FileType.custom + 扩展名列表`
  ///   4. 兜底：accept 为空 / 只有 `*/*` / 只有 MIME 但没扩展名
  ///      → `FileType.any`（能选任意文件，浏览器自己拒绝不合规上传）
  ///
  /// **关键坑**：任何时候都**不要**在没有 allowedExtensions 的情况下传
  /// `FileType.custom`。file_picker 在这种组合下会直接抛
  /// "Unsupported filter" 异常——很多客服系统 accept 值（比如空的、
  /// `image/*,application/pdf` 这种混合 MIME 组合）都会踩到这个坑。
  Future<List<String>> _handleAndroidFileSelection(
    FileSelectorParams params,
  ) async {
    try {
      final allowMultiple = params.mode == FileSelectorMode.openMultiple;
      // 过滤掉空字符串和 */*（等于"任意类型"，不算限制）
      final acceptedTypes = params.acceptTypes
          .map((type) => type.trim())
          .where((type) => type.isNotEmpty && type != '*/*')
          .toList();

      if (kDebugMode) {
        debugPrint(
          '[PortalWebView] file select: multi=$allowMultiple '
          'capture=${params.isCaptureEnabled} '
          'accept=$acceptedTypes',
        );
      }

      // 1) capture=true 且包含图片类型 → 直接拉相机
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

      // 2) 图片专属：所有类型都是 image/* 或常见图片扩展名。
      //    空 accept 不算图片专属，会 fallthrough 到最后的 FileType.any。
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
        return _mapFiles(result);
      }

      // 3) 有明确扩展名 → 用 FileType.custom 精准过滤
      final extensions = _extractAllowedExtensions(acceptedTypes);
      if (extensions != null && extensions.isNotEmpty) {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: allowMultiple,
          type: FileType.custom,
          allowedExtensions: extensions,
        );
        return _mapFiles(result);
      }

      // 4) 兜底：accept 为空 / 只写了 MIME 但没有点分扩展名 / 只有 */*
      //    用 FileType.any 让用户随便选，避免 "Unsupported filter" 异常。
      //    网页端有需要会自己在 JS 里拒绝不合规的上传。
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        type: FileType.any,
      );
      return _mapFiles(result);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[PortalWebView] File selection failed: $error\n$stack');
      }
      return <String>[];
    }
  }

  /// 把 FilePicker 结果映射成 file:// URI 列表。
  ///
  /// **重要**：不能直接返回 file.path！Android WebView 的
  /// onShowFileChooser 内部会做 `Uri.parse(...)`，裸文件路径（如
  /// `/data/user/0/xxx/1.png`）没 scheme，Chromium 会报
  /// `The file choice request has an invalid Uri` 直接拒收。
  /// 必须转成 `file:///data/user/0/xxx/1.png`。
  List<String> _mapFiles(FilePickerResult? result) {
    if (result == null || result.files.isEmpty) {
      return <String>[];
    }
    return result.files
        .map((file) => file.path)
        .whereType<String>()
        .map(_pathToWebViewUri)
        .toList();
  }

  /// 把 Android 本地文件路径转成 WebView 可接受的 file:// URI。
  /// 如果输入已经是 URI（比如 content:// 或 file://）就原样返回。
  String _pathToWebViewUri(String path) {
    if (path.startsWith('file://') ||
        path.startsWith('content://') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }
    return Uri.file(path).toString();
  }

  /// 把 HTML `accept` 属性里的点分扩展名（如 ".pdf", ".doc"）
  /// 提取成 FilePicker 需要的 List<String>（不带点，全小写）。
  ///
  /// 全是 MIME / 没有点分扩展名时返回 null。调用方需要据此选择
  /// `FileType.any` 而不是 `FileType.custom`，否则 file_picker 会抛异常。
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

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
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
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            )
          else
            const SizedBox(height: 2),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

class _PortalWindowsWebView extends StatefulWidget {
  final String title;
  final String url;
  final bool isDesktopSidebar;

  const _PortalWindowsWebView({
    required this.title,
    required this.url,
    required this.isDesktopSidebar,
  });

  @override
  State<_PortalWindowsWebView> createState() => _PortalWindowsWebViewState();
}

class _PortalWindowsWebViewState extends State<_PortalWindowsWebView> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<LoadingState>? _loadingSub;
  StreamSubscription<WebErrorStatus>? _errorSub;
  bool _controllerInitialized = false;
  bool _initializing = false;
  bool _isReady = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _PortalWindowsWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUrl = _normalizeUrl(widget.url);
    if (nextUrl == _normalizeUrl(oldWidget.url)) {
      return;
    }
    if (_isReady) {
      unawaited(_loadUrl(nextUrl));
      return;
    }
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    try {
      if (_controllerInitialized) {
        await _loadUrl(_normalizeUrl(widget.url), markReady: true);
        return;
      }

      final version = await WebviewController.getWebViewVersion();
      if (!mounted) return;
      if (version == null || version.trim().isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '当前电脑缺少 WebView2 运行环境';
        });
        return;
      }

      try {
        await _controller.initialize();
        _controllerInitialized = true;
        await _controller.setBackgroundColor(Colors.white);
        await _loadingSub?.cancel();
        await _errorSub?.cancel();
        _loadingSub = _controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() {
            _isLoading = state == LoadingState.loading;
          });
        });
        _errorSub = _controller.onLoadError.listen((_) {
          if (!mounted) return;
          setState(() {
            _errorMessage = '页面加载失败，可直接打开网站';
            _isLoading = false;
          });
        });
        await _loadUrl(_normalizeUrl(widget.url), markReady: true);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = '页面加载失败，可直接打开网站';
        });
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _loadUrl(String url, {bool markReady = false}) async {
    final normalized = _normalizeUrl(url);
    if (normalized.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '未配置可打开的网址';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    await _controller.loadUrl(normalized);
    if (!mounted) return;
    setState(() {
      _isReady = _isReady || markReady;
    });
  }

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(_normalizeUrl(widget.url));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    unawaited(_loadingSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _PortalExternalFallback(
        title: widget.title,
        url: widget.url,
        isDesktopSidebar: widget.isDesktopSidebar,
        message: _errorMessage!,
      );
    }

    return SafeArea(
      top: false,
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: _isReady
                ? Webview(_controller)
                : const Center(child: CircularProgressIndicator()),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _isLoading
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  )
                : const SizedBox(height: 2),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Tooltip(
              message: '在系统浏览器打开',
              child: FilledButton.tonal(
                onPressed: _openExternally,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(42, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                child: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalExternalFallback extends StatelessWidget {
  final String title;
  final String url;
  final bool isDesktopSidebar;
  final String? message;

  const _PortalExternalFallback({
    required this.title,
    required this.url,
    required this.isDesktopSidebar,
    this.message,
  });

  Future<void> _openPortal() async {
    final uri = Uri.tryParse(_normalizeUrl(url));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedTitle = title.isEmpty ? '打开网站' : title;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, isDesktopSidebar ? 12 : 20, 16, 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      resolvedTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (message != null && message!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _openPortal,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('直接打开'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: Colors.white,
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
