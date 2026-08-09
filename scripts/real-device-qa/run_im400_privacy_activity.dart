import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Actor {
  const Actor(this.name, this.userId, this.token);

  final String name;
  final String userId;
  final String token;
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;
  final HttpClient _client = HttpClient();

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Actor? actor,
    Map<String, dynamic>? body,
    bool allowBusinessError = false,
  }) async {
    final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (actor != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${actor.token}');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    final payload = raw.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (!allowBusinessError && (response.statusCode >= 400 || payload['code'] != 0)) {
      throw StateError('$method $path failed: HTTP ${response.statusCode} $payload');
    }
    return payload;
  }

  void close() => _client.close(force: true);
}

class WsClient {
  WsClient(this.actor, this.socket) {
    _subscription = socket.listen((data) {
      final decoded = jsonDecode(data.toString());
      if (decoded is Map) {
        events.add(Map<String, dynamic>.from(decoded));
      }
    });
  }

  final Actor actor;
  final WebSocket socket;
  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  late final StreamSubscription<dynamic> _subscription;

  static Future<WsClient> connect(String wsUrl, Actor actor) async {
    final socket = await WebSocket.connect(
      '$wsUrl?device_type=qa',
      headers: <String, dynamic>{
        HttpHeaders.authorizationHeader: 'Bearer ${actor.token}',
      },
    );
    socket.pingInterval = const Duration(seconds: 10);
    return WsClient(actor, socket);
  }

  void send(String type, Map<String, dynamic> data) {
    socket.add(jsonEncode(<String, dynamic>{'type': type, 'data': data}));
  }

  Future<Map<String, dynamic>?> waitFor(
    bool Function(Map<String, dynamic>) predicate, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final index = events.indexWhere(predicate);
      if (index >= 0) return events.removeAt(index);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return null;
  }

  void clear() => events.clear();

  Future<void> close() async {
    await socket.close(WebSocketStatus.normalClosure, 'qa complete');
    await _subscription.cancel();
  }
}

Map<String, dynamic> dataOf(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is! Map) throw StateError('response data missing: $payload');
  return Map<String, dynamic>.from(data);
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Actor> createActor(ApiClient api, String label, String runId) async {
  final username = 'qa_p${label.toLowerCase()}_$runId';
  final payload = await api.request(
    'POST',
    '/auth/register',
    body: <String, dynamic>{
      'username': username.substring(0, username.length.clamp(0, 20)),
      'password': 'QaPrivacy123',
      'nickname': 'Privacy $label',
      'gender': 'male',
      'device_id': 'privacy-$label-$runId',
      'device_type': 'qa',
      'device_name': 'Privacy QA $label',
    },
  );
  final data = dataOf(payload);
  final user = Map<String, dynamic>.from(data['user'] as Map);
  return Actor(label, user['uuid'].toString(), data['token'].toString());
}

Future<String> createPrivateChat(ApiClient api, Actor a, Actor b) async {
  final payload = await api.request(
    'POST',
    '/chat/create',
    actor: a,
    body: <String, dynamic>{
      'type': 1,
      'member_ids': <String>[b.userId],
    },
  );
  return dataOf(payload)['uuid'].toString();
}

Future<int> sendText(ApiClient api, Actor actor, String chatId, String text) async {
  final payload = await api.request(
    'POST',
    '/message/send',
    actor: actor,
    body: <String, dynamic>{
      'chat_id': chatId,
      'type': 1,
      'content': <String, dynamic>{'text': text},
      'msg_id': '${DateTime.now().microsecondsSinceEpoch}-${actor.name}',
    },
  );
  return (dataOf(payload)['seq'] as num).toInt();
}

bool activityEvent(Map<String, dynamic> event, String type, Actor actor) {
  return event['type'] == type && event['user_id'] == actor.userId;
}

Future<void> expectActivity(
  WsClient receiver,
  String type,
  Actor actor, {
  required bool expected,
}) async {
  final event = await receiver.waitFor(
    (item) => activityEvent(item, type, actor),
    timeout: expected ? const Duration(seconds: 3) : const Duration(milliseconds: 900),
  );
  check(expected ? event != null : event == null, '$type expected=$expected event=$event');
}

Future<void> main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args[0] : 'http://127.0.0.1:8080/api/v1';
  final outputDir = Directory(
    args.length > 1 ? args[1] : 'artifacts/real-device-qa/local-docker-dual-device-20260717/privacy-activity-api',
  );
  await outputDir.create(recursive: true);
  final api = ApiClient(baseUrl);
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final results = <Map<String, dynamic>>[];
  WsClient? aWs;
  WsClient? bWs;

  void passed(List<String> caseIds, String detail) {
    results.add(<String, dynamic>{'case_ids': caseIds, 'status': 'PASS', 'detail': detail});
  }

  try {
    final a = await createActor(api, 'A', runId);
    final b = await createActor(api, 'B', runId);
    final chatId = await createPrivateChat(api, a, b);
    final wsBase = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    aWs = await WsClient.connect('$wsBase/ws', a);
    bWs = await WsClient.connect('$wsBase/ws', b);
    for (final client in <WsClient>[aWs, bWs]) {
      client.send('subscribe', <String, dynamic>{'chat_ids': <String>[chatId]});
      final subscribed = await client.waitFor((event) => event['type'] == 'subscribed');
      check(subscribed != null, '${client.actor.name} subscribe failed: ${client.events}');
      client.clear();
    }

    aWs.send('typing', <String, dynamic>{'chat_id': chatId, 'action': 'start'});
    await expectActivity(bWs, 'typing', a, expected: true);
    aWs.send('read', <String, dynamic>{'chat_id': chatId, 'msg_seq': 1});
    await expectActivity(bWs, 'read', a, expected: true);

    await api.request(
      'PUT',
      '/user/privacy',
      actor: a,
      body: <String, dynamic>{
        'send_read_receipts': false,
        'show_typing_status': false,
      },
    );
    final privacyOff = dataOf(await api.request('GET', '/user/privacy', actor: a));
    check(privacyOff['send_read_receipts'] == false, 'read receipt setting did not persist');
    check(privacyOff['show_typing_status'] == false, 'typing setting did not persist');
    bWs.clear();
    aWs.send('typing', <String, dynamic>{'chat_id': chatId, 'action': 'start'});
    await expectActivity(bWs, 'typing', a, expected: false);
    aWs.send('read', <String, dynamic>{'chat_id': chatId, 'msg_seq': 2});
    await expectActivity(bWs, 'read', a, expected: false);

    final sentSeq = await sendText(api, b, chatId, 'read receipt privacy $runId');
    bWs.clear();
    await api.request(
      'POST',
      '/message/read',
      actor: a,
      body: <String, dynamic>{'chat_id': chatId, 'msg_seq': sentSeq},
    );
    await expectActivity(bWs, 'read', a, expected: false);
    final query = Uri(queryParameters: <String, String>{
      'chat_id': chatId,
      'before_seq': '0',
      'limit': '100',
    }).query;
    final messagesPayload = await api.request('GET', '/message/list?$query', actor: b);
    final rawMessages = messagesPayload['data'];
    final messages = rawMessages is List<dynamic>
        ? rawMessages
        : ((rawMessages as Map)['list'] ?? rawMessages['messages']) as List<dynamic>;
    final sent = messages.cast<Map>().map(Map<String, dynamic>.from).firstWhere(
          (message) => (message['seq'] as num?)?.toInt() == sentSeq,
        );
    check((sent['status'] as num?)?.toInt() != 3, 'disabled receipt still persisted shared read state');
    passed(<String>['IM-130'], 'read receipts can be disabled without leaking over WS or message history');
    passed(<String>['IM-140'], 'typing status can be disabled and is suppressed by the server');

    await api.request(
      'PUT',
      '/user/privacy',
      actor: a,
      body: <String, dynamic>{
        'send_read_receipts': true,
        'show_typing_status': true,
      },
    );
    bWs.clear();
    aWs.send('typing', <String, dynamic>{'chat_id': chatId, 'action': 'start'});
    await expectActivity(bWs, 'typing', a, expected: true);
    aWs.send('read', <String, dynamic>{'chat_id': chatId, 'msg_seq': sentSeq});
    await expectActivity(bWs, 'read', a, expected: true);

    await api.request(
      'POST',
      '/user/blocked',
      actor: a,
      body: <String, dynamic>{'user_id': b.userId},
    );
    final profile = dataOf(await api.request('GET', '/user/${a.userId}', actor: b));
    check(profile['status'] == 0, 'blocked user can still see online status: $profile');
    check(profile['last_seen'] == null, 'blocked user can still see last seen: $profile');
    check(!profile.containsKey('phone'), 'public blocked profile leaked phone: $profile');

    for (final sender in <Actor>[a, b]) {
      final blockedSend = await api.request(
        'POST',
        '/message/send',
        actor: sender,
        allowBusinessError: true,
        body: <String, dynamic>{
          'chat_id': chatId,
          'type': 1,
          'content': <String, dynamic>{'text': 'blocked send'},
          'msg_id': 'blocked-${sender.name}-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      check(blockedSend['code'] == 403, 'blocked send was not rejected for ${sender.name}: $blockedSend');
    }
    bWs.clear();
    aWs.send('typing', <String, dynamic>{'chat_id': chatId, 'action': 'start'});
    await expectActivity(bWs, 'typing', a, expected: false);
    aWs.send('read', <String, dynamic>{'chat_id': chatId, 'msg_seq': sentSeq});
    await expectActivity(bWs, 'read', a, expected: false);
    passed(
      <String>['IM-393'],
      'bilateral block suppresses messaging, typing, read receipts, online status, last seen and phone disclosure',
    );

    await api.request('DELETE', '/user/blocked/${b.userId}', actor: a);
    bWs.clear();
    aWs.send('typing', <String, dynamic>{'chat_id': chatId, 'action': 'start'});
    await expectActivity(bWs, 'typing', a, expected: true);
    await sendText(api, a, chatId, 'unblocked recovery $runId');
    passed(<String>['IM-130', 'IM-140', 'IM-393'], 'restoring settings and unblocking restores normal activity');

    final report = <String, dynamic>{
      'run_id': runId,
      'base_url': baseUrl,
      'chat_id': chatId,
      'actors': <String, String>{'a': a.userId, 'b': b.userId},
      'results': results,
      'status': results.every((item) => item['status'] == 'PASS') ? 'PASS' : 'FAIL',
      'tested_at': DateTime.now().toIso8601String(),
    };
    final output = File('${outputDir.path}${Platform.pathSeparator}privacy-activity-$runId.json');
    await output.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(output.path);
  } finally {
    await aWs?.close();
    await bWs?.close();
    api.close();
  }
}
