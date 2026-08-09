// 文件用途：提供 ConnectionStatusBanner 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 ConnectionStatusBanner，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api/websocket_service.dart';

bool shouldShowConnectionBanner(WSConnectionState state) {
  // 当前产品策略为静默自动重连，任何状态都不展示横幅，避免短暂网络切换被误解为故障。
  // 保留纯函数和组件骨架，便于未来调整策略时复用延迟显示与重试事件契约。
  return false;
}

// 关键声明：connection status banner 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 网络重连状态横幅
///
/// 使用方式：在 Scaffold 的 body 外层包一个 Stack，将本 widget 用
/// `Positioned(top: 0, left: 0, right: 0)` 叠放在内容之上即可。
///
/// ```dart
/// body: Stack(
///   children: [
///     navigationShell,
///     const Positioned(
///       top: 0, left: 0, right: 0,
///       child: ConnectionStatusBanner(),
///     ),
///   ],
/// ),
/// ```
class ConnectionStatusBanner extends ConsumerStatefulWidget {
  const ConnectionStatusBanner({super.key});

  @override
  ConsumerState<ConnectionStatusBanner> createState() =>
      _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends ConsumerState<ConnectionStatusBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  // 手动订阅负责显隐副作用；build 中的 watch 只读取文案和倒计时状态。
  ProviderSubscription<WSConnectionState>? _wsStateSub;
  Timer? _refreshTimer;
  Timer? _showDelayTimer; // 延迟显示，避免短暂抖动触发横幅
  bool _delayedVisible = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    // 倒计时由服务持有，定时器只触发显示刷新，不修改重连状态机。
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // 改为手动监听状态变化，把显隐控制从 build() 挪到回调里
    _wsStateSub = ref.listenManual<WSConnectionState>(
      webSocketServiceProvider,
      (previous, next) => _handleWsStateChange(next),
      fireImmediately: true,
    );
  }

  /// 处理 WS 状态变化
  ///
  /// 断线或重连持续 2 秒后显示，首次 connecting 不显示。
  void _handleWsStateChange(WSConnectionState next) {
    final wantShow = shouldShowConnectionBanner(next);

    if (wantShow) {
      // 2 秒内恢复的短抖动不弹横幅。
      if (_delayedVisible || _showDelayTimer != null) return;
      _showDelayTimer = Timer(const Duration(seconds: 2), () {
        _showDelayTimer = null;
        if (!mounted) return;
        if (shouldShowConnectionBanner(ref.read(webSocketServiceProvider))) {
          _setBannerVisible(true);
        }
      });
      return;
    }

    _showDelayTimer?.cancel();
    _showDelayTimer = null;
    _setBannerVisible(false);
  }

  /// 切换横幅显隐并驱动动画
  void _setBannerVisible(bool visible) {
    if (!mounted) return;
    if (_delayedVisible != visible) {
      setState(() => _delayedVisible = visible);
    }
    if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    // 订阅、两个定时器和 ticker 必须一起释放，防止页面销毁后继续收到状态事件。
    _wsStateSub?.close();
    _refreshTimer?.cancel();
    _showDelayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(webSocketServiceProvider);
    final wsService = ref.read(webSocketServiceProvider.notifier);

    // 动画完全收起后不渲染
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isDismissed) {
          return const SizedBox.shrink();
        }

        return SlideTransition(
          position: _slideAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: _BannerContent(
              message: wsService.connectionStatusMessage,
              countdown: wsService.nextRetrySeconds,
              isReconnecting: wsState == WSConnectionState.reconnecting,
              // Notifier 自行处理连接中的去重；UI 不等待结果，避免按钮状态绑死网络 Future。
              onRetry: () => unawaited(wsService.ensureConnectedForRealtime()),
            ),
          ),
        );
      },
    );
  }
}

// ─── 横幅内容 ──────────────────────────────────────────────────────────────

class _BannerContent extends StatelessWidget {
  final String message;
  final int countdown;
  final bool isReconnecting;
  final VoidCallback onRetry;

  const _BannerContent({
    required this.message,
    required this.countdown,
    required this.isReconnecting,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        color: const Color(0xFFE65100), // 深橙 — 重连中
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          bottom: 6,
          left: 16,
          right: 16,
        ),
        child: Row(
          children: [
            // 闪烁指示点
            const _PulsingDot(),
            const SizedBox(width: 10),
            // 状态文字
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
            // 倒计时圆圈（仅重连等待时显示）
            if (isReconnecting && countdown > 0)
              _CountdownBadge(seconds: countdown),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 闪烁圆点 ──────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── 倒计时徽章 ─────────────────────────────────────────────────────────────

class _CountdownBadge extends StatelessWidget {
  final int seconds;

  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${seconds}s',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
