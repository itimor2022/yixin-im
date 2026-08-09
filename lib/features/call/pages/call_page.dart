// 文件用途：实现 CallPage 页面及其交互流程，属于音视频通话。
// 核心逻辑：维护 CallPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/call_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../shared/widgets/avatar_widget.dart';

String _callText(
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

// 关键声明：call page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 通话展示入口；页面不拥有通话生命周期，所有状态流转和媒体控制都委托给 [CallService]。
class CallPage extends ConsumerStatefulWidget {
  const CallPage({super.key});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _connectingController;
  Timer? _timer;
  int _seconds = 0;

  /// 缓存 notifier，dispose 时不能使用 ref
  CallService? _callService;
  bool _initialized = false;

  /// 防止 build 内多次调度 pop
  bool _isClosing = false;
  CallType? _lastOrientationType;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
    _configureOrientation(currentState.callInfo?.type);

    // CallKit 可能先完成接听再创建 Flutter 页面，因此必须同时处理当前状态和后续回调。
    // 如果已经是 connected 状态，立即启动计时器
    // 这处理了从 CallKit 接听时，回调可能在页面创建前就已触发的情况
    if (currentState.state == CallState.connected) {
      debugPrint('[CallPage] Already connected, starting timer immediately');
      _startTimer();
    }

    callService.onCallConnected = () {
      debugPrint('[CallPage] onCallConnected triggered');
      if (mounted) {
        _startTimer();
      }
    };

    callService.onCallEnded = (reason) {
      debugPrint('[CallPage] onCallEnded: $reason');
      _timer?.cancel();
      _closeCallPage();
    };
  }

  void _closeCallPage() {
    // 状态监听和 build 都可能请求关闭，统一延后并幂等 pop，避免构建期修改导航栈。
    if (_isClosing) return;
    _isClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _syncDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_syncDuration);
      }
    });
  }

  void _syncDuration() {
    final elapsed = _callService?.callDuration.inSeconds ?? 0;
    _seconds = elapsed < 0 ? 0 : elapsed;
  }

  void _configureOrientation(CallType? type) {
    if (kIsWeb || type == null || _lastOrientationType == type) return;
    _lastOrientationType = type;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (type == CallType.video) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    } else {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _callService?.handleAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_syncDuration);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 清理回调，防止内存泄漏（不能使用 ref，widget 已 disposed）
    _callService?.onCallConnected = null;
    _callService?.onCallEnded = null;
    _callService = null;

    _connectingController?.dispose();
    _timer?.cancel();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]));
    }
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

  void _downgradeToVoice() {
    HapticFeedback.selectionClick();
    ref.read(callServiceProvider.notifier).downgradeToVoice();
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

  void _showMoreActions(bool isVideo) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      barrierColor: Colors.black.withOpacity(0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                _buildMoreActionTile(
                  icon: Icons.picture_in_picture_alt_rounded,
                  label: _callText(
                    context,
                    zhCN: '最小化通话',
                    zhTW: '最小化通話',
                    en: 'Minimize call',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _minimize();
                  },
                ),
                if (isVideo)
                  _buildMoreActionTile(
                    icon: Icons.flip_camera_ios_rounded,
                    label: _callText(
                      context,
                      zhCN: '翻转摄像头',
                      zhTW: '翻轉攝像頭',
                      en: 'Flip camera',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _switchCamera();
                    },
                  ),
                if (isVideo)
                  _buildMoreActionTile(
                    icon: Icons.phone_in_talk_rounded,
                    label: _callText(
                      context,
                      zhCN: '切换为语音通话',
                      zhTW: '切換為語音通話',
                      en: 'Switch to voice call',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _downgradeToVoice();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callServiceProvider);
    final callInfo = callState.callInfo;

    // 如果通话信息为空或通话已结束，自动关闭页面（用标志位防止重复调度）
    if (callInfo == null || callState.state == CallState.idle) {
      _closeCallPage();
      return const DarkSystemUiScope(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.shrink(),
        ),
      );
    }

    if (_lastOrientationType != callInfo.type) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _configureOrientation(callInfo.type);
      });
    }

    // 当状态变为 connected 时启动计时器（处理状态变化的情况）
    if (callState.state == CallState.connected && _timer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _timer == null) {
          debugPrint('[CallPage] State changed to connected, starting timer');
          _startTimer();
        }
      });
    }

    final isVideo = callInfo.type == CallType.video;
    final isConnected = callState.state == CallState.connected;
    final isOutgoing = callState.state == CallState.outgoing;
    final isConnecting = callState.state == CallState.connecting;
    final isReconnecting = callState.state == CallState.reconnecting;
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    // 桌面端使用紧凑布局
    if (isDesktop) {
      return _buildDesktopLayout(
        callState,
        callInfo,
        isVideo,
        isConnected,
        isOutgoing,
        isConnecting || isReconnecting,
      );
    }

    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 视频通话远端画面全屏铺底，未接通/语音时使用背景
            if (isVideo && isConnected)
              _buildVideoView(callState)
            else
              _buildGradientBackground(isVideo),

            // 顶部栏
            _buildTopBar(context, isVideo, callInfo, isConnected),

            // 中间内容
            if (!isVideo || !isConnected)
              _buildVoiceContent(
                callInfo,
                isConnected,
                isOutgoing,
                isConnecting || isReconnecting,
              ),

            if (isReconnecting)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 86,
                left: 24,
                right: 24,
                child: SafeArea(
                  child: Container(
                    key: const ValueKey('call_reconnecting_banner'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _callText(
                        context,
                        zhCN:
                            '网络中断，正在重连（${callState.reconnectSecondsRemaining}秒）',
                        zhTW:
                            '網路中斷，正在重連（${callState.reconnectSecondsRemaining}秒）',
                        en: 'Connection lost. Reconnecting (${callState.reconnectSecondsRemaining}s)',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

            // 底部控制栏
            _buildBottomControls(callState, isVideo, isConnected, isOutgoing),
          ],
        ),
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
              animation:
                  _connectingController ?? const AlwaysStoppedAnimation(0.0),
              builder: (context, child) {
                final scale = isConnected
                    ? 1.0
                    : 1.0 + ((_connectingController?.value ?? 0.0) * 0.05);
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
                        isCircle: true,
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
                  color: isConnected
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF6B8AFF),
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
                  _buildDesktopStatusText(
                    isOutgoing
                        ? _callText(
                            context,
                            zhCN: '正在呼叫',
                            zhTW: '正在通話',
                            en: 'Calling',
                          )
                        : (isConnecting
                            ? _callText(
                                context,
                                zhCN: '正在连接',
                                zhTW: '正在連線',
                                en: 'Connecting',
                              )
                            : _callText(
                                context,
                                zhCN: isVideo ? '视频通话' : '语音通话',
                                zhTW: isVideo ? '視訊通話' : '語音通話',
                                en: isVideo ? 'Video call' : 'Voice call',
                              )),
                  ),
              ],
            ),

            const SizedBox(height: 60),

            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 静音
                _buildDesktopCallButton(
                  buttonKey: const ValueKey('call_page_mute_button'),
                  icon: callState.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  label: _callText(
                    context,
                    zhCN: callState.isMuted ? '取消静音' : '静音',
                    zhTW: callState.isMuted ? '取消靜音' : '靜音',
                    en: callState.isMuted ? 'Unmute' : 'Mute',
                  ),
                  isActive: callState.isMuted,
                  onTap: _toggleMute,
                ),

                const SizedBox(width: 32),

                // 视频控制（仅视频通话）
                if (isVideo) ...[
                  _buildDesktopCallButton(
                    buttonKey: const ValueKey('call_page_video_toggle_button'),
                    icon: callState.isVideoEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: _callText(
                      context,
                      zhCN: callState.isVideoEnabled ? '关闭视频' : '开启视频',
                      zhTW: callState.isVideoEnabled ? '關閉視訊' : '開啟視訊',
                      en: callState.isVideoEnabled
                          ? 'Turn off video'
                          : 'Turn on video',
                    ),
                    isActive: !callState.isVideoEnabled,
                    onTap: _toggleVideo,
                  ),
                  const SizedBox(width: 32),
                ],

                // 挂断
                _buildDesktopCallButton(
                  buttonKey: const ValueKey('call_page_end_button'),
                  icon: Icons.call_end_rounded,
                  label: _callText(
                    context,
                    zhCN: isOutgoing ? '取消' : '挂断',
                    zhTW: isOutgoing ? '取消' : '掛斷',
                    en: isOutgoing ? 'Cancel' : 'End',
                  ),
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
        final dots =
            '.' * (((_connectingController?.value ?? 0.0) * 3).floor() + 1);
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
    Key? buttonKey,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEndCall = false,
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
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isEndCall
                        ? const Color(0xFFE53935)
                        : isActive
                            ? Colors.white
                            : const Color(0xFF2B3945),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isEndCall
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE53935).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color:
                        isEndCall || !isActive ? Colors.white : Colors.black87,
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
        ),
      ),
    );
  }

  /// 桌面端视频通话布局
  Widget _buildDesktopVideoLayout(
      CallServiceState callState, CallInfo callInfo) {
    final callService = ref.read(callServiceProvider.notifier);
    final hasRemoteUser = callInfo.remoteUid != null;
    final remoteVideoEnabled = callState.isRemoteVideoEnabled;
    final minimizeLabel = _callText(
      context,
      zhCN: '最小化',
      zhTW: '最小化',
      en: 'Minimize',
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0E1621),
      body: Stack(
        children: [
          // 远程视频（全屏）
          Positioned.fill(
            child: hasRemoteUser && remoteVideoEnabled
                ? callService.getRemoteView()
                : _buildDesktopRemoteVideoPlaceholder(
                    callInfo, hasRemoteUser, remoteVideoEnabled),
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
                    isCircle: true,
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
                  Semantics(
                    key: const ValueKey(
                        'call_page_desktop_video_minimize_button'),
                    button: true,
                    label: minimizeLabel,
                    onTap: _minimize,
                    child: Tooltip(
                      message: minimizeLabel,
                      child: MouseRegion(
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
                            child: const Icon(Icons.remove,
                                color: Colors.white, size: 20),
                          ),
                        ),
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
                border:
                    Border.all(color: Colors.white.withOpacity(0.1), width: 1),
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
                            _callText(
                              context,
                              zhCN: '摄像头已关闭',
                              zhTW: '攝像頭已關閉',
                              en: 'Camera is off',
                            ),
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
                    buttonKey: const ValueKey('call_page_mute_button'),
                    icon: callState.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: _callText(
                      context,
                      zhCN: '静音',
                      zhTW: '靜音',
                      en: 'Mute',
                    ),
                    isActive: callState.isMuted,
                    onTap: _toggleMute,
                  ),
                  const SizedBox(width: 24),
                  _buildDesktopVideoControlButton(
                    buttonKey: const ValueKey('call_page_video_toggle_button'),
                    icon: callState.isVideoEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: _callText(
                      context,
                      zhCN: '视频',
                      zhTW: '視訊',
                      en: 'Video',
                    ),
                    isActive: !callState.isVideoEnabled,
                    onTap: _toggleVideo,
                  ),
                  const SizedBox(width: 24),
                  _buildDesktopVideoControlButton(
                    buttonKey: const ValueKey('call_page_end_button'),
                    icon: Icons.call_end_rounded,
                    label: _callText(
                      context,
                      zhCN: '挂断',
                      zhTW: '掛斷',
                      en: 'End',
                    ),
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
  Widget _buildDesktopRemoteVideoPlaceholder(
      CallInfo callInfo, bool hasRemoteUser, bool remoteVideoEnabled) {
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
                isCircle: true,
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
                  hasRemoteUser
                      ? Icons.videocam_off_rounded
                      : Icons.hourglass_empty_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  _callText(
                    context,
                    zhCN: hasRemoteUser ? '对方已关闭摄像头' : '等待对方接听...',
                    zhTW: hasRemoteUser ? '對方已關閉攝像頭' : '等待對方接聽...',
                    en: hasRemoteUser
                        ? 'Remote camera is off'
                        : 'Waiting for answer...',
                  ),
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
    Key? buttonKey,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEndCall = false,
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
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isEndCall
                        ? const Color(0xFFE53935)
                        : isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isEndCall
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE53935).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color:
                        isEndCall || !isActive ? Colors.white : Colors.black87,
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
              : _buildRemoteVideoPlaceholder(
                  callInfo!, hasRemoteUser, remoteVideoEnabled),
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
                            _callText(
                              context,
                              zhCN: '摄像头已关',
                              zhTW: '攝像頭已關',
                              en: 'Camera off',
                            ),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                                _callText(
                                  context,
                                  zhCN: '点击切换',
                                  zhTW: '點擊切換',
                                  en: 'Tap to switch',
                                ),
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
  Widget _buildRemoteVideoPlaceholder(
      CallInfo callInfo, bool hasRemoteUser, bool remoteVideoEnabled) {
    final statusText = _callText(
      context,
      zhCN: hasRemoteUser ? '对方已关闭摄像头' : '等待对方接听...',
      zhTW: hasRemoteUser ? '對方已關閉攝像頭' : '等待對方接聽...',
      en: hasRemoteUser ? 'Remote camera is off' : 'Waiting for answer...',
    );
    final showSpinner = !hasRemoteUser;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF120303),
            Color(0xFF320A08),
            Color(0xFF050303),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
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
                  isCircle: true,
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
              : [
                  const Color(0xFF0F2027),
                  const Color(0xFF203A43),
                  const Color(0xFF2C5364)
                ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    bool isVideo,
    CallInfo callInfo,
    bool isConnected,
  ) {
    if (isVideo && isConnected) {
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            bottom: 28,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.56),
                Colors.transparent,
              ],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _buildTopButton(
                  buttonKey: const ValueKey('call_page_minimize_button'),
                  icon: Icons.picture_in_picture_alt_rounded,
                  semanticLabel: _callText(
                    context,
                    zhCN: '最小化',
                    zhTW: '最小化',
                    en: 'Minimize',
                  ),
                  onTap: _minimize,
                ),
              ),
              Text(
                _formatDuration(_seconds),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopButton(
                      buttonKey:
                          const ValueKey('call_page_top_switch_camera_button'),
                      icon: Icons.cameraswitch_rounded,
                      semanticLabel: _callText(
                        context,
                        zhCN: '切换摄像头',
                        zhTW: '切換攝像頭',
                        en: 'Switch camera',
                      ),
                      onTap: _switchCamera,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
              buttonKey: const ValueKey('call_page_minimize_button'),
              icon: Icons.keyboard_arrow_down_rounded,
              semanticLabel: _callText(
                context,
                zhCN: '最小化',
                zhTW: '最小化',
                en: 'Minimize',
              ),
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
                    _callText(
                      context,
                      zhCN: isVideo ? '视频通话' : '语音通话',
                      zhTW: isVideo ? '視訊通話' : '語音通話',
                      en: isVideo ? 'Video call' : 'Voice call',
                    ),
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
                buttonKey: const ValueKey('call_page_top_switch_camera_button'),
                icon: Icons.cameraswitch_rounded,
                semanticLabel: _callText(
                  context,
                  zhCN: '切换摄像头',
                  zhTW: '切換攝像頭',
                  en: 'Switch camera',
                ),
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
    Key? buttonKey,
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      key: buttonKey,
      button: true,
      label: semanticLabel,
      onTap: onTap,
      child: Tooltip(
        message: semanticLabel,
        child: GestureDetector(
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
        ),
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
              isCircle: true,
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
            _buildConnectingText(
              _callText(
                context,
                zhCN: '呼叫中',
                zhTW: '通話中',
                en: 'Calling',
              ),
            )
          else if (isConnecting)
            _buildConnectingText(
              _callText(
                context,
                zhCN: '连接中',
                zhTW: '連線中',
                en: 'Connecting',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectingText(String text) {
    return AnimatedBuilder(
      animation: _connectingController ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, _) {
        final dots =
            '.' * (((_connectingController?.value ?? 0.0) * 3).floor() + 1);
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 56,
          bottom: bottomInset + 20,
          left: 24,
          right: 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.82),
              Colors.black.withOpacity(0.34),
              Colors.transparent,
            ],
            stops: const [0.0, 0.62, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: isVideo
              ? [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_mute_button'),
                        icon: callState.isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _callText(
                          context,
                          zhCN: callState.isMuted ? '麦克风已关' : '麦克风已开',
                          zhTW: callState.isMuted ? '麥克風已關' : '麥克風已開',
                          en: callState.isMuted ? 'Mic off' : 'Mic on',
                        ),
                        isLight: !callState.isMuted,
                        onTap: _toggleMute,
                      ),
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_speaker_button'),
                        icon: callState.isSpeakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        label: _callText(
                          context,
                          zhCN: callState.isSpeakerOn ? '扬声器已开' : '扬声器已关',
                          zhTW: callState.isSpeakerOn ? '揚聲器已開' : '揚聲器已關',
                          en: callState.isSpeakerOn
                              ? 'Speaker on'
                              : 'Speaker off',
                        ),
                        isLight: callState.isSpeakerOn,
                        onTap: _toggleSpeaker,
                      ),
                      _buildWechatCallButton(
                        buttonKey:
                            const ValueKey('call_page_video_toggle_button'),
                        icon: callState.isVideoEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        label: _callText(
                          context,
                          zhCN: callState.isVideoEnabled ? '摄像头已开' : '摄像头已关',
                          zhTW: callState.isVideoEnabled ? '攝像頭已開' : '攝像頭已關',
                          en: callState.isVideoEnabled
                              ? 'Camera on'
                              : 'Camera off',
                        ),
                        isLight: callState.isVideoEnabled,
                        onTap: _toggleVideo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_more_button'),
                        icon: Icons.more_horiz_rounded,
                        label: _callText(
                          context,
                          zhCN: '更多',
                          zhTW: '更多',
                          en: 'More',
                        ),
                        onTap: () => _showMoreActions(isVideo),
                      ),
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_end_button'),
                        icon: Icons.call_end_rounded,
                        label: _callText(
                          context,
                          zhCN: isOutgoing ? '取消' : '挂断',
                          zhTW: isOutgoing ? '取消' : '掛斷',
                          en: isOutgoing ? 'Cancel' : 'End',
                        ),
                        isEndCall: true,
                        onTap: isOutgoing ? _cancelCall : _endCall,
                      ),
                      _buildWechatCallButton(
                        buttonKey:
                            const ValueKey('call_page_switch_camera_button'),
                        icon: Icons.flip_camera_ios_rounded,
                        label: _callText(
                          context,
                          zhCN: '翻转摄像头',
                          zhTW: '翻轉攝像頭',
                          en: 'Flip camera',
                        ),
                        onTap: _switchCamera,
                      ),
                    ],
                  ),
                ]
              : [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_mute_button'),
                        icon: callState.isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _callText(
                          context,
                          zhCN: callState.isMuted ? '麦克风已关' : '麦克风已开',
                          zhTW: callState.isMuted ? '麥克風已關' : '麥克風已開',
                          en: callState.isMuted ? 'Mic off' : 'Mic on',
                        ),
                        isLight: !callState.isMuted,
                        onTap: _toggleMute,
                      ),
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_speaker_button'),
                        icon: callState.isSpeakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        label: _callText(
                          context,
                          zhCN: callState.isSpeakerOn ? '扬声器已开' : '扬声器已关',
                          zhTW: callState.isSpeakerOn ? '揚聲器已開' : '揚聲器已關',
                          en: callState.isSpeakerOn
                              ? 'Speaker on'
                              : 'Speaker off',
                        ),
                        isLight: callState.isSpeakerOn,
                        onTap: _toggleSpeaker,
                      ),
                      _buildWechatCallButton(
                        buttonKey: const ValueKey('call_page_end_button'),
                        icon: Icons.call_end_rounded,
                        label: _callText(
                          context,
                          zhCN: isOutgoing ? '取消' : '挂断',
                          zhTW: isOutgoing ? '取消' : '掛斷',
                          en: isOutgoing ? 'Cancel' : 'End',
                        ),
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

  Widget _buildWechatCallButton({
    Key? buttonKey,
    required IconData icon,
    required String label,
    bool isLight = false,
    bool isEndCall = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 86,
      child: Semantics(
        key: buttonKey,
        button: true,
        enabled: onTap != null,
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
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: isEndCall
                        ? const Color(0xFFFF4D57)
                        : isLight
                            ? Colors.white
                            : Colors.white.withOpacity(0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isLight && !isEndCall ? Colors.black : Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
