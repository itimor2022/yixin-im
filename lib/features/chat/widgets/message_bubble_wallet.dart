// 文件用途：提供 _MessageBubbleWalletEntry 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleWalletEntry，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble wallet 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleWalletEntry on MessageBubble {
  /// 构建红包消息气泡（带实时状态）
  Widget _buildRedPacketBubble(
    BuildContext context,
    bool isOutgoing,
    bool isGroupChat,
  ) {
    RedPacketInfo? redPacket;
    try {
      final content = message.content;
      if (content.startsWith('{')) {
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        redPacket = RedPacketInfo.fromJson(jsonData);
      }
    } catch (e) {
      debugPrint('[RedPacket] Parse error: $e');
    }

    redPacket ??= RedPacketInfo(
      id: message.id,
      senderId: message.senderId,
      senderName: '',
      chatId: '',
      type: RedPacketType.normal,
      totalAmount: 0,
      totalCount: 1,
      remainingAmount: 0,
      remainingCount: 0,
      message: AppLocalizations.of(context).get('best_wishes_and_good_luck'),
      status: RedPacketStatus.active,
      isClaimed: false,
      createdAt: message.createdAt,
    );

    return _LiveRedPacketBubble(
      messageId: message.id,
      redPacket: redPacket,
      isOutgoing: isOutgoing,
      senderAvatar: message.senderAvatar,
      isGroupChat: isGroupChat,
    );
  }

  /// 构建转账消息气泡（带实时状态）
  Widget _buildTransferBubble(
    BuildContext context,
    bool isOutgoing,
    bool isDark,
  ) {
    TransferInfo? transfer;
    try {
      final content = message.content;
      if (content.startsWith('{')) {
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        transfer = TransferInfo.fromJson(jsonData);
      }
    } catch (e) {
      debugPrint('[Transfer] Parse error: $e');
    }

    transfer ??= TransferInfo(
      id: message.id,
      senderId: message.senderId,
      senderName: '',
      receiverId: '',
      receiverName: '',
      amount: 0,
      status: TransferStatus.pending,
      createdAt: message.createdAt,
    );

    return _LiveTransferBubble(
      messageId: message.id,
      transfer: transfer,
      isOutgoing: isOutgoing,
      senderAvatar: message.senderAvatar,
    );
  }
}

class WalletStatusCache {
  static final WalletStatusCache _instance = WalletStatusCache._();
  static WalletStatusCache get instance => _instance;
  WalletStatusCache._();

  // 内存缓存
  final Map<String, String> _rpCache = {}; // red_packet_id -> JSON
  final Map<String, String> _tfCache = {}; // transfer_id -> JSON
  String _accountId = '';
  int _generation = 0;

  int get generation => _generation;

  bool isGenerationCurrent(int generation) {
    return _accountId.isNotEmpty && generation == _generation;
  }

  void activateAccount(String accountId) {
    if (accountId.isEmpty || accountId == _accountId) return;
    _accountId = accountId;
    _generation++;
    _rpCache.clear();
    _tfCache.clear();
  }

  void freezeAccount(String accountId) {
    if (accountId.isNotEmpty && accountId != _accountId) return;
    _accountId = '';
    _generation++;
    _rpCache.clear();
    _tfCache.clear();
  }

  String? _storageKey(String prefix, String id) {
    if (_accountId.isEmpty) return null;
    final accountHash = sha256.convert(utf8.encode(_accountId));
    return 'acct_v1_${accountHash}_${prefix}_$id';
  }

  /// 缓存红包状态
  void cacheRedPacket(RedPacketInfo data, {required int generation}) {
    if (!isGenerationCurrent(generation)) return;
    final storageKey = _storageKey('rp_status', data.id);
    if (storageKey == null) return;
    final capturedGeneration = generation;
    final json = jsonEncode(data.toJson());
    _rpCache[data.id] = json;
    // 异步写 SharedPreferences（不阻塞）
    SharedPreferences.getInstance().then((prefs) {
      if (capturedGeneration == _generation && _accountId.isNotEmpty) {
        prefs.setString(storageKey, json);
      }
    });
  }

  /// 获取缓存的红包状态（内存优先，再查 SharedPreferences）
  RedPacketInfo? getCachedRedPacket(
    String rpId, {
    required int generation,
  }) {
    if (!isGenerationCurrent(generation)) return null;
    final mem = _rpCache[rpId];
    if (mem != null) {
      try {
        return RedPacketInfo.fromJson(jsonDecode(mem));
      } catch (_) {}
    }
    return null;
  }

  /// 异步获取（含 SharedPreferences）
  Future<RedPacketInfo?> getCachedRedPacketAsync(
    String rpId, {
    required int generation,
  }) async {
    if (!isGenerationCurrent(generation)) return null;
    final storageKey = _storageKey('rp_status', rpId);
    if (storageKey == null) return null;
    // 先查内存
    final cached = getCachedRedPacket(rpId, generation: generation);
    if (cached != null) return cached;
    // 再查磁盘
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation || _accountId.isEmpty) return null;
      final json = prefs.getString(storageKey);
      if (json != null && generation == _generation) {
        final data = RedPacketInfo.fromJson(jsonDecode(json));
        _rpCache[rpId] = json; // 回填内存
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// 缓存转账状态
  void cacheTransfer(TransferInfo data, {required int generation}) {
    if (!isGenerationCurrent(generation)) return;
    final storageKey = _storageKey('tf_status', data.id);
    if (storageKey == null) return;
    final capturedGeneration = generation;
    final json = jsonEncode(data.toJson());
    _tfCache[data.id] = json;
    SharedPreferences.getInstance().then((prefs) {
      if (capturedGeneration == _generation && _accountId.isNotEmpty) {
        prefs.setString(storageKey, json);
      }
    });
  }

  /// 获取缓存的转账状态
  TransferInfo? getCachedTransfer(
    String tfId, {
    required int generation,
  }) {
    if (!isGenerationCurrent(generation)) return null;
    final mem = _tfCache[tfId];
    if (mem != null) {
      try {
        return TransferInfo.fromJson(jsonDecode(mem));
      } catch (_) {}
    }
    return null;
  }

  Future<TransferInfo?> getCachedTransferAsync(
    String tfId, {
    required int generation,
  }) async {
    if (!isGenerationCurrent(generation)) return null;
    final storageKey = _storageKey('tf_status', tfId);
    if (storageKey == null) return null;
    final cached = getCachedTransfer(tfId, generation: generation);
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation || _accountId.isEmpty) return null;
      final json = prefs.getString(storageKey);
      if (json != null && generation == _generation) {
        final data = TransferInfo.fromJson(jsonDecode(json));
        _tfCache[tfId] = json;
        return data;
      }
    } catch (_) {}
    return null;
  }
}

class WalletBubbleRefreshNotifier extends ChangeNotifier {
  static final WalletBubbleRefreshNotifier _instance =
      WalletBubbleRefreshNotifier._();
  static WalletBubbleRefreshNotifier get instance => _instance;
  WalletBubbleRefreshNotifier._();

  /// 触发所有可见气泡刷新
  void refresh() {
    notifyListeners();
  }
}

class _LiveRedPacketBubble extends ConsumerStatefulWidget {
  final String messageId;
  final RedPacketInfo redPacket;
  final bool isOutgoing;
  final String? senderAvatar;
  final bool isGroupChat;

  const _LiveRedPacketBubble({
    required this.messageId,
    required this.redPacket,
    required this.isOutgoing,
    this.senderAvatar,
    this.isGroupChat = false,
  });

  @override
  ConsumerState<_LiveRedPacketBubble> createState() =>
      _LiveRedPacketBubbleState();
}

class _LiveRedPacketBubbleState extends ConsumerState<_LiveRedPacketBubble> {
  RedPacketInfo? _liveData;
  bool _fetching = false;
  late final int _cacheGeneration;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _cacheGeneration = WalletStatusCache.instance.generation;
    _loadCachedThenFetch();
    WalletBubbleRefreshNotifier.instance.addListener(_onGlobalRefresh);
  }

  @override
  void dispose() {
    WalletBubbleRefreshNotifier.instance.removeListener(_onGlobalRefresh);
    super.dispose();
  }

  /// 先从缓存加载（秒级命中），再决定是否需要网络请求
  Future<void> _loadCachedThenFetch() async {
    // 1. 同步读内存缓存
    final memCached = WalletStatusCache.instance.getCachedRedPacket(
      widget.redPacket.id,
      generation: _cacheGeneration,
    );
    if (memCached != null && mounted) {
      setState(() => _liveData = memCached);
      // 已终态（finished/expired），不再发 API
      if (memCached.status != RedPacketStatus.active) return;
    }
    // 2. 异步读 SharedPreferences
    if (_liveData == null) {
      final diskCached =
          await WalletStatusCache.instance.getCachedRedPacketAsync(
        widget.redPacket.id,
        generation: _cacheGeneration,
      );
      if (diskCached != null && mounted) {
        setState(() => _liveData = diskCached);
        if (diskCached.status != RedPacketStatus.active) return;
      }
    }
    // 3. 仍是 active（或无缓存），延迟拉取最新状态
    final current = _liveData ?? widget.redPacket;
    if (current.status == RedPacketStatus.active) {
      final delay = 200 + (widget.redPacket.id.hashCode % 800).abs();
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _fetchStatus();
      });
    }
  }

  void _onGlobalRefresh() {
    final current = _liveData ?? widget.redPacket;
    if (current.status == RedPacketStatus.active) {
      _fetchStatus();
    }
  }

  Future<void> _fetchStatus() async {
    if (_fetching) return;
    if (!WalletStatusCache.instance.isGenerationCurrent(_cacheGeneration)) {
      return;
    }
    _fetching = true;
    try {
      final apiClient = ApiClient();
      final token = await TokenStorage.getToken();
      if (token != null) apiClient.setToken(token);
      final svc = WalletService(apiClient);
      final resp = await svc.getRedPacket(widget.redPacket.id);
      if (resp.isSuccess &&
          resp.data != null &&
          mounted &&
          WalletStatusCache.instance.isGenerationCurrent(_cacheGeneration)) {
        final newData = resp.data!;
        setState(() => _liveData = newData);
        // 持久化到独立缓存（不写 Isar 消息 content，因为会被服务器数据覆盖）
        WalletStatusCache.instance.cacheRedPacket(
          newData,
          generation: _cacheGeneration,
        );
      }
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  void _showDetail() async {
    final currency = ref.read(walletCurrencyProvider);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedPacketDetailSheet(
        redPacket: _liveData ?? widget.redPacket,
        isOutgoing: widget.isOutgoing,
        senderAvatar: widget.senderAvatar,
        isGroupChat: widget.isGroupChat,
        currency: currency,
      ),
    );
    _fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    final rp = _liveData ?? widget.redPacket;
    final currency = ref.watch(walletCurrencyProvider);
    return RedPacketBubble(
      redPacket: rp,
      isOutgoing: widget.isOutgoing,
      onTap: _showDetail,
      currency: currency,
    );
  }
}

/// 转账气泡 — 自动拉取最新状态 + 实时刷新 + 本地持久化
class _LiveTransferBubble extends ConsumerStatefulWidget {
  final String messageId;
  final TransferInfo transfer;
  final bool isOutgoing;
  final String? senderAvatar;

  const _LiveTransferBubble({
    required this.messageId,
    required this.transfer,
    required this.isOutgoing,
    this.senderAvatar,
  });

  @override
  ConsumerState<_LiveTransferBubble> createState() =>
      _LiveTransferBubbleState();
}

class _LiveTransferBubbleState extends ConsumerState<_LiveTransferBubble> {
  TransferInfo? _liveData;
  bool _fetching = false;
  late final int _cacheGeneration;

  @override
  void initState() {
    super.initState();
    _cacheGeneration = WalletStatusCache.instance.generation;
    _loadCachedThenFetch();
    WalletBubbleRefreshNotifier.instance.addListener(_onGlobalRefresh);
  }

  @override
  void dispose() {
    WalletBubbleRefreshNotifier.instance.removeListener(_onGlobalRefresh);
    super.dispose();
  }

  Future<void> _loadCachedThenFetch() async {
    final memCached = WalletStatusCache.instance.getCachedTransfer(
      widget.transfer.id,
      generation: _cacheGeneration,
    );
    if (memCached != null && mounted) {
      setState(() => _liveData = memCached);
      if (memCached.status != TransferStatus.pending) return;
    }
    if (_liveData == null) {
      final diskCached =
          await WalletStatusCache.instance.getCachedTransferAsync(
        widget.transfer.id,
        generation: _cacheGeneration,
      );
      if (diskCached != null && mounted) {
        setState(() => _liveData = diskCached);
        if (diskCached.status != TransferStatus.pending) return;
      }
    }
    final current = _liveData ?? widget.transfer;
    if (current.status == TransferStatus.pending) {
      final delay = 200 + (widget.transfer.id.hashCode % 800).abs();
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _fetchStatus();
      });
    }
  }

  void _onGlobalRefresh() {
    final current = _liveData ?? widget.transfer;
    if (current.status == TransferStatus.pending) {
      _fetchStatus();
    }
  }

  Future<void> _fetchStatus() async {
    if (_fetching) return;
    if (!WalletStatusCache.instance.isGenerationCurrent(_cacheGeneration)) {
      return;
    }
    _fetching = true;
    try {
      final apiClient = ApiClient();
      final token = await TokenStorage.getToken();
      if (token != null) apiClient.setToken(token);
      final svc = WalletService(apiClient);
      final resp = await svc.getTransfer(widget.transfer.id);
      if (resp.isSuccess &&
          resp.data != null &&
          mounted &&
          WalletStatusCache.instance.isGenerationCurrent(_cacheGeneration)) {
        final newData = resp.data!;
        setState(() => _liveData = newData);
        WalletStatusCache.instance.cacheTransfer(
          newData,
          generation: _cacheGeneration,
        );
      }
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  void _showDetail() async {
    final currency = ref.read(walletCurrencyProvider);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransferDetailSheet(
        transfer: _liveData ?? widget.transfer,
        isOutgoing: widget.isOutgoing,
        senderAvatar: widget.senderAvatar,
        currency: currency,
      ),
    );
    _fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    final tf = _liveData ?? widget.transfer;
    final currency = ref.watch(walletCurrencyProvider);
    return TransferBubble(
      transfer: tf,
      isOutgoing: widget.isOutgoing,
      onTap: _showDetail,
      currency: currency,
    );
  }
}
