// 文件用途：提供 custom portal content 在 Web 平台的实现，服务于门户内容。
// 核心逻辑：实现 CustomPortalContent 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations.dart';

String _portalWebText({
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

// 关键声明：custom portal content web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
class CustomPortalContent extends StatefulWidget {
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
  State<CustomPortalContent> createState() => _CustomPortalContentState();
}

class _CustomPortalContentState extends State<CustomPortalContent> {
  static int _viewCounter = 0;
  late String _viewType;
  late String _currentUrl;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _currentUrl = _normalizeUrl(widget.url);
    _viewType = _registerIframe(_currentUrl);
  }

  @override
  void didUpdateWidget(covariant CustomPortalContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUrl = _normalizeUrl(widget.url);
    if (nextUrl != _currentUrl) {
      setState(() {
        _currentUrl = nextUrl;
        _viewType = _registerIframe(nextUrl);
      });
    }
  }

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  String _registerIframe(String url) {
    final viewType = 'custom-portal-iframe-${_viewCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      return html.IFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..allow =
            'autoplay; camera; clipboard-read; clipboard-write; fullscreen; geolocation; microphone; payment'
        ..referrerPolicy = 'strict-origin-when-cross-origin';
    });
    return viewType;
  }

  Future<void> _openInNewTab() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUrl.trim().isEmpty) {
      return _PortalWebUnavailable(
        title: widget.title,
        isDesktopSidebar: widget.isDesktopSidebar,
      );
    }

    return SafeArea(
      top: false,
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: HtmlElementView(
              key: ValueKey(_viewType),
              viewType: _viewType,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Tooltip(
              message: _portalWebText(
                zhCN: '如果页面未正常显示，可在新窗口打开',
                zhTW: '如果頁面未正常顯示，可在新視窗開啟',
                en: 'Open in a new window if the page does not display correctly',
              ),
              child: FilledButton.tonal(
                onPressed: _openInNewTab,
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

class _PortalWebUnavailable extends StatelessWidget {
  final String title;
  final bool isDesktopSidebar;

  const _PortalWebUnavailable({
    required this.title,
    required this.isDesktopSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, isDesktopSidebar ? 12 : 20, 16, 20),
        child: Center(
          child: Text(
            title.isEmpty
                ? _portalWebText(
                    zhCN: '网站暂不可用',
                    zhTW: '網站暫不可用',
                    en: 'Website is temporarily unavailable',
                  )
                : title,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
