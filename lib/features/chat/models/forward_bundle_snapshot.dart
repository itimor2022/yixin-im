// 文件用途：定义 ForwardBundleSnapshot 相关数据结构、字段转换与持久化模型，属于聊天与消息。
// 核心逻辑：定义 ForwardBundleSnapshot 的字段、默认值和序列化边界，保持服务端响应、内存对象与本地持久化格式一致。
import 'dart:convert';

// 关键声明：forward bundle snapshot 定义数据转换边界，负责默认值、空值兼容和 JSON/本地存储之间的双向映射。
class ForwardBundleSnapshot {
  final String title;
  final List<ForwardBundleSnapshotItem> items;

  const ForwardBundleSnapshot({required this.title, required this.items});

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory ForwardBundleSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ForwardBundleSnapshot(
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'Chat history',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                (item) => ForwardBundleSnapshotItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }

  static ForwardBundleSnapshot? tryParse(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final result = ForwardBundleSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return result.items.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }
}

class ForwardBundleSnapshotItem {
  final String sourceMessageId;
  final int type;
  final String senderName;
  final String senderAvatar;
  final Map<String, dynamic> content;
  final DateTime createdAt;
  final ForwardBundleSnapshot? nestedBundle;

  const ForwardBundleSnapshotItem({
    required this.sourceMessageId,
    required this.type,
    required this.senderName,
    required this.senderAvatar,
    required this.content,
    required this.createdAt,
    required this.nestedBundle,
  });

  factory ForwardBundleSnapshotItem.fromJson(Map<String, dynamic> json) {
    final content = json['content'] is Map
        ? Map<String, dynamic>.from(json['content'] as Map)
        : const <String, dynamic>{};
    final nested = content['forward_bundle'] is Map
        ? ForwardBundleSnapshot.fromJson(
            Map<String, dynamic>.from(content['forward_bundle'] as Map),
          )
        : null;
    return ForwardBundleSnapshotItem(
      sourceMessageId: json['source_message_id']?.toString() ?? '',
      type: (json['type'] as num?)?.toInt() ?? 1,
      senderName: json['sender_name']?.toString() ?? '',
      senderAvatar: json['sender_avatar']?.toString() ?? '',
      content: content,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      nestedBundle: nested,
    );
  }

  String preview({required bool english}) {
    final text = content['text']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
    switch (type) {
      case 2:
        return english ? '[Photo]' : '[图片]';
      case 3:
        return english ? '[Video]' : '[视频]';
      case 4:
        return english ? '[Voice]' : '[语音]';
      case 5:
        final file = content['file'];
        final name = file is Map ? file['name']?.toString().trim() ?? '' : '';
        return name.isEmpty ? (english ? '[File]' : '[文件]') : name;
      case 6:
        return english ? '[Location]' : '[位置]';
      case 8:
        return english ? '[Sticker]' : '[表情]';
      case 10:
        return english ? '[Contact]' : '[联系人名片]';
      case 11:
        return english ? '[Call]' : '[通话]';
      case 12:
        return english ? '[Red packet]' : '[红包]';
      case 13:
        return english ? '[Transfer]' : '[转账]';
      case 14:
        return nestedBundle?.title ?? (english ? '[Chat history]' : '[聊天记录]');
      default:
        return english ? '[Message]' : '[消息]';
    }
  }
}
