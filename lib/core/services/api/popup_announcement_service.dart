import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 全局弹窗公告(F-13) —— 与群公告 ChatAnnouncement、系统广播 systemAnnouncement 区分
class PopupAnnouncement {
  final int id;
  final String title;
  final String content;
  final String imageUrl;
  final String linkUrl;
  final int enabled;
  final String updatedAt;

  const PopupAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.linkUrl,
    required this.enabled,
    required this.updatedAt,
  });

  factory PopupAnnouncement.fromJson(Map<String, dynamic> json) {
    return PopupAnnouncement(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      linkUrl: json['link_url'] as String? ?? '',
      enabled: (json['enabled'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  /// 已读判定 key：内容更新(updated_at 变化)后重新弹一次
  String get readKey => '$id:$updatedAt';
}

class PopupAnnouncementService {
  PopupAnnouncementService(this._apiClient);

  final ApiClient _apiClient;

  /// 拉取当前启用的弹窗公告(enabled=1 ORDER BY id DESC LIMIT 1)
  /// 无启用公告时返回 null
  Future<PopupAnnouncement?> getActive() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>?>(
        '/popup-announcement/active',
        fromJson: (data) => data as Map<String, dynamic>?,
      );
      if (response.isSuccess && response.data != null) {
        return PopupAnnouncement.fromJson(response.data!);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PopupAnnouncement] getActive error: $e');
      }
    }
    return null;
  }
}

final popupAnnouncementServiceProvider =
    Provider<PopupAnnouncementService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PopupAnnouncementService(apiClient);
});
