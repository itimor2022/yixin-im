import 'package:flutter/material.dart';
import 'dart:math' as math;

///  官方认证标识（带动画）
class OfficialBadge extends StatefulWidget {
  final double size;

  const OfficialBadge({
    super.key,
    this.size = 18,
  });

  @override
  State<OfficialBadge> createState() => _OfficialBadgeState();
}

class _OfficialBadgeState extends State<OfficialBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _OfficialBadgePainter(
              progress: _controller.value,
            ),
            child: Center(
              child: Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: widget.size * 0.55,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OfficialBadgePainter extends CustomPainter {
  final double progress;

  _OfficialBadgePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 绘制主体 - 渐变蓝色星形背景
    final starPath = _createStarPath(center, radius, radius * 0.75, 6);
    
    // 渐变
    final gradient = SweepGradient(
      startAngle: progress * 2 * math.pi,
      colors: const [
        Color(0xFF3390EC), // Telegram 蓝
        Color(0xFF50A8EB),
        Color(0xFF69BFF8),
        Color(0xFF50A8EB),
        Color(0xFF3390EC),
      ],
      transform: GradientRotation(progress * 2 * math.pi),
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawPath(starPath, paint);

    // 绘制闪烁的小星星
    _drawSparkles(canvas, center, radius, progress);
  }

  Path _createStarPath(Offset center, double outerRadius, double innerRadius, int points) {
    final path = Path();
    final angle = math.pi / points;

    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final a = i * angle - math.pi / 2;
      final x = center.dx + r * math.cos(a);
      final y = center.dy + r * math.sin(a);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    return path;
  }

  void _drawSparkles(Canvas canvas, Offset center, double radius, double progress) {
    final sparklePaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    // 3个闪烁点，位置随动画变化
    for (int i = 0; i < 3; i++) {
      final angle = (progress * 2 + i / 3) * math.pi * 2;
      final sparkleRadius = radius * 0.12 * (0.5 + 0.5 * math.sin(progress * math.pi * 4 + i));
      
      if (sparkleRadius > 0.5) {
        final x = center.dx + radius * 0.7 * math.cos(angle);
        final y = center.dy + radius * 0.7 * math.sin(angle);
        canvas.drawCircle(Offset(x, y), sparkleRadius, sparklePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OfficialBadgePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 静态版本（不带动画，用于性能敏感的场景）
class OfficialBadgeStatic extends StatelessWidget {
  final double size;

  const OfficialBadgeStatic({
    super.key,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StaticBadgePainter(),
        child: Center(
          child: Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: size * 0.55,
          ),
        ),
      ),
    );
  }
}

class _StaticBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 绘制星形背景
    final starPath = _createStarPath(center, radius, radius * 0.75, 6);
    
    final paint = Paint()
      ..color = const Color(0xFF3390EC); // Telegram 蓝

    canvas.drawPath(starPath, paint);
  }

  Path _createStarPath(Offset center, double outerRadius, double innerRadius, int points) {
    final path = Path();
    final angle = math.pi / points;

    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final a = i * angle - math.pi / 2;
      final x = center.dx + r * math.cos(a);
      final y = center.dy + r * math.sin(a);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
