import 'dart:js_interop';
import 'package:web/web.dart' as web;

void setBrowserTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) return;

  web.document.title = normalized;
  try {
    web.window.localStorage.setItem('app_browser_title', normalized);
  } catch (_) {}
}
