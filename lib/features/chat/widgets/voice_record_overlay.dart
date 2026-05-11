import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/voice_record_service.dart';

/// 语音录制覆盖层
class VoiceRecordOverlay extends ConsumerStatefulWidget {
  final VoidCallback onSend;
  final VoidCallback onCancel;
  
  const VoiceRecordOverlay({
    super.key,
    required this.onSend,
    required this.onCancel,
  });
  
  @override
  ConsumerState<VoiceRecordOverlay> createState() => _VoiceRecordOverlayState();
}

class _VoiceRecordOverlayState extends ConsumerState<VoiceRecordOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isCancelling = false;
  double _dragOffset = 0;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recordState = ref.watch(voiceRecordProvider);
    
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dx;
          _isCancelling = _dragOffset < -80;
        });
        if (_isCancelling) {
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (details) {
        if (_isCancelling) {
          widget.onCancel();
        }
        setState(() {
          _dragOffset = 0;
          _isCancelling = false;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // 取消区域 - 优化样式
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: _isCancelling ? 56 : 44,
                height: _isCancelling ? 56 : 44,
                decoration: BoxDecoration(
                  color: _isCancelling 
                      ? AppColors.error
                      : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
                  shape: BoxShape.circle,
                  boxShadow: _isCancelling ? [
                    BoxShadow(
                      color: AppColors.error.withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ] : null,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isCancelling 
                      ? const Icon(
                          Icons.close_rounded,
                          key: ValueKey('cancel'),
                          color: Colors.white,
                          size: 26,
                        )
                      : Icon(
                          Icons.keyboard_arrow_left_rounded,
                          key: const ValueKey('arrow'),
                          color: isDark ? Colors.white54 : Colors.black45,
                          size: 28,
                        ),
                ),
              ),
              
              // 左滑取消提示
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _isCancelling ? 0.0 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '← 滑动取消',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),
              ),
              
              const Spacer(),
              
              // 录音时长
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1 + _pulseController.value * 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(recordState.duration),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              
              const Spacer(),
              
              // 声波动画
              SizedBox(
                width: 60,
                height: 40,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    amplitude: recordState.amplitude,
                    color: AppColors.primary,
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // 发送按钮
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onSend();
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 波形绘制器
class _WaveformPainter extends CustomPainter {
  final double amplitude;
  final Color color;
  
  _WaveformPainter({
    required this.amplitude,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    
    final barCount = 5;
    final barWidth = 3.0;
    final spacing = (size.width - barCount * barWidth) / (barCount + 1);
    final maxHeight = size.height * 0.8;
    final minHeight = size.height * 0.2;
    
    for (int i = 0; i < barCount; i++) {
      final x = spacing + i * (barWidth + spacing) + barWidth / 2;
      
      // 根据振幅和位置计算高度
      final phase = (i - barCount / 2).abs() / (barCount / 2);
      final height = minHeight + (maxHeight - minHeight) * amplitude * (1 - phase * 0.5);
      
      final y1 = (size.height - height) / 2;
      final y2 = y1 + height;
      
      canvas.drawLine(
        Offset(x, y1),
        Offset(x, y2),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.amplitude != amplitude;
  }
}

/// 语音消息气泡中的播放器
class VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final int duration; // 毫秒
  final bool isOutgoing;
  
  const VoiceMessagePlayer({
    super.key,
    required this.url,
    required this.duration,
    required this.isOutgoing,
  });
  
  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  bool _isPlaying = false;
  double _progress = 0;
  
  String _formatDuration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = widget.isOutgoing
        ? AppColors.primary
        : (isDark ? const Color(0xFF2C2C2E) : Colors.white);
    final textColor = widget.isOutgoing
        ? Colors.white
        : (isDark ? Colors.white : Colors.black);
    final secondaryColor = widget.isOutgoing
        ? Colors.white70
        : (isDark ? Colors.white54 : Colors.black54);
    
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放按钮
          GestureDetector(
            onTap: () {
              setState(() => _isPlaying = !_isPlaying);
              HapticFeedback.selectionClick();
              // TODO: 实现实际播放逻辑
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isOutgoing
                    ? Colors.white.withOpacity(0.2)
                    : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: widget.isOutgoing ? Colors.white : AppColors.primary,
                size: 22,
              ),
            ),
          ),
          
          const SizedBox(width: 10),
          
          // 波形和时长
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 简化波形
                SizedBox(
                  height: 20,
                  child: CustomPaint(
                    size: const Size(double.infinity, 20),
                    painter: _StaticWaveformPainter(
                      progress: _progress,
                      activeColor: textColor,
                      inactiveColor: secondaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(widget.duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 静态波形绘制器
class _StaticWaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  
  _StaticWaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // 固定种子保证波形一致
    final barCount = 25;
    final barWidth = 2.0;
    final spacing = (size.width - barCount * barWidth) / (barCount - 1);
    
    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final normalizedProgress = progress * barCount;
      
      final isActive = i < normalizedProgress;
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;
      
      final height = size.height * (0.3 + random.nextDouble() * 0.7);
      final y1 = (size.height - height) / 2;
      final y2 = y1 + height;
      
      canvas.drawLine(
        Offset(x + barWidth / 2, y1),
        Offset(x + barWidth / 2, y2),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant _StaticWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
