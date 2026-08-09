// 文件用途：提供 image file format 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 image file format 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'dart:typed_data';

// 关键声明：image file format 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：`detectImageFileExtension` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
/// Returns a lowercase extension including the leading dot.
///
/// The byte signature is authoritative. The source name is only a fallback for
/// formats whose short header is not available.
String detectImageFileExtension(Uint8List bytes, {String? source}) {
  if (_startsWith(bytes, const <int>[0xff, 0xd8, 0xff])) return '.jpg';
  if (_startsWith(
    bytes,
    const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  )) {
    return '.png';
  }
  if (_asciiAt(bytes, 0, 'GIF87a') || _asciiAt(bytes, 0, 'GIF89a')) {
    return '.gif';
  }
  if (_asciiAt(bytes, 0, 'RIFF') && _asciiAt(bytes, 8, 'WEBP')) {
    return '.webp';
  }
  if (bytes.length >= 12 && _asciiAt(bytes, 4, 'ftyp')) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand == 'avif' || brand == 'avis') return '.avif';
    if (<String>{
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'mif1',
      'msf1',
    }.contains(brand)) {
      return '.heic';
    }
  }

  final fallback = _extensionFromSource(source);
  return fallback ?? '.jpg';
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

bool _asciiAt(Uint8List bytes, int offset, String value) {
  if (offset < 0 || bytes.length < offset + value.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (bytes[offset + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

String? _extensionFromSource(String? source) {
  final value = source?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.startsWith('data:image/')) {
    final separator = value.indexOf(';');
    final subtype = value.substring(
      'data:image/'.length,
      separator > 0 ? separator : value.length,
    );
    return _normalizeExtension(subtype);
  }
  final uri = Uri.tryParse(value);
  final path = uri?.path.isNotEmpty == true ? uri!.path : value;
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return null;
  return _normalizeExtension(path.substring(dot + 1));
}

String? _normalizeExtension(String value) {
  switch (value.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return '.jpg';
    case 'png':
      return '.png';
    case 'gif':
      return '.gif';
    case 'webp':
      return '.webp';
    case 'avif':
      return '.avif';
    case 'heic':
    case 'heif':
      return '.heic';
    default:
      return null;
  }
}
