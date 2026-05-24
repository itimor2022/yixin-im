import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/call_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../shared/widgets/avatar_widget.dart';
import 'call_page.dart';

/// 来电界面 - TG风格
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
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isProcessing = false;

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

    // 设置状态栏
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    
    // 开始播放铃声和振动提醒
    _playRingtone();
    _startVibration();
    
    // 监听通话状态变化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupCallListener();
    });
  }
  
  Future<void> _playRingtone() async {
    try {
      // 循环播放铃声
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(AssetSource('sounds/ringtone.mp3'));
    } catch (e) {
      if (kDebugMode) debugPrint('[IncomingCall] Play ringtone error: $e');
    }
  }
  
  Future<void> _stopRingtone() async {
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }
  
  void _setupCallListener() {
    // 监听通话状态：若在处理前对方已挂断（状态变为 idle），自动关闭页面
    final callState = ref.read(callServiceProvider);
    if (callState.state != CallState.incoming && !_isProcessing) {
      _stopVibration();
      _stopRingtone();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
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
    _pulseController.dispose();
    _stopVibration();
    _stopRingtone();
    _ringtonePlayer.dispose();
    super.dispose();
  }

  void _acceptCall() {
    if (_isProcessing) return;
    _isProcessing = true;

    HapticFeedback.mediumImpact();
    _stopVibration();
    _ringtonePlayer.stop();

    _doAcceptCall();
  }

  /// 先完成接听握手，成功后再切换到通话页面
  Future<void> _doAcceptCall() async {
    try {
      final success = await ref.read(callServiceProvider.notifier).acceptCall();
      if (kDebugMode) debugPrint('[IncomingCall] Accept call result: $success');

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
        _startVibration();
        final errorMsg = ref.read(callServiceProvider).errorMessage ?? '接听失败，请重试';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[IncomingCall] Accept call error: $e');
      if (!mounted) return;
      _isProcessing = false;
      _startVibration();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('接听出错，请重试')),
      );
    }
  }

  void _rejectCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    
    HapticFeedback.mediumImpact();
    _stopVibration();
    await _stopRingtone();
    await ref.read(callServiceProvider.notifier).rejectCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callServiceProvider);
    final isVideo = widget.callInfo.type == CallType.video;
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    
    // 如果通话状态不再是来电中，自动关闭页面并停铃声
    if (callState.state != CallState.incoming && !_isProcessing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stopVibration();
        _stopRingtone(); // 立即停止铃声
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    // 桌面端使用紧凑布局
    if (isDesktop) {
      return _buildDesktopLayout(isVideo);
    }

    return Scaffold(
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
                  isVideo ? '视频通话' : '语音通话',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 8),

                // 来电提示
                Text(
                  _isProcessing ? '正在接听...' : '来电...',
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
                        icon: Icons.call_end_rounded,
                        label: '拒绝',
                        color: AppColors.error,
                        onTap: _rejectCall,
                      ),

                      // 接听
                      _buildCallButton(
                        icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        label: '接听',
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
                  isVideo ? '视频来电...' : '语音来电...',
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
                  icon: Icons.call_end_rounded,
                  label: '拒绝',
                  color: const Color(0xFFE53935),
                  onTap: _rejectCall,
                ),

                const SizedBox(width: 60),

                // 接听
                _buildDesktopIncomingButton(
                  icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  label: '接听',
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
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
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
    );
  }

  Widget _buildBackground(bool isVideo) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isVideo
              ? [const Color(0xFF667EEA), const Color(0xFF764BA2)]
              : [const Color(0xFF11998E), const Color(0xFF38EF7D)],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
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
    );
  }
}
