import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/theme/premium_theme_tokens.dart';
import '../../../shared/widgets/premium_widgets.dart';

class MembershipPlan {
  final int id;
  final String slug;
  final String name;
  final int durationDays;
  final double price;
  final double originalPrice;
  final String badgeLabel;
  final String badgeColor;
  final String description;
  final List<String> features;

  const MembershipPlan({
    required this.id,
    required this.slug,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.originalPrice,
    required this.badgeLabel,
    required this.badgeColor,
    required this.description,
    required this.features,
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> json) => MembershipPlan(
    id: json['id'] as int? ?? 0,
    slug: json['slug'] as String? ?? '',
    name: json['name'] as String? ?? '',
    durationDays: json['duration_days'] as int? ?? 0,
    price: (json['price'] as num?)?.toDouble() ?? 0,
    originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0,
    badgeLabel: json['badge_label'] as String? ?? '',
    badgeColor: json['badge_color'] as String? ?? '#3390EC',
    description: json['description'] as String? ?? '',
    features: ((json['features'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
  );
}

class MembershipInfo {
  final bool active;
  final String? status;
  final int? planId;
  final String? planName;
  final String? badgeLabel;
  final String? premiumType;
  final DateTime? expireAt;
  final List<String> features;

  const MembershipInfo({
    required this.active,
    this.status,
    this.planId,
    this.planName,
    this.badgeLabel,
    this.premiumType,
    this.expireAt,
    required this.features,
  });

  factory MembershipInfo.fromJson(Map<String, dynamic> json) => MembershipInfo(
    active: json['active'] as bool? ?? false,
    status: json['status'] as String?,
    planId: json['plan_id'] as int?,
    planName: json['plan_name'] as String?,
    badgeLabel: json['badge_label'] as String?,
    premiumType: json['premium_type'] as String?,
    expireAt: json['expire_at'] != null
        ? DateTime.tryParse(json['expire_at'])
        : null,
    features: ((json['features'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
  );
}

class MembershipBundle {
  final MembershipInfo? membership;
  final List<MembershipPlan> plans;
  const MembershipBundle({required this.membership, required this.plans});
}

class MembershipService {
  final ApiClient _api;
  MembershipService(this._api);

  Future<ApiResponse<MembershipBundle>> getBundle() {
    return _api.get(
      '/wallet/membership',
      fromJson: (data) {
        final map = data as Map<String, dynamic>;
        final membershipMap = map['membership'] as Map<String, dynamic>?;
        return MembershipBundle(
          membership: membershipMap == null
              ? null
              : MembershipInfo.fromJson(membershipMap),
          plans: ((map['plans'] as List?) ?? const [])
              .map((e) => MembershipPlan.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
    );
  }

  Future<ApiResponse<void>> purchase(int planId) {
    return _api.post<void>(
      '/wallet/membership/purchase',
      data: {'plan_id': planId},
    );
  }
}

final membershipServiceProvider = Provider(
  (ref) => MembershipService(ref.read(apiClientProvider)),
);

class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({super.key});

  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  MembershipBundle? _bundle;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  int? _selectedPlanId;

  String? _inferPremiumType(MembershipPlan? plan) {
    if (plan == null) return null;
    final label = '${plan.name} ${plan.badgeLabel} ${plan.description}'
        .toLowerCase();
    if (label.contains('年') || label.contains('year')) return 'yearly';
    if (label.contains('季') || label.contains('quarter')) return 'quarterly';
    if (plan.durationDays >= 300) return 'yearly';
    if (plan.durationDays >= 80) return 'quarterly';
    return null;
  }

  List<MembershipPlan> _orderedPlans(List<MembershipPlan> plans) {
    final copied = [...plans];
    copied.sort((a, b) {
      final aType = _inferPremiumType(a);
      final bType = _inferPremiumType(b);
      final aPriority = PremiumThemeTokens.isYearly(aType)
          ? 0
          : PremiumThemeTokens.isQuarterly(aType)
          ? 1
          : 2;
      final bPriority = PremiumThemeTokens.isYearly(bType)
          ? 0
          : PremiumThemeTokens.isQuarterly(bType)
          ? 1
          : 2;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);

      final aSave = _saveAmount(a);
      final bSave = _saveAmount(b);
      if (aSave != bSave) return bSave.compareTo(aSave);

      if (a.durationDays != b.durationDays) {
        return b.durationDays.compareTo(a.durationDays);
      }
      return a.price.compareTo(b.price);
    });
    return copied;
  }

  MembershipPlan? _defaultPlan(List<MembershipPlan> plans) {
    if (plans.isEmpty) return null;
    return _orderedPlans(plans).first;
  }

  MembershipPlan? _membershipPlanMatch(
    MembershipInfo? membership,
    List<MembershipPlan> plans,
  ) {
    if (membership == null || plans.isEmpty) return null;
    if (membership.planId != null) {
      for (final plan in plans) {
        if (plan.id == membership.planId) return plan;
      }
    }
    if (membership.premiumType != null && membership.premiumType!.isNotEmpty) {
      for (final plan in plans) {
        if (plan.slug == membership.premiumType) return plan;
      }
    }
    if (membership.planName != null && membership.planName!.isNotEmpty) {
      for (final plan in plans) {
        if (plan.name == membership.planName) return plan;
      }
    }
    return null;
  }

  MembershipPlan? get _selectedPlan {
    final plans = _bundle?.plans ?? const <MembershipPlan>[];
    for (final plan in plans) {
      if (plan.id == _selectedPlanId) return plan;
    }
    return _defaultPlan(plans);
  }

  String _planMarketingLabel(MembershipPlan plan) {
    final premiumType = _inferPremiumType(plan);
    final orderedPlans = _orderedPlans(
      _bundle?.plans ?? const <MembershipPlan>[],
    );
    final isTopPick =
        orderedPlans.isNotEmpty && orderedPlans.first.id == plan.id;
    if (isTopPick && PremiumThemeTokens.isYearly(premiumType)) {
      return '主推 · 最划算';
    }
    if (isTopPick) return '主推推荐';
    if (PremiumThemeTokens.isYearly(premiumType)) return '最划算';
    if (PremiumThemeTokens.isQuarterly(premiumType)) return '灵活升级';
    return plan.badgeLabel.isNotEmpty ? plan.badgeLabel : '推荐';
  }

  String _planSupportCopy(MembershipPlan plan) {
    final premiumType = _inferPremiumType(plan);
    if (PremiumThemeTokens.isYearly(premiumType)) {
      return '长期持有更省心，适合重度使用';
    }
    if (PremiumThemeTokens.isQuarterly(premiumType)) {
      return '先升级体验，预算和权益更平衡';
    }
    return plan.description;
  }

  double _dailyPrice(MembershipPlan plan) {
    if (plan.durationDays <= 0) return plan.price;
    return plan.price / plan.durationDays;
  }

  int _saveAmount(MembershipPlan plan) {
    if (plan.originalPrice <= plan.price) return 0;
    return (plan.originalPrice - plan.price).round();
  }

  String _membershipStatusLabel(MembershipInfo? membership) {
    if (membership?.active == true) return 'ACTIVE';
    if (membership?.status == 'expired') return 'EXPIRED';
    if (membership?.status == 'cancelled') return 'CANCELLED';
    return 'UPGRADE';
  }

  String _heroTitle(MembershipInfo? membership, MembershipPlan? selectedPlan) {
    if (membership?.active == true) {
      return '已开通 ${membership?.planName ?? 'Premium'}';
    }
    if (membership?.status == 'expired') {
      return '${membership?.planName ?? 'Premium'} 已到期，可继续续费恢复权益';
    }
    if (membership?.status == 'cancelled') {
      return '${membership?.planName ?? 'Premium'} 已停用，可重新开通';
    }
    final premiumType = _inferPremiumType(selectedPlan);
    if (PremiumThemeTokens.isYearly(premiumType)) {
      return '一次开通，全年保持 Premium 高阶身份';
    }
    if (PremiumThemeTokens.isQuarterly(premiumType)) {
      return '先升级 1 个季度，立刻体验 Premium 权益';
    }
    return '解锁更高级的 Premium 身份';
  }

  String _heroSubtitle(
    MembershipInfo? membership,
    MembershipPlan? selectedPlan,
  ) {
    if (membership?.active == true && membership?.expireAt != null) {
      return '有效期至 ${membership!.expireAt!.toLocal().toString().split('.').first}';
    }
    if (membership?.status == 'expired' && membership?.expireAt != null) {
      return '已于 ${membership!.expireAt!.toLocal().toString().split('.').first} 到期，续费后可恢复会员徽章和高级权益。';
    }
    if (membership?.status == 'cancelled') {
      return '当前会员已停用，重新开通后可立即恢复 Premium 身份与高级权限。';
    }
    final premiumType = _inferPremiumType(selectedPlan);
    if (PremiumThemeTokens.isYearly(premiumType) && selectedPlan != null) {
      return '年费方案更适合长期使用，约 ¥${_dailyPrice(selectedPlan).toStringAsFixed(2)}/天，权益体验更完整。';
    }
    if (PremiumThemeTokens.isQuarterly(premiumType) && selectedPlan != null) {
      return '季度方案更灵活，先低门槛升级体验，再决定是否长期持有。';
    }
    return '会员徽章、更高上传限制、高级贴纸权限、更多会话置顶。';
  }

  String _comparisonTitle(String? premiumType) {
    if (PremiumThemeTokens.isYearly(premiumType)) return '年费更适合长期持有';
    if (PremiumThemeTokens.isQuarterly(premiumType)) return '季费更适合先升级体验';
    return '按使用周期选择更合适的方案';
  }

  String _comparisonSubtitle(String? premiumType) {
    if (PremiumThemeTokens.isYearly(premiumType)) {
      return '日均成本更低，适合长期稳定使用 Premium 权益。';
    }
    if (PremiumThemeTokens.isQuarterly(premiumType)) {
      return '门槛更低、切换更灵活，适合先体验再决定。';
    }
    return '长期使用建议优先看年费，首次升级可以先从季度方案开始。';
  }

  String _ctaLabel(MembershipInfo? membership, MembershipPlan? selectedPlan) {
    final planName = selectedPlan?.name ?? '当前套餐';
    if (membership?.active == true) return '已开通 $planName';
    if (membership?.status == 'expired') return '立即续费 $planName';
    if (membership?.status == 'cancelled') return '重新开通 $planName';
    return selectedPlan == null ? '立即开通' : '立即开通 $planName';
  }

  List<Map<String, String>> _comparisonItems(List<MembershipPlan> plans) {
    final items = <Map<String, String>>[];
    final hasYearly = plans.any(
      (plan) => PremiumThemeTokens.isYearly(_inferPremiumType(plan)),
    );
    final hasQuarterly = plans.any(
      (plan) => PremiumThemeTokens.isQuarterly(_inferPremiumType(plan)),
    );

    if (hasYearly) {
      items.add({
        'type': 'yearly',
        'title': '年费',
        'subtitle': '更省 · 适合长期使用',
      });
    }
    if (hasQuarterly) {
      items.add({
        'type': 'quarterly',
        'title': '季费',
        'subtitle': '更灵活 · 适合先体验',
      });
    }
    return items;
  }

  MembershipPlan? _planForType(String? premiumType) {
    final plans = _orderedPlans(_bundle?.plans ?? const <MembershipPlan>[]);
    for (final plan in plans) {
      if (_inferPremiumType(plan) == premiumType) return plan;
    }
    return null;
  }

  void _selectPlanType(String? premiumType) {
    final plan = _planForType(premiumType);
    if (plan == null) return;
    setState(() => _selectedPlanId = plan.id);
  }

  Color _statusAccentColor(String? status, Color fallback) {
    switch (status) {
      case 'expired':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return const Color(0xFF64748B);
      default:
        return fallback;
    }
  }

  List<String> _heroHighlights(
    MembershipInfo? membership,
    MembershipPlan? selectedPlan,
  ) {
    if (membership?.active == true) {
      return [
        membership?.badgeLabel?.isNotEmpty == true
            ? membership!.badgeLabel!
            : 'Premium 身份已生效',
        membership?.expireAt != null ? '到期前权益持续可用' : '高级权益已解锁',
        '支持继续下次续费升级',
      ];
    }
    if (membership?.status == 'expired') {
      return ['会员徽章待恢复', '续费后立即恢复权益', '历史身份可延续'];
    }
    if (membership?.status == 'cancelled') {
      return ['当前状态已停用', '重新开通后即时恢复', '高级功能重新解锁'];
    }
    if (selectedPlan != null) {
      return [
        '${selectedPlan.durationDays} 天有效期',
        if (_saveAmount(selectedPlan) > 0) '立省 ¥${_saveAmount(selectedPlan)}',
        if (selectedPlan.features.isNotEmpty) selectedPlan.features.first,
      ];
    }
    return ['会员徽章', '高级权益', '更完整的 Premium 体验'];
  }

  bool _isTopPick(MembershipPlan plan) {
    final orderedPlans = _orderedPlans(_bundle?.plans ?? const <MembershipPlan>[]);
    return orderedPlans.isNotEmpty && orderedPlans.first.id == plan.id;
  }

  String _topPickReason(MembershipPlan plan) {
    final premiumType = _inferPremiumType(plan);
    if (PremiumThemeTokens.isYearly(premiumType)) {
      return '年费折算日均更低，适合长期稳定使用。';
    }
    if (PremiumThemeTokens.isQuarterly(premiumType)) {
      return '季度成本更轻，适合先升级体验后再决定。';
    }
    return '综合权益与价格表现，当前更值得优先选择。';
  }

  String _statusFootnote(MembershipInfo? membership) {
    if (membership?.status == 'expired') {
      return '续费后立即恢复 Premium 身份与权益';
    }
    if (membership?.status == 'cancelled') {
      return '重新开通后立即恢复会员功能';
    }
    return '支付成功后将自动刷新会员状态';
  }

  String _tipCardTitle(MembershipInfo? membership) {
    if (membership?.active == true) return '当前会员状态说明';
    if (membership?.status == 'expired') return '续费后可恢复的权益';
    if (membership?.status == 'cancelled') return '重新开通后可恢复的权益';
    return '开通后你将获得';
  }

  List<String> _tipCardItems(MembershipInfo? membership) {
    if (membership?.active == true) {
      return [
        '当前 Premium 身份已生效，可继续使用高级能力。',
        '会员到期前无需重复购买，状态会自动展示。',
        '如需长期持有，可在到期前关注续费方案。',
      ];
    }
    if (membership?.status == 'expired') {
      return [
        '续费后可恢复会员徽章与昵称展示效果。',
        '高级贴纸、上传限制等权益会重新开放。',
        '购买成功后页面会自动刷新当前状态。',
      ];
    }
    if (membership?.status == 'cancelled') {
      return [
        '重新开通后可恢复 Premium 身份与高级功能。',
        '会员标签、权益入口会按最新状态同步更新。',
        '购买成功后无需手动退出登录。',
      ];
    }
    return [
      '开通后可获得 Premium 身份标识与更多高级权限。',
      '不同套餐适合不同使用周期，可按需求自由选择。',
      '支付成功后会自动刷新账号会员状态。',
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final resp = await ref.read(membershipServiceProvider).getBundle();
      if (!mounted) return;
      setState(() {
        if (resp.isSuccess && resp.data != null) {
          _bundle = resp.data;
          final plans = _bundle?.plans ?? const <MembershipPlan>[];
          final matchedPlan = _membershipPlanMatch(_bundle?.membership, plans);
          _selectedPlanId = matchedPlan?.id ?? _defaultPlan(plans)?.id;
          _loadError = null;
        } else {
          _bundle = null;
          _selectedPlanId = null;
          _loadError = resp.message.isNotEmpty ? resp.message : '会员信息加载失败';
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bundle = null;
        _selectedPlanId = null;
        _loadError = '会员信息加载失败，请点击重试';
        _loading = false;
      });
    }
  }

  Future<void> _purchase() async {
    if (_selectedPlanId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      final resp = await ref
          .read(membershipServiceProvider)
          .purchase(_selectedPlanId!);
      if (!mounted) return;
      if (resp.isSuccess) {
        await ref.read(authServiceProvider.notifier).getCurrentUser();
        await _load();
        messenger.showSnackBar(const SnackBar(content: Text('会员开通成功')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(resp.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = _bundle?.membership;
    final plans = _orderedPlans(_bundle?.plans ?? const <MembershipPlan>[]);
    final selectedPlan = _selectedPlan;
    final selectedPremiumType = _inferPremiumType(selectedPlan);
    final selectedAccent = PremiumThemeTokens.accent(selectedPremiumType);
    final statusAccent = _statusAccentColor(membership?.status, selectedAccent);
    final selectedCta = _ctaLabel(membership, selectedPlan);
    final heroTitle = _heroTitle(membership, selectedPlan);
    final heroSubtitle = _heroSubtitle(membership, selectedPlan);
    final heroHighlights = _heroHighlights(membership, selectedPlan);
    final comparisonTitle = _comparisonTitle(selectedPremiumType);
    final comparisonSubtitle = _comparisonSubtitle(selectedPremiumType);
    final comparisonItems = _comparisonItems(plans);
    final hasPlans = plans.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Premium 会员')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PremiumCard(
                  isDark: false,
                  premiumType: 'warning',
                  padding: const EdgeInsets.all(20),
                  borderRadius: BorderRadius.circular(24),
                  colors: const [Colors.white, Color(0xFFFFFBEB)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFF59E0B),
                          ),
                          SizedBox(width: 10),
                          Text(
                            '会员页加载失败',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _loadError!,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _load,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('重新加载'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: PremiumCard(
                      key: ValueKey(
                        selectedPremiumType ?? 'default-premium-hero',
                      ),
                      isDark: true,
                      premiumType: selectedPremiumType,
                      padding: const EdgeInsets.all(20),
                      borderRadius: BorderRadius.circular(24),
                      colors: PremiumThemeTokens.isPremium(selectedPremiumType)
                          ? (PremiumThemeTokens.isYearly(selectedPremiumType)
                                ? const [
                                    Color(0xFF020202),
                                    Color(0xFF060606),
                                    Color(0xFF100C05),
                                    Color(0xFF1D1506),
                                    Color(0xFF2B1E08),
                                  ]
                                : PremiumThemeTokens.cardGradient(
                                    selectedPremiumType,
                                    const Color(0xFF111827),
                                  ))
                          : const [
                              Color(0xFF1D4ED8),
                              Color(0xFF7C3AED),
                              Color(0xFFEC4899),
                            ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.workspace_premium_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              PremiumChip(
                                label: _membershipStatusLabel(membership),
                                premiumType: membership?.status == 'expired'
                                    ? 'warning'
                                    : (membership?.status == 'cancelled'
                                          ? 'neutral'
                                          : selectedPremiumType),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: Text(
                              heroTitle,
                              key: ValueKey(
                                '${membership?.planName}_${selectedPremiumType}_title',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: Text(
                              heroSubtitle,
                              key: ValueKey(
                                '${membership?.expireAt}_${selectedPremiumType}_subtitle',
                              ),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: heroHighlights
                                .map(
                                  (e) => PremiumContainer(
                                    premiumType: selectedPremiumType,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: _buildPremiumTipCard(
                      membership,
                      selectedPremiumType,
                      key: ValueKey(
                        'tip_${membership?.status ?? selectedPremiumType ?? 'default'}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (comparisonItems.isNotEmpty) ...[
                    PremiumCard(
                      isDark: false,
                      premiumType: selectedPremiumType,
                      padding: const EdgeInsets.all(16),
                      borderRadius: BorderRadius.circular(20),
                      colors: const [Colors.white, Color(0xFFFAFBFF)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comparisonTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            comparisonSubtitle,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ...comparisonItems.map((item) {
                                final type = item['type'];
                                final active = type == selectedPremiumType;
                                final accent = PremiumThemeTokens.accent(type);
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: item == comparisonItems.first &&
                                              comparisonItems.length > 1
                                          ? 8
                                          : 0,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => _selectPlanType(type),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 220),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: active
                                                ? accent.withValues(alpha: 0.10)
                                                : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: active
                                                  ? accent.withValues(alpha: 0.28)
                                                  : Colors.black.withValues(alpha: 0.05),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['title']!,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: active ? accent : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                item['subtitle']!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: active
                                                      ? accent.withValues(alpha: 0.84)
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (!hasPlans)
                    PremiumCard(
                      isDark: false,
                      premiumType: 'neutral',
                      padding: const EdgeInsets.all(20),
                      borderRadius: BorderRadius.circular(20),
                      colors: const [Colors.white, Color(0xFFF8FAFC)],
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 10),
                              Text(
                                '当前暂无可购买套餐',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            '套餐正在配置中，请稍后下拉刷新或联系管理员处理。',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        const Text(
                          '选择套餐',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '主推方案已置顶',
                          style: TextStyle(
                            fontSize: 12,
                            color: selectedAccent.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...plans.map((plan) {
                      final selected = plan.id == _selectedPlanId;
                      final premiumType = _inferPremiumType(plan);
                      final accent = PremiumThemeTokens.accent(premiumType);
                      final isTopPick = _isTopPick(plan);
                      final isDarkTopPick =
                          isTopPick && PremiumThemeTokens.isYearly(premiumType);
                      final primaryTextColor = isDarkTopPick
                          ? const Color(0xFFFFF7E6)
                          : Colors.black87;
                      final secondaryTextColor = isDarkTopPick
                          ? Colors.white.withValues(alpha: 0.74)
                          : Colors.black54;
                      final mutedTextColor = isDarkTopPick
                          ? const Color(0xFFD6C39A)
                          : Colors.black45;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                        onTap: () => setState(() => _selectedPlanId = plan.id),
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          scale: selected ? 1.0 : 0.985,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            opacity: selected ? 1 : 0.9,
                            child: PremiumCard(
                              isDark: false,
                              premiumType: premiumType,
                              accentColor: isTopPick
                                  ? (PremiumThemeTokens.isYearly(premiumType)
                                        ? const Color(0xFFFFD36B)
                                        : accent)
                                  : (selected
                                        ? accent
                                        : accent.withValues(alpha: 0.72)),
                              padding: const EdgeInsets.all(16),
                              borderRadius: BorderRadius.circular(20),
                              colors: isTopPick
                                  ? (PremiumThemeTokens.isYearly(premiumType)
                                        ? const [
                                            Color(0xFF070605),
                                            Color(0xFF100C06),
                                            Color(0xFF1A1307),
                                            Color(0xFF2A1D08),
                                          ]
                                        : PremiumThemeTokens.cardGradient(
                                            premiumType,
                                            const Color(0xFFFFFCF5),
                                          ))
                                  : (selected
                                        ? PremiumThemeTokens.cardGradient(
                                            premiumType,
                                            Colors.white,
                                          )
                                        : const [
                                            Colors.white,
                                            Color(0xFFF8FAFF),
                                          ]),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isTopPick) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 14,
                                            color: accent,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '当前主推方案',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          plan.name,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                      ),
                                      PremiumChip(
                                        label: _planMarketingLabel(plan),
                                        premiumType: premiumType,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _planSupportCopy(plan),
                                    style: TextStyle(
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                  if (isTopPick) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _topPickReason(plan),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: accent.withValues(alpha: 0.84),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      AnimatedDefaultTextStyle(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        style: TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.bold,
                                          color: selected
                                              ? accent
                                              : primaryTextColor,
                                        ),
                                        child: Text(
                                          '¥${plan.price.toStringAsFixed(0)}',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          '约 ¥${_dailyPrice(plan).toStringAsFixed(2)}/天',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: selected
                                                ? accent.withValues(alpha: 0.86)
                                                : mutedTextColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (plan.originalPrice > plan.price)
                                        Text(
                                          '¥${plan.originalPrice.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            color: mutedTextColor,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                      const Spacer(),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        transitionBuilder: (child, animation) {
                                          return ScaleTransition(
                                            scale: animation,
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: selected
                                            ? Icon(
                                                Icons.check_circle_rounded,
                                                key: ValueKey(
                                                  'selected_${plan.id}',
                                                ),
                                                color: accent,
                                                size: 22,
                                              )
                                            : const SizedBox(
                                                key: ValueKey('unselected'),
                                                width: 22,
                                                height: 22,
                                              ),
                                      ),
                                    ],
                                  ),
                                  if (_saveAmount(plan) > 0) ...[
                                    const SizedBox(height: 8),
                                    PremiumContainer(
                                      premiumType: premiumType,
                                      borderRadius: BorderRadius.circular(999),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          '立省 ¥${_saveAmount(plan)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ...plan.features.map(
                                        (e) => PremiumContainer(
                                          premiumType: premiumType,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                            child: Text(
                                              e,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDarkTopPick
                                                    ? primaryTextColor
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                    const SizedBox(height: 12),
                    if (membership?.active == true)
                      PremiumCard(
                        isDark: false,
                        premiumType: selectedPremiumType,
                        padding: const EdgeInsets.all(16),
                        borderRadius: BorderRadius.circular(18),
                        colors: const [Colors.white, Color(0xFFF9FBFF)],
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: statusAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.verified_rounded,
                                color: statusAccent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '当前会员已生效',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    membership?.expireAt != null
                                        ? '有效期至 ${membership!.expireAt!.toLocal().toString().split('.').first}，当前无需重复购买。'
                                        : '当前权益已生效，无需重复购买。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: statusAccent.withValues(alpha: 0.78),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          begin: selectedAccent,
                          end: selectedAccent,
                        ),
                        duration: const Duration(milliseconds: 260),
                        builder: (context, color, child) {
                          return SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _purchase,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 0,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Text(
                                  _submitting ? '开通中...' : selectedCta,
                                  key: ValueKey(
                                    '${_submitting}_${selectedPlan?.id ?? 'default'}',
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 14,
                            color: selectedAccent.withValues(alpha: 0.72),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _statusFootnote(membership),
                            style: TextStyle(
                              fontSize: 12,
                              color: statusAccent.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPremiumTipCard(
    MembershipInfo? membership,
    String? premiumType, {
    Key? key,
  }) {
    final items = _tipCardItems(membership);
    return PremiumCard(
      key: key,
      isDark: false,
      premiumType: premiumType,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      colors: const [Colors.white, Color(0xFFFAFBFF)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tipCardTitle(membership),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Text('• $item')),
        ],
      ),
    );
  }
}
