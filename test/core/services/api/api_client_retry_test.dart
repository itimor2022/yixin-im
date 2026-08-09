import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/api_client.dart';

void main() {
  test('multipart request data is deep-cloned after the first send', () async {
    final original = FormData.fromMap(<String, dynamic>{
      'client_request_id': 'message-1',
      'file': MultipartFile.fromBytes(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        filename: 'image.jpg',
      ),
    });

    final firstBody = await original.readAsBytes();
    final retry = cloneRequestDataForRetry(original);

    expect(retry, isA<FormData>());
    expect(identical(retry, original), isFalse);
    expect(await (retry! as FormData).readAsBytes(), firstBody);
  });

  test('ordinary retry request data keeps its original identity', () {
    final data = <String, dynamic>{'client_msg_id': 'message-1'};

    expect(identical(cloneRequestDataForRetry(data), data), isTrue);
  });
}
