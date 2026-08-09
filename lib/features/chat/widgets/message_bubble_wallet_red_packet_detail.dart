// 文件用途：提供 _RedPacketDetailSheet 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _RedPacketDetailSheet，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble wallet red packet detail 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class _RedPacketDetailSheet extends StatefulWidget {
  final RedPacketInfo redPacket;
  final bool isOutgoing;
  final String? senderAvatar;
  final bool isGroupChat;
  final String currency;

  const _RedPacketDetailSheet({
    required this.redPacket,
    required this.isOutgoing,
    this.senderAvatar,
    this.isGroupChat = false,
    required this.currency,
  });

  @override
  State<_RedPacketDetailSheet> createState() => _RedPacketDetailSheetState();
}

class _RedPacketDetailSheetState extends State<_RedPacketDetailSheet> {
  bool _isClaimed = false;
  bool _isClaiming = false;
  double _claimedAmount = 0;
  String? _errorMsg;
  RedPacketInfo? _latestRedPacket;
  RedPacketDetail? _detail;
  bool _isLoadingDetail = false;
  String? _detailError;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    // 先从服务器获取最新红包状态
    _fetchRedPacketDetail();
  }

  /// 创建已认证的 ApiClient
  Future<ApiClient> _createApiClient() async {
    final apiClient = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null) {
      apiClient.setToken(token);
    }
    return apiClient;
  }

  /// 从服务器获取红包最新状态
  Future<void> _fetchRedPacketDetail({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingDetail = true;
        _detailError = null;
      });
    }
    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response =
          await walletService.getRedPacketDetail(widget.redPacket.id);
      if (response.isSuccess && response.data != null && mounted) {
        setState(() {
          _detail = response.data;
          _latestRedPacket = response.data!.redPacket;
          _isClaimed = response.data!.redPacket.isClaimed;
          _claimedAmount = response.data!.redPacket.claimedAmount ?? 0;
          _isLoadingDetail = false;
          _detailError = null;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingDetail = false;
          _detailError = _localizedServerUiMessage(
            context,
            raw: response.message,
            zhCN: '红包详情加载失败',
            zhTW: '紅包詳情載入失敗',
            en: 'Failed to load red packet details',
          );
        });
      }
    } catch (e) {
      debugPrint('[RedPacket] Fetch detail error: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
          _detailError = _localizedUiText(
            context,
            zhCN: '红包详情加载失败',
            zhTW: '紅包詳情載入失敗',
            en: 'Failed to load red packet details',
          );
        });
      }
    }
  }

  Future<void> _claimRedPacket() async {
    if (_isClaiming || _isClaimed) return;

    setState(() {
      _isClaiming = true;
      _errorMsg = null;
    });

    try {
      final apiClient = await _createApiClient();
      final walletService = WalletService(apiClient);
      final response = await walletService.claimRedPacket(widget.redPacket.id);

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final amount = (response.data!['amount'] as num?)?.toDouble() ?? 0;
        setState(() {
          _isClaimed = true;
          _isClaiming = false;
          _claimedAmount = amount;
        });
        HapticFeedback.mediumImpact();
        await _fetchRedPacketDetail(showLoading: false);
      } else {
        setState(() {
          _isClaiming = false;
          _errorMsg = _localizedServerUiMessage(
            context,
            raw: response.message,
            zhCN: '领取失败',
            zhTW: '領取失敗',
            en: 'Failed to claim',
          );
        });
        _fetchRedPacketDetail();
      }
    } catch (e) {
      debugPrint('[RedPacket] Claim error: $e');
      if (mounted) {
        setState(() {
          _isClaiming = false;
          _errorMsg = _localizedUiText(
            context,
            zhCN: '领取失败，请重试',
            zhTW: '領取失敗，請重試',
            en: 'Failed to claim, please try again',
          );
        });
      }
    }
  }

  String _formatClaimTime(DateTime value) {
    final local = toCurrentLocalTime(value);
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return DateFormat(isToday ? 'HH:mm' : 'MM-dd HH:mm').format(local);
  }

  Widget _buildClaimItem(
    BuildContext context,
    RedPacketClaim claim,
    bool isDark,
  ) {
    final displayName = claim.userName.trim().isEmpty
        ? _localizedUiText(
            context,
            zhCN: '群成员',
            zhTW: '群成員',
            en: 'Member',
          )
        : claim.userName.trim();
    final avatarUrl = claim.userAvatar?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isDark ? Colors.white12 : const Color(0xFFFFE4E4),
            backgroundImage: avatarUrl.isNotEmpty
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? Text(
                    displayName.characters.first,
                    style: const TextStyle(
                      color: Color(0xFFDC4B4B),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    if (claim.isBest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1D6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _localizedUiText(
                            context,
                            zhCN: '手气最佳',
                            zhTW: '手氣最佳',
                            en: 'Luckiest',
                          ),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFC47A00),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _formatClaimTime(claim.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${widget.currency}${claim.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimState(
    BuildContext context, {
    required RedPacketInfo redPacket,
    required bool isSender,
  }) {
    if (_isClaimed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.currency}${_claimedAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _localizedUiText(
              context,
              zhCN: '已存入余额',
              zhTW: '已存入餘額',
              en: 'Added to balance',
            ),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.82),
            ),
          ),
        ],
      );
    }

    if (isSender && !widget.isGroupChat) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.currency}${redPacket.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _localizedUiText(
              context,
              zhCN: '已发出',
              zhTW: '已發出',
              en: 'Sent',
            ),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.82),
            ),
          ),
        ],
      );
    }

    if (redPacket.status == RedPacketStatus.finished ||
        redPacket.status == RedPacketStatus.expired) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          redPacket.status == RedPacketStatus.finished
              ? _localizedUiText(
                  context,
                  zhCN: '红包已被领完',
                  zhTW: '紅包已被領完',
                  en: 'Red packet fully claimed',
                )
              : _localizedUiText(
                  context,
                  zhCN: '红包已过期',
                  zhTW: '紅包已過期',
                  en: 'Red packet expired',
                ),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.88),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _isClaiming ? null : _claimRedPacket,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFD75E),
              border: Border.all(color: Colors.white38, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: _isClaiming
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF9B6A00)),
                      ),
                    )
                  : Text(
                      _localizedUiText(
                        context,
                        zhCN: '开',
                        zhTW: '開',
                        en: 'Open',
                      ),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9B6A00),
                      ),
                    ),
            ),
          ),
        ),
        if (_errorMsg != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMsg!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redPacket = _latestRedPacket ?? widget.redPacket;
    final isSender = _detail?.isSender ?? widget.isOutgoing;
    final mediaSize = MediaQuery.sizeOf(context);
    final claimedCount = _detail?.claimedCount ??
        (redPacket.totalCount - redPacket.remainingCount);
    final claimedTotal = _detail?.claimedTotalAmount ??
        (redPacket.totalAmount - redPacket.remainingAmount);
    final senderName = redPacket.senderName.trim().isEmpty
        ? _localizedUiText(
            context,
            zhCN: '好友',
            zhTW: '好友',
            en: 'Friend',
          )
        : redPacket.senderName.trim();
    final title = isSender
        ? (widget.isGroupChat
            ? _localizedUiText(
                context,
                zhCN: '我发出的群红包',
                zhTW: '我發出的群紅包',
                en: 'My Group Red Packet',
              )
            : _localizedUiText(
                context,
                zhCN: '我发出的红包',
                zhTW: '我發出的紅包',
                en: 'My Red Packet',
              ))
        : '$senderName${_localizedUiText(context, zhCN: '的红包', zhTW: '的紅包', en: '\'s red packet')}';
    final avatarPath = widget.senderAvatar?.trim().isNotEmpty == true
        ? widget.senderAvatar!.trim()
        : redPacket.senderAvatar?.trim() ?? '';

    return Container(
      height: math.min(mediaSize.height * 0.92, 820),
      decoration: BoxDecoration(
        color: const Color(0xFFF45B52),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(0, -0.35),
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.58),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 8,
                  child: IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.32),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: Colors.white.withOpacity(0.18),
                    backgroundImage: avatarPath.isNotEmpty
                        ? CachedNetworkImageProvider(
                            ApiConfig.getMediaUrl(avatarPath),
                          )
                        : null,
                    child: avatarPath.isEmpty
                        ? Text(
                            senderName.characters.first,
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  redPacket.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.82),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildClaimState(
            context,
            redPacket: redPacket,
            isSender: isSender,
          ),
          const SizedBox(height: 18),

          // 底部信息
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: RefreshIndicator(
                  onRefresh: _fetchRedPacketDetail,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _localizedUiText(
                                context,
                                zhCN:
                                    '已领取 $claimedCount/${redPacket.totalCount} 个，共 ${widget.currency}${claimedTotal.toStringAsFixed(2)}',
                                zhTW:
                                    '已領取 $claimedCount/${redPacket.totalCount} 個，共 ${widget.currency}${claimedTotal.toStringAsFixed(2)}',
                                en: '$claimedCount/${redPacket.totalCount} claimed, ${widget.currency}${claimedTotal.toStringAsFixed(2)} total',
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    isDark ? Colors.white54 : Colors.grey[600],
                              ),
                            ),
                          ),
                          if (redPacket.type == RedPacketType.lucky)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF2D8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _localizedUiText(
                                  context,
                                  zhCN: '拼手气红包',
                                  zhTW: '拼手氣紅包',
                                  en: 'Lucky packet',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFC58A24),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      if (_isLoadingDetail) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ] else if (_detailError != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: _fetchRedPacketDetail,
                              icon: const Icon(Icons.refresh),
                              label: Text(_detailError!),
                            ),
                          ),
                        ),
                      ] else if ((_detail?.claims ?? const <RedPacketClaim>[])
                          .isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              _localizedUiText(
                                context,
                                zhCN: '暂时无人领取',
                                zhTW: '暫時無人領取',
                                en: 'No claims yet',
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    isDark ? Colors.white38 : Colors.grey[500],
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        for (final claim in _detail!.claims) ...[
                          _buildClaimItem(context, claim, isDark),
                          if (claim != _detail!.claims.last)
                            Divider(
                              height: 1,
                              indent: 52,
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                        ],
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
