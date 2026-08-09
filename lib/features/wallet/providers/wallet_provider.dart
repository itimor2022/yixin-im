// 文件用途：管理 WalletState 相关状态、异步加载与界面通知，属于钱包与支付。
// 核心逻辑：维护余额、交易记录、充值提现和支付密码状态，统一处理鉴权失败、加载刷新与本地化错误提示。
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/account_session_coordinator.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../services/wallet_service.dart';

String _walletProviderText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _walletErrorMessage({
  required String? raw,
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  return localizeServerMessage(
    raw,
    fallbackZhCN: zhCN,
    fallbackZhTW: zhTW,
    fallbackEn: en,
  );
}

// 关键声明：wallet provider 是状态边界，统一管理加载、成功、失败和刷新状态，避免页面直接维护异步请求结果。
/// 钱包状态
class WalletState {
  final WalletInfo? wallet;
  final List<Transaction> transactions;
  final bool isLoading;
  final bool isTransactionsLoading;
  final String? error;
  final int transactionPage;
  final bool hasMoreTransactions;

  const WalletState({
    this.wallet,
    this.transactions = const [],
    this.isLoading = false,
    this.isTransactionsLoading = false,
    this.error,
    this.transactionPage = 1,
    this.hasMoreTransactions = true,
  });

  WalletState copyWith({
    WalletInfo? wallet,
    List<Transaction>? transactions,
    bool? isLoading,
    bool? isTransactionsLoading,
    String? error,
    bool clearError = false,
    int? transactionPage,
    bool? hasMoreTransactions,
  }) {
    return WalletState(
      wallet: wallet ?? this.wallet,
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      isTransactionsLoading:
          isTransactionsLoading ?? this.isTransactionsLoading,
      error: clearError ? null : (error ?? this.error),
      transactionPage: transactionPage ?? this.transactionPage,
      hasMoreTransactions: hasMoreTransactions ?? this.hasMoreTransactions,
    );
  }
}

/// 当前账号的钱包页面投影，串行化资金操作并在成功后用服务端快照校准余额。
class WalletNotifier extends StateNotifier<WalletState> {
  final WalletService _walletService;
  final String _accountId;
  bool _isOperating = false;
  bool _isDisposed = false;

  WalletNotifier(this._walletService, this._accountId)
      : super(const WalletState());

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// 检查钱包是否可操作
  String? _checkOperability() {
    // 本地互斥只防止用户连续点击，不替代后端事务、幂等和余额校验。
    if (_isOperating) {
      return _walletProviderText(
        zhCN: '操作进行中，请稍候',
        zhTW: '操作進行中，請稍候',
        en: 'An operation is already in progress. Please wait.',
      );
    }
    if (state.wallet?.isLocked == true) {
      return _walletProviderText(
        zhCN: '钱包已锁定',
        zhTW: '錢包已鎖定',
        en: 'Wallet is locked',
      );
    }
    return null;
  }

  /// 加载钱包信息
  Future<void> loadWallet({bool silent = false}) async {
    if (_accountId.isEmpty || _isDisposed) return;
    // silent 模式（下拉刷新）不受全屏 loading 互斥限制
    if (!silent && state.isLoading) return;

    // silent 模式不显示 loading（下拉刷新时使用），保持当前余额可见
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      final response = await _walletService.getWallet();
      if (_isDisposed) return;
      if (response.isSuccess && response.data != null) {
        state = state.copyWith(
          wallet: response.data,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _walletErrorMessage(
            raw: response.message,
            zhCN: '加载钱包失败',
            zhTW: '載入錢包失敗',
            en: 'Failed to load wallet',
          ),
        );
      }
    } catch (e) {
      debugPrint('[Wallet] Load wallet error: $e');
      state = state.copyWith(
        isLoading: false,
        error: _walletProviderText(
          zhCN: '加载钱包失败',
          zhTW: '載入錢包失敗',
          en: 'Failed to load wallet',
        ),
      );
    }
  }

  /// 刷新钱包（静默模式，不清空余额显示）
  Future<void> refresh() async {
    if (_accountId.isEmpty || _isDisposed) return;
    state = state.copyWith(
      transactions: [],
      transactionPage: 1,
      hasMoreTransactions: true,
    );
    await loadWallet(silent: true);
    await loadTransactions();
  }

  /// 设置支付密码
  Future<bool> setPayPassword(String password, {String? oldPassword}) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return false;
    }
    _isOperating = true;
    try {
      final response = await _walletService.setPayPassword(
        password: password,
        oldPassword: oldPassword,
      );
      if (_isDisposed) return false;
      if (response.isSuccess) {
        await loadWallet();
        return true;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '设置支付密码失败',
          zhTW: '設定支付密碼失敗',
          en: 'Failed to set payment password',
        ),
      );
      return false;
    } catch (e) {
      debugPrint('[Wallet] Set pay password error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '设置支付密码失败',
          zhTW: '設定支付密碼失敗',
          en: 'Failed to set payment password',
        ),
      );
      return false;
    } finally {
      _isOperating = false;
    }
  }

  /// 验证支付密码
  Future<bool> verifyPayPassword(String password) async {
    try {
      final response = await _walletService.verifyPayPassword(password);
      if (_isDisposed) return false;
      return response.isSuccess && response.data == true;
    } catch (e) {
      debugPrint('[Wallet] Verify pay password error: $e');
      return false;
    }
  }

  /// 加载交易记录
  Future<void> loadTransactions({bool loadMore = false}) async {
    if (state.isTransactionsLoading) return;
    if (loadMore && !state.hasMoreTransactions) return;

    state = state.copyWith(isTransactionsLoading: true);

    try {
      // 分页只追加服务端返回的新页；是否还有下一页以服务端实际页长判断，
      // 不在客户端根据余额或交易金额推算，避免并发记账造成分页状态漂移。
      final page = loadMore ? state.transactionPage + 1 : 1;
      final response = await _walletService.getTransactions(page: page);
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final newTransactions = response.data!;
        state = state.copyWith(
          transactions: loadMore
              ? [...state.transactions, ...newTransactions]
              : newTransactions,
          transactionPage: page,
          hasMoreTransactions: newTransactions.length >= 20,
          isTransactionsLoading: false,
        );
      } else {
        state = state.copyWith(
          isTransactionsLoading: false,
          error: _walletErrorMessage(
            raw: response.message,
            zhCN: '加载交易记录失败',
            zhTW: '載入交易記錄失敗',
            en: 'Failed to load transaction history',
          ),
        );
      }
    } catch (e) {
      debugPrint('[Wallet] Load transactions error: $e');
      state = state.copyWith(
        isTransactionsLoading: false,
        error: _walletProviderText(
          zhCN: '加载交易记录失败',
          zhTW: '載入交易記錄失敗',
          en: 'Failed to load transaction history',
        ),
      );
    }
  }

  /// 发红包（带并发防护）
  Future<RedPacketInfo?> sendRedPacket({
    required String chatId,
    required RedPacketType type,
    required double totalAmount,
    required int totalCount,
    required String message,
    required String payPassword,
  }) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return null;
    }
    _isOperating = true;
    try {
      final response = await _walletService.sendRedPacket(
        chatId: chatId,
        type: type,
        totalAmount: totalAmount,
        totalCount: totalCount,
        message: message,
        payPassword: payPassword,
      );
      if (_isDisposed) return null;
      if (response.isSuccess && response.data != null) {
        // 不在本地扣减余额，重新拉取可同时吸收手续费、并发交易和服务端舍入结果。
        await loadWallet();
        return response.data;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '发红包失败',
          zhTW: '發紅包失敗',
          en: 'Failed to send red packet',
        ),
      );
      return null;
    } catch (e) {
      debugPrint('[Wallet] Send red packet error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '发红包失败',
          zhTW: '發紅包失敗',
          en: 'Failed to send red packet',
        ),
      );
      return null;
    } finally {
      _isOperating = false;
    }
  }

  /// 领红包（带并发防护）
  Future<Map<String, dynamic>?> claimRedPacket(String redPacketId) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return null;
    }
    _isOperating = true;
    try {
      final response = await _walletService.claimRedPacket(redPacketId);
      if (_isDisposed) return null;
      if (response.isSuccess && response.data != null) {
        // 领取金额与最新余额由服务端结算，成功后刷新而不是累加响应中的展示值。
        await loadWallet();
        return response.data;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '领取红包失败',
          zhTW: '領取紅包失敗',
          en: 'Failed to claim red packet',
        ),
      );
      return null;
    } catch (e) {
      debugPrint('[Wallet] Claim red packet error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '领取红包失败',
          zhTW: '領取紅包失敗',
          en: 'Failed to claim red packet',
        ),
      );
      return null;
    } finally {
      _isOperating = false;
    }
  }

  /// 转账（带并发防护）
  Future<TransferInfo?> transfer({
    required String receiverId,
    required double amount,
    String? remark,
    required String payPassword,
  }) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return null;
    }
    _isOperating = true;
    try {
      final response = await _walletService.transfer(
        receiverId: receiverId,
        amount: amount,
        remark: remark,
        payPassword: payPassword,
      );
      if (_isDisposed) return null;
      if (response.isSuccess && response.data != null) {
        // 转账创建成功后以钱包快照校准余额，避免本地浮点计算成为资金权威。
        await loadWallet();
        return response.data;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '转账失败',
          zhTW: '轉帳失敗',
          en: 'Transfer failed',
        ),
      );
      return null;
    } catch (e) {
      debugPrint('[Wallet] Transfer error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '转账失败',
          zhTW: '轉帳失敗',
          en: 'Transfer failed',
        ),
      );
      return null;
    } finally {
      _isOperating = false;
    }
  }

  /// 接收转账（带并发防护）
  Future<bool> acceptTransfer(String transferId) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return false;
    }
    _isOperating = true;
    try {
      final response = await _walletService.acceptTransfer(transferId);
      if (_isDisposed) return false;
      if (response.isSuccess) {
        await loadWallet();
        return true;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '接收转账失败',
          zhTW: '接收轉帳失敗',
          en: 'Failed to accept transfer',
        ),
      );
      return false;
    } catch (e) {
      debugPrint('[Wallet] Accept transfer error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '接收转账失败',
          zhTW: '接收轉帳失敗',
          en: 'Failed to accept transfer',
        ),
      );
      return false;
    } finally {
      _isOperating = false;
    }
  }

  /// 退回转账（带并发防护 + 余额刷新）
  Future<bool> rejectTransfer(String transferId) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return false;
    }
    _isOperating = true;
    try {
      final response = await _walletService.rejectTransfer(transferId);
      if (_isDisposed) return false;
      if (response.isSuccess) {
        await loadWallet(); // 退回转账后也要刷新余额
        return true;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '退回转账失败',
          zhTW: '退回轉帳失敗',
          en: 'Failed to reject transfer',
        ),
      );
      return false;
    } catch (e) {
      debugPrint('[Wallet] Reject transfer error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '退回转账失败',
          zhTW: '退回轉帳失敗',
          en: 'Failed to reject transfer',
        ),
      );
      return false;
    } finally {
      _isOperating = false;
    }
  }

  /// 提交提现申请（带并发防护）
  Future<bool> createWithdrawRequest({
    required int methodId,
    required double amount,
    required String formData,
    required String payPassword,
  }) async {
    final check = _checkOperability();
    if (check != null) {
      state = state.copyWith(error: check);
      return false;
    }
    _isOperating = true;
    try {
      final response = await _walletService.createWithdrawRequest(
        methodId: methodId,
        amount: amount,
        formData: formData,
        payPassword: payPassword,
      );
      if (_isDisposed) return false;
      if (response.isSuccess) {
        await loadWallet();
        return true;
      }
      state = state.copyWith(
        error: _walletErrorMessage(
          raw: response.message,
          zhCN: '提现申请失败',
          zhTW: '提現申請失敗',
          en: 'Failed to submit withdrawal request',
        ),
      );
      return false;
    } catch (e) {
      debugPrint('[Wallet] Create withdraw request error: $e');
      state = state.copyWith(
        error: _walletProviderText(
          zhCN: '提现申请失败',
          zhTW: '提現申請失敗',
          en: 'Failed to submit withdrawal request',
        ),
      );
      return false;
    } finally {
      _isOperating = false;
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 更新余额（本地更新，用于乐观更新）
  void updateBalance(double newBalance) {
    if (state.wallet != null) {
      state = state.copyWith(
        wallet: WalletInfo(
          id: state.wallet!.id,
          balance: newBalance,
          frozenBalance: state.wallet!.frozenBalance,
          hasPayPassword: state.wallet!.hasPayPassword,
          isLocked: state.wallet!.isLocked,
          createdAt: state.wallet!.createdAt,
        ),
      );
    }
  }

  void reset() {
    if (_isDisposed) return;
    state = const WalletState();
    _isOperating = false;
  }
}

/// 钱包服务 Provider
final walletServiceProvider = Provider<WalletService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return WalletService(apiClient);
});

/// 当前账号可见的钱包展示设置。
///
/// 使用 autoDispose，离开所有钱包相关页面后会释放；再次进入会重新读取后台
/// 配置，因此修改货币符号后不需要重新安装客户端。
final walletSettingsProvider =
    FutureProvider.autoDispose<WalletSettings>((ref) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return const WalletSettings();

  final response = await ref.watch(walletServiceProvider).getWalletSettings();
  if (!response.isSuccess || response.data == null) {
    return const WalletSettings();
  }
  return response.data!;
});

/// 后台货币符号的安全、响应式视图。
final walletCurrencyProvider = Provider.autoDispose<String>((ref) {
  final raw = ref.watch(walletSettingsProvider).valueOrNull?.currency.trim();
  return raw == null || raw.isEmpty ? '¥' : raw;
});

/// 钱包状态 Provider
final walletProvider =
    StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  final walletService = ref.watch(walletServiceProvider);
  final accountId = ref.watch(currentAccountIdProvider);
  return WalletNotifier(walletService, accountId);
});

/// 红包详情 Provider（按 ID 获取）
final redPacketProvider =
    FutureProvider.family<RedPacketInfo?, String>((ref, id) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return null;
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getRedPacket(id);
  return response.data;
});

/// 红包领取记录 Provider
final redPacketClaimsProvider =
    FutureProvider.family<List<RedPacketClaim>, String>((ref, id) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return const [];
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getRedPacketClaims(id);
  return response.data ?? [];
});

/// 转账详情 Provider
final transferProvider =
    FutureProvider.family<TransferInfo?, String>((ref, id) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return null;
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getTransfer(id);
  return response.data;
});

/// 提现方式 Provider
final withdrawMethodsProvider =
    FutureProvider<List<WithdrawMethod>>((ref) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return const [];
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getWithdrawMethods();
  return response.data ?? [];
});
