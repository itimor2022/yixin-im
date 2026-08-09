import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:generic_im/features/settings/pages/profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final viewports = <Size>[
    const Size(320, 568),
    const Size(393, 852),
    const Size(800, 1280),
  ];

  for (final viewport in viewports) {
    testWidgets(
      'QR card stays square without overflow at '
      '${viewport.width.toInt()}x${viewport.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ProfileQRCodePage(
                userUuid: 'layout-test-user',
                displayName: '兼容性测试用户昵称很长很长',
                username: 'layout_test_user',
                isSelfEntry: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        final qrFinder = find.byType(QrImageView);
        expect(qrFinder, findsOneWidget);
        final qrSize = tester.getSize(qrFinder);
        expect(qrSize.width, closeTo(qrSize.height, 0.01));
        expect(qrSize.width, lessThan(viewport.width));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('QR card supports enlarged Android system text', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(360, 720),
              textScaler: TextScaler.linear(2),
            ),
            child: ProfileQRCodePage(
              userUuid: 'layout-test-user',
              displayName: '兼容性测试用户昵称很长很长',
              username: 'layout_test_user',
              isSelfEntry: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final qrSize = tester.getSize(find.byType(QrImageView));
    expect(qrSize.width, closeTo(qrSize.height, 0.01));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
