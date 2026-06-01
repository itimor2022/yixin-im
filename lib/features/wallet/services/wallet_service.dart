import 'package:flutter/foundation.dart';
import '../../../core/services/api/api_client.dart';

/// 钱包信息
class WalletInfo {
  final int id;
  final double balance;
  final double frozenBalance;
  final bool hasPayPassword;
  final bool isLocked;
  final DateTime createdAt;

  const WalletInfo({
    required this.id,
    required this.balance,
    required this.frozenBalance,
    required this.hasPayPassword,
    required this.isLocked,
    required this.createdAt,
  });

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    return WalletInfo(
      id: json['id'] as int? ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      frozenBalance: (json['frozen_balance'] as num?)?.toDouble() ?? 0.0,
      hasPayPassword: json['has_pay_password'] as bool? ?? false,
      isLocked: json['is_locked'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// 交易类型
enum TransactionType {
  recharge, // 充值
  withdraw, // 提现
  transferOut, // 转出
  transferIn, // 转入
  redPacketSend, // 发红包
  redPacketReceive, // 收红包
  refund, // 退款
  adminRecharge, // 管理员充值
  adminDeduct, // 管理员扣减
  rechargeRejected, // 充值被拒绝
  unknown, // 未知类型（防止新增类型时崩溃或误显示）
}

extension TransactionTypeExtension on TransactionType {
  String get value {
    switch (this) {
      case TransactionType.recharge:
        return 'recharge';
      case TransactionType.withdraw:
        return 'withdraw';
      case TransactionType.transferOut:
        return 'transfer_out';
      case TransactionType.transferIn:
        return 'transfer_in';
      case TransactionType.redPacketSend:
        return 'red_packet_send';
      case TransactionType.redPacketReceive:
        return 'red_packet_receive';
      case TransactionType.refund:
        return 'refund';
      case TransactionType.adminRecharge:
        return 'admin_recharge';
      case TransactionType.adminDeduct:
        return 'admin_deduct';
      case TransactionType.rechargeRejected:
        return 'recharge_rejected';
      case TransactionType.unknown:
        return 'unknown';
    }
  }

  static TransactionType fromString(String value) {
    switch (value) {
      case 'recharge':
        return TransactionType.recharge;
      case 'withdraw':
        return TransactionType.withdraw;
      case 'transfer_out':
        return TransactionType.transferOut;
      case 'transfer_in':
        return TransactionType.transferIn;
      case 'red_packet_send':
        return TransactionType.redPacketSend;
      case 'red_packet_receive':
        return TransactionType.redPacketReceive;
      case 'refund':
        return TransactionType.refund;
      case 'admin_recharge':
        return TransactionType.adminRecharge;
      case 'admin_deduct':
        return TransactionType.adminDeduct;
      case 'recharge_rejected':
        return TransactionType.rechargeRejected;
      default:
        if (kDebugMode) debugPrint('[Wallet] Unknown transaction type: $value');
        return TransactionType.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case TransactionType.recharge:
        return '充值';
      case TransactionType.withdraw:
        return '提现';
      case TransactionType.transferOut:
        return '转账-转出';
      case TransactionType.transferIn:
        return '转账-转入';
      case TransactionType.redPacketSend:
        return '发出红包';
      case TransactionType.redPacketReceive:
        return '收到红包';
      case TransactionType.refund:
        return '退款';
      case TransactionType.adminRecharge:
        return '系统充值';
      case TransactionType.adminDeduct:
        return '系统扣减';
      case TransactionType.rechargeRejected:
        return '充值被拒绝';
      case TransactionType.unknown:
        return '未知类型';
    }
  }
}

/// 交易记录
class Transaction {
  final int id;
  final TransactionType type;
  final double amount;
  final double balanceAfter;
  final String? relatedId;
  final String? relatedUserId;
  final String? relatedUserName;
  final String? relatedUserAvatar;
  final String? remark;
  final DateTime createdAt;

  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.relatedId,
    this.relatedUserId,
    this.relatedUserName,
    this.relatedUserAvatar,
    this.remark,
    required this.createdAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // 处理 related_user 对象
    final relatedUser = json['related_user'] as Map<String, dynamic>?;

    return Transaction(
      id: json['id'] as int? ?? 0,
      type: TransactionTypeExtension.fromString(json['type'] as String? ?? ''),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0.0,
      relatedId: json['related_id'] as String?,
      relatedUserId: relatedUser?['id'] as String?,
      relatedUserName: relatedUser?['nickname'] as String?,
      relatedUserAvatar: relatedUser?['avatar'] as String?,
      remark: json['remark'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// 是否是收入
  bool get isIncome =>
      type == TransactionType.recharge ||
      type == TransactionType.transferIn ||
      type == TransactionType.redPacketReceive ||
      type == TransactionType.refund ||
      type == TransactionType.adminRecharge;
}

/// 红包类型
enum RedPacketType {
  normal, // 普通红包
  lucky, // 拼手气红包
}

extension RedPacketTypeExtension on RedPacketType {
  String get value => this == RedPacketType.normal ? 'normal' : 'lucky';

  static RedPacketType fromString(String value) {
    return value == 'lucky' ? RedPacketType.lucky : RedPacketType.normal;
  }

  String get displayName => this == RedPacketType.normal ? '普通红包' : '拼手气红包';
}

/// 红包状态
enum RedPacketStatus {
  active, // 可领取
  finished, // 已抢完
  expired, // 已过期
}

extension RedPacketStatusExtension on RedPacketStatus {
  String get value {
    switch (this) {
      case RedPacketStatus.active:
        return 'active';
      case RedPacketStatus.finished:
        return 'finished';
      case RedPacketStatus.expired:
        return 'expired';
    }
  }

  static RedPacketStatus fromString(String value) {
    switch (value) {
      case 'finished':
        return RedPacketStatus.finished;
      case 'expired':
        return RedPacketStatus.expired;
      default:
        return RedPacketStatus.active;
    }
  }
}

/// 红包信息
class RedPacketInfo {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String chatId;
  final RedPacketType type;
  final double totalAmount;
  final int totalCount;
  final double remainingAmount;
  final int remainingCount;
  final String message;
  final RedPacketStatus status;
  final bool isClaimed;
  final double? claimedAmount;
  final DateTime? expiredAt;
  final DateTime createdAt;

  const RedPacketInfo({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.chatId,
    required this.type,
    required this.totalAmount,
    required this.totalCount,
    required this.remainingAmount,
    required this.remainingCount,
    required this.message,
    required this.status,
    required this.isClaimed,
    this.claimedAmount,
    this.expiredAt,
    required this.createdAt,
  });

  factory RedPacketInfo.fromJson(Map<String, dynamic> json) {
    final senderAvatar =
        ApiConfig.getMediaUrl(json['sender_avatar']?.toString());
    return RedPacketInfo(
      id: json['id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '',
      senderAvatar: senderAvatar.isEmpty ? null : senderAvatar,
      chatId: json['chat_id'] as String? ?? '',
      type: RedPacketTypeExtension.fromString(
          json['type'] as String? ?? 'normal'),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      totalCount: json['total_count'] as int? ?? 1,
      remainingAmount: (json['remaining_amount'] as num?)?.toDouble() ?? 0.0,
      remainingCount: json['remaining_count'] as int? ?? 0,
      message: json['message'] as String? ?? '恭喜发财，大吉大利',
      status: RedPacketStatusExtension.fromString(
          json['status'] as String? ?? 'active'),
      isClaimed: json['is_claimed'] as bool? ?? false,
      claimedAmount: (json['claimed_amount'] as num?)?.toDouble(),
      expiredAt: json['expired_at'] != null
          ? DateTime.parse(json['expired_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'chat_id': chatId,
      'type': type.value,
      'total_amount': totalAmount,
      'total_count': totalCount,
      'remaining_amount': remainingAmount,
      'remaining_count': remainingCount,
      'message': message,
      'status': status.value,
      'is_claimed': isClaimed,
      'claimed_amount': claimedAmount,
      'expired_at': expiredAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 红包领取记录
class RedPacketClaim {
  final String id;
  final String redPacketId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final double amount;
  final bool isBest; // 是否是手气最佳
  final DateTime createdAt;

  const RedPacketClaim({
    required this.id,
    required this.redPacketId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.amount,
    required this.isBest,
    required this.createdAt,
  });

  factory RedPacketClaim.fromJson(Map<String, dynamic> json) {
    final userAvatar = ApiConfig.getMediaUrl(json['user_avatar']?.toString());
    return RedPacketClaim(
      id: json['id'] as String? ?? '',
      redPacketId: json['red_packet_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      userName: json['user_name'] as String? ?? '',
      userAvatar: userAvatar.isEmpty ? null : userAvatar,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isBest: json['is_best'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// 转账状态
enum TransferStatus {
  pending, // 待接收
  accepted, // 已接收
  rejected, // 已退回
  expired, // 已过期
}

extension TransferStatusExtension on TransferStatus {
  String get value {
    switch (this) {
      case TransferStatus.pending:
        return 'pending';
      case TransferStatus.accepted:
        return 'accepted';
      case TransferStatus.rejected:
        return 'rejected';
      case TransferStatus.expired:
        return 'expired';
    }
  }

  static TransferStatus fromString(String value) {
    switch (value) {
      case 'accepted':
        return TransferStatus.accepted;
      case 'rejected':
        return TransferStatus.rejected;
      case 'expired':
        return TransferStatus.expired;
      default:
        return TransferStatus.pending;
    }
  }

  String get displayName {
    switch (this) {
      case TransferStatus.pending:
        return '待接收';
      case TransferStatus.accepted:
        return '已接收';
      case TransferStatus.rejected:
        return '已退回';
      case TransferStatus.expired:
        return '已过期';
    }
  }
}

/// 转账信息
class TransferInfo {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;
  final double amount;
  final String? remark;
  final TransferStatus status;
  final DateTime? expiredAt;
  final DateTime createdAt;

  const TransferInfo({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    required this.amount,
    this.remark,
    required this.status,
    this.expiredAt,
    required this.createdAt,
  });

  factory TransferInfo.fromJson(Map<String, dynamic> json) {
    final senderAvatar =
        ApiConfig.getMediaUrl(json['sender_avatar']?.toString());
    final receiverAvatar =
        ApiConfig.getMediaUrl(json['receiver_avatar']?.toString());
    return TransferInfo(
      id: json['id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '',
      senderAvatar: senderAvatar.isEmpty ? null : senderAvatar,
      receiverId: json['receiver_id'] as String? ?? '',
      receiverName: json['receiver_name'] as String? ?? '',
      receiverAvatar: receiverAvatar.isEmpty ? null : receiverAvatar,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      remark: json['remark'] as String?,
      status: TransferStatusExtension.fromString(
          json['status'] as String? ?? 'pending'),
      expiredAt: json['expired_at'] != null
          ? DateTime.parse(json['expired_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'receiver_avatar': receiverAvatar,
      'amount': amount,
      'remark': remark,
      'status': status.value,
      'expired_at': expiredAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 钱包设置
class WalletSettings {
  final String currency;
  final String currencyName;
  final int redPacketExpireHours;
  final int transferExpireHours;
  final String walletNotice;
  final String rechargeNotice;
  final String withdrawNotice;
  final bool rechargeReview; // true=人工审核

  const WalletSettings({
    this.currency = '¥',
    this.currencyName = '人民币',
    this.redPacketExpireHours = 24,
    this.transferExpireHours = 24,
    this.walletNotice = '',
    this.rechargeNotice = '',
    this.withdrawNotice = '',
    this.rechargeReview = false,
  });

  factory WalletSettings.fromJson(Map<String, dynamic> json) {
    return WalletSettings(
      currency: json['wallet_currency'] as String? ?? '¥',
      currencyName: json['wallet_currency_name'] as String? ?? '人民币',
      redPacketExpireHours:
          int.tryParse(json['red_packet_expire_hours']?.toString() ?? '24') ??
              24,
      transferExpireHours:
          int.tryParse(json['transfer_expire_hours']?.toString() ?? '24') ?? 24,
      walletNotice: json['wallet_notice'] as String? ?? '',
      rechargeNotice: json['recharge_notice'] as String? ?? '',
      withdrawNotice: json['withdraw_notice'] as String? ?? '',
      rechargeReview: json['recharge_review']?.toString() == '1',
    );
  }
}

/// 充值方式
class RechargeMethod {
  final int id;
  final String name;
  final String? icon;
  final String type; // qrcode, bank, manual
  final String? qrcodeUrl;
  final String? accountInfo;
  final double minAmount;
  final double maxAmount;
  final String? remark;
  final int status;

  const RechargeMethod({
    required this.id,
    required this.name,
    this.icon,
    required this.type,
    this.qrcodeUrl,
    this.accountInfo,
    required this.minAmount,
    required this.maxAmount,
    this.remark,
    required this.status,
  });

  factory RechargeMethod.fromJson(Map<String, dynamic> json) {
    return RechargeMethod(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      type: json['type'] as String? ?? 'manual',
      qrcodeUrl: json['qrcode_url'] as String?,
      accountInfo: json['account_info'] as String?,
      minAmount: (json['min_amount'] as num?)?.toDouble() ?? 0,
      maxAmount: (json['max_amount'] as num?)?.toDouble() ?? 50000,
      remark: json['remark'] as String?,
      status: json['status'] as int? ?? 1,
    );
  }
}

/// 钱包 API 服务
class WalletService {
  final ApiClient _api;

  WalletService(this._api);

  /// 获取钱包信息
  Future<ApiResponse<WalletInfo>> getWallet() async {
    return _api.get<WalletInfo>(
      '/wallet',
      fromJson: (data) => WalletInfo.fromJson(data as Map<String, dynamic>),
    );
  }

  /// 设置支付密码
  Future<ApiResponse<void>> setPayPassword({
    required String password,
    String? oldPassword,
  }) async {
    return _api.post<void>(
      '/wallet/pay-password',
      data: {
        'password': password,
        if (oldPassword != null) 'old_password': oldPassword,
      },
    );
  }

  /// 验证支付密码
  Future<ApiResponse<bool>> verifyPayPassword(String password) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/wallet/verify-password',
      data: {'password': password},
      fromJson: (data) => data as Map<String, dynamic>,
    );
    if (response.isSuccess) {
      return ApiResponse<bool>(
        code: response.code,
        message: response.message,
        data: response.data?['valid'] as bool? ?? false,
      );
    }
    return ApiResponse<bool>(
      code: response.code,
      message: response.message,
      data: false,
    );
  }

  /// 充值（直接模式）
  Future<ApiResponse<Map<String, dynamic>>> recharge(double amount) async {
    return _api.post<Map<String, dynamic>>(
      '/wallet/recharge',
      data: {'amount': amount},
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  /// 获取交易记录
  Future<ApiResponse<List<Transaction>>> getTransactions({
    int page = 1,
    int pageSize = 20,
    TransactionType? type,
  }) async {
    return _api.get<List<Transaction>>(
      '/wallet/transactions',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (type != null) 'type': type.value,
      },
      fromJson: (data) {
        // 后端返回 {list: [...], total, page, page_size}
        final list =
            data is Map ? (data['list'] as List? ?? []) : (data as List? ?? []);
        return list
            .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  // ========== 红包相关 ==========

  /// 发红包
  Future<ApiResponse<RedPacketInfo>> sendRedPacket({
    required String chatId,
    required RedPacketType type,
    required double totalAmount,
    required int totalCount,
    required String message,
    required String payPassword,
  }) async {
    return _api.post<RedPacketInfo>(
      '/wallet/red-packet/send',
      data: {
        'chat_id': chatId,
        'type': type.value,
        'total_amount': totalAmount,
        'total_count': totalCount,
        'message': message,
        'pay_password': payPassword,
      },
      fromJson: (data) => RedPacketInfo.fromJson(data as Map<String, dynamic>),
    );
  }

  /// 领红包
  Future<ApiResponse<Map<String, dynamic>>> claimRedPacket(
      String redPacketId) async {
    return _api.post<Map<String, dynamic>>(
      '/wallet/red-packet/$redPacketId/claim',
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  /// 获取红包详情
  Future<ApiResponse<RedPacketInfo>> getRedPacket(String redPacketId) async {
    return _api.get<RedPacketInfo>(
      '/wallet/red-packet/$redPacketId',
      fromJson: (data) => RedPacketInfo.fromJson(data as Map<String, dynamic>),
    );
  }

  /// 获取红包领取记录
  Future<ApiResponse<List<RedPacketClaim>>> getRedPacketClaims(
      String redPacketId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/wallet/red-packet/$redPacketId',
      fromJson: (data) => data as Map<String, dynamic>,
    );
    if (response.isSuccess && response.data != null) {
      final claimsJson = response.data!['claims'] as List? ?? [];
      final claims = claimsJson
          .map((e) => RedPacketClaim.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResponse<List<RedPacketClaim>>(
        code: response.code,
        message: response.message,
        data: claims,
      );
    }
    return ApiResponse<List<RedPacketClaim>>(
      code: response.code,
      message: response.message,
      data: [],
    );
  }

  // ========== 转账相关 ==========

  /// 发起转账
  Future<ApiResponse<TransferInfo>> transfer({
    required String receiverId,
    required double amount,
    String? remark,
    required String payPassword,
  }) async {
    return _api.post<TransferInfo>(
      '/wallet/transfer/send',
      data: {
        'receiver_id': receiverId,
        'amount': amount,
        if (remark != null) 'remark': remark,
        'pay_password': payPassword,
      },
      fromJson: (data) => TransferInfo.fromJson(data as Map<String, dynamic>),
    );
  }

  /// 接收转账
  Future<ApiResponse<void>> acceptTransfer(String transferId) async {
    return _api.post<void>('/wallet/transfer/$transferId/accept');
  }

  /// 退回转账
  Future<ApiResponse<void>> rejectTransfer(String transferId) async {
    return _api.post<void>('/wallet/transfer/$transferId/reject');
  }

  /// 获取转账详情
  Future<ApiResponse<TransferInfo>> getTransfer(String transferId) async {
    return _api.get<TransferInfo>(
      '/wallet/transfer/$transferId',
      fromJson: (data) => TransferInfo.fromJson(data as Map<String, dynamic>),
    );
  }

  // ========== 提现相关 ==========

  /// 获取提现方式列表
  Future<ApiResponse<List<WithdrawMethod>>> getWithdrawMethods() async {
    return _api.get<List<WithdrawMethod>>(
      '/wallet/withdraw/methods',
      fromJson: (data) => (data as List)
          .map((e) => WithdrawMethod.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取钱包设置
  Future<ApiResponse<WalletSettings>> getWalletSettings() async {
    return _api.get<WalletSettings>(
      '/wallet/settings',
      fromJson: (data) => WalletSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  /// 获取充值方式列表
  Future<ApiResponse<List<RechargeMethod>>> getRechargeMethods() async {
    return _api.get<List<RechargeMethod>>(
      '/wallet/recharge-methods',
      fromJson: (data) => (data as List)
          .map((e) => RechargeMethod.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 微信/支付宝在线充值配置（无密钥）
  Future<ApiResponse<Map<String, dynamic>>> getOnlinePayOptions() async {
    return _api.get<Map<String, dynamic>>(
      '/wallet/online-pay/options',
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  /// 创建在线支付订单
  Future<ApiResponse<Map<String, dynamic>>> createOnlinePay({
    required double amount,
    required String channel,
    required String clientPlatform,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/wallet/online-pay/create',
      data: {
        'amount': amount,
        'channel': channel,
        'client_platform': clientPlatform,
      },
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getOnlinePayOrder(
      String outTradeNo) async {
    return _api.get<Map<String, dynamic>>(
      '/wallet/online-pay/order/$outTradeNo',
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  /// 提交充值订单（人工审核模式）
  Future<ApiResponse<Map<String, dynamic>>> createRechargeOrder({
    required int methodId,
    required double amount,
    String? proofImage,
    String? remark,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/wallet/recharge-order',
      data: {
        'method_id': methodId,
        'amount': amount,
        if (proofImage != null) 'proof_image': proofImage,
        if (remark != null && remark.isNotEmpty) 'remark': remark,
      },
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  /// 获取用户充值订单列表
  Future<ApiResponse<List<Map<String, dynamic>>>> getRechargeOrders() async {
    return _api.get<List<Map<String, dynamic>>>(
      '/wallet/recharge-orders',
      fromJson: (data) =>
          (data as List).map((e) => e as Map<String, dynamic>).toList(),
    );
  }

  /// 发起提现申请
  Future<ApiResponse<Map<String, dynamic>>> createWithdrawRequest({
    required int methodId,
    required double amount,
    required String formData,
    required String payPassword,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/wallet/withdraw',
      data: {
        'method_id': methodId,
        'amount': amount,
        'form_data': formData,
        'pay_password': payPassword,
      },
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }
}

/// 提现方式
class WithdrawMethod {
  final int id;
  final String name;
  final String? icon;
  final String fields; // JSON格式的表单字段配置
  final double minAmount;
  final double maxAmount;
  final double fee; // 手续费百分比
  final int status;
  final int sort;

  const WithdrawMethod({
    required this.id,
    required this.name,
    this.icon,
    required this.fields,
    required this.minAmount,
    required this.maxAmount,
    required this.fee,
    required this.status,
    required this.sort,
  });

  factory WithdrawMethod.fromJson(Map<String, dynamic> json) {
    return WithdrawMethod(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      fields: json['fields'] as String? ?? '[]',
      minAmount: (json['min_amount'] as num?)?.toDouble() ?? 0,
      maxAmount: (json['max_amount'] as num?)?.toDouble() ?? 50000,
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      status: json['status'] as int? ?? 1,
      sort: json['sort'] as int? ?? 0,
    );
  }
}
