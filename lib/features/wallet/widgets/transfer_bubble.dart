// 文件用途：提供 TransferBubble 可复用界面组件，服务于钱包与支付。
// 核心逻辑：根据输入模型和状态渲染 TransferBubble，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart' show ApiConfig;
import '../services/wallet_service.dart';

String _transferBubbleText(
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

// 关键声明：transfer bubble 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 转账消息气泡 - 仿微信简洁风格
class TransferBubble extends StatelessWidget {
  final TransferInfo transfer;
  final bool isOutgoing;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onTap;
  final String currency;

  const TransferBubble({
    super.key,
    required this.transfer,
    required this.isOutgoing,
    this.onAccept,
    this.onReject,
    this.onTap,
    this.currency = '¥',
  });

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final isAccepted = transfer.status == TransferStatus.accepted;
    final isRejected = transfer.status == TransferStatus.rejected;
    final isExpired = transfer.status == TransferStatus.expired;

    // 颜色 — 只有过期变灰，其他状态保持橙色主色调，通过文字区分
    Color primaryColor;
    if (isExpired) {
      primaryColor = const Color(0xFFBEBEBE);
    } else {
      primaryColor = const Color(0xFFFFA940);
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      child: Container(
        width: 230,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 主体区域
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primaryColor,
                    primaryColor.withOpacity(0.85),
                  ],
                ),
              ),
              child: Row(
                children: [
                  // 转账图标
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/stickers/zhuanzhang.png',
                        width: 28,
                        height: 28,
                        errorBuilder: (_, __, ___) => Icon(
                          isOutgoing
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 金额和状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$currency${transfer.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getStatusText(context),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 底部标识
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isExpired
                    ? const Color(0xFF9E9E9E)
                    : const Color(0xFFE69330),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStatusIcon(),
                    size: 12,
                    color: Colors.white.withOpacity(0.8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _transferBubbleText(
                      context,
                      zhCN: '转账',
                      zhTW: '轉帳',
                      en: 'Transfer',
                    ),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const Spacer(),
                  if (transfer.remark?.isNotEmpty == true)
                    Text(
                      transfer.remark!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (transfer.status) {
      case TransferStatus.pending:
        return Icons.schedule;
      case TransferStatus.accepted:
        return Icons.check_circle_outline;
      case TransferStatus.rejected:
        return Icons.cancel_outlined;
      case TransferStatus.expired:
        return Icons.access_time;
    }
  }

  String _getStatusText(BuildContext context) {
    if (isOutgoing) {
      switch (transfer.status) {
        case TransferStatus.pending:
          return _transferBubbleText(
            context,
            zhCN: '待对方收款',
            zhTW: '待對方收款',
            en: 'Waiting for recipient',
          );
        case TransferStatus.accepted:
          return _transferBubbleText(
            context,
            zhCN: '已被收款',
            zhTW: '已被收款',
            en: 'Received by recipient',
          );
        case TransferStatus.rejected:
          return _transferBubbleText(
            context,
            zhCN: '已退还',
            zhTW: '已退還',
            en: 'Returned',
          );
        case TransferStatus.expired:
          return _transferBubbleText(
            context,
            zhCN: '已过期退还',
            zhTW: '已過期退還',
            en: 'Expired and returned',
          );
      }
    } else {
      switch (transfer.status) {
        case TransferStatus.pending:
          return _transferBubbleText(
            context,
            zhCN: '请收款',
            zhTW: '請收款',
            en: 'Please accept',
          );
        case TransferStatus.accepted:
          return _transferBubbleText(
            context,
            zhCN: '已收款',
            zhTW: '已收款',
            en: 'Received',
          );
        case TransferStatus.rejected:
          return _transferBubbleText(
            context,
            zhCN: '已退还',
            zhTW: '已退還',
            en: 'Returned',
          );
        case TransferStatus.expired:
          return _transferBubbleText(
            context,
            zhCN: '已过期',
            zhTW: '已過期',
            en: 'Expired',
          );
      }
    }
  }
}

/// 转账详情弹窗
class TransferDetailDialog extends StatelessWidget {
  final TransferInfo transfer;
  final bool isOutgoing;
  final String peerName;
  final String? peerAvatar;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final String currency;

  const TransferDetailDialog({
    super.key,
    required this.transfer,
    required this.isOutgoing,
    required this.peerName,
    this.peerAvatar,
    this.onAccept,
    this.onReject,
    this.currency = '¥',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPending = transfer.status == TransferStatus.pending;
    final isAccepted = transfer.status == TransferStatus.accepted;

    Color primaryColor;
    if (isAccepted) {
      primaryColor = const Color(0xFF07C160);
    } else {
      primaryColor = const Color(0xFFFFA940);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部区域
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Column(
                children: [
                  // 关闭按钮
                  Align(
                    alignment: Alignment.topRight,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.close,
                        color: Colors.white.withOpacity(0.6),
                        size: 22,
                      ),
                    ),
                  ),

                  // 头像
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white24,
                      backgroundImage: peerAvatar?.isNotEmpty == true
                          ? CachedNetworkImageProvider(
                              ApiConfig.getMediaUrl(peerAvatar!))
                          : null,
                      child: peerAvatar?.isNotEmpty != true
                          ? Text(
                              peerName.isNotEmpty
                                  ? peerName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    isOutgoing
                        ? _transferBubbleText(
                            context,
                            zhCN: '转账给 $peerName',
                            zhTW: '轉帳給 $peerName',
                            en: 'Transfer to $peerName',
                          )
                        : _transferBubbleText(
                            context,
                            zhCN: '来自 $peerName',
                            zhTW: '來自 $peerName',
                            en: 'From $peerName',
                          ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // 金额区域
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(
                    '$currency${transfer.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (transfer.remark?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        transfer.remark!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 状态或操作按钮
            if (!isOutgoing && isPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onReject?.call();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              isDark ? Colors.white60 : Colors.grey[700],
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.grey[300]!,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _transferBubbleText(
                            context,
                            zhCN: '拒收',
                            zhTW: '拒收',
                            en: 'Decline',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onAccept?.call();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _transferBubbleText(
                            context,
                            zhCN: '收款',
                            zhTW: '收款',
                            en: 'Accept',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(),
                        size: 16,
                        color: _getStatusColor(),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusText(context),
                        style: TextStyle(
                          fontSize: 13,
                          color: _getStatusColor(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (transfer.status) {
      case TransferStatus.pending:
        return const Color(0xFFFFA940);
      case TransferStatus.accepted:
        return const Color(0xFF07C160);
      case TransferStatus.rejected:
        return Colors.red;
      case TransferStatus.expired:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (transfer.status) {
      case TransferStatus.pending:
        return Icons.schedule;
      case TransferStatus.accepted:
        return Icons.check_circle;
      case TransferStatus.rejected:
        return Icons.cancel;
      case TransferStatus.expired:
        return Icons.access_time;
    }
  }

  String _getStatusText(BuildContext context) {
    if (isOutgoing) {
      switch (transfer.status) {
        case TransferStatus.pending:
          return _transferBubbleText(
            context,
            zhCN: '待对方收款',
            zhTW: '待對方收款',
            en: 'Waiting for recipient',
          );
        case TransferStatus.accepted:
          return _transferBubbleText(
            context,
            zhCN: '对方已收款',
            zhTW: '對方已收款',
            en: 'Recipient received it',
          );
        case TransferStatus.rejected:
          return _transferBubbleText(
            context,
            zhCN: '已退还',
            zhTW: '已退還',
            en: 'Returned',
          );
        case TransferStatus.expired:
          return _transferBubbleText(
            context,
            zhCN: '已过期退还',
            zhTW: '已過期退還',
            en: 'Expired and returned',
          );
      }
    } else {
      switch (transfer.status) {
        case TransferStatus.pending:
          return _transferBubbleText(
            context,
            zhCN: '待收款',
            zhTW: '待收款',
            en: 'Waiting to accept',
          );
        case TransferStatus.accepted:
          return _transferBubbleText(
            context,
            zhCN: '已收款',
            zhTW: '已收款',
            en: 'Received',
          );
        case TransferStatus.rejected:
          return _transferBubbleText(
            context,
            zhCN: '已退还',
            zhTW: '已退還',
            en: 'Returned',
          );
        case TransferStatus.expired:
          return _transferBubbleText(
            context,
            zhCN: '已过期',
            zhTW: '已過期',
            en: 'Expired',
          );
      }
    }
  }
}

/// 显示转账详情弹窗
Future<void> showTransferDetailDialog(
  BuildContext context, {
  required TransferInfo transfer,
  required bool isOutgoing,
  required String peerName,
  String? peerAvatar,
  VoidCallback? onAccept,
  VoidCallback? onReject,
  String currency = '¥',
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => TransferDetailDialog(
      transfer: transfer,
      isOutgoing: isOutgoing,
      peerName: peerName,
      peerAvatar: peerAvatar,
      onAccept: onAccept,
      onReject: onReject,
      currency: currency,
    ),
  );
}
