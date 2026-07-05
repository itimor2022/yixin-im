import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'contact_provider.dart';

/// 未读好友申请数量(新的朋友红点用)
class FriendRequestNotifier extends StateNotifier<int> {
  FriendRequestNotifier(this._ref) : super(0);

  final Ref _ref;

  /// 从服务器拉取待验证申请数量
  Future<void> load() async {
    try {
      final list =
          await _ref.read(contactListProvider.notifier).getFriendRequests();
      state = list.length;
    } catch (e) {
      if (kDebugMode) debugPrint('[FriendRequest] load failed: $e');
    }
  }

  /// 收到新申请,红点 +1
  void increment() => state = state + 1;

  /// 进入"新的朋友"页后清零
  void clear() => state = 0;
}

final friendRequestProvider =
    StateNotifierProvider<FriendRequestNotifier, int>((ref) {
  final notifier = FriendRequestNotifier(ref);
  
  Future.microtask(() => notifier.load());
  
  return notifier;
});
