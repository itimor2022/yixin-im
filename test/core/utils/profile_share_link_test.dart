import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/utils/profile_share_link.dart';

void main() {
  const userId = '0c557813-6154-4354-bcd4-8eab4e77b3ee';

  test('normalizes an H5 origin to the client-open landing page', () {
    final url = buildUserProfileShareUrl(
      userId: userId,
      name: '这个',
      configuredBaseUrl: 'https://h5.example.com/',
    );

    expect(
      url,
      'https://h5.example.com/open.html?type=user&id=$userId&name=%E8%BF%99%E4%B8%AA',
    );
  });

  test('does not duplicate an existing hash marker', () {
    final url = buildUserProfileShareUrl(
      userId: userId,
      configuredBaseUrl: 'https://h5.example.com/#/',
    );

    expect(
      url,
      'https://h5.example.com/open.html?type=user&id=$userId',
    );
  });

  test('rejects an API setting and uses the compiled H5 fallback', () {
    final url = buildUserProfileShareUrl(
      userId: userId,
      configuredBaseUrl: 'https://api.example.com',
      compiledPublicH5Url: 'https://h5.example.com',
    );

    expect(
      url,
      'https://h5.example.com/open.html?type=user&id=$userId',
    );
  });

  test('uses the current web origin if the configured value is an API', () {
    final url = buildUserProfileShareUrl(
      userId: userId,
      configuredBaseUrl: 'https://api.example.com/api/v1',
      currentWebUri: Uri.parse('https://h5.example.com/#/home'),
    );

    expect(
      url,
      'https://h5.example.com/open.html?type=user&id=$userId',
    );
  });

  test('returns empty when no public H5 origin is available', () {
    expect(
      buildUserProfileShareUrl(
        userId: userId,
        configuredBaseUrl: 'https://api.example.com',
      ),
      isEmpty,
    );
  });
}
