import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/utils/chat_attachment_menu_layout.dart';

void main() {
  test('nine enabled actions create pages of eight and one', () {
    final pages =
        paginateChatAttachmentActions(List<int>.generate(9, (i) => i));

    expect(pages, hasLength(2));
    expect(pages.first, orderedEquals(List<int>.generate(8, (i) => i)));
    expect(pages.last, orderedEquals([8]));
  });

  test('filtered actions keep order and do not leave gaps', () {
    final pages = paginateChatAttachmentActions(['album', 'call', 'burn']);

    expect(pages, hasLength(1));
    expect(pages.single, orderedEquals(['album', 'call', 'burn']));
  });

  test('only burn after read remains on the first page', () {
    final pages = paginateChatAttachmentActions(['burn']);

    expect(pages, hasLength(1));
    expect(pages.single, orderedEquals(['burn']));
  });

  test('empty actions produce no pages', () {
    expect(paginateChatAttachmentActions<Object>([]), isEmpty);
  });

  test('invalid page size is rejected', () {
    expect(
      () => paginateChatAttachmentActions([1], pageSize: 0),
      throwsArgumentError,
    );
  });
}
