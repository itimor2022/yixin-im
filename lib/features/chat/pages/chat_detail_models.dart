// 文件用途：实现 _PendingImage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _PendingImage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail models 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 待发送图片（支持 web bytes 和原生 path 两种模式）
class _PendingImage {
  final Uint8List? bytes; // web
  final String? path; // native
  final int? width;
  final int? height;
  final String ext;
  final String name;
  final bool originalRequested;

  const _PendingImage({
    this.bytes,
    this.path,
    this.width,
    this.height,
    required this.ext,
    required this.name,
    this.originalRequested = false,
  });
}

/// 聊天类型
class _MessageDisplayItem {
  final MessageItem message;
  final List<MessageItem> albumMessages;

  const _MessageDisplayItem({
    required this.message,
    this.albumMessages = const [],
  });

  bool get isAlbum => albumMessages.length > 1;
}

enum ChatType { private, group, channel }

// 流程逻辑：`_chatDetailText` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
String _chatDetailText(
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
