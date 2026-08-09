// 文件用途：提供 CallOverlay 可复用界面组件，服务于音视频通话。
// 核心逻辑：根据输入模型和状态渲染 CallOverlay，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/call_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../pages/call_page.dart';
import '../pages/incoming_call_page.dart';

// 关键声明：call overlay 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 通话悬浮窗 - 可拖动的小窗口
class CallOverlay extends ConsumerStatefulWidget {
  const CallOverlay({super.key});

  @override
  ConsumerState<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends ConsumerState<CallOverlay> {
  Offset _position = const Offset(20, 100);
  Timer? _timer;
  int _seconds = 0;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    final callState = ref.read(callServiceProvider);
    if (callState.callInfo?.connectTime != null) {
      _seconds =
          DateTime.now().difference(callState.callInfo!.connectTime!).inSeconds;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _openCallPage() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).toggleMinimize();
    // 使用 rootNavigatorKey 导航，因为 Overlay 不在 Navigator 树中
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const CallPage(),
        settings: const RouteSettings(name: '/call'),
      ),
    );
  }

  void _endCall() {
    HapticFeedback.mediumImpact();
    ref.read(callServiceProvider.notifier).endCall();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callServiceProvider);
    final callInfo = callState.callInfo;

    if (callInfo == null || !callState.isMinimized) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;
    final isVideo = callInfo.type == CallType.video;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onTap: _openCallPage,
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(0, screenSize.width - 160),
              (_position.dy + details.delta.dy).clamp(
                MediaQuery.of(context).padding.top,
                screenSize.height - 100,
              ),
            );
          });
        },
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头像和名字
              Row(
                children: [
                  AvatarWidget(
                    name: callInfo.remoteName,
                    avatar: callInfo.remoteAvatar,
                    userId: callInfo.remoteUserId,
                    size: 36,
                    isCircle: true,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          callInfo.remoteName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.call_rounded,
                              size: 12,
                              color: AppColors.online,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(_seconds),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.online,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 展开
                  _buildMiniButton(
                    icon: Icons.open_in_full_rounded,
                    color: Colors.white24,
                    onTap: _openCallPage,
                  ),
                  // 静音
                  _buildMiniButton(
                    icon: callState.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    color: callState.isMuted ? Colors.white : Colors.white24,
                    iconColor: callState.isMuted ? Colors.black : Colors.white,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(callServiceProvider.notifier).toggleMute();
                    },
                  ),
                  // 挂断
                  _buildMiniButton(
                    icon: Icons.call_end_rounded,
                    color: AppColors.error,
                    onTap: _endCall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniButton({
    required IconData icon,
    required Color color,
    Color iconColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
  }
}

/// iOS 风格来电条配色（更柔和、贴近系统来电）
const Color _iosPipGreen = Color(0xFF34C759);
const Color _iosPipRed = Color(0xFFFF3B30);

/// 来电顶部画中画 - 从后台返回或前台有来电时在顶部显示，点击进入全屏来电页
/// iOS 使用毛玻璃 + 圆角卡片；Android 保持深色条
class IncomingCallPip extends ConsumerWidget {
  const IncomingCallPip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callServiceProvider);
    if (callState.state != CallState.incoming || callState.callInfo == null) {
      return const SizedBox.shrink();
    }
    final callInfo = callState.callInfo!;
    final isVideo = callInfo.type == CallType.video;
    final isIOS = Platform.isIOS;
    final l10n = AppLocalizations.of(context);

    final content = SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          final navigator = rootNavigatorKey.currentState;
          if (navigator != null) {
            navigator.push(
              PageRouteBuilder(
                opaque: false,
                barrierDismissible: false,
                pageBuilder: (_, __, ___) =>
                    IncomingCallPage(callInfo: callInfo),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
            );
          }
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isIOS ? 16 : 16,
            vertical: isIOS ? 14 : 12,
          ),
          child: Row(
            children: [
              AvatarWidget(
                name: callInfo.remoteName,
                avatar: callInfo.remoteAvatar,
                userId: callInfo.remoteUserId,
                size: isIOS ? 48 : 44,
                isCircle: true,
              ),
              SizedBox(width: isIOS ? 14 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      callInfo.remoteName,
                      style: TextStyle(
                        fontSize: isIOS ? 17 : 16,
                        fontWeight: FontWeight.w600,
                        color: isIOS ? const Color(0xFF1C1C1E) : Colors.white,
                        letterSpacing: isIOS ? -0.41 : 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVideo ? l10n.videoCall : l10n.voiceCall,
                      style: TextStyle(
                        fontSize: isIOS ? 13 : 12,
                        color: isIOS
                            ? const Color(0xFF8E8E93)
                            : Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              _pipButton(
                icon: Icons.call_end_rounded,
                color: isIOS ? _iosPipRed : AppColors.error,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ref.read(callServiceProvider.notifier).rejectCall();
                },
                size: isIOS ? 44 : 40,
              ),
              SizedBox(width: isIOS ? 12 : 8),
              _pipButton(
                icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: isIOS ? _iosPipGreen : AppColors.online,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ref.read(callServiceProvider.notifier).acceptCall();
                },
                size: isIOS ? 44 : 40,
              ),
            ],
          ),
        ),
      ),
    );

    // Android：顶部画中画，圆角卡片 + 阴影，更好看
    return Positioned(
      left: 12,
      right: 12,
      top: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF252528),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(20)),
            border:
                Border.all(color: Colors.white.withOpacity(0.06), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _pipButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 40,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size / 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

/// 全局通话悬浮窗包装器
class CallOverlayWrapper extends ConsumerWidget {
  final Widget child;

  const CallOverlayWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callServiceProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        // 仅通话中最小化时显示小窗；来电：iOS 用 CallKit，Android 前台用应用内全屏接听页、后台用系统全屏
        if (callState.isInCall && callState.isMinimized) const CallOverlay(),
      ],
    );
  }
}
