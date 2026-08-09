import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:generic_im/core/services/account_session_coordinator.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/features/wallet/providers/wallet_provider.dart';
import 'package:generic_im/features/wallet/services/wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wallet settings preserve the configured currency symbol', () {
    final settings = WalletSettings.fromJson(<String, dynamic>{
      'wallet_currency': r'$',
      'wallet_currency_name': 'USD',
    });

    expect(settings.currency, r'$');
    expect(settings.currencyName, 'USD');
  });

  test('wallet currency provider exposes the backend symbol', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        currentAccountIdProvider.overrideWithValue('account-a'),
        apiClientProvider.overrideWithValue(_WalletSettingsApiClient()),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      walletSettingsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(walletSettingsProvider.future);

    expect(container.read(walletCurrencyProvider), r'$');
  });
}

class _WalletSettingsApiClient extends ApiClient {
  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    dynamic cancelToken,
  }) async {
    expect(path, '/wallet/settings');
    final raw = <String, dynamic>{
      'wallet_currency': r'$',
      'wallet_currency_name': 'USD',
    };
    return ApiResponse<T>(
      code: 0,
      message: 'success',
      data: fromJson!(raw),
    );
  }
}
