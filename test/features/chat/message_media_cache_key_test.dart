import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/providers/message_provider.dart';
import 'package:generic_im/features/chat/widgets/message_bubble.dart';

Widget _app(MessageItem message) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MessageBubble(message: message),
      ),
    ),
  );
}

MessageItem _mediaMessage({
  required MessageItemType type,
  required String mediaId,
  String? thumbnailMediaId,
  String? thumbnail,
}) {
  return MessageItem(
    id: 'message-$mediaId',
    chatId: 'chat-1',
    senderId: 'user-2',
    senderName: 'User 2',
    type: type,
    content: '',
    mediaId: mediaId,
    mediaUrl: 'https://s3.example.com/object?X-Amz-Signature=video',
    thumbnailMediaId: thumbnailMediaId,
    thumbnail: thumbnail,
    mediaSize: 1024,
    mediaDuration: type == MessageItemType.video ? 5000 : null,
    isOutgoing: false,
    status: MessageStatus.sent,
    createdAt: DateTime(2026, 7, 27),
    seq: 1,
  );
}

void main() {
  testWidgets('video thumbnail cache identity survives signed URL rotation',
      (tester) async {
    await tester.pumpWidget(
      _app(
        _mediaMessage(
          type: MessageItemType.video,
          mediaId: 'video-media-id',
          thumbnailMediaId: 'thumbnail-media-id',
          thumbnail:
              'https://s3.example.com/thumb.jpg?X-Amz-Signature=short-lived',
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'media:thumbnail-media-id');
  });

  testWidgets('image cache identity uses the private media id', (tester) async {
    await tester.pumpWidget(
      _app(
        _mediaMessage(
          type: MessageItemType.image,
          mediaId: 'image-media-id',
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'media:image-media-id');
  });
}
