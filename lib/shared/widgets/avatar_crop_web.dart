import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('File reading not supported on web');
}

Future<String> saveCroppedFile(Uint8List data) async {
  throw UnsupportedError('File saving not supported on web');
}
