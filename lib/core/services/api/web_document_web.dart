import 'dart:js_interop';
import 'package:web/web.dart' as web;

final Map<dynamic, JSFunction> _callbackMap = {};

void webAddEventListener(String type, dynamic callback) {
  final void Function() voidFn = () { (callback as Function)(); };
  final jsFunc = voidFn.toJS;
  _callbackMap[callback] = jsFunc;
  web.document.addEventListener(type, jsFunc);
}

void webRemoveEventListener(String type, dynamic callback) {
  final jsFunc = _callbackMap.remove(callback);
  if (jsFunc != null) {
    web.document.removeEventListener(type, jsFunc);
  }
}

bool webDocumentHidden() => web.document.hidden;
