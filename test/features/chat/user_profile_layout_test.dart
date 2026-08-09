import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/account_session_coordinator.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/core/services/api/system_settings_service.dart';
import 'package:generic_im/features/chat/pages/user_profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile header supports narrow screens and enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAccountIdProvider.overrideWithValue('layout-account'),
          apiClientProvider.overrideWithValue(_ProfileLayoutApiClient()),
          systemSettingsProvider.overrideWith(
            (ref) async => const SystemSettings(),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: UserProfilePage(
              userId: 'layout-user',
              name: '这是一个用于验证窄屏适配的超长用户昵称',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('通话'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(
      appBar.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _ProfileLayoutApiClient extends ApiClient {
  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    dynamic cancelToken,
  }) async {
    dynamic data;
    if (path == '/user/layout-user') {
      data = <String, dynamic>{
        'id': 'layout-user',
        'uuid': 'layout-user',
        'username': 'layout_user',
        'nickname': '这是一个用于验证窄屏适配的超长用户昵称',
        'bio': '测试资料',
        'status': 1,
      };
    } else if (path.startsWith('/user/blocked/check')) {
      data = <String, dynamic>{'is_blocked': false};
    } else if (path == '/contact/list') {
      data = <String, dynamic>{
        'list': <dynamic>[],
        'total': 0,
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
