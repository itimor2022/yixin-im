import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/core/services/api/websocket_service.dart';
import 'package:generic_im/features/contacts/providers/contact_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('refresh bypasses the fresh-list cache after adding a contact',
      () async {
    final api = _ContactApiClient(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[
        _contact(id: 1, uuid: 'user-1', username: 'first'),
      ],
      <Map<String, dynamic>>[
        _contact(id: 1, uuid: 'user-1', username: 'first'),
        _contact(id: 2, uuid: 'user-2', username: 'new-contact'),
      ],
    ]);
    final webSocket = WebSocketService();
    final notifier = ContactListNotifier(api, webSocket, 'account-a');

    await notifier.loadFromServer(force: true);
    expect(notifier.state.map((item) => item.uuid), <String?>['user-1']);
    expect(api.getCalls, 1);

    // This is the path used after add/already-contact. It must not be skipped
    // by the 30-second freshness window.
    await notifier.refresh();

    expect(
      notifier.state.map((item) => item.uuid),
      <String?>['user-1', 'user-2'],
    );
    expect(api.getCalls, 2);

    notifier.dispose();
    webSocket.dispose();
    api.dispose();
  });
}

Map<String, dynamic> _contact({
  required int id,
  required String uuid,
  required String username,
}) {
  return <String, dynamic>{
    'id': id,
    'uuid': uuid,
    'name': username,
    'nickname': username,
    'username': username,
    'is_online': false,
  };
}

class _ContactApiClient extends ApiClient {
  _ContactApiClient(this.pages);

  final List<List<Map<String, dynamic>>> pages;
  int getCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    dynamic cancelToken,
  }) async {
    expect(path, '/contact/list');
    final index = getCalls < pages.length ? getCalls : pages.length - 1;
    final list = pages[index];
    getCalls++;
    final payload = <String, dynamic>{
      'list': list,
      'total': list.length,
      'page': 1,
      'page_size': 500,
    };
    return ApiResponse<T>(
      code: 0,
      message: 'success',
      data: payload as T,
    );
  }
}
