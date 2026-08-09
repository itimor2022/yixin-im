// 文件用途：提供 _MessageBubbleImage 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleImage，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble image 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleImage on MessageBubble {
  // 流程逻辑：`_buildImageBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildImageBubble(
    Color bubbleColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          final imageUrl = _getImageUrl();
          if (imageUrl == null) return;

          Navigator.of(context).push(
            PageRouteBuilder(
              opaque: false,
              barrierColor: Colors.black87,
              pageBuilder: (ctx, animation, secondaryAnimation) {
                return _ImagePreviewPage(
                  imageUrl: imageUrl,
                  isLocalFile: ChatMediaCacheManager.isLocalPath(imageUrl),
                );
              },
              transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: _getBubbleRadius(isOutgoing),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _getBubbleRadius(isOutgoing),
            child: Stack(
              children: [
                _buildSizedMedia(280, 400),
                Positioned(
                  right: 0,
                  bottom: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 8, 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('HH:mm')
                              .format(toCurrentLocalTime(message.createdAt)),
                          style: AppTextStyles.timestamp.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (isOutgoing) ...[
                          const SizedBox(width: 3),
                          _buildStatusIcon(Colors.white),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _getImageUrl() {
    final localPath = message.localPath;
    if (ChatMediaCacheManager.isLocalPath(localPath) &&
        File(localPath!).existsSync()) {
      return localPath;
    }
    if (message.mediaUrl == null) return null;

    final url = ChatMediaCacheManager.normalizeUrl(message.mediaUrl);

    if (ChatMediaCacheManager.isLocalPath(url)) {
      return url;
    }

    return url;
  }
}
