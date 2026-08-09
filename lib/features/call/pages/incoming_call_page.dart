// 文件用途：实现 IncomingCallPage 页面及其交互流程，属于音视频通话。
// 核心逻辑：维护 IncomingCallPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/incoming_call_tone_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../shared/widgets/avatar_widget.dart';
import 'call_page.dart';

String _incomingCallText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：incoming call page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 应用内来电入口；铃声和导航由页面管理，接听/拒绝的业务结果由 [CallService] 决定。
class IncomingCallPage extends ConsumerStatefulWidget {
  final CallInfo callInfo;

  const IncomingCallPage({
    super.key,
    required this.callInfo,
  });

  @override
  ConsumerState<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends ConsumerState<IncomingCallPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _vibrationTimer;
  final IncomingCallToneService _ringtone = IncomingCallToneService();
  ProviderSubscription<CallServiceState>? _callStateSubscription;
  bool _isProcessing = false;
  bool _isClosing = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 开始播放铃声和振动提醒
    unawaited(_ringtone.start());
    _startVibration();

    _callStateSubscription = ref.listenManual<CallServiceState>(
      callServiceProvider,
      (previous, next) => _handleCallStateChanged(next),
    );
  }

  void _handleCallStateChanged(CallServiceState callState) {
    if (callState.state == CallState.incoming) return;

    _stopAlerts();
    // Keep the route while an in-app answer is completing, then replace it
    // with CallPage. A remote hangup or answer failure closes it immediately.
    if (!_isProcessing || callState.state == CallState.idle) {
      _closeIncomingPage();
    }
  }

  void _stopAlerts() {
    _stopVibration();
    unawaited(_ringtone.stop());
  }

  void _closeIncomingPage() {
    if (_isClosing) return;
    _isClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _startVibration() {
    // 立即振动一次
    HapticFeedback.heavyImpact();

    // 每隔1.5秒振动一次
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  @override
  void dispose() {
    _callStateSubscription?.close();
    _callStateSubscription = null;
    _pulseController.dispose();
    _stopVibration();
    unawaited(_ringtone.dispose());
    super.dispose();
  }

  void _acceptCall() {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    HapticFeedback.mediumImpact();
    _stopAlerts();

    _doAcceptCall();
  }

  /// 先完成接听握手，成功后再切换到通话页面
  Future<void> _doAcceptCall() async {
    try {
      // 只有服务端接听和 RTC 加入都成功后才替换页面，避免进入一个实际未连接的通话界面。
      final success = await ref.read(callServiceProvider.notifier).acceptCall();
      debugPrint('[IncomingCall] Accept call result: $success');

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            settings: const RouteSettings(name: '/call'),
            pageBuilder: (_, __, ___) => const CallPage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, __, ___, child) => child,
          ),
        );
      } else {
        // 接听失败：回退标志位，允许重试或让用户拒接
        _isProcessing = false;
        if (ref.read(callServiceProvider).state == CallState.incoming) {
          unawaited(_ringtone.start());
          _startVibration();
        }
        final errorMsg = ref.read(callServiceProvider).errorMessage ??
            _incomingCallText(
              context,
              zhCN: '接听失败，请重试',
              zhTW: '接聽失敗，請重試',
              en: 'Failed to answer. Please try again.',
            );
        final failedState = ref.read(callServiceProvider);
        final permanentlyDenied = failedState.permissionIssue ==
                CallPermissionIssue.microphonePermanentlyDenied ||
            failedState.permissionIssue ==
                CallPermissionIssue.cameraPermanentlyDenied;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            action: permanentlyDenied
                ? SnackBarAction(
                    label: _incomingCallText(
                      context,
                      zhCN: '设置',
                      zhTW: '設定',
                      en: 'Settings',
                    ),
                    onPressed: () => ref
                        .read(callServiceProvider.notifier)
                        .openCallPermissionSettings(),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      debugPrint('[IncomingCall] Accept call error: $e');
      if (!mounted) return;
      _isProcessing = false;
      if (ref.read(callServiceProvider).state == CallState.incoming) {
        unawaited(_ringtone.start());
        _startVibration();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _incomingCallText(
              context,
              zhCN: '接听出错，请重试',
              zhTW: '接聽出錯，請重試',
              en: 'An error occurred while answering. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  void _rejectCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    HapticFeedback.mediumImpact();
    _stopAlerts();
    await ref.read(callServiceProvider.notifier).rejectCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callInfo.type == CallType.video;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    // 桌面端使用紧凑布局
    if (isDesktop) {
      return _buildDesktopLayout(isVideo);
    }

    return DarkSystemUiScope(
      child: Scaffold(
        body: Stack(
          children: [
            // 背景
            _buildBackground(isVideo),

            // 模糊效果
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                color: Colors.black.withOpacity(0.4),
              ),
            ),

            // 内容
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // 通话类型提示
                  Text(
                    _incomingCallText(
                      context,
                      zhCN: isVideo ? '视频通话' : '语音通话',
                      zhTW: isVideo ? '視訊通話' : '語音通話',
                      en: isVideo ? 'Video call' : 'Voice call',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 来电提示
                  Text(
                    _incomingCallText(
                      context,
                      zhCN: _isProcessing ? '正在接听...' : '来电...',
                      zhTW: _isProcessing ? '正在接聽...' : '來電...',
                      en: _isProcessing ? 'Answering...' : 'Incoming call...',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // 头像（带脉冲动画）
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: AvatarWidget(
                            name: widget.callInfo.remoteName,
                            avatar: widget.callInfo.remoteAvatar,
                            userId: widget.callInfo.remoteUserId,
                            size: 120,
                            isCircle: true,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // 名字
                  Text(
                    widget.callInfo.remoteName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),

                  const Spacer(),

                  // 操作按钮
                  Padding(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 拒绝
                        _buildCallButton(
                          buttonKey:
                              const ValueKey('incoming_call_decline_button'),
                          icon: Icons.call_end_rounded,
                          label: _incomingCallText(
                            context,
                            zhCN: '拒绝',
                            zhTW: '拒絕',
                            en: 'Decline',
                          ),
                          color: AppColors.error,
                          onTap: _rejectCall,
                        ),

                        // 接听
                        _buildCallButton(
                          buttonKey:
                              const ValueKey('incoming_call_answer_button'),
                          icon: isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          label: _incomingCallText(
                            context,
                            zhCN: '接听',
                            zhTW: '接聽',
                            en: 'Answer',
                          ),
                          color: AppColors.online,
                          onTap: _acceptCall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端来电布局 - TG风格
  Widget _buildDesktopLayout(bool isVideo) {
    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 头像区域 - 带呼吸动画
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF4CAF50).withOpacity(0.3),
                          const Color(0xFF4CAF50).withOpacity(0.1),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF4CAF50).withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: AvatarWidget(
                        name: widget.callInfo.remoteName,
                        avatar: widget.callInfo.remoteAvatar,
                        userId: widget.callInfo.remoteUserId,
                        size: 108,
                        isCircle: true,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 28),

            // 名字
            Text(
              widget.callInfo.remoteName,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 12),

            // 来电状态
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 18,
                  color: const Color(0xFF4CAF50),
                ),
                const SizedBox(width: 8),
                Text(
                  _incomingCallText(
                    context,
                    zhCN: isVideo ? '视频来电...' : '语音来电...',
                    zhTW: isVideo ? '視訊來電...' : '語音來電...',
                    en: isVideo
                        ? 'Incoming video call...'
                        : 'Incoming voice call...',
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 60),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 拒绝
                _buildDesktopIncomingButton(
                  buttonKey: const ValueKey('incoming_call_decline_button'),
                  icon: Icons.call_end_rounded,
                  label: _incomingCallText(
                    context,
                    zhCN: '拒绝',
                    zhTW: '拒絕',
                    en: 'Decline',
                  ),
                  color: const Color(0xFFE53935),
                  onTap: _rejectCall,
                ),

                const SizedBox(width: 60),

                // 接听
                _buildDesktopIncomingButton(
                  buttonKey: const ValueKey('incoming_call_answer_button'),
                  icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  label: _incomingCallText(
                    context,
                    zhCN: '接听',
                    zhTW: '接聽',
                    en: 'Answer',
                  ),
                  color: const Color(0xFF4CAF50),
                  onTap: _acceptCall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端来电按钮
  Widget _buildDesktopIncomingButton({
    Key? buttonKey,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      key: buttonKey,
      button: true,
      label: label,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground(bool isVideo) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isVideo
              ? [const Color(0xFF111827), const Color(0xFF3F3F46)]
              : [const Color(0xFF11998E), const Color(0xFF38EF7D)],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    Key? buttonKey,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      key: buttonKey,
      button: true,
      label: label,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
