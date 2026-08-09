// 文件用途：封装 MessageDetailMember 相关业务流程与外部能力调用，属于聊天与消息。
// 核心逻辑：封装 MessageDetailMember 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import '../../../core/services/api/api_client.dart';

// 关键声明：message detail service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class MessageDetailMember {
  final String userId;
  final String nickname;
  final String avatar;
  final int role;
  final bool isRead;
  final bool isDelivered;
  final bool deliveredKnown;

  const MessageDetailMember({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.role,
    required this.isRead,
    required this.isDelivered,
    required this.deliveredKnown,
  });

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory MessageDetailMember.fromJson(Map<String, dynamic> json) {
    return MessageDetailMember(
      userId: json['user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      role: (json['role'] as num?)?.toInt() ?? 0,
      isRead: json['read'] == true,
      isDelivered: json['delivered'] == true,
      deliveredKnown: json['delivered_known'] == true,
    );
  }
}

class MessageReceiptSummary {
  final int recipientCount;
  final int readCount;
  final int unreadCount;
  final int deliveredCount;
  final bool deliveryCountKnown;
  final bool canViewMembers;
  final bool memberProtectionOn;
  final List<MessageDetailMember> members;

  const MessageReceiptSummary({
    required this.recipientCount,
    required this.readCount,
    required this.unreadCount,
    required this.deliveredCount,
    required this.deliveryCountKnown,
    required this.canViewMembers,
    required this.memberProtectionOn,
    required this.members,
  });

  factory MessageReceiptSummary.fromJson(Map<String, dynamic> json) {
    final canViewMembers = json['can_view_members'] == true;
    final rawMembers = json['members'];
    final members = canViewMembers && rawMembers is List
        ? rawMembers
            .whereType<Map>()
            .map(
              (item) => MessageDetailMember.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
        : const <MessageDetailMember>[];
    return MessageReceiptSummary(
      recipientCount: (json['recipient_count'] as num?)?.toInt() ?? 0,
      readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      deliveredCount: (json['delivered_count'] as num?)?.toInt() ?? 0,
      deliveryCountKnown: json['delivery_count_known'] == true,
      canViewMembers: canViewMembers,
      memberProtectionOn: json['member_protection_on'] == true,
      members: members,
    );
  }
}

class MessageDetailData {
  final String messageId;
  final String chatId;
  final int seq;
  final int type;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? editedAt;
  final bool revoked;
  final MessageReceiptSummary receipts;

  const MessageDetailData({
    required this.messageId,
    required this.chatId,
    required this.seq,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.editedAt,
    required this.revoked,
    required this.receipts,
  });

  factory MessageDetailData.fromJson(Map<String, dynamic> json) {
    final message = Map<String, dynamic>.from(json['message'] as Map? ?? {});
    final receipts = Map<String, dynamic>.from(json['receipts'] as Map? ?? {});
    return MessageDetailData(
      messageId: message['message_id']?.toString() ?? '',
      chatId: message['chat_id']?.toString() ?? '',
      seq: (message['seq'] as num?)?.toInt() ?? 0,
      type: (message['type'] as num?)?.toInt() ?? 0,
      status: message['status']?.toString() ?? 'sent',
      createdAt: _parseDate(message['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: _parseDate(message['updated_at']),
      editedAt: _parseDate(message['edited_at']),
      revoked: message['revoked'] == true,
      receipts: MessageReceiptSummary.fromJson(receipts),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

class MessageDetailService {
  final ApiClient _apiClient;

  const MessageDetailService(this._apiClient);

  Future<MessageDetailData> fetch({
    required String chatId,
    required String messageId,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/message/detail',
      queryParameters: {'chat_id': chatId, 'msg_id': messageId},
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
    if (!response.isSuccess || response.data == null) {
      throw StateError(
        response.message.isEmpty ? 'message_detail_failed' : response.message,
      );
    }
    return MessageDetailData.fromJson(response.data!);
  }
}
