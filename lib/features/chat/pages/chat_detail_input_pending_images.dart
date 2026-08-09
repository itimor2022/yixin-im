// 文件用途：实现 _ChatDetailInputPendingImages 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailInputPendingImages 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail input pending images 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailInputPendingImages on _ChatDetailPageState {
  /// 待发送图片预览面板
  Widget _buildPendingImagesPanel(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primaryWithOpacity(context, 0.15)
            : AppColors.primaryWithOpacity(context, 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                _localizedText(
                  zhCN: '${_pendingImages.length} 张图片（可输入说明文字后发送）',
                  zhTW: '${_pendingImages.length} 張圖片（可輸入說明文字後傳送）',
                  en: '${_pendingImages.length} photos selected. Add a caption before sending.',
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _updateState(() => _pendingImages.clear()),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pendingImages.length,
              itemBuilder: (_, i) {
                final img = _pendingImages[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildPendingImagePreview(img),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              _updateState(() => _pendingImages.removeAt(i)),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建待发送图片缩略图
  Widget _buildPendingImagePreview(_PendingImage img) {
    // 流程逻辑：`fallback` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
    Widget fallback() {
      return Container(
        width: 80,
        height: 80,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, size: 24),
      );
    }

    if (img.bytes != null) {
      return Image.memory(
        img.bytes!,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    final path = img.path;
    if (path == null || path.isEmpty) return fallback();
    final file = File(path);
    if (!file.existsSync()) return fallback();
    return Image.file(
      file,
      width: 80,
      height: 80,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
}
