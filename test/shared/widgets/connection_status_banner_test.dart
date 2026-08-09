import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/websocket_service.dart';
import 'package:generic_im/shared/widgets/connection_status_banner.dart';

void main() {
  test('websocket reconnect states stay silent', () {
    expect(
      shouldShowConnectionBanner(WSConnectionState.disconnected),
      isFalse,
    );
    expect(
      shouldShowConnectionBanner(WSConnectionState.reconnecting),
      isFalse,
    );
    expect(shouldShowConnectionBanner(WSConnectionState.connecting), isFalse);
    expect(shouldShowConnectionBanner(WSConnectionState.connected), isFalse);
  });
}
