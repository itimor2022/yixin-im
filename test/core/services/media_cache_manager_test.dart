import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/media_cache_manager.dart';

void main() {
  test('persistent outgoing copy survives deletion of its temporary source',
      () async {
    final root = await Directory.systemTemp.createTemp('outgoing-media-');
    final sourceDirectory = Directory('${root.path}/tmp');
    final destinationDirectory = Directory('${root.path}/support');
    await sourceDirectory.create();
    final source = File('${sourceDirectory.path}/picked.JPG');

    try {
      await source.writeAsBytes(<int>[1, 3, 3, 7]);
      final persisted = await ChatMediaCacheManager.copyMediaIntoDirectory(
        source: source,
        directory: destinationDirectory,
        stableName: '../message:1',
      );

      expect(persisted.path, endsWith('_message_1.jpg'));
      await source.delete();
      expect(await persisted.exists(), isTrue);
      expect(await persisted.readAsBytes(), <int>[1, 3, 3, 7]);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('persistent outgoing copy is idempotent for the same message', () async {
    final root = await Directory.systemTemp.createTemp('outgoing-media-');
    final source = File('${root.path}/picked.png');
    final destinationDirectory = Directory('${root.path}/support');

    try {
      await source.writeAsBytes(<int>[4, 2]);
      final first = await ChatMediaCacheManager.copyMediaIntoDirectory(
        source: source,
        directory: destinationDirectory,
        stableName: 'message-2',
      );
      final second = await ChatMediaCacheManager.copyMediaIntoDirectory(
        source: source,
        directory: destinationDirectory,
        stableName: 'message-2',
      );

      expect(second.path, first.path);
      expect(await second.readAsBytes(), <int>[4, 2]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
