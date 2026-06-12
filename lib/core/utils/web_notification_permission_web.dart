import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String> requestBrowserNotificationPermission() async {
  try {
    final permission = web.Notification.permission;
    if (permission == 'granted' || permission == 'denied') {
      return permission;
    }
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart;
  } catch (e) {
    return 'denied';
  }
}

String getBrowserNotificationPermission() {
  try {
    return web.Notification.permission;
  } catch (_) {
    return 'default';
  }
}
