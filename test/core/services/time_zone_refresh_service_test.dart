import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/time_zone_refresh_service.dart';

void main() {
  test('time zone refresh is requested only when offset changes', () {
    expect(
      didTimeZoneOffsetChange(
        const Duration(hours: 8),
        const Duration(hours: 9),
      ),
      isTrue,
    );
    expect(
      didTimeZoneOffsetChange(
        const Duration(hours: 8),
        const Duration(hours: 8),
      ),
      isFalse,
    );
  });

  test('current local time keeps the instant through a UTC round trip', () {
    final cachedLocal = DateTime.parse('2026-07-17T02:49:00+08:00').toLocal();

    final refreshed = toCurrentLocalTime(cachedLocal);

    expect(refreshed.isUtc, isFalse);
    expect(
      refreshed.microsecondsSinceEpoch,
      cachedLocal.microsecondsSinceEpoch,
    );
    expect(refreshed, cachedLocal.toUtc().toLocal());
  });
}
