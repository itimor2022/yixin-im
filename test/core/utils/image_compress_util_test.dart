import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/utils/image_compress_util.dart';

void main() {
  test('original image mode and GIF preserve source bytes', () {
    expect(
      shouldSkipChatImageCompression(
        originalRequested: true,
        extension: 'jpg',
      ),
      isTrue,
    );
    expect(
      shouldSkipChatImageCompression(
        originalRequested: false,
        extension: 'GIF',
      ),
      isTrue,
    );
    expect(
      shouldSkipChatImageCompression(
        originalRequested: false,
        extension: 'jpg',
      ),
      isFalse,
    );
  });
}
