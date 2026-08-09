import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/chat_service.dart' as api;
import 'package:generic_im/core/services/storage/models/message_model.dart';
import 'package:generic_im/features/chat/providers/message_provider.dart';

MessageItem _message({
  required String id,
  required int seq,
  MessageStatus status = MessageStatus.sent,
  DateTime? createdAt,
  String content = 'hello',
  bool isEdited = false,
  DateTime? editedAt,
  bool isOutgoing = true,
  bool burnAfterRead = false,
  bool burnLocked = false,
  int? burnCountdownSeconds,
  String? localPath,
  String? mediaUrl,
  String? mediaId,
  MessageItemType type = MessageItemType.text,
}) {
  return MessageItem(
    id: id,
    chatId: 'chat-1',
    senderId: 'user-1',
    senderName: 'User',
    content: content,
    status: status,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    seq: seq,
    isEdited: isEdited,
    editedAt: editedAt,
    isOutgoing: isOutgoing,
    burnAfterRead: burnAfterRead,
    burnLocked: burnLocked,
    burnCountdownSeconds: burnCountdownSeconds,
    localPath: localPath,
    mediaUrl: mediaUrl,
    mediaId: mediaId,
    type: type,
  );
}

void main() {
  test('message item keeps private media identifiers for URL resolution', () {
    final message = api.Message.fromJson({
      'msg_id': 'msg-1',
      'chat_id': 'chat-1',
      'seq': 1,
      'sender_id': 'user-2',
      'sender_name': 'User 2',
      'type': 3,
      'content': {
        'media': {
          'media_id': 'video-media-id',
          'thumbnail_media_id': 'thumbnail-media-id',
          'url': 'https://bucket.s3.amazonaws.com/video.mp4',
          'thumbnail': 'https://bucket.s3.amazonaws.com/thumb.jpg',
          'size': 10,
          'mime_type': 'video/mp4',
        },
      },
      'created_at': '2026-07-27T00:00:00Z',
    });

    final item = MessageItem.fromApiMessage(message, 'user-1');

    expect(item.mediaId, 'video-media-id');
    expect(item.thumbnailMediaId, 'thumbnail-media-id');
    expect(
      item.mediaUrl,
      isNull,
      reason: 'private S3 objects must wait for an authenticated access URL',
    );
    expect(
      item.thumbnail,
      isNull,
      reason: 'private S3 thumbnails must not start an unsigned 403 request',
    );
  });

  test('legacy public media URL remains immediately displayable', () {
    final message = api.Message.fromJson({
      'msg_id': 'msg-public',
      'chat_id': 'chat-1',
      'seq': 2,
      'sender_id': 'user-2',
      'sender_name': 'User 2',
      'type': 2,
      'content': {
        'media': {
          'url': 'https://cdn.example.com/image.jpg',
          'size': 10,
          'mime_type': 'image/jpeg',
        },
      },
      'created_at': '2026-07-27T00:00:00Z',
    });

    final item = MessageItem.fromApiMessage(message, 'user-1');

    expect(item.mediaId, isNull);
    expect(item.mediaUrl, 'https://cdn.example.com/image.jpg');
  });

  test('unsigned CloudFront media waits for its authenticated access URL', () {
    final message = api.Message.fromJson({
      'msg_id': 'msg-cloudfront',
      'chat_id': 'chat-1',
      'seq': 3,
      'sender_id': 'user-2',
      'sender_name': 'User 2',
      'type': 2,
      'content': {
        'media': {
          'media_id': 'cloudfront-media-id',
          'thumbnail_media_id': 'cloudfront-thumbnail-id',
          'url':
              'https://d45wtpn3fz3we.cloudfront.net/uploads/images/object.png',
          'thumbnail':
              'https://d45wtpn3fz3we.cloudfront.net/uploads/images/object_thumbnail.jpg',
          'size': 10,
          'mime_type': 'image/png',
        },
      },
      'created_at': '2026-07-27T00:00:00Z',
    });

    final item = MessageItem.fromApiMessage(message, 'user-1');

    expect(item.mediaUrl, isNull);
    expect(item.thumbnail, isNull);
  });

  test('cached message keeps private video and thumbnail identifiers', () {
    final cached = MessageModel()
      ..accountId = 'user-1'
      ..id = 'message-1'
      ..chatId = 'chat-1'
      ..senderId = 'user-2'
      ..senderName = 'User 2'
      ..senderAvatar = null
      ..senderNicknameColor = null
      ..senderEmojiAvatar = null
      ..type = MsgType.video
      ..content = ''
      ..seq = 1
      ..localPath = null
      ..remoteUrl = null
      ..mediaId = 'video-media-id'
      ..thumbnail = null
      ..thumbnailMediaId = 'thumbnail-media-id'
      ..mediaWidth = 1920
      ..mediaHeight = 1080
      ..mediaSize = 100
      ..mediaDuration = 5000
      ..fileName = null
      ..isOutgoing = false
      ..status = MsgStatus.sent
      ..isRead = false
      ..replyToId = null
      ..replyToPreview = null
      ..forwardFrom = null
      ..reactions = null
      ..contactUserId = null
      ..contactName = null
      ..contactAvatar = null
      ..contactUsername = null
      ..createdAt = DateTime(2026, 7, 27)
      ..cachedAt = DateTime(2026, 7, 27)
      ..editedAt = null
      ..isDeleted = false
      ..burnAfterRead = false
      ..burnAfterSeconds = 0;

    final item = MessageItem.fromMessageModel(cached);

    expect(item.mediaId, 'video-media-id');
    expect(item.thumbnailMediaId, 'thumbnail-media-id');
  });

  group('burn-after-read reliability', () {
    test('unopened incoming burn message blocks cumulative read cursor', () {
      final messages = [
        _message(id: 'normal-12', seq: 12, isOutgoing: false),
        _message(
          id: 'burn-11',
          seq: 11,
          isOutgoing: false,
          burnAfterRead: true,
          burnLocked: true,
        ),
        _message(id: 'normal-10', seq: 10, isOutgoing: false),
      ];

      expect(debugLatestReadableSeqBeforeLockedBurn(messages, 12), 10);
    });

    test('revealed burn message allows read cursor to advance', () {
      final messages = [
        _message(id: 'normal-12', seq: 12, isOutgoing: false),
        _message(
          id: 'burn-11',
          seq: 11,
          isOutgoing: false,
          burnAfterRead: true,
          burnCountdownSeconds: 10,
        ),
      ];

      expect(debugLatestReadableSeqBeforeLockedBurn(messages, 12), 12);
    });

    test('burned receipt keeps placeholder and active countdown locally', () {
      final locked = _message(
        id: 'burn-10',
        seq: 10,
        isOutgoing: false,
        burnAfterRead: true,
      );
      final revealed = _message(
        id: 'burn-11',
        seq: 11,
        isOutgoing: false,
        burnAfterRead: true,
        burnCountdownSeconds: 8,
      );

      final result = debugApplyBurnedReceipt([revealed, locked], 11);

      expect(result, hasLength(2));
      expect(result.last.id, 'burn-10');
      expect(result.last.burnLocked, isTrue);
      expect(result.last.status, MessageStatus.read);
      expect(result.first.id, 'burn-11');
      expect(result.first.burnCountdownSeconds, 8);
      expect(result.first.burnLocked, isFalse);
    });
  });

  test('merged forward retries per target with one stable id', () async {
    final attempts = <String, List<String>>{};
    final results = await forwardBundleToTargetsReliably(
      const ['chat-a', 'chat-a', 'chat-b'],
      (targetId, clientMsgId) async {
        attempts.putIfAbsent(targetId, () => []).add(clientMsgId);
        return targetId == 'chat-b' || attempts[targetId]!.length > 1;
      },
      retryDelay: Duration.zero,
      clientMsgIdFactory: () => 'bundle-id-${attempts.length}',
    );

    expect(results.length, 2);
    expect(results.every((result) => result.succeeded), isTrue);
    expect(attempts['chat-a']!.length, 2);
    expect(attempts['chat-a']!.toSet().length, 1);
    expect(attempts['chat-b']!.length, 1);
  });

  test('rapid sends reach the server in submission order', () async {
    final queue = SequentialMessageSendQueue();
    final started = <int>[];
    final finished = <int>[];

    final tasks = List.generate(10, (index) {
      return queue.enqueue(() async {
        started.add(index);
        await Future<void>.delayed(
          Duration(milliseconds: index.isEven ? 8 : 1),
        );
        finished.add(index);
        return index;
      });
    });

    final results = await Future.wait(tasks);

    expect(started, List.generate(10, (index) => index));
    expect(finished, List.generate(10, (index) => index));
    expect(results, List.generate(10, (index) => index));
  });

  test('server acknowledged message replaces local sending placeholder', () {
    final local = _message(
      id: 'client-1',
      seq: 0,
      status: MessageStatus.sending,
      createdAt: DateTime(2026, 1, 1, 10),
    );
    final server = _message(
      id: 'client-1',
      seq: 12,
      status: MessageStatus.sent,
      createdAt: DateTime(2026, 1, 1, 10, 0, 2),
    );

    final result = debugDedupeReliableMessageWindow([local, server]);

    expect(result, hasLength(1));
    expect(result.single.id, 'client-1');
    expect(result.single.seq, 12);
    expect(result.single.status, MessageStatus.sent);
  });

  test('messages with server seq are ordered by seq, not arrival time', () {
    final newerByTime = _message(
      id: 'm-1',
      seq: 10,
      createdAt: DateTime(2026, 1, 1, 10, 0, 5),
    );
    final newerBySeq = _message(
      id: 'm-2',
      seq: 11,
      createdAt: DateTime(2026, 1, 1, 10),
    );

    final result = debugDedupeReliableMessageWindow([newerByTime, newerBySeq]);

    expect(result.map((m) => m.id), ['m-2', 'm-1']);
  });

  test('multi-forward restores authoritative server sequence order', () {
    final newestFirst = [
      _message(id: 'm-12', seq: 12),
      _message(id: 'm-10', seq: 10),
      _message(id: 'm-11', seq: 11),
    ];

    final result = orderMessagesForForward(newestFirst);

    expect(result.map((message) => message.id), ['m-10', 'm-11', 'm-12']);
  });

  test('multi-forward fallback preserves displayed order for tied timestamps',
      () {
    final sameTime = DateTime(2026, 7, 16, 20);
    final messages = [
      _message(id: 'pending-b', seq: 0, createdAt: sameTime),
      _message(id: 'server', seq: 5, createdAt: sameTime),
      _message(id: 'pending-a', seq: 0, createdAt: sameTime),
    ];

    final result = orderMessagesForForward(messages);

    expect(result.map((message) => message.id), [
      'server',
      'pending-b',
      'pending-a',
    ]);
  });

  test('multi-forward retries one failure and continues with stable ids',
      () async {
    final messages = [
      _message(id: 'm-a', seq: 10),
      _message(id: 'm-b', seq: 11),
    ];
    final calls = <String>[];
    var firstMessageAttempts = 0;
    var idCounter = 0;

    final result = await forwardMessagesReliably(
      messages,
      (message, clientMsgId) async {
        calls.add('${message.id}:$clientMsgId');
        if (message.id == 'm-a' && firstMessageAttempts++ == 0) {
          return false;
        }
        return true;
      },
      retryDelay: Duration.zero,
      clientMsgIdFactory: () => 'client-${idCounter++}',
    );

    expect(calls, [
      'm-a:client-0',
      'm-a:client-0',
      'm-b:client-1',
    ]);
    expect(result.successCount, 2);
    expect(result.failedMessageIds, isEmpty);
    expect(result.isComplete, isTrue);
  });

  test('multi-forward reports a permanent failure without aborting', () async {
    final messages = [
      _message(id: 'm-a', seq: 10),
      _message(id: 'm-b', seq: 11),
    ];
    final attempted = <String>[];

    final result = await forwardMessagesReliably(
      messages,
      (message, _) async {
        attempted.add(message.id);
        return message.id == 'm-b';
      },
      retryDelay: Duration.zero,
      clientMsgIdFactory: () => 'fixed',
    );

    expect(attempted, ['m-a', 'm-a', 'm-b']);
    expect(result.successCount, 1);
    expect(result.failedMessageIds, ['m-a']);
    expect(result.isComplete, isFalse);
  });

  test('multi-target forward deduplicates targets and isolates failures',
      () async {
    final messages = [
      _message(id: 'm-a', seq: 10),
      _message(id: 'm-b', seq: 11),
    ];
    final calls = <String>[];
    var idCounter = 0;

    final results = await forwardMessagesToTargetsReliably(
      messages,
      ['chat-b', 'chat-a', 'chat-b', '  '],
      (targetId, message, clientMsgId) async {
        calls.add('$targetId:${message.id}:$clientMsgId');
        return !(targetId == 'chat-b' && message.id == 'm-a');
      },
      retryDelay: Duration.zero,
      clientMsgIdFactory: () => 'client-${idCounter++}',
    );

    expect(results.map((item) => item.targetChatId), ['chat-b', 'chat-a']);
    expect(results.first.messages.failedMessageIds, ['m-a']);
    expect(results.last.messages.isComplete, isTrue);
    expect(calls, [
      'chat-b:m-a:client-0',
      'chat-b:m-a:client-0',
      'chat-b:m-b:client-1',
      'chat-a:m-a:client-2',
      'chat-a:m-b:client-3',
    ]);
  });

  test('duplicate server seq keeps the authoritative server message', () {
    final localEcho = _message(
      id: 'local_1',
      seq: 20,
      status: MessageStatus.sending,
    );
    final server = _message(
      id: 'server-1',
      seq: 20,
      status: MessageStatus.read,
    );

    final result = debugDedupeReliableMessageWindow([localEcho, server]);

    expect(result, hasLength(1));
    expect(result.single.id, 'server-1');
    expect(result.single.status, MessageStatus.read);
  });

  test('offline sync merge only inserts missing server messages', () {
    final current = [
      _message(id: 'm-3', seq: 3),
      _message(id: 'm-1', seq: 1),
    ];
    final incoming = [
      _message(id: 'm-2', seq: 2),
      _message(id: 'dup-by-seq', seq: 3),
      _message(id: 'm-1', seq: 1),
    ];

    final result = debugMergeReliableSyncedWindow(current, incoming);

    expect(result.map((m) => m.id), ['m-3', 'm-2', 'm-1']);
  });

  test('recent reconciliation heals an edit that kept the same seq', () {
    final createdAt = DateTime(2026, 1, 1, 10);
    final editedAt = DateTime(2026, 1, 1, 10, 5);
    final current = [
      _message(
        id: 'm-1',
        seq: 8,
        content: 'before edit',
        status: MessageStatus.read,
        createdAt: createdAt,
      ),
    ];
    final snapshot = [
      _message(
        id: 'm-1',
        seq: 8,
        content: 'after edit',
        isEdited: true,
        editedAt: editedAt,
        createdAt: createdAt.add(const Duration(seconds: 2)),
      ),
    ];

    final result = debugReconcileReliableMessageWindow(current, snapshot);

    expect(result, hasLength(1));
    expect(result.single.content, 'after edit');
    expect(result.single.isEdited, isTrue);
    expect(result.single.editedAt, editedAt);
    expect(result.single.seq, 8);
    expect(result.single.status, MessageStatus.read);
    expect(result.single.createdAt, createdAt);
  });

  test('server reconciliation preserves a persistent outgoing media path', () {
    final current = [
      _message(
        id: 'image-1',
        seq: 0,
        status: MessageStatus.sending,
        type: MessageItemType.image,
        localPath: '/Application Support/account_media/outgoing/image-1.jpg',
        mediaUrl: '/Application Support/account_media/outgoing/image-1.jpg',
      ),
    ];
    final snapshot = [
      _message(
        id: 'image-1',
        seq: 81,
        type: MessageItemType.image,
        mediaId: 'media-1',
      ),
    ];

    final result = debugReconcileReliableMessageWindow(current, snapshot);

    expect(result, hasLength(1));
    expect(
      result.single.localPath,
      '/Application Support/account_media/outgoing/image-1.jpg',
    );
    expect(result.single.mediaId, 'media-1');
    expect(result.single.seq, 81);
  });

  test('recent reconciliation preserves messages outside server window', () {
    final current = [
      _message(id: 'm-40', seq: 40),
      _message(id: 'm-1', seq: 1),
    ];
    final snapshot = [
      _message(id: 'm-40', seq: 40, content: 'server snapshot'),
      _message(id: 'm-39', seq: 39),
    ];

    final result = debugReconcileReliableMessageWindow(current, snapshot);

    expect(result.map((message) => message.id), ['m-40', 'm-39', 'm-1']);
    expect(result.first.content, 'server snapshot');
  });

  test('sparse latest local window needs initial history backfill', () {
    final localWindow = [
      _message(id: 'm-68', seq: 68),
      _message(id: 'm-67', seq: 67),
      _message(id: 'm-66', seq: 66),
      _message(id: 'm-65', seq: 65),
    ];

    expect(debugShouldBackfillInitialHistoryWindow(localWindow), isTrue);
  });

  test('full local window does not trigger initial history backfill', () {
    final localWindow = List.generate(
      30,
      (index) => _message(id: 'm-${30 - index}', seq: 30 - index),
    );

    expect(debugShouldBackfillInitialHistoryWindow(localWindow), isFalse);
  });

  test('history starting from first seq does not trigger backfill', () {
    final localWindow = [
      _message(id: 'm-1', seq: 1),
    ];

    expect(debugShouldBackfillInitialHistoryWindow(localWindow), isFalse);
  });

  test('active realtime window stays bounded and preserves a failed send', () {
    final messages = List<MessageItem>.generate(250, (index) {
      final seq = 250 - index;
      return _message(
        id: 'm-$seq',
        seq: seq,
        status: seq == 1 ? MessageStatus.failed : MessageStatus.sent,
      );
    });

    final result = boundActiveRealtimeMessageWindow(messages, limit: 200);

    expect(result, hasLength(200));
    expect(result.first.seq, 250);
    expect(result.any((message) => message.id == 'm-1'), isTrue);
    expect(result.map((message) => message.id).toSet(), hasLength(200));
  });

  test('persistence batch keeps the latest snapshot per message id', () async {
    final writes = <List<MessageItem>>[];
    final batcher = MessagePersistenceBatcher(
      (messages) async => writes.add(messages),
      delay: const Duration(hours: 1),
    );

    batcher.addAll([
      _message(id: 'm-1', seq: 1, content: 'old'),
      _message(id: 'm-2', seq: 2),
    ]);
    batcher.addAll([
      _message(id: 'm-1', seq: 3, content: 'latest'),
    ]);
    await batcher.flushNow();

    expect(writes, hasLength(1));
    expect(writes.single, hasLength(2));
    expect(
      writes.single.singleWhere((message) => message.id == 'm-1').content,
      'latest',
    );
    expect(batcher.pendingCount, 0);
    await batcher.close();
  });
}
