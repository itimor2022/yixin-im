import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/deep_link_service.dart';

void main() {
  group('appRouteFromExternalLink', () {
    test('maps a shared user link to the profile route', () {
      expect(
        appRouteFromExternalLink(
          'genericim://user/0c557813-6154-4354-bcd4-8eab4e77b3ee'
          '?name=%E8%BF%99%E4%B8%AA',
        ),
        '/user/0c557813-6154-4354-bcd4-8eab4e77b3ee'
        '?name=%E8%BF%99%E4%B8%AA',
      );
    });

    test('keeps only supported display query parameters', () {
      expect(
        appRouteFromExternalLink(
          'genericim://user/user-1?name=Alice&avatar=https%3A%2F%2Fimg.test%2Fa.png&admin=true',
        ),
        '/user/user-1?name=Alice&avatar=https%3A%2F%2Fimg.test%2Fa.png',
      );
    });

    test('rejects unsupported, incomplete, and web links', () {
      expect(appRouteFromExternalLink('genericim://group/invite-1'), isNull);
      expect(appRouteFromExternalLink('genericim://user'), isNull);
      expect(appRouteFromExternalLink('https://h5.example.com'), isNull);
    });
  });
}
