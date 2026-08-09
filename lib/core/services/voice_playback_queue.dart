// 文件用途：封装 VoicePlaybackQueueItem 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 VoicePlaybackQueueItem 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
// 关键声明：voice playback queue 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
/// 自动连播排序所需的最小消息信息。
///
/// 队列项只描述顺序，不持有播放器或文件资源；实际播放状态由调用方管理。
class VoicePlaybackQueueItem {
  const VoicePlaybackQueueItem({
    required this.id,
    required this.chatId,
    required this.seq,
    required this.createdAt,
  });

  final String id;
  final String chatId;
  final int seq;
  final DateTime createdAt;
}

String? nextVoicePlaybackId({
  required List<VoicePlaybackQueueItem> items,
  required String currentId,
}) {
  // 连播严格限制在当前会话内，避免一条语音结束后跳到其他聊天。
  final currentIndex = items.indexWhere((item) => item.id == currentId);
  if (currentIndex < 0) return null;
  final current = items[currentIndex];

  final sameChat = items
      .where((item) => item.chatId == current.chatId)
      .toList(growable: false)
    ..sort((left, right) {
      final leftHasSeq = left.seq > 0;
      final rightHasSeq = right.seq > 0;
      // 双方都有服务端序号时以 seq 为权威；缺少序号的历史/本地消息退回时间排序。
      if (leftHasSeq && rightHasSeq) {
        final bySeq = left.seq.compareTo(right.seq);
        if (bySeq != 0) return bySeq;
      } else {
        final byTime = left.createdAt.compareTo(right.createdAt);
        if (byTime != 0) return byTime;
      }
      // 时间相同时用稳定 ID 消除排序不确定性，保证各次计算得到同一结果。
      return left.id.compareTo(right.id);
    });

  final index = sameChat.indexWhere((item) => item.id == currentId);
  if (index < 0 || index + 1 >= sameChat.length) return null;
  return sameChat[index + 1].id;
}
