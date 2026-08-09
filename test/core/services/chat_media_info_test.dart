import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/chat_service.dart';

void main() {
  test('media payload keeps lifecycle identifiers', () {
    final media = MediaInfo(
      mediaId: 'video-media-id',
      url: 'https://media.example.com/video.mp4',
      thumbnailMediaId: 'thumbnail-media-id',
      thumbnail: 'https://media.example.com/thumbnail.jpg',
      size: 1024,
      mimeType: 'video/mp4',
    );

    final json = media.toJson();
    expect(json['media_id'], 'video-media-id');
    expect(json['thumbnail_media_id'], 'thumbnail-media-id');

    final decoded = MediaInfo.fromJson(json);
    expect(decoded.mediaId, 'video-media-id');
    expect(decoded.thumbnailMediaId, 'thumbnail-media-id');
  });

  test('voice and file payloads keep media id', () {
    expect(
      VoiceInfo(
        mediaId: 'voice-media-id',
        url: '/voice.m4a',
        duration: 1000,
        size: 100,
      ).toJson()['media_id'],
      'voice-media-id',
    );
    expect(
      FileInfo(
        mediaId: 'file-media-id',
        url: '/report.pdf',
        name: 'report.pdf',
        size: 200,
        mimeType: 'application/pdf',
      ).toJson()['media_id'],
      'file-media-id',
    );
  });
}
