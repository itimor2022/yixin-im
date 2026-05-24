import 'dart:js_interop';
import 'package:web/web.dart' as web;

void webAddEventListener(String type, dynamic callback) {
  web.document.addEventListener(type, (callback as JSFunction));
}

void webRemoveEventListener(String type, dynamic callback) {
  web.document.removeEventListener(type, (callback as JSFunction));
}

bool webDocumentHidden() => web.document.hidden;
