// 文件用途：提供 二维码 image decoder 在 Web 平台的实现，服务于聊天与消息。
// 核心逻辑：实现 二维码 image decoder 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
// ignore_for_file: avoid_web_libraries_in_flutter, undefined_function

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:js/js_util.dart' as js_util;

// 关键声明：二维码 image decoder web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：`isQrImageDecodeSupported` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
bool isQrImageDecodeSupported() {
  return _hasBarcodeDetector() || _hasZxing();
}

Future<String?> decodeQrImageBytes(
  Uint8List bytes, {
  String mimeType = 'image/png',
}) async {
  if (!isQrImageDecodeSupported()) return null;

  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final image = html.ImageElement();

  try {
    final loaded = Future.any<bool>([
      image.onLoad.first.then((_) => true),
      image.onError.first.then((_) => false),
      Future<bool>.delayed(const Duration(seconds: 5), () => false),
    ]);
    image.src = url;

    if (!await loaded) return null;

    if (_hasBarcodeDetector()) {
      final value = await _decodeWithBarcodeDetector(image);
      if (value != null) return value;
    }

    if (_hasZxing()) {
      return await _decodeWithZxing(image);
    }
  } catch (_) {
    return null;
  } finally {
    html.Url.revokeObjectUrl(url);
  }

  return null;
}

bool _hasBarcodeDetector() =>
    js_util.hasProperty(html.window, 'BarcodeDetector');

bool _hasZxing() {
  if (!js_util.hasProperty(html.window, 'ZXing')) return false;
  final zxing = js_util.getProperty<Object?>(html.window, 'ZXing');
  return zxing != null && js_util.hasProperty(zxing, 'BrowserQRCodeReader');
}

Future<String?> _decodeWithBarcodeDetector(html.ImageElement image) async {
  final constructor =
      js_util.getProperty<Object?>(html.window, 'BarcodeDetector');
  if (constructor == null) return null;

  final detector = js_util.callConstructor(
    constructor,
    [
      js_util.jsify({
        'formats': ['qr_code'],
      }),
    ],
  ) as Object;
  final promise =
      js_util.callMethod<Object?>(detector, 'detect', [image]) as Object;
  final result = await js_util.promiseToFuture<Object?>(promise);
  if (result == null) return null;

  final lengthValue = js_util.getProperty<Object?>(result, 'length');
  final length = lengthValue is num
      ? lengthValue.toInt()
      : int.tryParse(lengthValue?.toString() ?? '') ?? 0;

  for (var i = 0; i < length; i += 1) {
    final barcode = js_util.getProperty<Object?>(result, i.toString());
    if (barcode == null) continue;
    final rawValue = js_util.getProperty<Object?>(barcode, 'rawValue');
    final value = rawValue?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }

  return null;
}

Future<String?> _decodeWithZxing(html.ImageElement image) async {
  final zxing = js_util.getProperty<Object?>(html.window, 'ZXing');
  if (zxing == null) return null;

  final constructor =
      js_util.getProperty<Object?>(zxing, 'BrowserQRCodeReader');
  if (constructor == null) return null;

  final reader = js_util.callConstructor(constructor, const []) as Object;
  final promise = js_util.callMethod<Object?>(
    reader,
    'decodeFromImageElement',
    [image],
  ) as Object;
  final result = await js_util.promiseToFuture<Object?>(promise);
  if (result == null) return null;

  Object? rawValue;
  if (js_util.hasProperty(result, 'text')) {
    rawValue = js_util.getProperty<Object?>(result, 'text');
  }
  if ((rawValue?.toString().trim() ?? '').isEmpty &&
      js_util.hasProperty(result, 'getText')) {
    rawValue = js_util.callMethod<Object?>(result, 'getText', const []);
  }

  final value = rawValue?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}
