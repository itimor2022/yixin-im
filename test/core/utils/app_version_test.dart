import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/utils/app_version.dart';

void main() {
  test('compares semantic version and build number components', () {
    expect(compareAppVersions('5.0.1+40', '5.0.0+39'), greaterThan(0));
    expect(compareAppVersions('5.0.0+40', '5.0.0+39'), greaterThan(0));
    expect(compareAppVersions('5.0.0+39', '5.0.1+1'), lessThan(0));
  });

  test('treats missing components as zero', () {
    expect(compareAppVersions('5.0', '5.0.0'), 0);
    expect(compareAppVersions('', '0.0.0'), 0);
  });

  test('supports minimum-version gating', () {
    const current = '5.0.0+39';
    expect(compareAppVersions('5.0.1', current), greaterThan(0));
    expect(compareAppVersions('5.0.0', current), lessThan(0));
  });
}
