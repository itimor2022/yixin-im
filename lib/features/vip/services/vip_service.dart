// 文件用途：封装 VipEntitlements 相关业务流程与外部能力调用，属于会员权益。
// 核心逻辑：封装 VipEntitlements 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';

// 关键声明：VIP service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class VipEntitlements {
  final bool canCreateGroup;
  final bool canCreateChannel;
  final int maxOwnedGroups;
  final int maxOwnedChannels;
  final int maxGroupMembers;
  final int maxChannelMembers;
  final int maxPinnedChats;
  final int uploadImageLimitMB;
  final int uploadVideoLimitMB;
  final int uploadVoiceLimitMB;
  final int uploadFileLimitMB;
  final bool canSetPublicUsername;
  final bool canEnableMemberProtection;
  final String badge;
  final String badgeIcon;

  const VipEntitlements({
    this.canCreateGroup = false,
    this.canCreateChannel = false,
    this.maxOwnedGroups = 0,
    this.maxOwnedChannels = 0,
    this.maxGroupMembers = 0,
    this.maxChannelMembers = 0,
    this.maxPinnedChats = 5,
    this.uploadImageLimitMB = 10,
    this.uploadVideoLimitMB = 100,
    this.uploadVoiceLimitMB = 20,
    this.uploadFileLimitMB = 100,
    this.canSetPublicUsername = false,
    this.canEnableMemberProtection = false,
    this.badge = '',
    this.badgeIcon = '',
  });

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory VipEntitlements.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return VipEntitlements(
      canCreateGroup: data['can_create_group'] == true,
      canCreateChannel: data['can_create_channel'] == true,
      maxOwnedGroups:
          int.tryParse(data['max_owned_groups']?.toString() ?? '') ?? 0,
      maxOwnedChannels:
          int.tryParse(data['max_owned_channels']?.toString() ?? '') ?? 0,
      maxGroupMembers:
          int.tryParse(data['max_group_members']?.toString() ?? '') ?? 0,
      maxChannelMembers:
          int.tryParse(data['max_channel_members']?.toString() ?? '') ?? 0,
      maxPinnedChats:
          int.tryParse(data['max_pinned_chats']?.toString() ?? '') ?? 5,
      uploadImageLimitMB:
          int.tryParse(data['upload_image_limit_mb']?.toString() ?? '') ?? 10,
      uploadVideoLimitMB:
          int.tryParse(data['upload_video_limit_mb']?.toString() ?? '') ?? 100,
      uploadVoiceLimitMB:
          int.tryParse(data['upload_voice_limit_mb']?.toString() ?? '') ?? 20,
      uploadFileLimitMB:
          int.tryParse(data['upload_file_limit_mb']?.toString() ?? '') ?? 100,
      canSetPublicUsername: data['can_set_public_username'] == true,
      canEnableMemberProtection: data['can_enable_member_protection'] == true,
      badge: data['badge']?.toString() ?? '',
      badgeIcon: _normalizeVipBadgeIcon(data['badge_icon']),
    );
  }
}

class VipPlan {
  final int id;
  final String code;
  final String name;
  final int level;
  final String levelName;
  final int durationDays;
  final double price;
  final double originalPrice;
  final VipEntitlements benefits;
  final String description;
  final bool enabled;

  const VipPlan({
    required this.id,
    required this.code,
    required this.name,
    required this.level,
    required this.levelName,
    required this.durationDays,
    required this.price,
    required this.originalPrice,
    required this.benefits,
    required this.description,
    required this.enabled,
  });

  factory VipPlan.fromJson(Map<String, dynamic> json) {
    return VipPlan(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      level: int.tryParse(json['level']?.toString() ?? '') ?? 0,
      levelName: json['level_name']?.toString() ?? '',
      durationDays: int.tryParse(json['duration_days']?.toString() ?? '') ?? 0,
      price: (json['price'] as num?)?.toDouble() ??
          double.tryParse(json['price']?.toString() ?? '') ??
          0,
      originalPrice: (json['original_price'] as num?)?.toDouble() ??
          double.tryParse(json['original_price']?.toString() ?? '') ??
          0,
      benefits: VipEntitlements.fromJson(
        (json['benefits'] as Map?)?.cast<String, dynamic>(),
      ),
      description: json['description']?.toString() ?? '',
      enabled: json['enabled'] != false,
    );
  }
}

class VipStatus {
  final int level;
  final String levelName;
  final bool isActive;
  final String badge;
  final String badgeIcon;
  final DateTime? expiredAt;
  final VipPlan? plan;
  final VipEntitlements entitlements;

  const VipStatus({
    this.level = 0,
    this.levelName = '普通用户',
    this.isActive = false,
    this.badge = '',
    this.badgeIcon = '',
    this.expiredAt,
    this.plan,
    this.entitlements = const VipEntitlements(),
  });

  factory VipStatus.fromJson(Map<String, dynamic> json) {
    final planData = (json['plan'] as Map?)?.cast<String, dynamic>();
    final entitlements = VipEntitlements.fromJson(
      (json['entitlements'] as Map?)?.cast<String, dynamic>(),
    );
    final badgeIcon = _normalizeVipBadgeIcon(json['badge_icon']);
    return VipStatus(
      level: int.tryParse(json['level']?.toString() ?? '') ?? 0,
      levelName: json['level_name']?.toString() ?? '',
      isActive: json['is_active'] == true,
      badge: json['badge']?.toString() ?? '',
      badgeIcon: badgeIcon.isNotEmpty ? badgeIcon : entitlements.badgeIcon,
      expiredAt: _parseDate(json['expired_at']),
      plan: planData == null ? null : VipPlan.fromJson(planData),
      entitlements: entitlements,
    );
  }
}

class VipPurchaseResult {
  final Map<String, dynamic>? order;
  final VipStatus status;

  const VipPurchaseResult({this.order, required this.status});

  factory VipPurchaseResult.fromJson(Map<String, dynamic> json) {
    return VipPurchaseResult(
      order: (json['order'] as Map?)?.cast<String, dynamic>(),
      status: VipStatus.fromJson(
        (json['status'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class VipOrder {
  final int id;
  final String orderNo;
  final int planId;
  final String planName;
  final int planLevel;
  final double amount;
  final String payMethod;
  final String status;
  final DateTime? paidAt;
  final String transactionId;
  final String remark;
  final DateTime? createdAt;

  const VipOrder({
    required this.id,
    required this.orderNo,
    required this.planId,
    required this.planName,
    required this.planLevel,
    required this.amount,
    required this.payMethod,
    required this.status,
    this.paidAt,
    this.transactionId = '',
    this.remark = '',
    this.createdAt,
  });

  factory VipOrder.fromJson(Map<String, dynamic> json) {
    return VipOrder(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      orderNo: json['order_no']?.toString() ?? '',
      planId: int.tryParse(json['plan_id']?.toString() ?? '') ?? 0,
      planName: json['plan_name']?.toString() ?? '',
      planLevel: int.tryParse(json['plan_level']?.toString() ?? '') ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ??
          double.tryParse(json['amount']?.toString() ?? '') ??
          0,
      payMethod: json['pay_method']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      paidAt: _parseDate(json['paid_at']),
      transactionId: json['transaction_id']?.toString() ?? '',
      remark: json['remark']?.toString() ?? '',
      createdAt: _parseDate(json['created_at']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

String _normalizeVipBadgeIcon(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return '';
  return ApiConfig.getMediaUrl(text);
}

class VipService {
  VipService(this._api);

  final ApiClient _api;

  Future<ApiResponse<List<VipPlan>>> getPlans() async {
    final response = await _api.get<List<VipPlan>>(
      '/vip/plans',
      fromJson: (data) =>
          (data as List).map((item) => VipPlan.fromJson(item)).toList(),
    );
    return _localize(response, fallbackEn: 'Failed to load VIP plans');
  }

  Future<ApiResponse<VipStatus>> getStatus() async {
    final response = await _api.get<VipStatus>(
      '/vip/status',
      fromJson: (data) => VipStatus.fromJson(data),
    );
    return _localize(response, fallbackEn: 'Failed to load VIP status');
  }

  Future<ApiResponse<VipPurchaseResult>> purchase(int planId) async {
    final response = await _api.post<VipPurchaseResult>(
      '/vip/purchase',
      data: {'plan_id': planId},
      fromJson: (data) => VipPurchaseResult.fromJson(data),
    );
    return _localize(
      response,
      fallbackZhCN: '开通会员失败',
      fallbackZhTW: '開通會員失敗',
      fallbackEn: 'Failed to activate VIP',
    );
  }

  Future<ApiResponse<List<VipOrder>>> getOrders({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _api.get<List<VipOrder>>(
      '/vip/orders',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
      fromJson: (data) {
        final list =
            data is Map ? (data['list'] as List? ?? []) : (data as List? ?? []);
        return list
            .map((item) => VipOrder.fromJson(item as Map<String, dynamic>))
            .toList();
      },
    );
    return _localize(response, fallbackEn: 'Failed to load VIP orders');
  }

  ApiResponse<T> _localize<T>(
    ApiResponse<T> response, {
    String? fallbackZhCN,
    String? fallbackZhTW,
    required String fallbackEn,
  }) {
    if (response.isSuccess) return response;
    return ApiResponse<T>(
      code: response.code,
      message: localizeServerMessage(
        response.message,
        fallbackZhCN: fallbackZhCN,
        fallbackZhTW: fallbackZhTW,
        fallbackEn: fallbackEn,
      ),
      data: response.data,
    );
  }
}

final vipServiceProvider = Provider<VipService>((ref) {
  return VipService(ref.watch(apiClientProvider));
});

String vipLevelName(BuildContext context, int level) {
  if (level >= 2) return 'SVIP';
  if (level == 1) return 'VIP';
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return 'Free';
    case AppLanguage.zhTW:
      return '普通使用者';
    case AppLanguage.zhCN:
      return '普通用户';
  }
}
