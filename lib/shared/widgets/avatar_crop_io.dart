import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<Uint8List> readFileBytes(String path) async {
  return await File(path).readAsBytes();
}

Future<String> saveCroppedFile(Uint8List data) async {
  final tempDir = await getTemporaryDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final file = File('${tempDir.path}/cropped_avatar_$timestamp.jpg');
  await file.writeAsBytes(data);
  return file.path;
}
