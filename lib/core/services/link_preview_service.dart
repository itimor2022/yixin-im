import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api/api_client.dart';

/// 链接预览数据
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

  factory LinkPreviewData.fromJson(Map<String, dynamic> json) {
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

/// 链接预览 Provider（按 URL 缓存结果，autoDispose=false 保持全局缓存）
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
    if (kDebugMode) debugPrint('[LinkPreview] 获取失败 $url: $e');
  }
  return null;
});
