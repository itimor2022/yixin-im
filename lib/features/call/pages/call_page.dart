import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/call_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../shared/widgets/avatar_widget.dart';

/// 通话页面 - TG风格
class CallPage extends ConsumerStatefulWidget {
  const CallPage({super.key});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage>
    with SingleTickerProviderStateMixin {
  AnimationController? _connectingController;
  Timer? _timer;
  int _seconds = 0;
  /// 缓存 notifier，dispose 时不能使用 ref
  CallService? _callService;
  bool _initialized = false;
  /// 防止 build 内多次调度 pop
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    
    // 【优化】延迟初始化动画控制器，减少首帧渲染压力
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _connectingController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1000),
        )..repeat();
        _setupCallListener();
        setState(() => _initialized = true);
      }
    });
  }

  void _setupCallListener() {
    _callService = ref.read(callServiceProvider.notifier);
    final callService = _callService!;
    final currentState = ref.read(callServiceProvider);

    // 如果已经是 connected 状态，立即启动计时器
    // 这处理了从 CallKit 接听时，回调可能在页面创建前就已触发的情况
    if (currentState.state == CallState.connected) {
      if (kDebugMode) debugPrint('[CallPage] Already connected, starting timer immediately');
      _startTimer();
    }

    callService.onCallConnected = () {
      if (kDebugMode) debugPrint('[CallPage] onCallConnected triggered');
      if (mounted) {
        _startTimer();
      }
    };

    callService.onCallEnded = (reason) {
      if (kDebugMode) debugPrint('[CallPage] onCallEnded: $reason');
      _timer?.cancel();
      // 延迟一帧确保状态已更新，然后安全关闭页面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    };
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  @override
  void dispose() {
    // 清理回调，防止内存泄漏（不能使用 ref，widget 已 disposed）
    _callService?.onCallConnected = null;
    _callService?.onCallEnded = null;
    _callService = null;

    _connectingController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).toggleMute();
  }

  void _toggleSpeaker() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).toggleSpeaker();
  }

  void _toggleVideo() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).toggleVideo();
  }

  void _switchCamera() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).switchCamera();
  }

  void _endCall() {
    HapticFeedback.mediumImpact();
    ref.read(callServiceProvider.notifier).endCall();
  }

  void _cancelCall() {
    HapticFeedback.mediumImpact();
    ref.read(callServiceProvider.notifier).cancelCall();
    // 不需要手动 pop，cancelCall 会触发 onCallEnded 回调，
    // 或者 build 方法检测到 idle 状态后会自动关闭页面
  }

  void _minimize() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).toggleMinimize();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callServiceProvider);
    final callInfo = callState.callInfo;

    // 如果通话信息为空或通话已结束，自动关闭页面（用标志位防止重复调度）
    if (callInfo == null || callState.state == CallState.idle) {
      if (!_isClosing) {
        _isClosing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    
    // 当状态变为 connected 时启动计时器（处理状态变化的情况）
    if (callState.state == CallState.connected && _timer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _timer == null) {
          if (kDebugMode) debugPrint('[CallPage] State changed to connected, starting timer');
          _startTimer();
        }
      });
    }

    final isVideo = callInfo.type == CallType.video;
    final isConnected = callState.state == CallState.connected;
    final isOutgoing = callState.state == CallState.outgoing;
    final isConnecting = callState.state == CallState.connecting;
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    // 桌面端使用紧凑布局
    if (isDesktop) {
      return _buildDesktopLayout(callState, callInfo, isVideo, isConnected, isOutgoing, isConnecting);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 视频背景或渐变背景
          if (isVideo && isConnected)
            _buildVideoView(callState)
          else
            _buildGradientBackground(isVideo),

          // 顶部栏
          _buildTopBar(context, isVideo, callInfo),

          // 中间内容
          if (!isVideo || !isConnected)
            _buildVoiceContent(callInfo, isConnected, isOutgoing, isConnecting),

          // 底部控制栏
          _buildBottomControls(callState, isVideo, isConnected, isOutgoing),
        ],
      ),
    );
  }

  /// 桌面端通话布局 - TG风格
  Widget _buildDesktopLayout(
    CallServiceState callState,
    CallInfo callInfo,
    bool isVideo,
    bool isConnected,
    bool isOutgoing,
    bool isConnecting,
  ) {
    // 视频通话使用更大窗口
    if (isVideo && isConnected) {
      return _buildDesktopVideoLayout(callState, callInfo);
    }
    
    // 语音通话/呼叫中布局
    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 头像区域 - 带呼吸动画
            AnimatedBuilder(
              animation: _connectingController ?? const AlwaysStoppedAnimation(0.0),
              builder: (context, child) {
                final scale = isConnected ? 1.0 : 1.0 + ((_connectingController?.value ?? 0.0) * 0.05);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF6B8AFF).withOpacity(0.3),
                          const Color(0xFF6B8AFF).withOpacity(0.1),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF6B8AFF).withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: AvatarWidget(
                        name: callInfo.remoteName,
                        avatar: callInfo.remoteAvatar,
                        userId: callInfo.remoteUserId,
                        size: 96,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 名字
            Text(
              callInfo.remoteName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 8),

            // 状态
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 16,
                  color: isConnected ? const Color(0xFF4CAF50) : const Color(0xFF6B8AFF),
                ),
                const SizedBox(width: 8),
                if (isConnected)
                  Text(
                    _formatDuration(_seconds),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF4CAF50),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  )
                else
                  _buildDesktopStatusText(isOutgoing ? '正在呼叫' : (isConnecting ? '正在连接' : (isVideo ? '视频通话' : '语音通话'))),
              ],
            ),

            const SizedBox(height: 60),

            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 静音
                _buildDesktopCallButton(
                  icon: callState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: callState.isMuted ? '取消静音' : '静音',
                  isActive: callState.isMuted,
                  onTap: _toggleMute,
                ),

                const SizedBox(width: 32),

                // 视频控制（仅视频通话）
                if (isVideo) ...[
                  _buildDesktopCallButton(
                    icon: callState.isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    label: callState.isVideoEnabled ? '关闭视频' : '开启视频',
                    isActive: !callState.isVideoEnabled,
                    onTap: _toggleVideo,
                  ),
                  const SizedBox(width: 32),
                ],

                // 挂断
                _buildDesktopCallButton(
                  icon: Icons.call_end_rounded,
                  label: isOutgoing ? '取消' : '挂断',
                  isActive: false,
                  isEndCall: true,
                  onTap: isOutgoing ? _cancelCall : _endCall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端状态文字
  Widget _buildDesktopStatusText(String text) {
    return AnimatedBuilder(
      animation: _connectingController ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, _) {
        final dots = '.' * (((_connectingController?.value ?? 0.0) * 3).floor() + 1);
        return Text(
          '$text$dots',
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF6B8AFF),
          ),
        );
      },
    );
  }

  /// 桌面端通话控制按钮
  Widget _buildDesktopCallButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEndCall = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isEndCall 
                    ? const Color(0xFFE53935)
                    : isActive 
                        ? Colors.white 
                        : const Color(0xFF2B3945),
                borderRadius: BorderRadius.circular(16),
                boxShadow: isEndCall ? [
                  BoxShadow(
                    color: const Color(0xFFE53935).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ] : null,
              ),
              child: Icon(
                icon,
                color: isEndCall || !isActive ? Colors.white : Colors.black87,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端视频通话布局
  Widget _buildDesktopVideoLayout(CallServiceState callState, CallInfo callInfo) {
    final callService = ref.read(callServiceProvider.notifier);
    final hasRemoteUser = callInfo.remoteUid != null;
    final remoteVideoEnabled = callState.isRemoteVideoEnabled;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0E1621),
      body: Stack(
        children: [
          // 远程视频（全屏）
          Positioned.fill(
            child: hasRemoteUser && remoteVideoEnabled
                ? callService.getRemoteView()
                : _buildDesktopRemoteVideoPlaceholder(callInfo, hasRemoteUser, remoteVideoEnabled),
          ),
          
          // 顶部信息栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.5),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  AvatarWidget(
                    name: callInfo.remoteName,
                    avatar: callInfo.remoteAvatar,
                    userId: callInfo.remoteUserId,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        callInfo.remoteName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            size: 14,
                            color: Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(_seconds),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF4CAF50),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  // 最小化按钮
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _minimize,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.remove, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 本地视频小窗口
          Positioned(
            bottom: 100,
            right: 20,
            child: Container(
              width: 180,
              height: 135,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: callState.isVideoEnabled
                  ? callService.getLocalView()
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_off_rounded,
                            color: Colors.white.withOpacity(0.4),
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '摄像头已关闭',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          
          // 底部控制栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDesktopVideoControlButton(
                    icon: callState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: '静音',
                    isActive: callState.isMuted,
                    onTap: _toggleMute,
                  ),
                  const SizedBox(width: 24),
                  _buildDesktopVideoControlButton(
                    icon: callState.isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    label: '视频',
                    isActive: !callState.isVideoEnabled,
                    onTap: _toggleVideo,
                  ),
                  const SizedBox(width: 24),
                  _buildDesktopVideoControlButton(
                    icon: Icons.call_end_rounded,
                    label: '挂断',
                    isActive: false,
                    isEndCall: true,
                    onTap: _endCall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 桌面端远程视频占位
  Widget _buildDesktopRemoteVideoPlaceholder(CallInfo callInfo, bool hasRemoteUser, bool remoteVideoEnabled) {
    return Container(
      color: const Color(0xFF17212B),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: AvatarWidget(
                name: callInfo.remoteName,
                avatar: callInfo.remoteAvatar,
                userId: callInfo.remoteUserId,
                size: 80,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              callInfo.remoteName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasRemoteUser ? Icons.videocam_off_rounded : Icons.hourglass_empty_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  hasRemoteUser ? '对方已关闭摄像头' : '等待对方接听...',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端视频控制按钮
  Widget _buildDesktopVideoControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEndCall = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isEndCall 
                    ? const Color(0xFFE53935)
                    : isActive 
                        ? Colors.white 
                        : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                boxShadow: isEndCall ? [
                  BoxShadow(
                    color: const Color(0xFFE53935).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ] : null,
              ),
              child: Icon(
                icon,
                color: isEndCall || !isActive ? Colors.white : Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoView(CallServiceState callState) {
    final callService = ref.read(callServiceProvider.notifier);
    final callInfo = callState.callInfo;
    final hasRemoteUser = callInfo?.remoteUid != null;
    final remoteVideoEnabled = callState.isRemoteVideoEnabled;
    
    return Stack(
      children: [
        // 远程视频（全屏）或等待/关闭画面
        Positioned.fill(
          child: hasRemoteUser && remoteVideoEnabled
              ? callService.getRemoteView()
              : _buildRemoteVideoPlaceholder(callInfo!, hasRemoteUser, remoteVideoEnabled),
        ),

        // 本地视频（小窗口）- 可拖动
        Positioned(
          top: MediaQuery.of(context).padding.top + 80,
          right: 16,
          child: GestureDetector(
            onTap: _switchCamera,
            child: Container(
              width: 110,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // 本地视频或关闭提示
                  if (callState.isVideoEnabled)
                    Positioned.fill(child: callService.getLocalView())
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_off_rounded,
                            color: Colors.white.withOpacity(0.6),
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '摄像头已关',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // 切换摄像头提示
                  if (callState.isVideoEnabled)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.flip_camera_ios_rounded,
                                color: Colors.white70,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '点击切换',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 远程视频占位画面（等待连接或对方关闭摄像头）
  Widget _buildRemoteVideoPlaceholder(CallInfo callInfo, bool hasRemoteUser, bool remoteVideoEnabled) {
    final statusText = hasRemoteUser 
        ? '对方已关闭摄像头' 
        : '等待对方接听...';
    final showSpinner = !hasRemoteUser;
    
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: AvatarWidget(
                name: callInfo.remoteName,
                avatar: callInfo.remoteAvatar,
                userId: callInfo.remoteUserId,
                size: 100,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              callInfo.remoteName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSpinner) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    Icons.videocam_off_rounded,
                    size: 18,
                    color: Colors.white.withOpacity(0.6),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientBackground(bool isVideo) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isVideo
              ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
              : [const Color(0xFF0F2027), const Color(0xFF203A43), const Color(0xFF2C5364)],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isVideo, CallInfo callInfo) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.5),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // 最小化按钮
            _buildTopButton(
              icon: Icons.keyboard_arrow_down_rounded,
              onTap: _minimize,
            ),
            
            const Spacer(),

            // 通话类型
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isVideo ? '视频通话' : '语音通话',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // 切换摄像头（视频通话时显示）
            if (isVideo)
              _buildTopButton(
                icon: Icons.cameraswitch_rounded,
                onTap: _switchCamera,
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildVoiceContent(
    CallInfo callInfo,
    bool isConnected,
    bool isOutgoing,
    bool isConnecting,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头像
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: AvatarWidget(
              name: callInfo.remoteName,
              avatar: callInfo.remoteAvatar,
              userId: callInfo.remoteUserId,
              size: 100,
            ),
          ),

          const SizedBox(height: 20),

          // 名字
          Text(
            callInfo.remoteName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 8),

          // 状态
          if (isConnected)
            Text(
              _formatDuration(_seconds),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            )
          else if (isOutgoing)
            _buildConnectingText('呼叫中')
          else if (isConnecting)
            _buildConnectingText('连接中'),
        ],
      ),
    );
  }

  Widget _buildConnectingText(String text) {
    return AnimatedBuilder(
      animation: _connectingController ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, _) {
        final dots = '.' * (((_connectingController?.value ?? 0.0) * 3).floor() + 1);
        return Text(
          '$text$dots',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        );
      },
    );
  }

  Widget _buildBottomControls(
    CallServiceState callState,
    bool isVideo,
    bool isConnected,
    bool isOutgoing,
  ) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 20,
          bottom: MediaQuery.of(context).padding.bottom + 30,
          left: 24,
          right: 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 静音
                _buildControlButton(
                  icon: callState.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  label: callState.isMuted ? '取消静音' : '静音',
                  isActive: callState.isMuted,
                  onTap: _toggleMute,
                ),

                // 视频通话特有控制
                if (isVideo) ...[
                  // 开关视频
                  _buildControlButton(
                    icon: callState.isVideoEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: callState.isVideoEnabled ? '关闭视频' : '开启视频',
                    isActive: !callState.isVideoEnabled,
                    onTap: _toggleVideo,
                  ),
                  
                  // 切换摄像头
                  _buildControlButton(
                    icon: Icons.flip_camera_ios_rounded,
                    label: '切换摄像头',
                    isActive: false,
                    onTap: _switchCamera,
                  ),
                ] else
                  // 扬声器（语音通话时显示）
                  _buildControlButton(
                    icon: callState.isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    label: callState.isSpeakerOn ? '关闭扬声器' : '扬声器',
                    isActive: callState.isSpeakerOn,
                    onTap: _toggleSpeaker,
                  ),

                // 挂断
                _buildEndCallButton(isOutgoing),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildEndCallButton(bool isOutgoing) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: isOutgoing ? _cancelCall : _endCall,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.error.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isOutgoing ? '取消' : '挂断',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
