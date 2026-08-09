// 文件用途：实现 _TopToastWidget 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _TopToastWidget 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail feedback widgets 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// Telegram 风格顶部浮动提示
class _TopToastWidget extends StatefulWidget {
  final String message;
  final bool isDark;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // 自动消失
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: padding.top + 60 + (_slideAnimation.value * 50),
          left: 16,
          right: 16,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF2C2C2E).withOpacity(0.95)
                      : Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 消息删除破碎动画
class _MessageDeleteAnimation extends StatefulWidget {
  final Offset screenCenter;
  final VoidCallback onComplete;

  const _MessageDeleteAnimation({
    required this.screenCenter,
    required this.onComplete,
  });

  @override
  State<_MessageDeleteAnimation> createState() =>
      _MessageDeleteAnimationState();
}

class _MessageDeleteAnimationState extends State<_MessageDeleteAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 创建粒子
    _particles = List.generate(25, (index) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 150 + _random.nextDouble() * 200;
      final size = 4 + _random.nextDouble() * 8;

      return _Particle(
        x: widget.screenCenter.dx + (_random.nextDouble() - 0.5) * 80,
        y: widget.screenCenter.dy + (_random.nextDouble() - 0.5) * 40,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 100,
        size: size,
        color: [
          Colors.grey[400]!,
          Colors.grey[500]!,
          Colors.grey[600]!,
          Colors.blueGrey[300]!,
        ][_random.nextInt(4)],
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 10,
      );
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  double x, y;
  double vx, vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final gravity = 800.0;
    final time = progress * 0.6; // 动画时间（秒）

    for (final p in particles) {
      // 计算位置（带重力）
      final x = p.x + p.vx * time;
      final y = p.y + p.vy * time + 0.5 * gravity * time * time;

      // 透明度随时间减少
      final opacity = (1 - progress).clamp(0.0, 1.0);

      // 大小随时间缩小
      final currentSize = p.size * (1 - progress * 0.5);

      // 旋转
      final rotation = p.rotation + p.rotationSpeed * progress;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      // 绘制不规则碎片
      final path = Path();
      path.moveTo(-currentSize / 2, -currentSize / 3);
      path.lineTo(currentSize / 2, -currentSize / 2);
      path.lineTo(currentSize / 3, currentSize / 2);
      path.lineTo(-currentSize / 3, currentSize / 3);
      path.close();

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
