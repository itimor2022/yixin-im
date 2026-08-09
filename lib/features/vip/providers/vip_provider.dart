// 文件用途：管理 VipOrderListState 相关状态、异步加载与界面通知，属于会员权益。
// 核心逻辑：以 Riverpod 暴露 VipOrderListState 状态，串联 API、本地缓存和生命周期事件，统一处理加载、刷新、失败与重试。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/account_session_coordinator.dart';
import '../services/vip_service.dart';

final vipPlansProvider = FutureProvider<List<VipPlan>>((ref) async {
  final response = await ref.watch(vipServiceProvider).getPlans();
  if (response.isSuccess && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message);
});

final vipStatusProvider = FutureProvider<VipStatus>((ref) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return const VipStatus();
  final response = await ref.watch(vipServiceProvider).getStatus();
  if (response.isSuccess && response.data != null) {
    return response.data!;
  }
  throw Exception(response.message);
});

// 关键声明：VIP provider 是状态边界，统一管理加载、成功、失败和刷新状态，避免页面直接维护异步请求结果。
class VipOrderListState {
  const VipOrderListState({
    this.orders = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.error,
  });

  final List<VipOrder> orders;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? error;

  VipOrderListState copyWith({
    List<VipOrder>? orders,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
  }) {
    return VipOrderListState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class VipOrdersNotifier extends StateNotifier<VipOrderListState> {
  VipOrdersNotifier(this._service, this._accountId)
      : super(const VipOrderListState());

  final VipService _service;
  final String _accountId;
  bool _isDisposed = false;
  static const int _pageSize = 20;

  Future<void> load({bool refresh = false}) async {
    if (_accountId.isEmpty || _isDisposed) return;
    if (state.isLoading) return;
    if (!refresh && !state.hasMore) return;

    final nextPage = refresh ? 1 : state.page;
    state = state.copyWith(isLoading: true, clearError: true);
    final response = await _service.getOrders(
      page: nextPage,
      pageSize: _pageSize,
    );
    if (_isDisposed) return;

    if (response.isSuccess && response.data != null) {
      final nextOrders =
          refresh ? response.data! : [...state.orders, ...response.data!];
      state = state.copyWith(
        orders: nextOrders,
        isLoading: false,
        hasMore: response.data!.length >= _pageSize,
        page: nextPage + 1,
        clearError: true,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      error: response.message,
    );
  }

  void reset() {
    if (_isDisposed) return;
    state = const VipOrderListState();
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

final vipOrdersProvider =
    StateNotifierProvider<VipOrdersNotifier, VipOrderListState>((ref) {
  final accountId = ref.watch(currentAccountIdProvider);
  return VipOrdersNotifier(ref.watch(vipServiceProvider), accountId);
});

Future<VipPurchaseResult> purchaseVipPlan(WidgetRef ref, int planId) async {
  final accountId = ref.read(currentAccountIdProvider);
  if (accountId.isEmpty) {
    throw StateError('No active account');
  }
  final response = await ref.read(vipServiceProvider).purchase(planId);
  if (ref.read(currentAccountIdProvider) != accountId) {
    throw StateError('Account changed while purchasing VIP');
  }
  if (response.isSuccess && response.data != null) {
    ref.invalidate(vipStatusProvider);
    ref.invalidate(vipPlansProvider);
    unawaited(ref.read(vipOrdersProvider.notifier).load(refresh: true));
    return response.data!;
  }
  throw Exception(response.message);
}
