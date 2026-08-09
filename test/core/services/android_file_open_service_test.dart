import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/android_file_open_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.genericim/file_open');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('passes the private path to the Android FileProvider bridge', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return <String, dynamic>{
        'opened': true,
        'reason': 'chooser_started',
      };
    });

    final result = await AndroidFileOpenService.openFile(
      path: '/data/user/0/com.genericim.app/files/example.zip',
      fileName: 'example.zip',
    );

    expect(result.opened, isTrue);
    expect(result.reason, 'chooser_started');
    expect(received?.method, 'openFile');
    expect(received?.arguments, <String, dynamic>{
      'path': '/data/user/0/com.genericim.app/files/example.zip',
      'file_name': 'example.zip',
    });
  });

  test('preserves a native no-handler reason for the fallback UI', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      return <String, dynamic>{'opened': false, 'reason': 'no_handler'};
    });

    final result = await AndroidFileOpenService.openFile(
      path: '/data/user/0/com.genericim.app/files/example.unknown',
      fileName: 'example.unknown',
    );

    expect(result.opened, isFalse);
    expect(result.reason, 'no_handler');
  });
}
