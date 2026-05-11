import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/api/api_client.dart' show ApiConfig;
import '../services/wallet_service.dart';

/// 转账消息气泡 - 仿微信简洁风格
class TransferBubble extends StatelessWidget {
  final TransferInfo transfer;
  final bool isOutgoing;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onTap;

  const TransferBubble({
    super.key,
    required this.transfer,
    required this.isOutgoing,
    this.onAccept,
    this.onReject,
    this.onTap,
  });

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
                          '¥${transfer.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getStatusText(),
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
                    '转账',
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

  String _getStatusText() {
    if (isOutgoing) {
      switch (transfer.status) {
        case TransferStatus.pending:
          return '待对方收款';
        case TransferStatus.accepted:
          return '已被收款';
        case TransferStatus.rejected:
          return '已退还';
        case TransferStatus.expired:
          return '已过期退还';
      }
    } else {
      switch (transfer.status) {
        case TransferStatus.pending:
          return '请收款';
        case TransferStatus.accepted:
          return '已收款';
        case TransferStatus.rejected:
          return '已退还';
        case TransferStatus.expired:
          return '已过期';
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

  const TransferDetailDialog({
    super.key,
    required this.transfer,
    required this.isOutgoing,
    required this.peerName,
    this.peerAvatar,
    this.onAccept,
    this.onReject,
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
                          ? CachedNetworkImageProvider(ApiConfig.getMediaUrl(peerAvatar!))
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
                    isOutgoing ? '转账给 $peerName' : '来自 $peerName',
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
                    '¥${transfer.amount.toStringAsFixed(2)}',
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
                          foregroundColor: isDark ? Colors.white60 : Colors.grey[700],
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.grey[300]!,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('拒收'),
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
                        child: const Text('收款'),
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
                        _getStatusText(),
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

  String _getStatusText() {
    if (isOutgoing) {
      switch (transfer.status) {
        case TransferStatus.pending:
          return '待对方收款';
        case TransferStatus.accepted:
          return '对方已收款';
        case TransferStatus.rejected:
          return '已退还';
        case TransferStatus.expired:
          return '已过期退还';
      }
    } else {
      switch (transfer.status) {
        case TransferStatus.pending:
          return '待收款';
        case TransferStatus.accepted:
          return '已收款';
        case TransferStatus.rejected:
          return '已退还';
        case TransferStatus.expired:
          return '已过期';
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
    ),
  );
}
