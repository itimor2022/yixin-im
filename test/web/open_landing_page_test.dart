import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client-open landing page contains app and H5 fallbacks', () {
    final html = File('web/open.html').readAsStringSync();

    expect(html, contains('genericim://user/'));
    expect(html, contains('/#/user/'));
    expect(html, contains('打开客户端'));
    expect(html, contains('继续使用网页版'));
    expect(html, contains('location.replace(webUrl)'));
  });
}
