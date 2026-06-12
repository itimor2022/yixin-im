import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('firebaseGetFCMToken')
external JSPromise<JSAny?> _firebaseGetFCMToken(JSString vapidKey);

Future<String?> getWebFCMToken(String vapidKey) async {
  try {
    final result = await _firebaseGetFCMToken(vapidKey.toJS).toDart;
    if (result == null || result.isNull || result.isUndefined) return null;
    return (result as JSString).toDart;
  } catch (e) {
    debugPrint('[FCM Web] getWebFCMToken error: \$e');
    return null;
  }
}
