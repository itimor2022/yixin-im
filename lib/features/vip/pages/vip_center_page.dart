// 文件用途：实现 VipCenterPage 页面及其交互流程，属于会员权益。
// 核心逻辑：维护 VipCenterPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../wallet/providers/wallet_provider.dart';
import '../../wallet/services/wallet_service.dart';
import '../providers/vip_provider.dart';
import '../services/vip_service.dart';

const _vipGold = Color(0xFFD5B36A);
const _vipGoldDark = Color(0xFFB98B35);
const _vipInk = Color(0xFF17191E);
const _vipInkSoft = Color(0xFF292D35);
const _vipWarmBackground = Color(0xFFF6F4EF);

String _vipText(
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

// 关键声明：VIP center page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class VipCenterPage extends ConsumerStatefulWidget {
  const VipCenterPage({super.key});

  @override
  ConsumerState<VipCenterPage> createState() => _VipCenterPageState();
}

class _VipCenterPageState extends ConsumerState<VipCenterPage> {
  int? _selectedPlanId;
  int? _previewPlanId;
  int? _purchasingPlanId;
  bool _showAllBenefits = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadWallet(silent: true);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(vipStatusProvider);
    ref.invalidate(vipPlansProvider);
    await ref.read(walletProvider.notifier).loadWallet(silent: true);
    await Future.wait([
      ref.read(vipStatusProvider.future),
      ref.read(vipPlansProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusAsync = ref.watch(vipStatusProvider);
    final plansAsync = ref.watch(vipPlansProvider);
    final walletState = ref.watch(walletProvider);
    final currency = ref.watch(walletCurrencyProvider);
    final status = statusAsync.valueOrNull;
    final plans = plansAsync.valueOrNull ?? const <VipPlan>[];
    final selectedPlan = _effectiveSelectedPlan(plans, status);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : _vipWarmBackground,
      appBar: _buildAppBar(context, isDark),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: _vipGoldDark,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWideLayout = constraints.maxWidth >= 720;
            final horizontalPadding = isWideLayout ? 24.0 : 0.0;
            final sectionPadding = isWideLayout ? 0.0 : 20.0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                isWideLayout ? 12 : 0,
                horizontalPadding,
                28,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusAndBenefits(
                          context,
                          statusAsync,
                          plans,
                          currency,
                          isDark,
                        ),
                        if (plansAsync.hasError) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: sectionPadding,
                            ),
                            child: _InlineStateCard(
                              icon: Icons.cloud_off_rounded,
                              title: _vipText(
                                context,
                                zhCN: '套餐加载失败',
                                zhTW: '套餐載入失敗',
                                en: 'Failed to load plans',
                              ),
                              actionText: _vipText(
                                context,
                                zhCN: '重新加载',
                                zhTW: '重新載入',
                                en: 'Try again',
                              ),
                              onAction: () => ref.invalidate(vipPlansProvider),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: sectionPadding,
                          ),
                          child: _WalletCard(
                            wallet: walletState.wallet,
                            currency: currency,
                            isLoading: walletState.isLoading,
                            isDark: isDark,
                            onRecharge: () => context.push('/wallet/recharge'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: selectedPlan == null
          ? null
          : _PurchaseBar(
              plan: selectedPlan,
              currency: currency,
              status: status,
              wallet: walletState.wallet,
              walletLoading: walletState.isLoading,
              isPurchasing: _purchasingPlanId != null,
              isDark: isDark,
              onPressed: () => _purchasePlan(selectedPlan, status),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDark) {
    const background = Color(0xFF14161B);
    return AppBar(
      backgroundColor: background,
      toolbarHeight: 52,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        _vipText(
          context,
          zhCN: '会员中心',
          zhTW: '會員中心',
          en: 'Membership',
        ),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: Colors.white,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        TextButton(
          onPressed: () => context.push('/vip/orders'),
          child: Text(
            _vipText(
              context,
              zhCN: '订单',
              zhTW: '訂單',
              en: 'Orders',
            ),
            style: TextStyle(
              color: const Color(0xFFE4C77E),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildStatusAndBenefits(
    BuildContext context,
    AsyncValue<VipStatus> statusAsync,
    List<VipPlan> plans,
    String currency,
    bool isDark,
  ) {
    return statusAsync.when(
      data: (status) => LayoutBuilder(
        builder: (context, constraints) {
          VipPlan? previewPlan;
          for (final plan in plans) {
            if (plan.id == _previewPlanId) {
              previewPlan = plan;
              break;
            }
          }
          final hero = _MembershipCarousel(
            status: status,
            plans: plans,
            currency: currency,
            selectedPlanId: _selectedPlanId,
            onPreviewChanged: (plan) {
              final selectable =
                  plan == null || !_isLowerThanCurrent(plan, status);
              setState(() {
                _previewPlanId = plan?.id;
                if (plan != null && selectable) {
                  _selectedPlanId = plan.id;
                }
              });
            },
          );
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations == true;
          final benefits = AnimatedSwitcher(
            duration: Duration(milliseconds: reduceMotion ? 0 : 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(previewPlan?.id ?? -1),
              child: _BenefitsCard(
                entitlements: previewPlan?.benefits ?? status.entitlements,
                title: previewPlan == null
                    ? _vipText(
                        context,
                        zhCN: '我的权益',
                        zhTW: '我的權益',
                        en: 'My benefits',
                      )
                    : _vipText(
                        context,
                        zhCN: '${previewPlan.levelName}权益',
                        zhTW: '${previewPlan.levelName}權益',
                        en: '${previewPlan.levelName} benefits',
                      ),
                expanded: _showAllBenefits,
                isDark: isDark,
                onToggle: () {
                  setState(() => _showAllBenefits = !_showAllBenefits);
                },
              ),
            ),
          );
          if (constraints.maxWidth >= 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: hero),
                const SizedBox(width: 16),
                Expanded(child: benefits),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: benefits,
              ),
            ],
          );
        },
      ),
      loading: () => const Column(
        children: [
          _SkeletonCard(height: 196),
          SizedBox(height: 16),
          _SkeletonCard(height: 192),
        ],
      ),
      error: (_, __) => _InlineStateCard(
        icon: Icons.workspace_premium_outlined,
        title: _vipText(
          context,
          zhCN: '会员状态加载失败',
          zhTW: '會員狀態載入失敗',
          en: 'Failed to load membership',
        ),
        actionText: _vipText(
          context,
          zhCN: '重新加载',
          zhTW: '重新載入',
          en: 'Try again',
        ),
        onAction: () => ref.invalidate(vipStatusProvider),
      ),
    );
  }

  VipPlan? _effectiveSelectedPlan(
    List<VipPlan> plans,
    VipStatus? status,
  ) {
    final available =
        plans.where((plan) => !_isLowerThanCurrent(plan, status)).toList();
    if (available.isEmpty) return null;
    for (final plan in available) {
      if (plan.id == _selectedPlanId) return plan;
    }
    return _recommendedPlan(available, status) ?? available.first;
  }

  VipPlan? _recommendedPlan(List<VipPlan> plans, VipStatus? status) {
    final available =
        plans.where((plan) => !_isLowerThanCurrent(plan, status)).toList();
    if (available.isEmpty) return null;
    available.sort((a, b) {
      final aSaving = (a.originalPrice - a.price).clamp(0, double.infinity);
      final bSaving = (b.originalPrice - b.price).clamp(0, double.infinity);
      final savingCompare = bSaving.compareTo(aSaving);
      if (savingCompare != 0) return savingCompare;
      return b.durationDays.compareTo(a.durationDays);
    });
    return available.first;
  }

  bool _isLowerThanCurrent(VipPlan plan, VipStatus? status) {
    return status?.isActive == true && (status?.level ?? 0) > plan.level;
  }

  Future<void> _purchasePlan(VipPlan plan, VipStatus? status) async {
    if (_purchasingPlanId != null) return;

    var wallet = ref.read(walletProvider).wallet;
    if (wallet == null) {
      await ref.read(walletProvider.notifier).loadWallet();
      wallet = ref.read(walletProvider).wallet;
    }
    if (!mounted) return;
    if (wallet?.isLocked == true) {
      _showMessage(
        _vipText(
          context,
          zhCN: '钱包已锁定，暂时无法购买会员',
          zhTW: '錢包已鎖定，暫時無法購買會員',
          en: 'Your wallet is locked',
        ),
        isError: true,
      );
      return;
    }

    HapticFeedback.selectionClick();
    final decision = await showModalBottomSheet<_PurchaseDecision>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PurchaseConfirmSheet(
        plan: plan,
        status: status,
        wallet: wallet,
        currency: ref.read(walletCurrencyProvider),
      ),
    );
    if (!mounted || decision == null) return;
    if (decision == _PurchaseDecision.recharge) {
      context.push('/wallet/recharge');
      return;
    }

    setState(() => _purchasingPlanId = plan.id);
    try {
      await purchaseVipPlan(ref, plan.id);
      await ref.read(walletProvider.notifier).loadWallet(silent: true);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _showMessage(
        _vipText(
          context,
          zhCN: '会员已开通',
          zhTW: '會員已開通',
          en: 'Membership activated',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = _cleanError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          action: _isInsufficientBalanceError(message)
              ? SnackBarAction(
                  label: _vipText(
                    context,
                    zhCN: '去充值',
                    zhTW: '去充值',
                    en: 'Top up',
                  ),
                  textColor: Colors.white,
                  onPressed: () => context.push('/wallet/recharge'),
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _purchasingPlanId = null);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  bool _isInsufficientBalanceError(String message) {
    return message.contains('余额不足') ||
        message.contains('餘額不足') ||
        message.toLowerCase().contains('insufficient');
  }
}

class _MembershipCarousel extends StatefulWidget {
  const _MembershipCarousel({
    required this.status,
    required this.plans,
    required this.currency,
    required this.selectedPlanId,
    required this.onPreviewChanged,
  });

  final VipStatus status;
  final List<VipPlan> plans;
  final String currency;
  final int? selectedPlanId;
  final ValueChanged<VipPlan?> onPreviewChanged;

  @override
  State<_MembershipCarousel> createState() => _MembershipCarouselState();
}

class _MembershipCarouselState extends State<_MembershipCarousel>
    with SingleTickerProviderStateMixin {
  late final PageController _controller;
  late final AnimationController _effectsController;
  int _pageIndex = 0;
  bool _motionInitialized = false;

  int get _pageCount => widget.plans.length + 1;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _effectsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) return;
    _motionInitialized = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      _effectsController.value = 1;
    } else {
      _effectsController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _MembershipCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pageIndex >= _pageCount) {
      _pageIndex = (_pageCount - 1).clamp(0, _pageCount);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(_pageIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _effectsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = MediaQuery.sizeOf(context).width >= 720 ? 208.0 : 196.0;
    return Column(
      children: [
        SizedBox(
          height: heroHeight,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            clipBehavior: Clip.none,
            itemCount: _pageCount,
            onPageChanged: (index) {
              HapticFeedback.selectionClick();
              setState(() => _pageIndex = index);
              if (MediaQuery.maybeOf(context)?.disableAnimations != true) {
                _effectsController.forward(from: 0);
              }
              widget.onPreviewChanged(
                index == 0 ? null : widget.plans[index - 1],
              );
            },
            itemBuilder: (context, index) {
              final plan = index == 0 ? null : widget.plans[index - 1];
              final disabled = plan != null &&
                  widget.status.isActive &&
                  widget.status.level > plan.level;
              final card = MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: RepaintBoundary(
                  child: _MembershipHero(
                    status: widget.status,
                    plan: plan,
                    currency: widget.currency,
                    selected: plan?.id == widget.selectedPlanId,
                    disabled: disabled,
                    isFocused: index == _pageIndex,
                    effectAnimation: _effectsController,
                  ),
                ),
              );
              return AnimatedBuilder(
                animation: _controller,
                child: card,
                builder: (context, child) {
                  final currentPage =
                      _controller.hasClients && _controller.page != null
                          ? _controller.page!
                          : _pageIndex.toDouble();
                  final delta = (currentPage - index).clamp(-1.0, 1.0);
                  final distance = delta.abs();
                  return Transform.translate(
                    offset: Offset(0, 5 * distance),
                    child: Transform.rotate(
                      angle: delta * 0.008,
                      child: Transform.scale(
                        scale: 1 - 0.025 * distance,
                        alignment: delta > 0
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: child,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _pageCount > 1
                      ? _vipText(
                          context,
                          zhCN: '左右滑动查看不同会员',
                          zhTW: '左右滑動查看不同會員',
                          en: 'Swipe to explore memberships',
                        )
                      : _vipText(
                          context,
                          zhCN: '当前会员状态',
                          zhTW: '目前會員狀態',
                          en: 'Current membership',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (_pageCount <= 6)
                for (var index = 0; index < _pageCount; index++) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == _pageIndex ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == _pageIndex
                          ? _vipGoldDark
                          : _vipGold.withOpacity(0.32),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  if (index != _pageCount - 1) const SizedBox(width: 4),
                ]
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _vipGold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_pageIndex + 1}/$_pageCount',
                    style: const TextStyle(
                      color: _vipGoldDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MembershipHero extends StatelessWidget {
  const _MembershipHero({
    required this.status,
    required this.plan,
    required this.currency,
    required this.selected,
    required this.disabled,
    required this.isFocused,
    required this.effectAnimation,
  });

  final VipStatus status;
  final VipPlan? plan;
  final String currency;
  final bool selected;
  final bool disabled;
  final bool isFocused;
  final Animation<double> effectAnimation;

  @override
  Widget build(BuildContext context) {
    final isStatusCard = plan == null;
    final active = status.isActive;
    final level = plan?.level ?? status.level;
    final title = isStatusCard
        ? active
            ? status.levelName
            : _vipText(
                context,
                zhCN: '普通用户',
                zhTW: '普通使用者',
                en: 'Free member',
              )
        : plan!.levelName.trim().isNotEmpty
            ? plan!.levelName
            : plan!.name;
    final subtitle = isStatusCard
        ? active
            ? status.expiredAt == null
                ? _vipText(
                    context,
                    zhCN: '会员权益已生效',
                    zhTW: '會員權益已生效',
                    en: 'Membership benefits are active',
                  )
                : _vipText(
                    context,
                    zhCN: '有效期至 ${_formatDate(status.expiredAt!)}',
                    zhTW: '有效期至 ${_formatDate(status.expiredAt!)}',
                    en: 'Valid until ${_formatDate(status.expiredAt!)}',
                  )
            : _vipText(
                context,
                zhCN: '开通会员，解锁更多权益',
                zhTW: '開通會員，解鎖更多權益',
                en: 'Unlock more benefits with membership',
              )
        : plan!.description.trim().isNotEmpty
            ? plan!.description.trim()
            : _vipText(
                context,
                zhCN: '${plan!.durationDays}天会员权益',
                zhTW: '${plan!.durationDays}天會員權益',
                en: '${plan!.durationDays} days of membership',
              );
    final accent = level >= 2
        ? const Color(0xFFD8C0FF)
        : level == 1
            ? const Color(0xFFE4C77E)
            : _vipGold;
    final gradient = level >= 2
        ? const [Color(0xFF31264A), Color(0xFF15161D)]
        : level == 1
            ? const [Color(0xFF382F20), Color(0xFF17191E)]
            : const [_vipInk, _vipInkSoft];
    final badgeText = disabled
        ? _vipText(
            context,
            zhCN: '仅查看',
            zhTW: '僅查看',
            en: 'View only',
          )
        : selected
            ? _vipText(
                context,
                zhCN: '已选择',
                zhTW: '已選擇',
                en: 'Selected',
              )
            : isStatusCard
                ? _vipText(
                    context,
                    zhCN: '当前',
                    zhTW: '目前',
                    en: 'Current',
                  )
                : '';

    return Semantics(
      label: '$title，$subtitle',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.1),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _VipCardEffectsPainter(
                      animation: effectAnimation,
                      accent: accent,
                      level: level,
                      active: isFocused,
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: -26,
                top: -42,
                child: _HeroDecoration(size: 132),
              ),
              Positioned(
                right: 24,
                bottom: 18,
                child: Icon(
                  level >= 2
                      ? Icons.auto_awesome_rounded
                      : Icons.diamond_outlined,
                  size: 64,
                  color: accent.withOpacity(0.12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: effectAnimation,
                          builder: (context, child) {
                            final pulse = isFocused
                                ? math.sin(effectAnimation.value * math.pi)
                                : 0.0;
                            return Transform.scale(
                              scale: 1 + pulse * 0.055,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.98),
                                  accent.withOpacity(0.92),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.28),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              isStatusCard && !active
                                  ? Icons.person_rounded
                                  : level >= 2
                                      ? Icons.auto_awesome_rounded
                                      : Icons.workspace_premium_rounded,
                              size: 30,
                              color: _vipInk,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (badgeText.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    _HeroStatePill(
                                      text: badgeText,
                                      accent: accent,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isStatusCard
                                  ? active
                                      ? _vipText(
                                          context,
                                          zhCN: '当前会员身份',
                                          zhTW: '目前會員身份',
                                          en: 'Current membership',
                                        )
                                      : _vipText(
                                          context,
                                          zhCN: '普通账户',
                                          zhTW: '普通帳戶',
                                          en: 'Free account',
                                        )
                                  : plan!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isStatusCard
                                ? active
                                    ? _vipText(
                                        context,
                                        zhCN: '权益已生效',
                                        zhTW: '權益已生效',
                                        en: 'Active',
                                      )
                                    : _vipText(
                                        context,
                                        zhCN: '可升级',
                                        zhTW: '可升級',
                                        en: 'Upgrade',
                                      )
                                : '$currency${plan!.price.toStringAsFixed(2)}',
                            maxLines: 1,
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
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
        ),
      ),
    );
  }
}

class _HeroStatePill extends StatelessWidget {
  const _HeroStatePill({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VipCardEffectsPainter extends CustomPainter {
  _VipCardEffectsPainter({
    required this.animation,
    required this.accent,
    required this.level,
    required this.active,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color accent;
  final int level;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final progress =
        active ? Curves.easeInOutCubic.transform(animation.value) : 1.0;
    final bounds = Offset.zero & size;
    final radius = RRect.fromRectAndCorners(
      bounds.deflate(0.8),
      bottomLeft: const Radius.circular(32),
      bottomRight: const Radius.circular(32),
    );

    canvas.save();
    canvas.clipRRect(radius);

    final glowCenter = Offset(
      size.width * (0.76 + 0.05 * math.sin(progress * math.pi)),
      size.height * (0.2 + 0.035 * math.cos(progress * math.pi)),
    );
    final glowRect = Rect.fromCircle(
      center: glowCenter,
      radius: size.shortestSide * 0.58,
    );
    canvas.drawCircle(
      glowCenter,
      size.shortestSide * 0.58,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withOpacity(level >= 2 ? 0.18 : 0.12),
            accent.withOpacity(0),
          ],
        ).createShader(glowRect),
    );

    if (active && animation.value < 0.96) {
      final shimmerX = size.width * (-0.35 + progress * 1.7);
      final shimmerWidth = size.width * 0.18;
      final shimmerPath = Path()
        ..moveTo(shimmerX - shimmerWidth, 0)
        ..lineTo(shimmerX, 0)
        ..lineTo(shimmerX + shimmerWidth * 0.55, size.height)
        ..lineTo(shimmerX - shimmerWidth * 0.45, size.height)
        ..close();
      canvas.drawPath(
        shimmerPath,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withOpacity(0),
              Colors.white.withOpacity(level >= 2 ? 0.17 : 0.12),
              Colors.white.withOpacity(0),
            ],
          ).createShader(bounds),
      );
    }

    final sparklePositions = <Offset>[
      Offset(size.width * 0.71, size.height * 0.24),
      Offset(size.width * 0.86, size.height * 0.43),
      Offset(size.width * 0.64, size.height * 0.72),
      Offset(size.width * 0.92, size.height * 0.76),
      Offset(size.width * 0.77, size.height * 0.58),
      Offset(size.width * 0.95, size.height * 0.18),
    ];
    for (var index = 0; index < sparklePositions.length; index++) {
      if (level == 0 && index > 1) break;
      if (level == 1 && index > 3) break;
      final phase = math.sin((progress + index * 0.23) * math.pi * 2).abs();
      final sparkleRadius = 1.2 + phase * (level >= 2 ? 1.8 : 1.1);
      final paint = Paint()
        ..color = accent.withOpacity(0.2 + phase * 0.42)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      final point = sparklePositions[index];
      canvas.drawCircle(point, sparkleRadius, paint);
      if (level >= 2 && sparkleRadius > 2.1) {
        canvas.drawLine(
          point.translate(-sparkleRadius * 1.8, 0),
          point.translate(sparkleRadius * 1.8, 0),
          paint,
        );
        canvas.drawLine(
          point.translate(0, -sparkleRadius * 1.8),
          point.translate(0, sparkleRadius * 1.8),
          paint,
        );
      }
    }

    canvas.restore();

    if (level > 0) {
      canvas.drawRRect(
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.35 : 0.9
          ..shader = SweepGradient(
            transform: GradientRotation(progress * math.pi * 0.8),
            colors: [
              accent.withOpacity(0.04),
              accent.withOpacity(active ? 0.46 : 0.2),
              accent.withOpacity(0.04),
              accent.withOpacity(active ? 0.28 : 0.14),
              accent.withOpacity(0.04),
            ],
          ).createShader(bounds),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VipCardEffectsPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.level != level ||
        oldDelegate.active != active ||
        oldDelegate.animation != animation;
  }
}

class _HeroDecoration extends StatelessWidget {
  const _HeroDecoration({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.78,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.035)),
          borderRadius: BorderRadius.circular(42),
        ),
        child: Center(
          child: Container(
            width: size * 0.64,
            height: size * 0.64,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.035)),
              borderRadius: BorderRadius.circular(34),
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitsCard extends StatelessWidget {
  const _BenefitsCard({
    required this.entitlements,
    required this.title,
    required this.expanded,
    required this.isDark,
    required this.onToggle,
  });

  final VipEntitlements entitlements;
  final String title;
  final bool expanded;
  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkCard : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF322A1D).withOpacity(0.055),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE8CD88), _vipGoldDark],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimaryFor(context),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640 ? 4 : 2;
              const spacing = 10.0;
              final tileWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              final tiles = <Widget>[
                _BenefitTile(
                  icon: Icons.forum_rounded,
                  label: _vipText(
                    context,
                    zhCN: '创建群聊',
                    zhTW: '建立群聊',
                    en: 'Groups',
                  ),
                  value: '${entitlements.maxOwnedGroups}',
                  unit: _vipText(
                    context,
                    zhCN: '个',
                    zhTW: '個',
                    en: '',
                  ),
                  isDark: isDark,
                ),
                _BenefitTile(
                  icon: Icons.live_tv_rounded,
                  label: _vipText(
                    context,
                    zhCN: '频道',
                    zhTW: '頻道',
                    en: 'Channels',
                  ),
                  value: '${entitlements.maxOwnedChannels}',
                  unit: _vipText(
                    context,
                    zhCN: '个',
                    zhTW: '個',
                    en: '',
                  ),
                  isDark: isDark,
                ),
                _BenefitTile(
                  icon: Icons.groups_rounded,
                  label: _vipText(
                    context,
                    zhCN: '群成员',
                    zhTW: '群成員',
                    en: 'Members',
                  ),
                  value: '${entitlements.maxGroupMembers}',
                  unit: _vipText(
                    context,
                    zhCN: '人',
                    zhTW: '人',
                    en: '',
                  ),
                  isDark: isDark,
                ),
                _BenefitTile(
                  icon: Icons.folder_rounded,
                  label: _vipText(
                    context,
                    zhCN: '文件传输',
                    zhTW: '檔案傳輸',
                    en: 'Files',
                  ),
                  value: '${entitlements.uploadFileLimitMB}',
                  unit: 'MB',
                  isDark: isDark,
                ),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final tile in tiles)
                    SizedBox(width: tileWidth, child: tile),
                ],
              );
            },
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BenefitChip(
                    icon: Icons.push_pin_rounded,
                    text: _vipText(
                      context,
                      zhCN: '置顶 ${entitlements.maxPinnedChats}',
                      zhTW: '置頂 ${entitlements.maxPinnedChats}',
                      en: '${entitlements.maxPinnedChats} pinned chats',
                    ),
                    isDark: isDark,
                  ),
                  _BenefitChip(
                    icon: Icons.image_rounded,
                    text: _vipText(
                      context,
                      zhCN: '图片 ${entitlements.uploadImageLimitMB}MB',
                      zhTW: '圖片 ${entitlements.uploadImageLimitMB}MB',
                      en: 'Images ${entitlements.uploadImageLimitMB}MB',
                    ),
                    isDark: isDark,
                  ),
                  _BenefitChip(
                    icon: Icons.videocam_rounded,
                    text: _vipText(
                      context,
                      zhCN: '视频 ${entitlements.uploadVideoLimitMB}MB',
                      zhTW: '影片 ${entitlements.uploadVideoLimitMB}MB',
                      en: 'Videos ${entitlements.uploadVideoLimitMB}MB',
                    ),
                    isDark: isDark,
                  ),
                  _BenefitChip(
                    icon: Icons.mic_rounded,
                    text: _vipText(
                      context,
                      zhCN: '语音 ${entitlements.uploadVoiceLimitMB}MB',
                      zhTW: '語音 ${entitlements.uploadVoiceLimitMB}MB',
                      en: 'Voice ${entitlements.uploadVoiceLimitMB}MB',
                    ),
                    isDark: isDark,
                  ),
                  if (entitlements.canSetPublicUsername)
                    _BenefitChip(
                      icon: Icons.alternate_email_rounded,
                      text: _vipText(
                        context,
                        zhCN: '公开群号',
                        zhTW: '公開群號',
                        en: 'Public username',
                      ),
                      isDark: isDark,
                    ),
                  if (entitlements.canEnableMemberProtection)
                    _BenefitChip(
                      icon: Icons.shield_rounded,
                      text: _vipText(
                        context,
                        zhCN: '成员保护',
                        zhTW: '成員保護',
                        en: 'Member protection',
                      ),
                      isDark: isDark,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: onToggle,
              iconAlignment: IconAlignment.end,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(
                expanded
                    ? _vipText(
                        context,
                        zhCN: '收起权益',
                        zhTW: '收起權益',
                        en: 'Show less',
                      )
                    : _vipText(
                        context,
                        zhCN: '查看全部权益',
                        zhTW: '查看全部權益',
                        en: 'View all benefits',
                      ),
              ),
              style: TextButton.styleFrom(
                foregroundColor:
                    isDark ? const Color(0xFFE4C77E) : _vipGoldDark,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.darkControlBackground : const Color(0xFFFAF8F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : const Color(0xFFF0ECE4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _vipGold.withOpacity(isDark ? 0.16 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _vipGoldDark, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: AppColors.textPrimaryFor(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        TextSpan(
                          text: unit,
                          style: TextStyle(
                            color: AppColors.textSecondaryFor(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

class _BenefitChip extends StatelessWidget {
  const _BenefitChip({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  final IconData icon;
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.darkControlBackground : const Color(0xFFFAF8F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _vipGoldDark),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: AppColors.textSecondaryFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimaryFor(context),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textTertiaryFor(context),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.plans,
    required this.currency,
    required this.status,
    required this.selectedPlanId,
    required this.recommendedPlanId,
    required this.isDark,
    required this.onSelected,
  });

  final List<VipPlan> plans;
  final String currency;
  final VipStatus? status;
  final int? selectedPlanId;
  final int? recommendedPlanId;
  final bool isDark;
  final ValueChanged<VipPlan> onSelected;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return _InlineStateCard(
        icon: Icons.event_busy_rounded,
        title: _vipText(
          context,
          zhCN: '暂无可售会员套餐',
          zhTW: '暫無可售會員套餐',
          en: 'No membership plans available',
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < plans.length; index++) ...[
          _PlanCard(
            plan: plans[index],
            currency: currency,
            selected: plans[index].id == selectedPlanId,
            recommended: plans[index].id == recommendedPlanId,
            disabled: status?.isActive == true &&
                (status?.level ?? 0) > plans[index].level,
            currentLevel: status?.isActive == true &&
                (status?.level ?? 0) == plans[index].level,
            isDark: isDark,
            onTap: () => onSelected(plans[index]),
          ),
          if (index != plans.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.currency,
    required this.selected,
    required this.recommended,
    required this.disabled,
    required this.currentLevel,
    required this.isDark,
    required this.onTap,
  });

  final VipPlan plan;
  final String currency;
  final bool selected;
  final bool recommended;
  final bool disabled;
  final bool currentLevel;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedFill =
        isDark ? const Color(0xFF30291D) : const Color(0xFFFFFBF2);
    final normalFill = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = selected
        ? _vipGoldDark
        : isDark
            ? AppColors.darkDivider
            : const Color(0xFFE6E1D8);

    return AnimatedOpacity(
      opacity: disabled ? 0.52 : 1,
      duration: const Duration(milliseconds: 180),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            decoration: BoxDecoration(
              color: selected ? selectedFill : normalFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: selected ? 1.6 : 1,
              ),
              boxShadow: !isDark && selected
                  ? [
                      BoxShadow(
                        color: _vipGold.withOpacity(0.12),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (recommended && !disabled)
                  Positioned(
                    right: -17,
                    top: -17,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(13, 6, 13, 6),
                      decoration: const BoxDecoration(
                        color: _vipGoldDark,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(19),
                          bottomLeft: Radius.circular(13),
                        ),
                      ),
                      child: Text(
                        _vipText(
                          context,
                          zhCN: '推荐',
                          zhTW: '推薦',
                          en: 'Best value',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: selected
                                ? const LinearGradient(
                                    colors: [Color(0xFFE5C477), _vipGoldDark],
                                  )
                                : null,
                            color: selected
                                ? null
                                : isDark
                                    ? AppColors.darkControlBackground
                                    : const Color(0xFFF5F2EC),
                          ),
                          child: Icon(
                            Icons.calendar_month_rounded,
                            color: selected ? Colors.white : _vipGoldDark,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      plan.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            AppColors.textPrimaryFor(context),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _DurationPill(days: plan.durationDays),
                                  if (currentLevel) ...[
                                    const SizedBox(width: 7),
                                    _SmallOutlinePill(
                                      text: _vipText(
                                        context,
                                        zhCN: '当前等级',
                                        zhTW: '目前等級',
                                        en: 'Current',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 8,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.end,
                                children: [
                                  Text(
                                    '$currency${plan.price.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: AppColors.textPrimaryFor(context),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  if (plan.originalPrice > plan.price) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                        '$currency${plan.originalPrice.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: AppColors.textTertiaryFor(
                                              context),
                                          fontSize: 12,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(top: 17),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  selected ? _vipGoldDark : Colors.transparent,
                              border: Border.all(
                                color: selected
                                    ? _vipGoldDark
                                    : AppColors.textTertiaryFor(context),
                                width: 1.4,
                              ),
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 17,
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _PlanBenefitPill(
                          text: _vipText(
                            context,
                            zhCN: '建群 ${plan.benefits.maxOwnedGroups}',
                            zhTW: '建群 ${plan.benefits.maxOwnedGroups}',
                            en: '${plan.benefits.maxOwnedGroups} groups',
                          ),
                          isDark: isDark,
                        ),
                        if (plan.benefits.canCreateChannel)
                          _PlanBenefitPill(
                            text: _vipText(
                              context,
                              zhCN: '频道 ${plan.benefits.maxOwnedChannels}',
                              zhTW: '頻道 ${plan.benefits.maxOwnedChannels}',
                              en: '${plan.benefits.maxOwnedChannels} channels',
                            ),
                            isDark: isDark,
                          ),
                        _PlanBenefitPill(
                          text: _vipText(
                            context,
                            zhCN: '群上限 ${plan.benefits.maxGroupMembers}',
                            zhTW: '群上限 ${plan.benefits.maxGroupMembers}',
                            en: '${plan.benefits.maxGroupMembers} members',
                          ),
                          isDark: isDark,
                        ),
                        _PlanBenefitPill(
                          text: _vipText(
                            context,
                            zhCN: '文件 ${plan.benefits.uploadFileLimitMB}MB',
                            zhTW: '檔案 ${plan.benefits.uploadFileLimitMB}MB',
                            en: '${plan.benefits.uploadFileLimitMB}MB files',
                          ),
                          isDark: isDark,
                        ),
                      ],
                    ),
                    if (disabled) ...[
                      const SizedBox(height: 10),
                      Text(
                        _vipText(
                          context,
                          zhCN: '当前会员等级更高，不能选择此套餐',
                          zhTW: '目前會員等級更高，不能選擇此套餐',
                          en: 'Your current membership level is higher',
                        ),
                        style: TextStyle(
                          color: AppColors.textSecondaryFor(context),
                          fontSize: 12,
                        ),
                      ),
                    ] else if (plan.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        plan.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondaryFor(context),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkControlBackground
            : const Color(0xFFF2EFE9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _vipText(
          context,
          zhCN: '$days天',
          zhTW: '$days天',
          en: '$days days',
        ),
        style: TextStyle(
          color: AppColors.textSecondaryFor(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SmallOutlinePill extends StatelessWidget {
  const _SmallOutlinePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: _vipGoldDark.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _vipGoldDark,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PlanBenefitPill extends StatelessWidget {
  const _PlanBenefitPill({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.darkControlBackground : const Color(0xFFF5F1E8),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? const Color(0xFFE8D39B) : const Color(0xFF8B6825),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.currency,
    required this.isLoading,
    required this.isDark,
    required this.onRecharge,
  });

  final WalletInfo? wallet;
  final String currency;
  final bool isLoading;
  final bool isDark;
  final VoidCallback onRecharge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : const Color(0xFFE8E3DA),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkControlBackground
                  : const Color(0xFFF5F2EC),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: isDark ? const Color(0xFFE4C77E) : _vipInk,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _vipText(
              context,
              zhCN: '钱包余额',
              zhTW: '錢包餘額',
              en: 'Wallet balance',
            ),
            style: TextStyle(
              color: AppColors.textPrimaryFor(context),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isLoading && wallet == null
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(
                    '$currency${(wallet?.balance ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: AppColors.textPrimaryFor(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          if (wallet?.isLocked == true)
            Text(
              _vipText(
                context,
                zhCN: '已锁定',
                zhTW: '已鎖定',
                en: 'Locked',
              ),
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            TextButton(
              onPressed: onRecharge,
              style: TextButton.styleFrom(
                foregroundColor:
                    isDark ? const Color(0xFFE4C77E) : _vipGoldDark,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                _vipText(
                  context,
                  zhCN: '充值',
                  zhTW: '充值',
                  en: 'Top up',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _PurchaseBar extends StatelessWidget {
  const _PurchaseBar({
    required this.plan,
    required this.currency,
    required this.status,
    required this.wallet,
    required this.walletLoading,
    required this.isPurchasing,
    required this.isDark,
    required this.onPressed,
  });

  final VipPlan plan;
  final String currency;
  final VipStatus? status;
  final WalletInfo? wallet;
  final bool walletLoading;
  final bool isPurchasing;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = isPurchasing ||
        wallet?.isLocked == true ||
        (wallet == null && walletLoading);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations == true;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkDivider : const Color(0xFFECE7DE),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vipText(
                        context,
                        zhCN: '实付',
                        zhTW: '實付',
                        en: 'Total',
                      ),
                      style: TextStyle(
                        color: AppColors.textSecondaryFor(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 1),
                    AnimatedSwitcher(
                      duration: Duration(
                        milliseconds: reduceMotion ? 0 : 240,
                      ),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.92,
                              end: 1,
                            ).animate(animation),
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        );
                      },
                      child: FittedBox(
                        key: ValueKey<int>(plan.id),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$currency${plan.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: _vipGoldDark,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 190,
                height: 52,
                child: ElevatedButton(
                  onPressed: disabled ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vipGold,
                    disabledBackgroundColor: isDark
                        ? AppColors.darkDivider
                        : const Color(0xFFD9D5CC),
                    foregroundColor: _vipInk,
                    disabledForegroundColor: AppColors.textTertiaryFor(context),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: isPurchasing
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: _vipInk,
                          ),
                        )
                      : Text(
                          wallet?.isLocked == true
                              ? _vipText(
                                  context,
                                  zhCN: '钱包已锁定',
                                  zhTW: '錢包已鎖定',
                                  en: 'Wallet locked',
                                )
                              : _purchaseActionText(context, status, plan),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
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

enum _PurchaseDecision { purchase, recharge }

class _PurchaseConfirmSheet extends StatelessWidget {
  const _PurchaseConfirmSheet({
    required this.plan,
    required this.status,
    required this.wallet,
    required this.currency,
  });

  final VipPlan plan;
  final VipStatus? status;
  final WalletInfo? wallet;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balance = wallet?.balance ?? 0;
    final insufficient = balance < plan.price;
    final expectedExpiry = _expectedExpiry(status, plan);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkDivider : const Color(0xFFD8D5CF),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _vipText(
              context,
              zhCN: '确认开通',
              zhTW: '確認開通',
              en: 'Confirm purchase',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimaryFor(context),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : const Color(0xFFFFFBF2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _vipGold.withOpacity(0.55)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFE5C477), _vipGoldDark],
                    ),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: TextStyle(
                          color: AppColors.textPrimaryFor(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _vipText(
                          context,
                          zhCN: '${plan.durationDays}天会员权益',
                          zhTW: '${plan.durationDays}天會員權益',
                          en: '${plan.durationDays} days of membership',
                        ),
                        style: TextStyle(
                          color: AppColors.textSecondaryFor(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$currency${plan.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: _vipGoldDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ConfirmRow(
            label: _vipText(
              context,
              zhCN: '钱包余额',
              zhTW: '錢包餘額',
              en: 'Wallet balance',
            ),
            value: '$currency${balance.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          _ConfirmRow(
            label: _vipText(
              context,
              zhCN: '预计到期',
              zhTW: '預計到期',
              en: 'Expected expiry',
            ),
            value: _formatDate(expectedExpiry),
          ),
          if (status?.isActive == true &&
              (status?.level ?? 0) < plan.level) ...[
            const SizedBox(height: 12),
            Text(
              _vipText(
                context,
                zhCN: '更高等级套餐将立即生效，并按当前计费规则计算有效期。',
                zhTW: '更高等級套餐將立即生效，並按目前計費規則計算有效期。',
                en: 'The higher membership level starts immediately under the current billing rules.',
              ),
              style: TextStyle(
                color: AppColors.textSecondaryFor(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (insufficient) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _vipText(
                  context,
                  zhCN:
                      '余额不足，还差 $currency${(plan.price - balance).toStringAsFixed(2)}',
                  zhTW:
                      '餘額不足，還差 $currency${(plan.price - balance).toStringAsFixed(2)}',
                  en: 'Insufficient balance. Add $currency${(plan.price - balance).toStringAsFixed(2)}.',
                ),
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                insufficient
                    ? _PurchaseDecision.recharge
                    : _PurchaseDecision.purchase,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _vipGold,
                foregroundColor: _vipInk,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                insufficient
                    ? _vipText(
                        context,
                        zhCN: '余额不足，去充值',
                        zhTW: '餘額不足，去充值',
                        en: 'Top up wallet',
                      )
                    : _vipText(
                        context,
                        zhCN: '确认支付 $currency${plan.price.toStringAsFixed(2)}',
                        zhTW: '確認支付 $currency${plan.price.toStringAsFixed(2)}',
                        en: 'Pay $currency${plan.price.toStringAsFixed(2)}',
                      ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondaryFor(context),
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimaryFor(context),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InlineStateCard extends StatelessWidget {
  const _InlineStateCard({
    required this.icon,
    required this.title,
    this.actionText,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textTertiaryFor(context)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondaryFor(context),
              fontSize: 14,
            ),
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: _vipGoldDark),
              child: Text(actionText!),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanLoadingBlock extends StatelessWidget {
  const _PlanLoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SkeletonCard(height: 140),
        SizedBox(height: 10),
        _SkeletonCard(height: 140),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

String _purchaseActionText(
  BuildContext context,
  VipStatus? status,
  VipPlan plan,
) {
  if (status?.isActive == true) {
    if ((status?.level ?? 0) == plan.level) {
      return _vipText(
        context,
        zhCN: '立即续费',
        zhTW: '立即續費',
        en: 'Renew now',
      );
    }
    if ((status?.level ?? 0) < plan.level) {
      return _vipText(
        context,
        zhCN: '切换至 ${plan.levelName}',
        zhTW: '切換至 ${plan.levelName}',
        en: 'Switch to ${plan.levelName}',
      );
    }
  }
  return _vipText(
    context,
    zhCN: '立即开通',
    zhTW: '立即開通',
    en: 'Activate now',
  );
}

DateTime _expectedExpiry(VipStatus? status, VipPlan plan) {
  final now = DateTime.now();
  var start = now;
  final currentExpiry = status?.expiredAt;
  if (status?.isActive == true &&
      currentExpiry != null &&
      currentExpiry.isAfter(now) &&
      (status?.level ?? 0) >= plan.level) {
    start = currentExpiry;
  }
  return start.add(Duration(days: plan.durationDays));
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
