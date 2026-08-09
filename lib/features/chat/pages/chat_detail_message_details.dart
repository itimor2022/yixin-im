// 文件用途：实现 _ChatDetailMessageDetails 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMessageDetails 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail message details 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMessageDetails on _ChatDetailPageState {
  // 流程逻辑：`_openMessageDetails` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _openMessageDetails(MessageItem message) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageDetailPage(
          message: message,
          service: MessageDetailService(ref.read(apiClientProvider)),
        ),
      ),
    );
  }
}
