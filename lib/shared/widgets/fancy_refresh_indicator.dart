// 文件用途：提供 FancyRefreshIndicator 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 FancyRefreshIndicator，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:async';

import 'package:flutter/cupertino.dart' hide RefreshCallback;
import 'package:flutter/material.dart';

import '../../core/services/notification_sound_service.dart';

// 关键声明：fancy refresh indicator 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class FancyRefreshIndicator extends StatefulWidget {
  final Widget child;
  final RefreshCallback onRefresh;
  final double topOffset;

  const FancyRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.topOffset = 12,
  });

  @override
  State<FancyRefreshIndicator> createState() => _FancyRefreshIndicatorState();
}

class _FancyRefreshIndicatorState extends State<FancyRefreshIndicator> {
  RefreshIndicatorStatus? _status;
  Timer? _hideTimer;
  bool _armedHapticPlayed = false;

  void _handleStatusChange(RefreshIndicatorStatus? status) {
    if (_status == status) return;

    _hideTimer?.cancel();
    _hideTimer = null;

    if (status == RefreshIndicatorStatus.canceled) {
      _armedHapticPlayed = false;
      setState(() => _status = null);
      return;
    }

    if (status == RefreshIndicatorStatus.armed && !_armedHapticPlayed) {
      _armedHapticPlayed = true;
      GlobalHaptics.selection();
    }

    setState(() => _status = status);

    if (status == RefreshIndicatorStatus.done) {
      _armedHapticPlayed = false;
      _hideTimer = Timer(const Duration(milliseconds: 120), () {
        if (!mounted || _status != RefreshIndicatorStatus.done) return;
        setState(() => _status = null);
      });
    } else if (status == null) {
      _armedHapticPlayed = false;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final visible =
        _status != null && _status != RefreshIndicatorStatus.canceled;

    return Stack(
      children: [
        Positioned.fill(
          child: RefreshIndicator.noSpinner(
            onRefresh: widget.onRefresh,
            onStatusChange: _handleStatusChange,
            triggerMode: RefreshIndicatorTriggerMode.onEdge,
            child: widget.child,
          ),
        ),
        Positioned(
          top: widget.topOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -0.16),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: Center(child: _WechatRefreshIndicator(status: _status)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WechatRefreshIndicator extends StatelessWidget {
  final RefreshIndicatorStatus? status;

  const _WechatRefreshIndicator({required this.status});

  bool get _isRefreshing =>
      status == RefreshIndicatorStatus.refresh ||
      status == RefreshIndicatorStatus.snap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xCC1C1C1E) : Colors.white.withOpacity(0.72);
    final indicatorColor =
        isDark ? const Color(0xFFE5E7EB) : const Color(0xFF6B7280);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.10 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: _isRefreshing
            ? CupertinoActivityIndicator(
                radius: 7.5,
                color: indicatorColor,
              )
            : Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: indicatorColor,
              ),
      ),
    );
  }
}
