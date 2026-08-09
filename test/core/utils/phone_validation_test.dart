import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/utils/phone_validation.dart';

void main() {
  group('isValidMainlandChinaMobile', () {
    test('accepts supported mainland mobile prefixes', () {
      expect(isValidMainlandChinaMobile('13800138000'), isTrue);
      expect(isValidMainlandChinaMobile('19912345678'), isTrue);
      expect(isValidMainlandChinaMobile(' 15812345678 '), isTrue);
    });

    test('rejects invalid prefixes and malformed values', () {
      expect(isValidMainlandChinaMobile('10000000000'), isFalse);
      expect(isValidMainlandChinaMobile('12000000000'), isFalse);
      expect(isValidMainlandChinaMobile('1380013800'), isFalse);
      expect(isValidMainlandChinaMobile('+8613800138000'), isFalse);
      expect(isValidMainlandChinaMobile('1380013800a'), isFalse);
    });
  });
}
