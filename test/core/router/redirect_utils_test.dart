import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/router/redirect_utils.dart';

void main() {
  group('safeInAppRedirect', () {
    test('allows internal app routes with query strings', () {
      expect(
        safeInAppRedirect('/user/abc?chat_id=123'),
        '/user/abc?chat_id=123',
      );
    });

    test('rejects external and protocol-relative urls', () {
      expect(safeInAppRedirect('https://example.com/user/abc'), isNull);
      expect(safeInAppRedirect('//example.com/user/abc'), isNull);
    });

    test('rejects auth routes to avoid login redirect loops', () {
      expect(safeInAppRedirect('/'), isNull);
      expect(safeInAppRedirect('/login'), isNull);
      expect(safeInAppRedirect('/register'), isNull);
      expect(safeInAppRedirect('/forgot-password'), isNull);
    });
  });

  group('loginLocationWithRedirect', () {
    test('encodes the current internal route', () {
      expect(
        loginLocationWithRedirect(Uri.parse('/user/abc?chat_id=123')),
        '/login?redirect=%2Fuser%2Fabc%3Fchat_id%3D123',
      );
    });

    test('falls back to login for auth routes', () {
      expect(loginLocationWithRedirect(Uri.parse('/')), '/login');
      expect(loginLocationWithRedirect(Uri.parse('/login')), '/login');
    });
  });

  group('splashLocationWithRedirect', () {
    test('encodes a protected deep link for cold start', () {
      expect(
        splashLocationWithRedirect(Uri.parse('/user/abc?chat_id=123')),
        '/?redirect=%2Fuser%2Fabc%3Fchat_id%3D123',
      );
    });

    test('falls back to splash for auth routes', () {
      expect(splashLocationWithRedirect(Uri.parse('/')), '/');
      expect(splashLocationWithRedirect(Uri.parse('/login')), '/');
    });
  });
}
