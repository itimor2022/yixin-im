// 文件用途：封装 AccountSessionPhase 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：协调登录、刷新、切换账号和注销流程，串联本地缓存清理、WebSocket 断开和全局状态重置。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// 关键声明：账号会话协调器以 epoch 区分异步任务归属，切换账号或退出时先隔离旧状态再执行可超时清理。
enum AccountSessionPhase { inactive, active, exiting }

enum SessionExitReason {
  manual,
  tokenExpired,
  forcedOffline,
  deviceTerminated,
  accountDataCleared,
  encryptionIdentityReset,
  accountDeleted,
}

class AccountContext {
  const AccountContext({required this.accountId, required this.epoch});

  final String accountId;
  final int epoch;

  bool get isValid => accountId.trim().isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is AccountContext &&
        other.accountId == accountId &&
        other.epoch == epoch;
  }

  @override
  int get hashCode => Object.hash(accountId, epoch);
}

/// 账号会话的单一生命周期状态；`epoch` 用来让旧账号启动的异步任务主动失效。
class AccountSessionState {
  const AccountSessionState({
    this.accountId = '',
    this.epoch = 0,
    this.phase = AccountSessionPhase.inactive,
    this.exitReason,
  });

  final String accountId;
  final int epoch;
  final AccountSessionPhase phase;
  final SessionExitReason? exitReason;

  AccountContext get context =>
      AccountContext(accountId: accountId, epoch: epoch);

  bool get isActive =>
      phase == AccountSessionPhase.active && accountId.isNotEmpty;
}

/// 协调认证、缓存和后台任务的账号切换边界，不持有各业务模块的具体清理实现。
class AccountSessionCoordinator extends StateNotifier<AccountSessionState> {
  AccountSessionCoordinator() : super(const AccountSessionState());

  Future<void>? _exitFuture;

  AccountContext activate(String accountId) {
    final normalized = accountId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }

    if (state.isActive && state.accountId == normalized) {
      return state.context;
    }

    // 每次账号身份变化都推进 epoch，异步任务应捕获 context 并在落盘或更新 UI 前校验。
    state = AccountSessionState(
      accountId: normalized,
      epoch: state.epoch + 1,
      phase: AccountSessionPhase.active,
    );
    return state.context;
  }

  // 流程逻辑：`isCurrent` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  bool isCurrent(AccountContext captured, {bool requireActive = true}) {
    if (!captured.isValid || captured != state.context) return false;
    return !requireActive || state.phase == AccountSessionPhase.active;
  }

  bool isActiveAccount(String accountId) {
    return state.isActive && state.accountId == accountId.trim();
  }

  Future<void> exit({
    required SessionExitReason reason,
    void Function(AccountContext context)? quarantine,
    Future<void> Function(AccountContext context)? remoteCleanup,
    Future<void> Function(AccountContext context)? localCleanup,
    Duration remoteTimeout = const Duration(seconds: 3),
  }) {
    final running = _exitFuture;
    if (running != null) return running;

    final completer = Completer<void>();
    _exitFuture = completer.future;
    final previousAccountId = state.accountId;
    final exitContext = AccountContext(
      accountId: previousAccountId,
      epoch: state.epoch + 1,
    );

    // 先同步隔离可见状态，再做可能超时的网络退出，保证旧账号数据不会继续出现在界面。
    // Publish the new epoch synchronously. Account-scoped providers can drop
    // visible state before any network cleanup starts.
    state = AccountSessionState(
      accountId: previousAccountId,
      epoch: exitContext.epoch,
      phase: AccountSessionPhase.exiting,
      exitReason: reason,
    );
    try {
      quarantine?.call(exitContext);
    } catch (_) {
      // Quarantine hooks are best effort and must not strand an exit future.
    }

    Future<void>(() async {
      try {
        // 服务端解绑属于尽力而为；无论网络结果如何，本地凭据和运行时状态都必须继续清除。
        if (remoteCleanup != null && exitContext.isValid) {
          try {
            await remoteCleanup(exitContext).timeout(remoteTimeout);
          } catch (_) {
            // Remote cleanup is best effort. Local credential removal and
            // runtime teardown must always continue.
          }
        }

        if (localCleanup != null) {
          try {
            await localCleanup(exitContext);
          } catch (_) {
            // Individual services are required to be idempotent. A failed
            // cleanup must not leave the account authenticated locally.
          }
        }
      } finally {
        // 清理钩子失败也必须完成退出 Future，防止后续登录永久等待同一个退出任务。
        state = AccountSessionState(
          epoch: state.epoch,
          phase: AccountSessionPhase.inactive,
          exitReason: reason,
        );
        _exitFuture = null;
        completer.complete();
      }
    });

    return completer.future;
  }
}

final accountSessionCoordinatorProvider =
    StateNotifierProvider<AccountSessionCoordinator, AccountSessionState>(
        (ref) {
  return AccountSessionCoordinator();
});

final currentAccountIdProvider = Provider<String>((ref) {
  final session = ref.watch(accountSessionCoordinatorProvider);
  return session.isActive ? session.accountId : '';
});
