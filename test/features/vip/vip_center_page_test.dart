import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/features/vip/pages/vip_center_page.dart';
import 'package:generic_im/features/vip/providers/vip_provider.dart';
import 'package:generic_im/features/vip/services/vip_service.dart';
import 'package:generic_im/features/wallet/providers/wallet_provider.dart';
import 'package:generic_im/features/wallet/services/wallet_service.dart';

class _FixedWalletNotifier extends WalletNotifier {
  _FixedWalletNotifier()
      : super(WalletService(ApiClient()), 'vip-ui-test-account') {
    state = WalletState(
      wallet: WalletInfo(
        id: 1,
        balance: 200,
        frozenBalance: 0,
        hasPayPassword: false,
        isLocked: false,
        createdAt: DateTime(2026),
      ),
    );
  }

  @override
  Future<void> loadWallet({bool silent = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders redesigned membership hierarchy on a phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/vip',
      routes: [
        GoRoute(
          path: '/vip',
          builder: (_, __) => const VipCenterPage(),
        ),
        GoRoute(
          path: '/vip/orders',
          builder: (_, __) => const Scaffold(body: Text('orders')),
        ),
        GoRoute(
          path: '/wallet/recharge',
          builder: (_, __) => const Scaffold(body: Text('recharge')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vipStatusProvider.overrideWith(
            (ref) async => const VipStatus(
              level: 0,
              levelName: '普通用户',
              isActive: false,
              entitlements: VipEntitlements(
                canCreateGroup: true,
                maxOwnedGroups: 1,
                maxOwnedChannels: 0,
                maxGroupMembers: 100,
                maxChannelMembers: 100,
                maxPinnedChats: 5,
                uploadImageLimitMB: 10,
                uploadVideoLimitMB: 100,
                uploadVoiceLimitMB: 20,
                uploadFileLimitMB: 100,
              ),
            ),
          ),
          vipPlansProvider.overrideWith(
            (ref) async => const [
              VipPlan(
                id: 1,
                code: 'vip_month',
                name: 'VIP 月卡',
                level: 1,
                levelName: 'VIP',
                durationDays: 30,
                price: 18,
                originalPrice: 30,
                benefits: VipEntitlements(
                  canCreateGroup: true,
                  canCreateChannel: true,
                  maxOwnedGroups: 5,
                  maxOwnedChannels: 10,
                  maxGroupMembers: 500,
                  maxChannelMembers: 500,
                  uploadFileLimitMB: 500,
                ),
                description: '适合日常建群和文件传输',
                enabled: true,
              ),
              VipPlan(
                id: 2,
                code: 'vip_year',
                name: 'VIP 年卡',
                level: 1,
                levelName: 'VIP',
                durationDays: 365,
                price: 168,
                originalPrice: 216,
                benefits: VipEntitlements(
                  canCreateGroup: true,
                  canCreateChannel: true,
                  maxOwnedGroups: 5,
                  maxOwnedChannels: 10,
                  maxGroupMembers: 500,
                  maxChannelMembers: 500,
                  uploadFileLimitMB: 500,
                ),
                description: 'VIP 权益一年有效',
                enabled: true,
              ),
              VipPlan(
                id: 3,
                code: 'svip_month',
                name: 'SVIP 月卡',
                level: 2,
                levelName: 'SVIP',
                durationDays: 30,
                price: 38,
                originalPrice: 58,
                benefits: VipEntitlements(
                  canCreateGroup: true,
                  canCreateChannel: true,
                  maxOwnedGroups: 20,
                  maxOwnedChannels: 10,
                  maxGroupMembers: 1000,
                  maxChannelMembers: 5000,
                  uploadFileLimitMB: 2048,
                ),
                description: '适合需要频道和更高容量的用户',
                enabled: true,
              ),
            ],
          ),
          walletProvider.overrideWith((ref) => _FixedWalletNotifier()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('会员中心'), findsOneWidget);
    expect(find.text('普通用户'), findsOneWidget);
    expect(find.text('我的权益'), findsOneWidget);
    expect(find.text('左右滑动查看不同会员'), findsOneWidget);
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.viewportFraction, 1);
    expect(find.text('¥168.00'), findsOneWidget);
    expect(find.text('立即开通'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();

    expect(find.text('VIP 月卡'), findsOneWidget);
    expect(find.text('¥18.00'), findsWidgets);
    expect(find.text('VIP权益'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();

    expect(find.text('VIP 年卡'), findsOneWidget);
    expect(find.text('¥168.00'), findsWidgets);

    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();

    expect(find.text('SVIP 月卡'), findsOneWidget);
    expect(find.text('SVIP权益'), findsOneWidget);
    expect(find.text('¥38.00'), findsWidgets);

    await tester.drag(find.byType(PageView), const Offset(340, 0));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(340, 0));
    await tester.pumpAndSettle();

    expect(find.text('VIP 月卡'), findsOneWidget);
    expect(find.text('¥18.00'), findsWidgets);
    await tester.tap(find.text('立即开通'));
    await tester.pumpAndSettle();

    expect(find.text('确认开通'), findsOneWidget);
    expect(find.text('确认支付 ¥18.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
