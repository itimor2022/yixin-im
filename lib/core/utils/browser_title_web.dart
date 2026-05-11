// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void setBrowserTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) {
    return;
  }

  html.document.title = normalized;
  try {
    html.window.localStorage['app_browser_title'] = normalized;
  } catch (_) {}
}
