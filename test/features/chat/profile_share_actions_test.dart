import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/core/services/api/system_settings_service.dart';
import 'package:generic_im/core/services/account_session_coordinator.dart';
import 'package:generic_im/features/chat/pages/user_profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  String? clipboardText;
  MethodCall? shareCall;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    clipboardText = null;
    shareCall = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text']?.toString();
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
      shareCall = call;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
  });

  testWidgets('profile card actions work after the previous sheet is closed',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('test-account'),
          apiClientProvider.overrideWithValue(_ProfileApiClient()),
          systemSettingsProvider.overrideWith(
            (ref) async => const SystemSettings(
              // Reproduce the production misconfiguration. The compiled H5
              // fallback is exercised by the pure link-builder tests.
              registerBaseUrl: 'https://api.example.com',
            ),
          ),
        ],
        child: const MaterialApp(
          home: UserProfilePage(
            userId: 'test-user',
            name: '测试用户',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openShareSheet() async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享联系人'));
      await tester.pumpAndSettle();
      expect(find.text('分享名片'), findsOneWidget);
      expect(find.text('二维码名片'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('发送给好友'), findsOneWidget);
    }

    await openShareSheet();
    await tester.tap(find.text('二维码名片'));
    await tester.pumpAndSettle();
    expect(find.text('扫码添加好友或打开资料页'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await openShareSheet();
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    const compiledPublicH5Url = String.fromEnvironment('GENERIC_IM_PUBLIC_H5_URL');
    if (compiledPublicH5Url.isEmpty) {
      expect(clipboardText, 'genericim://user/test-user');
      expect(find.text('二维码内容已复制'), findsOneWidget);
    } else {
      expect(
        clipboardText,
        startsWith(
          '$compiledPublicH5Url/open.html?type=user&id=test-user',
        ),
      );
      expect(find.text('账号链接已复制'), findsOneWidget);
    }

    // Headless Chrome cannot dismiss the operating system share surface.
    // The VM test still verifies the platform call; Chrome covers the three
    // in-app actions below on the real web runtime.
    if (!kIsWeb) {
      await openShareSheet();
      await tester.tap(find.text('分享名片'));
      await tester.pumpAndSettle();
      expect(shareCall?.method, 'share');
      expect(shareCall?.arguments.toString(), contains('test-user'));
    }

    await openShareSheet();
    await tester.tap(find.text('发送给好友'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('选择好友'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('好友一'), findsOneWidget);
  });
}

class _ProfileApiClient extends ApiClient {
  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    dynamic cancelToken,
  }) async {
    dynamic data;
    if (path == '/user/test-user') {
      data = <String, dynamic>{
        'id': 'test-user',
        'username': 'test',
        'nickname': '测试用户',
        'bio': '测试资料',
        'status': 1,
      };
    } else if (path.startsWith('/user/blocked/check')) {
      data = <String, dynamic>{'is_blocked': false};
    } else if (path == '/contact/list') {
      data = <String, dynamic>{
        'list': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'friend-1',
            'uuid': 'friend-1',
            'name': '好友一',
            'nickname': '好友一',
            'username': 'friend_one',
            'is_online': true,
          },
        ],
        'total': 1,
        'page': 1,
        'page_size': 500,
      };
    } else if (path.endsWith('/common-groups')) {
      data = <String, dynamic>{'groups': <dynamic>[]};
    } else if (path.endsWith('/common-info')) {
      data = <String, dynamic>{
        'common_group_count': 0,
        'common_contact_count': 0,
        'common_contacts': <dynamic>[],
      };
    } else {
      data = <String, dynamic>{};
    }

    return ApiResponse<T>(
      code: 0,
      message: 'success',
      data: data as T,
    );
  }
}
