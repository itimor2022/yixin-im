import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/endpoint_manager.dart';

void main() {
  test('remote bootstrap does not retain loopback fallback endpoints', () {
    final config = EndpointBootstrapConfig.fromJson({
      'api_endpoints': [
        {'id': 'online-api', 'url': 'https://im.example.com', 'priority': 10},
        {'id': 'stale-local-api', 'url': 'http://127.0.0.1:8080'},
      ],
      'ws_endpoints': [
        {
          'id': 'online-ws',
          'url': 'wss://im.example.com/api/v1/ws',
          'priority': 10,
        },
        {
          'id': 'stale-local-ws',
          'url': 'ws://127.0.0.1:8080/api/v1/ws',
        },
      ],
      'media_base_urls': ['https://media.example.com'],
    });

    expect(config.apiEndpoints.map((entry) => entry.url), [
      'https://im.example.com',
    ]);
    expect(config.wsEndpoints.map((entry) => entry.url), [
      'wss://im.example.com/api/v1/ws',
    ]);
    expect(config.mediaBaseUrls, ['https://media.example.com']);
  });
}
