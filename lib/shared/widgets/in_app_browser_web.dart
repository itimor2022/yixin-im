import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class InAppBrowser extends StatelessWidget {
  final String url;
  final String? title;
  final bool hideAddressBar;

  const InAppBrowser({
    super.key,
    required this.url,
    this.title,
    this.hideAddressBar = false,
  });

  static Future<void> open(
    BuildContext context,
    String url, {
    String? title,
    bool hideAddressBar = false,
  }) async {
    final uri = Uri.tryParse(_normalizeUrl(url));
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  static String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      open(context, url, title: title, hideAddressBar: hideAddressBar);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return const SizedBox.shrink();
  }
}
