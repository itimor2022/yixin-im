import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/utils/image_file_format.dart';

void main() {
  test('detects PNG from bytes even when the source says jpg', () {
    final bytes = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);

    expect(
      detectImageFileExtension(bytes, source: 'https://example.test/a.jpg'),
      '.png',
    );
  });

  test('detects common image signatures', () {
    expect(
      detectImageFileExtension(Uint8List.fromList(<int>[0xff, 0xd8, 0xff])),
      '.jpg',
    );
    expect(
      detectImageFileExtension(
        Uint8List.fromList('GIF89a'.codeUnits),
      ),
      '.gif',
    );
    expect(
      detectImageFileExtension(
        Uint8List.fromList('RIFFxxxxWEBP'.codeUnits),
      ),
      '.webp',
    );
  });
}
