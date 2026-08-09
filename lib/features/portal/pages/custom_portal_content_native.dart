// 文件用途：提供 custom portal content 在原生平台的实现，服务于门户内容。
// 核心逻辑：实现 CustomPortalContent 的原生平台分支，封装系统权限或文件能力，并保持跨平台调用契约一致。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';

String _portalText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：custom portal content native 是原生平台实现，集中处理系统权限、文件或窗口能力，避免业务层散落平台判断。
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
      message: _portalText(
        zhCN: '当前设备暂不支持内嵌网站，可直接打开',
        zhTW: '目前裝置暫不支援內嵌網站，可直接開啟',
        en: 'This device does not support embedded web pages. Open it directly instead.',
      ),
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

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
            _controller.setJavaScriptMode(
              url.startsWith('https://')
                  ? JavaScriptMode.unrestricted
                  : JavaScriptMode.disabled,
            );
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
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    controller.loadRequest(Uri.parse(initialUrl));
    return controller;
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
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.primaryFor(context),
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
          _errorMessage = _portalText(
            zhCN: '当前电脑缺少 WebView2 运行环境',
            zhTW: '目前電腦缺少 WebView2 執行環境',
            en: 'WebView2 runtime is missing on this computer',
          );
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
            _errorMessage = _portalText(
              zhCN: '页面加载失败，可直接打开网站',
              zhTW: '頁面載入失敗，可直接開啟網站',
              en: 'Page failed to load. Open the website directly instead.',
            );
            _isLoading = false;
          });
        });
        await _loadUrl(_normalizeUrl(widget.url), markReady: true);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = _portalText(
            zhCN: '页面加载失败，可直接打开网站',
            zhTW: '頁面載入失敗，可直接開啟網站',
            en: 'Page failed to load. Open the website directly instead.',
          );
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
        _errorMessage = _portalText(
          zhCN: '未配置可打开的网址',
          zhTW: '未設定可開啟的網址',
          en: 'No website URL is configured',
        );
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
                ? LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryFor(context),
                    ),
                  )
                : const SizedBox(height: 2),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Tooltip(
              message: _portalText(
                zhCN: '在系统浏览器打开',
                zhTW: '在系統瀏覽器開啟',
                en: 'Open in system browser',
              ),
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
    final resolvedTitle = title.isEmpty
        ? _portalText(
            zhCN: '打开网站',
            zhTW: '開啟網站',
            en: 'Open Website',
          )
        : title;
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
                      label: Text(
                        _portalText(
                          zhCN: '直接打开',
                          zhTW: '直接開啟',
                          en: 'Open Directly',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: AppColors.onPrimaryFor(context),
                        backgroundColor: AppColors.primaryFor(context),
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
