import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/checkin_service.dart';
import '../../../shared/utils/snackbar_utils.dart';

// ===== 设计 tokens（与"我的"页保持一致的极简调）=====
const Color _kPrimary = Color(0xFF1A3A6B);
const Color _kPrimaryDeep = Color(0xFFE64545);
const Color _kBgLight = Color(0xFFF7F8FA);
const Color _kBgDark = Color(0xFF0D1117);
const Color _kSurfaceLight = Colors.white;
const Color _kSurfaceDark = Color(0xFF14161E);
const Color _kTextPrimary = Color(0xFF111827);
const Color _kTextSecondary = Color(0xFF6B7280);
const Color _kTextTertiary = Color(0xFF9CA3AF);
const Color _kSoftGray = Color(0xFFF3F5F8);

/// 签到 —— 全新颠覆式设计
///
/// 三段结构：
///   1. **Hero 打卡卡** —— 蓝色渐变，大号"连续 N 天"数字、右侧脉冲呼吸的立即签到 CTA、
///      顶部气氛小徽章、底部本周脉搏 7 段进度条
///   2. **双 stat pill 行** —— 累计签到 / 本月签到
///   3. **日历卡** —— 白底圆角卡，签到日格子采用主色柔和渐变+右下角小勾，
///      今天用主色描边环，普通日仅数字
class CheckinPage extends ConsumerStatefulWidget {
  const CheckinPage({super.key});

  @override
  ConsumerState<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends ConsumerState<CheckinPage>
    with SingleTickerProviderStateMixin {
  CheckinCalendar _data = const CheckinCalendar();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _submitting = false;
  bool _firstLoadDone = false;
  late final AnimationController _pulseCtrl;

  String get _monthStr =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await ref.read(checkinServiceProvider).getCalendar(month: _monthStr);
      if (mounted) setState(() => _data = data);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _firstLoadDone = true;
        });
      }
    }
  }

  Future<void> _checkin() async {
    if (_submitting || _data.checkedToday) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      await ref.read(checkinServiceProvider).doCheckin();
      if (mounted) {
        HapticFeedback.lightImpact();
        final l10n = AppLocalizations.of(context);
        AppSnackBar.success(context, l10n.checkinSuccess);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        AppSnackBar.error(context, '${l10n.checkinFailed}：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _kBgDark : _kBgLight;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: isDark ? Colors.white70 : _kTextPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.checkin,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : _kTextPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: !_firstLoadDone && _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(_kPrimary),
              ),
            )
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    _buildHero(isDark),
                    const SizedBox(height: 14),
                    _buildStatsRow(isDark),
                    const SizedBox(height: 14),
                    _buildCalendarCard(isDark),
                  ],
                ),
              ),
            ),
    );
  }

  // ===================================================================
  // Hero：渐变卡 + 大号 streak + 呼吸脉冲 CTA + 本周脉搏
  // ===================================================================
  Widget _buildHero(bool isDark) {
    final continuous = _data.continuousDays;
    final done = _data.checkedToday;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kPrimaryDeep, _kPrimary],
          ),
          boxShadow: [
            BoxShadow(
              color: _kPrimary.withOpacity(0.32),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              const Positioned(
                right: -40,
                top: -40,
                child: _DecorCircle(size: 180, opacity: 0.10),
              ),
              const Positioned(
                right: 60,
                bottom: -70,
                child: _DecorCircle(size: 150, opacity: 0.07),
              ),
              const Positioned(
                left: -30,
                bottom: -30,
                child: _DecorCircle(size: 110, opacity: 0.05),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _loading
                              ? l10n.checkinSyncing
                              : (done
                                  ? l10n.checkinTodayDone
                                  : l10n.checkinTodayPending),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        _StreakBadge(continuous: continuous),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$continuous',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 60,
                                        fontWeight: FontWeight.w800,
                                        height: 1.0,
                                        letterSpacing: -1.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' ${l10n.checkinDayUnit}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.checkinContinuous,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _HeroCta(
                          done: done,
                          submitting: _submitting,
                          onTap: _checkin,
                          pulseCtrl: _pulseCtrl,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _WeeklyPulse(
                      checkedDays: _data.checkedDays.toSet(),
                      animation: _pulseCtrl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================================================================
  // Stats：双 pill（累计/本月）
  // ===================================================================
  Widget _buildStatsRow(bool isDark) {
    final surface = isDark ? _kSurfaceDark : _kSurfaceLight;
    final title = isDark ? Colors.white : _kTextPrimary;
    final sub = isDark ? Colors.white54 : _kTextSecondary;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _StatPill(
              icon: Icons.emoji_events_rounded,
              iconTint: const Color(0xFFF59E0B),
              label: l10n.checkinTotal,
              value: '${_data.totalDays}',
              unit: l10n.checkinDayUnit,
              surface: surface,
              titleColor: title,
              subColor: sub,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatPill(
              icon: Icons.calendar_month_rounded,
              iconTint: _kPrimary,
              label: l10n.checkinMonth,
              value: '${_data.checkedDays.length}',
              unit: l10n.checkinDayUnit,
              surface: surface,
              titleColor: title,
              subColor: sub,
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // 日历卡：月份切换 + 日历格子
  // ===================================================================
  Widget _buildCalendarCard(bool isDark) {
    final surface = isDark ? _kSurfaceDark : _kSurfaceLight;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.32 : 0.03),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 14),
        child: Column(
          children: [
            _buildMonthPicker(isDark),
            const SizedBox(height: 10),
            _buildCalendarGrid(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthPicker(bool isDark) {
    final txt = isDark ? Colors.white : _kTextPrimary;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _CircleIconBtn(
            icon: Icons.chevron_left_rounded,
            onTap: () => _changeMonth(-1),
            isDark: isDark,
          ),
          Expanded(
            child: Center(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: txt, fontWeight: FontWeight.w600),
                  children: [
                    TextSpan(
                      text: '${_month.year}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kTextTertiary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const WidgetSpan(child: SizedBox(width: 8)),
                    TextSpan(
                      text: '${_month.month} ${l10n.checkinMonthUnit}',
                      style: TextStyle(
                        fontSize: 17,
                        color: txt,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _CircleIconBtn(
            icon: Icons.chevron_right_rounded,
            onTap: () => _changeMonth(1),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(bool isDark) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = first.weekday % 7; // Sun=0
    final checked = _data.checkedDays.toSet();
    final l10n = AppLocalizations.of(context);
    final weekLabels = [
      l10n.checkinWeekdaySun,
      l10n.checkinWeekdayMon,
      l10n.checkinWeekdayTue,
      l10n.checkinWeekdayWed,
      l10n.checkinWeekdayThu,
      l10n.checkinWeekdayFri,
      l10n.checkinWeekdaySat,
    ];
    final now = DateTime.now();

    Widget label(String s, {bool weekend = false}) => Center(
          child: Text(
            s,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: isDark
                  ? Colors.white54
                  : (weekend ? const Color(0xFFEF6060) : _kTextTertiary),
            ),
          ),
        );

    final cells = <Widget>[];
    for (var i = 0; i < 7; i++) {
      cells.add(label(weekLabels[i], weekend: i == 0 || i == 6));
    }
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final dateStr =
          '${_month.year}-${_month.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final isChecked = checked.contains(dateStr);
      final isToday =
          _month.year == now.year && _month.month == now.month && d == now.day;
      cells.add(_DayCell(
        day: d,
        isChecked: isChecked,
        isToday: isToday,
        isDark: isDark,
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      childAspectRatio: 1,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      children: cells,
    );
  }
}

// =====================================================================
// Hero 装饰性大圆（气泡）
// =====================================================================
class _DecorCircle extends StatelessWidget {
  final double size;
  final double opacity;
  const _DecorCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

// =====================================================================
// 连续天数徽章：右上角小 chip
// =====================================================================
class _StreakBadge extends StatelessWidget {
  final int continuous;
  const _StreakBadge({required this.continuous});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    late final IconData icon;
    late final String label;
    if (continuous >= 30) {
      icon = Icons.local_fire_department_rounded;
      label = l10n.checkinStreakFire;
    } else if (continuous >= 7) {
      icon = Icons.auto_awesome_rounded;
      label = l10n.checkinStreakKeep;
    } else if (continuous >= 1) {
      icon = Icons.spa_rounded;
      label = l10n.checkinStreakStart;
    } else {
      icon = Icons.bedtime_rounded;
      label = l10n.checkinStreakPending;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.28), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Hero 内嵌 CTA（白色底 + 主色文字 + 光晕呼吸）
// =====================================================================
class _HeroCta extends StatelessWidget {
  final bool done;
  final bool submitting;
  final VoidCallback onTap;
  final AnimationController pulseCtrl;
  const _HeroCta({
    required this.done,
    required this.submitting,
    required this.onTap,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (context, _) {
        final t = pulseCtrl.value;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: done ? Colors.white.withOpacity(0.20) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: done
                ? Border.all(color: Colors.white.withOpacity(0.5), width: 1)
                : null,
            boxShadow: (done || submitting)
                ? null
                : [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.30 + 0.30 * t),
                      blurRadius: 18 + 10 * t,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: (done || submitting) ? null : onTap,
              child: Center(
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(_kPrimary),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            done
                                ? Icons.check_circle_rounded
                                : Icons.bolt_rounded,
                            size: 18,
                            color: done ? Colors.white : _kPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            done
                                ? l10n.checkinCheckedToday
                                : l10n.checkinButton,
                            style: TextStyle(
                              color: done ? Colors.white : _kPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
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

// =====================================================================
// 本周脉搏：7 个进度条 + 今日呼吸光晕
// =====================================================================
class _WeeklyPulse extends StatelessWidget {
  final Set<String> checkedDays;
  final Animation<double> animation;
  const _WeeklyPulse({
    required this.checkedDays,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final labels = [
      l10n.checkinWeekdayMon,
      l10n.checkinWeekdayTue,
      l10n.checkinWeekdayWed,
      l10n.checkinWeekdayThu,
      l10n.checkinWeekdayFri,
      l10n.checkinWeekdaySat,
      l10n.checkinWeekdaySun,
    ];
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          children: List.generate(7, (i) {
            final date = monday.add(Duration(days: i));
            final dateStr =
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final isToday = date.year == now.year &&
                date.month == now.month &&
                date.day == now.day;
            final isDone = checkedDays.contains(dateStr);
            final glow = isToday && !isDone;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 6 ? 5 : 0),
                child: Column(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: isDone
                            ? Colors.white
                            : Colors.white.withOpacity(0.25),
                        boxShadow: glow
                            ? [
                                BoxShadow(
                                  color: Colors.white.withOpacity(
                                      0.35 + 0.35 * animation.value),
                                  blurRadius: 6 + 4 * animation.value,
                                  spreadRadius: 0.5,
                                ),
                              ]
                            : null,
                        border: isToday && !isDone
                            ? Border.all(color: Colors.white, width: 1.2)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      labels[i],
                      style: TextStyle(
                        color: isToday
                            ? Colors.white
                            : Colors.white.withOpacity(0.6),
                        fontSize: 10.5,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// =====================================================================
// Stat pill：图标块 + 标签 + 大号数字
// =====================================================================
class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color iconTint;
  final String label;
  final String value;
  final String unit;
  final Color surface;
  final Color titleColor;
  final Color subColor;

  const _StatPill({
    required this.icon,
    required this.iconTint,
    required this.label,
    required this.value,
    required this.unit,
    required this.surface,
    required this.titleColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconTint.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconTint, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: subColor,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(
                          fontSize: 12,
                          color: subColor,
                          fontWeight: FontWeight.w500,
                        ),
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
}

// =====================================================================
// 月份切换圆按钮
// =====================================================================
class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  const _CircleIconBtn({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? Colors.white.withOpacity(0.06) : _kSoftGray,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isDark ? Colors.white70 : _kTextPrimary,
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 日历单元格：普通日 / 签到日渐变 / 今天描边环
// =====================================================================
class _DayCell extends StatelessWidget {
  final int day;
  final bool isChecked;
  final bool isToday;
  final bool isDark;
  const _DayCell({
    required this.day,
    required this.isChecked,
    required this.isToday,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // 签到日：主色渐变方块 + 白字 + 右下小勾
    if (isChecked) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPrimaryDeep, _kPrimary],
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withOpacity(0.30),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$day',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Positioned(
                right: 3,
                bottom: 3,
                child: Icon(
                  Icons.check_rounded,
                  size: 10,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 今天但还没签：主色描边环
    if (isToday) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            color: _kPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _kPrimary, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: const TextStyle(
              color: _kPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }
    // 普通日
    return Center(
      child: Text(
        '$day',
        style: TextStyle(
          color: isDark ? Colors.white70 : const Color(0xFF374151),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
