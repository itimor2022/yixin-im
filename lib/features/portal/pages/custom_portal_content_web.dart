import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
      final container = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..style.overflow = 'auto'
        ..style.pointerEvents = 'auto'
        ..style.touchAction = 'auto';

      final iframe = web.HTMLIFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..style.pointerEvents = 'auto'
        ..style.touchAction = 'auto'
        ..setAttribute('scrolling', 'yes')
        ..allow =
            'autoplay; camera; clipboard-read; clipboard-write; fullscreen; geolocation; microphone; payment'
        ..referrerPolicy = 'strict-origin-when-cross-origin';

      container.append(iframe);
      return container;
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
      child: HtmlElementView(
        key: ValueKey(_viewType),
        viewType: _viewType,
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
            title.isEmpty ? '网站暂不可用' : title,
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
