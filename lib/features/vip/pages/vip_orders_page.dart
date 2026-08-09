// 文件用途：实现 VipOrdersPage 页面及其交互流程，属于会员权益。
// 核心逻辑：维护 VipOrdersPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../wallet/providers/wallet_provider.dart';
import '../providers/vip_provider.dart';
import '../services/vip_service.dart';
import '../widgets/vip_badge.dart';

String _vipOrderText(
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

// 关键声明：VIP orders page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class VipOrdersPage extends ConsumerStatefulWidget {
  const VipOrdersPage({super.key});

  @override
  ConsumerState<VipOrdersPage> createState() => _VipOrdersPageState();
}

class _VipOrdersPageState extends ConsumerState<VipOrdersPage> {
  final _scrollController = ScrollController();

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vipOrdersProvider.notifier).load(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180) {
      final state = ref.read(vipOrdersProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(vipOrdersProvider.notifier).load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(vipOrdersProvider);
    final currency = ref.watch(walletCurrencyProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _vipOrderText(
            context,
            zhCN: '购买记录',
            zhTW: '購買記錄',
            en: 'Purchase History',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _vipOrderTextPrimary(context),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: _vipOrderTextPrimary(context),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryFor(context),
        onRefresh: () => ref.read(vipOrdersProvider.notifier).load(
              refresh: true,
            ),
        child: _buildBody(context, isDark, state, currency),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    VipOrderListState state,
    String currency,
  ) {
    if (state.isLoading && state.orders.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (state.orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.24),
          Icon(
            Icons.receipt_long_outlined,
            size: 58,
            color: _vipOrderTextTertiary(context),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              state.error?.isNotEmpty == true
                  ? state.error!
                  : _vipOrderText(
                      context,
                      zhCN: '暂无购买记录',
                      zhTW: '暫無購買記錄',
                      en: 'No purchase history yet',
                    ),
              style: TextStyle(
                fontSize: 15,
                color: _vipOrderTextSecondary(context),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: state.orders.length + (state.isLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 1),
      itemBuilder: (context, index) {
        if (index >= state.orders.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _OrderRow(
          order: state.orders[index],
          isDark: isDark,
          currency: currency,
        );
      },
    );
  }
}

Color _vipOrderTextPrimary(BuildContext context) =>
    AppColors.textPrimaryFor(context);

Color _vipOrderTextSecondary(BuildContext context) =>
    AppColors.textSecondaryFor(context);

Color _vipOrderTextTertiary(BuildContext context) =>
    AppColors.textTertiaryFor(context);

Color _vipOrderCard(bool isDark) =>
    isDark ? AppColors.darkCard : AppColors.lightCard;

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.isDark,
    required this.currency,
  });

  final VipOrder order;
  final bool isDark;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);
    final planName = order.planName.trim().isNotEmpty
        ? order.planName.trim()
        : _vipOrderText(
            context,
            zhCN: '会员套餐',
            zhTW: '會員套餐',
            en: 'VIP plan',
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _vipOrderCard(isDark),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(order.id == 0 ? 0 : 8),
          bottom: Radius.circular(order.id == 0 ? 0 : 8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.workspace_premium_outlined,
                color: statusColor,
                size: 21,
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
                          planName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _vipOrderTextPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      VipBadge(
                        level: order.planLevel,
                        text: order.planLevel >= 2 ? 'SVIP' : 'VIP',
                        compact: true,
                        height: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _orderNoText(context, order.orderNo),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: _vipOrderTextTertiary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(context, order.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: _vipOrderTextTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currency${order.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _vipOrderTextPrimary(context),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusText(context, order.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _orderNoText(BuildContext context, String value) {
    if (value.trim().isEmpty) {
      return _vipOrderText(
        context,
        zhCN: '订单号 -',
        zhTW: '訂單號 -',
        en: 'Order -',
      );
    }
    return _vipOrderText(
      context,
      zhCN: '订单号 $value',
      zhTW: '訂單號 $value',
      en: 'Order $value',
    );
  }

  String _statusText(BuildContext context, String status) {
    switch (status) {
      case 'paid':
        return _vipOrderText(context, zhCN: '已支付', zhTW: '已付款', en: 'Paid');
      case 'pending':
        return _vipOrderText(context, zhCN: '待支付', zhTW: '待付款', en: 'Pending');
      case 'canceled':
        return _vipOrderText(context, zhCN: '已取消', zhTW: '已取消', en: 'Canceled');
      case 'failed':
        return _vipOrderText(context, zhCN: '失败', zhTW: '失敗', en: 'Failed');
      case 'refunded':
        return _vipOrderText(context, zhCN: '已退款', zhTW: '已退款', en: 'Refunded');
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF07C160);
      case 'pending':
        return const Color(0xFFFFA940);
      case 'failed':
      case 'canceled':
        return AppColors.error;
      default:
        return const Color(0xFF8E8E93);
    }
  }

  String _formatTime(BuildContext context, DateTime? time) {
    if (time == null) {
      return _vipOrderText(context, zhCN: '时间 -', zhTW: '時間 -', en: 'Time -');
    }
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
