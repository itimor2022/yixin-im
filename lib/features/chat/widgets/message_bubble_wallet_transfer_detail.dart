// 文件用途：提供 _TransferDetailSheet 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _TransferDetailSheet，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble wallet transfer detail 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 转账详情 Sheet — 微信风格
class _TransferDetailSheet extends StatefulWidget {
  final TransferInfo transfer;
  final bool isOutgoing;
  final String? senderAvatar;
  final String currency;

  const _TransferDetailSheet({
    required this.transfer,
    required this.isOutgoing,
    this.senderAvatar,
    required this.currency,
  });

  @override
  State<_TransferDetailSheet> createState() => _TransferDetailSheetState();
}

class _TransferDetailSheetState extends State<_TransferDetailSheet> {
  bool _isAccepted = false;
  bool _isAccepting = false;
  bool _isRejected = false;
  String? _errorMsg;
  TransferInfo? _latestTransfer;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _isAccepted = widget.transfer.status == TransferStatus.accepted;
    _isRejected = widget.transfer.status == TransferStatus.rejected;
    _fetchTransferDetail();
  }

  Future<ApiClient> _createApiClient() async {
    final apiClient = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null) apiClient.setToken(token);
    return apiClient;
  }

  Future<void> _fetchTransferDetail() async {
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.getTransfer(widget.transfer.id);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _latestTransfer = response.data;
          _isAccepted = response.data!.status == TransferStatus.accepted;
          _isRejected = response.data!.status == TransferStatus.rejected;
        });
      }
    } catch (e) {
      debugPrint('[Transfer] Fetch detail error: $e');
    }
  }

  Future<void> _acceptTransfer() async {
    if (_isAccepting || _isAccepted) return;
    setState(() {
      _isAccepting = true;
      _errorMsg = null;
    });
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.acceptTransfer(widget.transfer.id);
      if (!mounted) return;
      if (response.isSuccess) {
        setState(() {
          _isAccepted = true;
          _isAccepting = false;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() {
          _isAccepting = false;
          _errorMsg = _localizedServerUiMessage(
            context,
            raw: response.message,
            zhCN: '收款失败',
            zhTW: '收款失敗',
            en: 'Failed to accept transfer',
          );
        });
        _fetchTransferDetail();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isAccepting = false;
          _errorMsg = _localizedUiText(
            context,
            zhCN: '收款失败',
            zhTW: '收款失敗',
            en: 'Failed to accept transfer',
          );
        });
    }
  }

  Future<void> _rejectTransfer() async {
    if (_isAccepting || _isAccepted || _isRejected) return;
    setState(() {
      _isAccepting = true;
      _errorMsg = null;
    });
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.rejectTransfer(widget.transfer.id);
      if (!mounted) return;
      if (response.isSuccess) {
        setState(() {
          _isRejected = true;
          _isAccepting = false;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() {
          _isAccepting = false;
          _errorMsg = _localizedServerUiMessage(
            context,
            raw: response.message,
            zhCN: '退还失败',
            zhTW: '退還失敗',
            en: 'Failed to return transfer',
          );
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isAccepting = false;
          _errorMsg = _localizedUiText(
            context,
            zhCN: '退还失败',
            zhTW: '退還失敗',
            en: 'Failed to return transfer',
          );
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final transfer = _latestTransfer ?? widget.transfer;
    final isPending = !_isAccepted &&
        !_isRejected &&
        transfer.status == TransferStatus.pending;
    final isExpired = transfer.status == TransferStatus.expired;

    const txOrange = Color(0xFFFFA940);
    const txGreen = Color(0xFF07C160);

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 顶部彩色头
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isAccepted
                    ? [txGreen, const Color(0xFF06AD56)]
                    : [txOrange, const Color(0xFFE69330)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // 拖拽条 + 关闭
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.7),
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 图标
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/stickers/zhuanzhang.png',
                      width: 36,
                      height: 36,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.payments_outlined,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 金额
                Text(
                  '${widget.currency}${transfer.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                // 描述
                Text(
                  widget.isOutgoing
                      ? '${_localizedUiText(context, zhCN: '转账给', zhTW: '轉帳給', en: 'Transfer to ')}${transfer.receiverName.isNotEmpty ? transfer.receiverName : _localizedUiText(context, zhCN: '好友', zhTW: '好友', en: 'Friend')}'
                      : '${_localizedUiText(context, zhCN: '来自', zhTW: '來自', en: 'Transfer from ')}${transfer.senderName.isNotEmpty ? transfer.senderName : _localizedUiText(context, zhCN: '好友', zhTW: '好友', en: 'Friend')}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          // 详情
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _row(
                    isDark,
                    _localizedUiText(
                      context,
                      zhCN: '当前状态',
                      zhTW: '目前狀態',
                      en: 'Status',
                    ),
                    _isAccepted
                        ? _localizedUiText(
                            context,
                            zhCN: '已收款',
                            zhTW: '已收款',
                            en: 'Received',
                          )
                        : _isRejected
                            ? _localizedUiText(
                                context,
                                zhCN: '已退还',
                                zhTW: '已退還',
                                en: 'Returned',
                              )
                            : isExpired
                                ? _localizedUiText(
                                    context,
                                    zhCN: '已过期',
                                    zhTW: '已過期',
                                    en: 'Expired',
                                  )
                                : _localizedUiText(
                                    context,
                                    zhCN: '待收款',
                                    zhTW: '待收款',
                                    en: 'Pending',
                                  ),
                    color: _isAccepted
                        ? txGreen
                        : _isRejected
                            ? Colors.red
                            : isPending
                                ? txOrange
                                : Colors.grey,
                  ),
                  _div(isDark),
                  if (transfer.remark?.isNotEmpty == true) ...[
                    _row(
                      isDark,
                      _localizedUiText(
                        context,
                        zhCN: '转账说明',
                        zhTW: '轉帳說明',
                        en: 'Transfer Note',
                      ),
                      transfer.remark!,
                    ),
                    _div(isDark),
                  ],
                  _row(
                    isDark,
                    _localizedUiText(
                      context,
                      zhCN: '转账时间',
                      zhTW: '轉帳時間',
                      en: 'Transfer Time',
                    ),
                    DateFormat('yyyy-MM-dd HH:mm')
                        .format(toCurrentLocalTime(transfer.createdAt)),
                  ),
                  _div(isDark),
                  _row(
                    isDark,
                    _localizedUiText(
                      context,
                      zhCN: '转账单号',
                      zhTW: '轉帳單號',
                      en: 'Transfer ID',
                    ),
                    transfer.id.length > 16
                        ? '${transfer.id.substring(0, 16)}...'
                        : transfer.id,
                  ),
                  if (_errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  const Spacer(),
                  // 底部按钮
                  if (!widget.isOutgoing && isPending) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _isAccepting ? null : _rejectTransfer,
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    isDark ? Colors.white60 : Colors.grey[700],
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.grey[300]!,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: Text(
                                _localizedUiText(
                                  context,
                                  zhCN: '退还',
                                  zhTW: '退還',
                                  en: 'Return',
                                ),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isAccepting ? null : _acceptTransfer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: txGreen,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: _isAccepting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      _localizedUiText(
                                        context,
                                        zhCN: '确认收款',
                                        zhTW: '確認收款',
                                        en: 'Accept Transfer',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_isAccepted) ...[
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: txGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: txGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_localizedUiText(context, zhCN: '已收款', zhTW: '已收款', en: 'Received')} ${widget.currency}${transfer.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: txGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(bool dark, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: dark ? Colors.white54 : Colors.grey[600],
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color ?? (dark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      );
  Widget _div(bool dark) =>
      Divider(height: 1, color: dark ? Colors.white10 : Colors.grey[200]);
}
