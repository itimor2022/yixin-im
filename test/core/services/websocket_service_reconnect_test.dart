import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:generic_im/core/services/api/websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('token refresh and auth reconnect cannot strand the transport',
      () async {
    final harness = _WebSocketHarness();
    final service = WebSocketService(
      channelFactory: harness.create,
      readyWaiter: harness.waitUntilReady,
    );

    await service.connect('old-token', deviceType: 'ios');
    expect(service.connectionState, WSConnectionState.connected);

    service.applyRefreshedHttpToken('new-token');
    await Future<void>.delayed(Duration.zero);

    // Mirrors the auth provider emitting authenticated again during the
    // token-refresh force reconnect.
    await service
        .connect('new-token', deviceType: 'ios')
        .timeout(const Duration(seconds: 5));

    expect(service.connectionState, WSConnectionState.connected);
    expect(harness.createdChannels, 2);
    expect(harness.requestedUris.last.queryParameters['token'], 'new-token');

    await service.disconnect(clearToken: true);
    service.dispose();
  });
}

class _WebSocketHarness {
  final Map<WebSocketChannel, int> _channelNumbers = {};
  final List<Uri> requestedUris = [];

  int get createdChannels => _channelNumbers.length;

  WebSocketChannel create(Uri uri) {
    requestedUris.add(uri);
    final number = _channelNumbers.length + 1;
    final incoming = StreamController<List<int>>(
      onCancel: () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    final outgoing = StreamController<List<int>>();
    final channel = WebSocketChannel(
      StreamChannel<List<int>>(incoming.stream, outgoing.sink),
      serverSide: false,
    );
    _channelNumbers[channel] = number;
    return channel;
  }

  Future<void> waitUntilReady(WebSocketChannel channel) async {
    final number = _channelNumbers[channel];
    if (number == 2) {
      // Keep the replacement handshake open long enough for the old
      // subscription cancellation to expose the original race.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
