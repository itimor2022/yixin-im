// 文件用途：封装 LinkPreviewData 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 LinkPreviewData 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api/api_client.dart';

// 关键声明：link preview service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 服务端解析网页后返回的链接预览数据。
///
/// 标题、描述和图片地址都来自外部页面，展示层仍需按不可信内容处理，
/// 不应据此执行导航、HTML 或脚本。
class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;
  final String? favicon;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.siteName,
    this.favicon,
  });

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory LinkPreviewData.fromJson(Map<String, dynamic> json) {
    // 空字符串归一为 null，避免 UI 把“有字段但无内容”误判为有效预览。
    String? img = json['image'] as String?;
    if (img != null && img.isEmpty) img = null;
    String? fav = json['favicon'] as String?;
    if (fav != null && fav.isEmpty) fav = null;

    return LinkPreviewData(
      url: json['url'] as String? ?? '',
      title: _nonEmpty(json['title'] as String?),
      description: _nonEmpty(json['description'] as String?),
      image: img,
      siteName: _nonEmpty(json['site_name'] as String?),
      favicon: fav,
    );
  }

  /// 是否有可显示的内容（标题或描述）
  bool get hasContent =>
      (title != null && title!.isNotEmpty) ||
      (description != null && description!.isNotEmpty);

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}

/// 按 URL 请求并缓存链接预览；非 autoDispose 让同一 ProviderContainer 内复用结果。
///
/// URL 的协议与访问安全由服务端接口最终校验。网络失败、无有效元数据或响应格式
/// 不匹配时返回 null，让聊天消息退回普通链接展示。
final linkPreviewProvider =
    FutureProvider.family<LinkPreviewData?, String>((ref, url) async {
  final api = ref.read(apiClientProvider);
  try {
    final response = await api.get(
      '/link-preview',
      queryParameters: {'url': url},
    );
    if (response.isSuccess && response.data != null) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return LinkPreviewData.fromJson(data);
      }
    }
  } catch (e) {
    debugPrint('[LinkPreview] 获取失败 $url: $e');
  }
  return null;
});
