// 文件用途：定义 VipProfileSummary 相关数据结构、字段转换与持久化模型，属于会员权益。
// 核心逻辑：定义 VipProfileSummary 的字段、默认值和序列化边界，保持服务端响应、内存对象与本地持久化格式一致。
import '../../../core/services/api/api_client.dart';

// 关键声明：VIP profile summary 定义数据转换边界，负责默认值、空值兼容和 JSON/本地存储之间的双向映射。
class VipProfileSummary {
  const VipProfileSummary({
    this.level = 0,
    this.levelName = '普通用户',
    this.isActive = false,
    this.badge = '',
    this.badgeIcon = '',
  });

  static const inactive = VipProfileSummary();

  final int level;
  final String levelName;
  final bool isActive;
  final String badge;
  final String badgeIcon;

  bool get visible => isActive && level > 0;

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory VipProfileSummary.fromJson(dynamic json) {
    if (json is! Map) return VipProfileSummary.inactive;
    return VipProfileSummary(
      level: int.tryParse(json['level']?.toString() ?? '') ?? 0,
      levelName: json['level_name']?.toString() ?? '',
      isActive: json['is_active'] == true,
      badge: json['badge']?.toString() ?? '',
      badgeIcon: _normalizeBadgeIcon(json['badge_icon']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VipProfileSummary &&
        other.level == level &&
        other.levelName == levelName &&
        other.isActive == isActive &&
        other.badge == badge &&
        other.badgeIcon == badgeIcon;
  }

  @override
  int get hashCode => Object.hash(level, levelName, isActive, badge, badgeIcon);
}

String _normalizeBadgeIcon(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return '';
  return ApiConfig.getMediaUrl(text);
}
