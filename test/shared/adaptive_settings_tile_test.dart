import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/shared/widgets/adaptive_settings_tile.dart';

Widget _host({required double width, required double textScale}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: AdaptiveSettingsTapTile(
              title: '清除本机账号数据',
              subtitle: '删除当前账号聊天、草稿、离线消息和私有媒体；保留加密密钥',
              titleStyle: const TextStyle(fontSize: 16, color: Colors.red),
              subtitleStyle: const TextStyle(fontSize: 15, color: Colors.grey),
              chevronColor: Colors.grey,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('stacks long localized text on a narrow screen', (tester) async {
    await tester.pumpWidget(_host(width: 320, textScale: 1));

    expect(tester.takeException(), isNull);
    final titleTop = tester.getTopLeft(find.text('清除本机账号数据')).dy;
    final subtitleTop =
        tester.getTopLeft(find.text('删除当前账号聊天、草稿、离线消息和私有媒体；保留加密密钥')).dy;
    expect(subtitleTop, greaterThan(titleTop));
  });

  testWidgets('does not overflow with accessibility text scaling',
      (tester) async {
    await tester.pumpWidget(_host(width: 360, textScale: 2));

    expect(tester.takeException(), isNull);
    expect(find.text('清除本机账号数据'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
