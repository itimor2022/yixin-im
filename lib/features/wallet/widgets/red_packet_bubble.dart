// 文件用途：提供 RedPacketBubble 可复用界面组件，服务于钱包与支付。
// 核心逻辑：根据输入模型和状态渲染 RedPacketBubble，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart' show ApiConfig;
import '../services/wallet_service.dart';

String _redPacketText(
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

// 关键声明：red packet bubble 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 红包消息气泡 - 仿微信简洁风格
class RedPacketBubble extends StatelessWidget {
  final RedPacketInfo redPacket;
  final bool isOutgoing;
  final VoidCallback? onTap;
  final String currency;

  const RedPacketBubble({
    super.key,
    required this.redPacket,
    required this.isOutgoing,
    this.onTap,
    this.currency = '¥',
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = redPacket.status == RedPacketStatus.expired;
    final isClaimed = redPacket.isClaimed;
    final isFinished = redPacket.status == RedPacketStatus.finished;
    final isActive = !isExpired && !isFinished;

    // 红包颜色 — 始终保持红色，只通过文字区分状态
    final primaryColor =
        isExpired ? const Color(0xFFBEBEBE) : const Color(0xFFE84C3D);
    final secondaryColor =
        isExpired ? const Color(0xFF9E9E9E) : const Color(0xFFC0392B);

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
              color: primaryColor.withOpacity(0.2),
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
                  colors: [primaryColor, secondaryColor],
                ),
              ),
              child: Row(
                children: [
                  // 红包图标
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/stickers/hongbao.png',
                        width: 28,
                        height: 28,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.redeem,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 祝福语
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          redPacket.message,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getStatusText(context),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.75),
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
                color: isActive
                    ? const Color(0xFFD4433E)
                    : const Color(0xFF8E8E8E),
              ),
              child: Row(
                children: [
                  Text(
                    _redPacketText(
                      context,
                      zhCN: '红包',
                      zhTW: '紅包',
                      en: 'Red packet',
                    ),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const Spacer(),
                  if (isClaimed && redPacket.claimedAmount != null)
                    Text(
                      '$currency${redPacket.claimedAmount!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(BuildContext context) {
    if (redPacket.isClaimed) {
      return _redPacketText(
        context,
        zhCN: '已领取',
        zhTW: '已領取',
        en: 'Claimed',
      );
    }
    switch (redPacket.status) {
      case RedPacketStatus.active:
        return _redPacketText(
          context,
          zhCN: '领取红包',
          zhTW: '領取紅包',
          en: 'Claim red packet',
        );
      case RedPacketStatus.expired:
        return _redPacketText(
          context,
          zhCN: '已过期',
          zhTW: '已過期',
          en: 'Expired',
        );
      case RedPacketStatus.finished:
        return _redPacketText(
          context,
          zhCN: '已领完',
          zhTW: '已領完',
          en: 'Fully claimed',
        );
    }
  }
}

/// 开红包弹窗
class OpenRedPacketDialog extends StatefulWidget {
  final RedPacketInfo redPacket;
  final String senderName;
  final String? senderAvatar;
  final Future<double?> Function() onOpen;
  final String currency;

  const OpenRedPacketDialog({
    super.key,
    required this.redPacket,
    required this.senderName,
    this.senderAvatar,
    required this.onOpen,
    this.currency = '¥',
  });

  @override
  State<OpenRedPacketDialog> createState() => _OpenRedPacketDialogState();
}

class _OpenRedPacketDialogState extends State<OpenRedPacketDialog>
    with TickerProviderStateMixin {
  bool _isOpening = false;
  bool _isOpened = false;
  double? _amount;
  late AnimationController _pulseController;
  late AnimationController _openController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _openScaleAnimation;
  late Animation<double> _amountScaleAnimation;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _openController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _openScaleAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _openController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _amountScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _openController,
        curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _openController.dispose();
    super.dispose();
  }

  Future<void> _openRedPacket() async {
    if (_isOpening || _isOpened) return;

    HapticFeedback.heavyImpact();
    setState(() => _isOpening = true);

    final amount = await widget.onOpen();

    if (amount != null) {
      setState(() {
        _amount = amount;
        _isOpened = true;
      });
      _openController.forward();
      HapticFeedback.mediumImpact();
    } else {
      setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE84C3D), Color(0xFFC0392B)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 关闭按钮
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(_amount),
                  child: Icon(
                    Icons.close,
                    color: Colors.white.withOpacity(0.6),
                    size: 24,
                  ),
                ),
              ),
            ),

            // 发送者头像
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                backgroundImage: widget.senderAvatar?.isNotEmpty == true
                    ? CachedNetworkImageProvider(
                        ApiConfig.getMediaUrl(widget.senderAvatar!))
                    : null,
                child: widget.senderAvatar?.isNotEmpty != true
                    ? Text(
                        widget.senderName.isNotEmpty
                            ? widget.senderName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),

            const SizedBox(height: 12),

            // 发送者名称
            Text(
              _redPacketText(
                context,
                zhCN: '${widget.senderName}的红包',
                zhTW: '${widget.senderName}的紅包',
                en: '${widget.senderName}\'s red packet',
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 8),

            // 祝福语
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.redPacket.message,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.85),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 32),

            // 开红包按钮或金额显示
            SizedBox(
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 金额显示
                  AnimatedBuilder(
                    animation: _amountScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _amountScaleAnimation.value,
                        child: Opacity(
                          opacity: _isOpened ? 1.0 : 0.0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${widget.currency}${(_amount ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFFD700),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _redPacketText(
                                  context,
                                  zhCN: '已存入余额',
                                  zhTW: '已存入餘額',
                                  en: 'Added to balance',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // 开红包按钮
                  AnimatedBuilder(
                    animation: _openScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isOpened ? _openScaleAnimation.value : 1.0,
                        child: Opacity(
                          opacity: _isOpened ? 0.0 : 1.0,
                          child: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale:
                                    _isOpening ? 0.95 : _pulseAnimation.value,
                                child: GestureDetector(
                                  onTap: _openRedPacket,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFD700),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFFD700)
                                              .withOpacity(0.4),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: _isOpening
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                  Color(0xFFC0392B),
                                                ),
                                              ),
                                            )
                                          : Text(
                                              _redPacketText(
                                                context,
                                                zhCN: '开',
                                                zhTW: '開',
                                                en: 'Open',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFC0392B),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 底部装饰
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Text(
                  _redPacketText(
                    context,
                    zhCN: '红包',
                    zhTW: '紅包',
                    en: 'Red packet',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 显示开红包弹窗
Future<double?> showOpenRedPacketDialog(
  BuildContext context, {
  required RedPacketInfo redPacket,
  required String senderName,
  String? senderAvatar,
  required Future<double?> Function() onOpen,
  String currency = '¥',
}) {
  return showDialog<double?>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (context) => OpenRedPacketDialog(
      redPacket: redPacket,
      senderName: senderName,
      senderAvatar: senderAvatar,
      onOpen: onOpen,
      currency: currency,
    ),
  );
}
