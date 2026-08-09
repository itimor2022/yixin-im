import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/voice_playback_audio_context.dart';
import 'package:generic_im/core/services/voice_playback_queue.dart';

VoicePlaybackQueueItem item(
  String id, {
  String chatId = 'chat-1',
  int seq = 0,
  int second = 0,
}) {
  return VoicePlaybackQueueItem(
    id: id,
    chatId: chatId,
    seq: seq,
    createdAt: DateTime(2026, 7, 16, 16, 0, second),
  );
}

void main() {
  test('voice queue advances by authoritative sequence in the same chat', () {
    final result = nextVoicePlaybackId(
      items: [
        item('later-arrival', seq: 12, second: 1),
        item('current', seq: 10, second: 9),
        item('next', seq: 11, second: 5),
        item('other-chat', chatId: 'chat-2', seq: 11),
      ],
      currentId: 'current',
    );

    expect(result, 'next');
  });

  test('voice queue falls back to creation time before server sequence', () {
    final result = nextVoicePlaybackId(
      items: [
        item('third', second: 3),
        item('first', second: 1),
        item('second', second: 2),
      ],
      currentId: 'first',
    );

    expect(result, 'second');
  });

  test('voice queue stops at the last item or a missing item', () {
    final items = [item('first', seq: 1), item('last', seq: 2)];

    expect(
      nextVoicePlaybackId(items: items, currentId: 'last'),
      isNull,
    );
    expect(
      nextVoicePlaybackId(items: items, currentId: 'missing'),
      isNull,
    );
  });

  test('proximity temporarily overrides the preferred playback route', () {
    expect(
      resolveVoicePlaybackRoute(
        preferredRoute: VoicePlaybackRoute.speaker,
        proximityNear: false,
      ),
      VoicePlaybackRoute.speaker,
    );
    expect(
      resolveVoicePlaybackRoute(
        preferredRoute: VoicePlaybackRoute.speaker,
        proximityNear: true,
      ),
      VoicePlaybackRoute.earpiece,
    );
    expect(
      resolveVoicePlaybackRoute(
        preferredRoute: VoicePlaybackRoute.earpiece,
        proximityNear: false,
      ),
      VoicePlaybackRoute.earpiece,
    );
  });
}
