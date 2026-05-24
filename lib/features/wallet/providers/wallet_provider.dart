import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/api_client.dart';
import '../services/wallet_service.dart';

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
      isTransactionsLoading: isTransactionsLoading ?? this.isTransactionsLoading,
      error: clearError ? null : (error ?? this.error),
      transactionPage: transactionPage ?? this.transactionPage,
      hasMoreTransactions: hasMoreTransactions ?? this.hasMoreTransactions,
    );
  }
}

/// 钱包状态管理
class WalletNotifier extends StateNotifier<WalletState> {
  final WalletService _walletService;
  bool _isOperating = false;
  bool _isDisposed = false;

  WalletNotifier(this._walletService) : super(const WalletState());

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// 检查钱包是否可操作
  String? _checkOperability() {
    if (_isOperating) return '操作进行中，请稍候';
    if (state.wallet?.isLocked == true) return '钱包已锁定';
    return null;
  }

  /// 加载钱包信息
  Future<void> loadWallet({bool silent = false}) async {
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
          error: response.message ?? '加载钱包失败',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Load wallet error: $e');
      state = state.copyWith(
        isLoading: false,
        error: '加载钱包失败',
      );
    }
  }

  /// 刷新钱包（静默模式，不清空余额显示）
  Future<void> refresh() async {
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
    if (check != null) { state = state.copyWith(error: check); return false; }
    _isOperating = true;
    try {
      final response = await _walletService.setPayPassword(
        password: password,
        oldPassword: oldPassword,
      );
      if (response.isSuccess) {
        await loadWallet();
        return true;
      }
      state = state.copyWith(error: response.message ?? '设置支付密码失败');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Set pay password error: $e');
      state = state.copyWith(error: '设置支付密码失败');
      return false;
    } finally {
      _isOperating = false;
    }
  }

  /// 验证支付密码
  Future<bool> verifyPayPassword(String password) async {
    try {
      final response = await _walletService.verifyPayPassword(password);
      return response.isSuccess && response.data == true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Verify pay password error: $e');
      return false;
    }
  }

  /// 充值（测试用）
  Future<bool> recharge(double amount) async {
    try {
      final response = await _walletService.recharge(amount);
      if (response.isSuccess) {
        // 充值成功后刷新钱包余额
        await loadWallet();
        return true;
      }
      state = state.copyWith(error: response.message ?? '充值失败');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Recharge error: $e');
      state = state.copyWith(error: '充值失败');
      return false;
    }
  }

  /// 加载交易记录
  Future<void> loadTransactions({bool loadMore = false}) async {
    if (state.isTransactionsLoading) return;
    if (loadMore && !state.hasMoreTransactions) return;

    state = state.copyWith(isTransactionsLoading: true);

    try {
      final page = loadMore ? state.transactionPage + 1 : 1;
      final response = await _walletService.getTransactions(page: page);

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
          error: response.message,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Load transactions error: $e');
      state = state.copyWith(
        isTransactionsLoading: false,
        error: '加载交易记录失败',
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
    if (check != null) { state = state.copyWith(error: check); return null; }
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
      if (response.isSuccess && response.data != null) {
        await loadWallet();
        return response.data;
      }
      state = state.copyWith(error: response.message ?? '发红包失败');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Send red packet error: $e');
      state = state.copyWith(error: '发红包失败');
      return null;
    } finally {
      _isOperating = false;
    }
  }

  /// 领红包（带并发防护）
  Future<Map<String, dynamic>?> claimRedPacket(String redPacketId) async {
    final check = _checkOperability();
    if (check != null) { state = state.copyWith(error: check); return null; }
    _isOperating = true;
    try {
      final response = await _walletService.claimRedPacket(redPacketId);
      if (response.isSuccess && response.data != null) {
        await loadWallet();
        return response.data;
      }
      state = state.copyWith(error: response.message ?? '领取红包失败');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Claim red packet error: $e');
      state = state.copyWith(error: '领取红包失败');
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
    if (check != null) { state = state.copyWith(error: check); return null; }
    _isOperating = true;
    try {
      final response = await _walletService.transfer(
        receiverId: receiverId,
        amount: amount,
        remark: remark,
        payPassword: payPassword,
      );
      if (response.isSuccess && response.data != null) {
        await loadWallet();
        return response.data;
      }
      state = state.copyWith(error: response.message ?? '转账失败');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Transfer error: $e');
      state = state.copyWith(error: '转账失败');
      return null;
    } finally {
      _isOperating = false;
    }
  }

  /// 接收转账（带并发防护）
  Future<bool> acceptTransfer(String transferId) async {
    final check = _checkOperability();
    if (check != null) { state = state.copyWith(error: check); return false; }
    _isOperating = true;
    try {
      final response = await _walletService.acceptTransfer(transferId);
      if (response.isSuccess) {
        await loadWallet();
        return true;
      }
      state = state.copyWith(error: response.message ?? '接收转账失败');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Accept transfer error: $e');
      state = state.copyWith(error: '接收转账失败');
      return false;
    } finally {
      _isOperating = false;
    }
  }

  /// 退回转账（带并发防护 + 余额刷新）
  Future<bool> rejectTransfer(String transferId) async {
    final check = _checkOperability();
    if (check != null) { state = state.copyWith(error: check); return false; }
    _isOperating = true;
    try {
      final response = await _walletService.rejectTransfer(transferId);
      if (response.isSuccess) {
        await loadWallet(); // 退回转账后也要刷新余额
        return true;
      }
      state = state.copyWith(error: response.message ?? '退回转账失败');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Reject transfer error: $e');
      state = state.copyWith(error: '退回转账失败');
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
    if (check != null) { state = state.copyWith(error: check); return false; }
    _isOperating = true;
    try {
      final response = await _walletService.createWithdrawRequest(
        methodId: methodId,
        amount: amount,
        formData: formData,
        payPassword: payPassword,
      );
      if (response.isSuccess) {
        await loadWallet();
        return true;
      }
      state = state.copyWith(error: response.message ?? '提现申请失败');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wallet] Create withdraw request error: $e');
      state = state.copyWith(error: '提现申请失败');
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
}

/// 钱包服务 Provider
final walletServiceProvider = Provider<WalletService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return WalletService(apiClient);
});

/// 钱包状态 Provider
final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  final walletService = ref.watch(walletServiceProvider);
  return WalletNotifier(walletService);
});

/// 红包详情 Provider（按 ID 获取）
final redPacketProvider = FutureProvider.family<RedPacketInfo?, String>((ref, id) async {
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getRedPacket(id);
  return response.data;
});

/// 红包领取记录 Provider
final redPacketClaimsProvider = FutureProvider.family<List<RedPacketClaim>, String>((ref, id) async {
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getRedPacketClaims(id);
  return response.data ?? [];
});

/// 转账详情 Provider
final transferProvider = FutureProvider.family<TransferInfo?, String>((ref, id) async {
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getTransfer(id);
  return response.data;
});

/// 提现方式 Provider
final withdrawMethodsProvider = FutureProvider<List<WithdrawMethod>>((ref) async {
  final walletService = ref.watch(walletServiceProvider);
  final response = await walletService.getWithdrawMethods();
  return response.data ?? [];
});
