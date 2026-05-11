import 'package:flutter/material.dart';

import '../../core/theme/premium_theme_tokens.dart';

class PremiumChip extends StatefulWidget {
  final String label;
  final String? premiumType;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const PremiumChip({
    super.key,
    required this.label,
    required this.premiumType,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.fontSize = 10,
  });

  @override
  State<PremiumChip> createState() => _PremiumChipState();
}

class _PremiumChipState extends State<PremiumChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: PremiumThemeTokens.isYearly(widget.premiumType)
            ? 2400
            : 1500,
      ),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PremiumChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.premiumType != widget.premiumType) {
      _controller.duration = Duration(
        milliseconds: PremiumThemeTokens.isYearly(widget.premiumType)
            ? 2400
            : 1500,
      );
      _controller
        ..reset()
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = PremiumThemeTokens.accent(widget.premiumType);

    if (!PremiumThemeTokens.isPremium(widget.premiumType)) {
      return Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: PremiumThemeTokens.badgeFill(widget.premiumType),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final scale = PremiumThemeTokens.isYearly(widget.premiumType)
            ? 1 + (t * 0.024)
            : 1 + (t * 0.024);
        final glowOpacity = PremiumThemeTokens.isYearly(widget.premiumType)
            ? 0.18 + (t * 0.08)
            : 0.16 + (t * 0.08);

        return Transform.scale(
          scale: scale,
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color: PremiumThemeTokens.badgeFill(widget.premiumType),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: PremiumThemeTokens.isYearly(widget.premiumType)
                    ? Colors.white.withOpacity(0.16)
                    : accent.withOpacity(0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(glowOpacity),
                  blurRadius: PremiumThemeTokens.isYearly(widget.premiumType)
                      ? 12
                      : 10,
                  spreadRadius: PremiumThemeTokens.isYearly(widget.premiumType)
                      ? 0.2
                      : 0,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Text(
        widget.label,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class PremiumContainer extends StatelessWidget {
  final String? premiumType;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry borderRadius;

  const PremiumContainer({
    super.key,
    required this.premiumType,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  });

  @override
  Widget build(BuildContext context) {
    if (!PremiumThemeTokens.hasThemedStyle(premiumType)) {
      return padding == null ? child : Padding(padding: padding!, child: child);
    }

    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: PremiumThemeTokens.inlineChipGradient(premiumType),
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );

    return padding == null
        ? content
        : Padding(padding: padding!, child: content);
  }
}

class PremiumCard extends StatefulWidget {
  final Widget child;
  final bool isDark;
  final String? premiumType;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final Color? accentColor;
  final List<Color>? colors;

  const PremiumCard({
    super.key,
    required this.child,
    required this.isDark,
    this.premiumType,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.accentColor,
    this.colors,
  });

  @override
  State<PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<PremiumCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: PremiumThemeTokens.isYearly(widget.premiumType)
            ? 3200
            : 1900,
      ),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PremiumCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.premiumType != widget.premiumType) {
      _controller.duration = Duration(
        milliseconds: PremiumThemeTokens.isYearly(widget.premiumType)
            ? 3200
            : 1900,
      );
      _controller
        ..reset()
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone =
        widget.accentColor ?? PremiumThemeTokens.accent(widget.premiumType);
    final backgroundColors =
        widget.colors ??
        (PremiumThemeTokens.hasThemedStyle(widget.premiumType)
            ? PremiumThemeTokens.cardGradient(
                widget.premiumType,
                widget.isDark ? const Color(0xFF151D2D) : Colors.white,
              )
            : (widget.isDark
                  ? const [Color(0xFF151D2D), Color(0xFF111827)]
                  : const [Colors.white, Color(0xFFF8FAFF)]));

    if (!PremiumThemeTokens.isPremium(widget.premiumType)) {
      return Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: backgroundColors,
          ),
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: tone.withOpacity(widget.isDark ? 0.22 : 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: tone.withOpacity(widget.isDark ? 0.14 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final shimmerAlignment = PremiumThemeTokens.isYearly(widget.premiumType)
            ? Alignment(-1.2 + (t * 2.4), -0.2)
            : Alignment(-1.2 + (t * 2.4), 0.2);
        final shadowOpacity = PremiumThemeTokens.isYearly(widget.premiumType)
            ? (widget.isDark ? 0.12 : 0.08) + (t * 0.04)
            : (widget.isDark ? 0.11 : 0.06) + (t * 0.04);
        final blur = PremiumThemeTokens.isYearly(widget.premiumType)
            ? 18 + (t * 6)
            : 16 + (t * 6);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: backgroundColors,
            ),
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: PremiumThemeTokens.isYearly(widget.premiumType)
                  ? tone.withOpacity(widget.isDark ? 0.24 : 0.16)
                  : tone.withOpacity(widget.isDark ? 0.22 : 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: tone.withOpacity(shadowOpacity),
                blurRadius: blur,
                offset: const Offset(0, 8),
              ),
              if (PremiumThemeTokens.isYearly(widget.premiumType))
                BoxShadow(
                  color: Colors.black.withOpacity(widget.isDark ? 0.24 : 0.10),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              children: [
                Padding(padding: widget.padding, child: child),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: shimmerAlignment,
                      child: FractionallySizedBox(
                        widthFactor:
                            PremiumThemeTokens.isYearly(widget.premiumType)
                            ? 0.42
                            : 0.32,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(
                                  PremiumThemeTokens.isYearly(
                                        widget.premiumType,
                                      )
                                      ? 0.14
                                      : 0.10,
                                ),
                                Colors.white.withOpacity(0.02),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
