import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/endpoint_manager.dart';

void main() {
  test('default endpoints stay local in the generic delivery', () {
    expect(EndpointManager.fallbackServerUrl, 'http://127.0.0.1:8080');
    expect(
      EndpointManager.fallbackWsUrl,
      'ws://127.0.0.1:8080/api/v1/ws',
    );
  });
}
