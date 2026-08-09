import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/chat_service.dart';

void main() {
  test('normalizes mention-all separately from explicit member ids', () {
    final result = normalizeMessageMentions(
      const ['member-a', '__all__', 'member-a', 'member-b'],
    );

    expect(result.mentionAll, isTrue);
    expect(result.memberIds, const ['member-a', 'member-b']);
  });

  test('does not send a reserved sentinel as a member id', () {
    final result = normalizeMessageMentions(const ['__all__']);

    expect(result.mentionAll, isTrue);
    expect(result.memberIds, isNull);
  });
}
