import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/android_notification_settings_service.dart';

void main() {
  test('background restriction status reports either restriction source', () {
    expect(
      AndroidBackgroundRestrictionStatus.fromMap({
        'ignoring_battery_optimizations': false,
        'background_restricted': false,
      }).needsAttention,
      isTrue,
    );
    expect(
      AndroidBackgroundRestrictionStatus.fromMap({
        'ignoring_battery_optimizations': true,
        'background_restricted': true,
      }).needsAttention,
      isTrue,
    );
    expect(
      AndroidBackgroundRestrictionStatus.fromMap({
        'ignoring_battery_optimizations': true,
        'background_restricted': false,
      }).needsAttention,
      isFalse,
    );
  });
}
