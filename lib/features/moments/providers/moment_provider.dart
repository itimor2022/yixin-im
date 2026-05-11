import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/notification_sound_service.dart';

/// 动态可见性
enum MomentVisibility {
  public, // 完全公开（所有人可见）
  contacts, // 仅联系人可见
  selected, // 选择特定联系人
  private, // 私密（仅自己可见）
}

extension MomentVisibilityX on MomentVisibility {
  String get label {
    switch (this) {
      case MomentVisibility.public:
        return '公开';
      case MomentVisibility.contacts:
        return '联系人';
      case MomentVisibility.selected:
        return '部分可见';
      case MomentVisibility.private:
        return '私密';
    }
  }

  IconData get icon {
    switch (this) {
      case MomentVisibility.public:
        return Icons.public;
      case MomentVisibility.contacts:
        return Icons.people_outline;
      case MomentVisibility.selected:
        return Icons.person_outline;
      case MomentVisibility.private:
        return Icons.lock_outline;
    }
  }

  int get value {
    switch (this) {
      case MomentVisibility.public:
        return 1;
      case MomentVisibility.contacts:
        return 2;
      case MomentVisibility.selected:
        return 3;
      case MomentVisibility.private:
        return 4;
    }
  }

  static MomentVisibility fromValue(int value) {
    switch (value) {
      case 1:
        return MomentVisibility.public;
      case 2:
        return MomentVisibility.contacts;
      case 3:
        return MomentVisibility.selected;
      case 4:
        return MomentVisibility.private;
      default:
        return MomentVisibility.public;
    }
  }
}

/// 动态内容类型
enum MomentContentType {
  text, // 纯文字
  image, // 图片
  video, // 视频
}

/// 动态数据模型
class Moment {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String content;
  final MomentContentType contentType;
  final List<String> mediaUrls; // 图片/视频URL列表
  final String? videoThumbnail; // 视频封面
  final List<String> topics; // 话题标签
  final MomentVisibility visibility;
  final List<String>? selectedContacts; // 选择可见的联系人ID
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final bool isLiked;
  final int status;
  final String? reviewReason;

  const Moment({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.content,
    this.contentType = MomentContentType.text,
    this.mediaUrls = const [],
    this.videoThumbnail,
    this.topics = const [],
    this.visibility = MomentVisibility.public,
    this.selectedContacts,
    required this.createdAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.isLiked = false,
    this.status = 1,
    this.reviewReason,
  });

  Moment copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    String? content,
    MomentContentType? contentType,
    List<String>? mediaUrls,
    String? videoThumbnail,
    List<String>? topics,
    MomentVisibility? visibility,
    List<String>? selectedContacts,
    DateTime? createdAt,
    int? likeCount,
    int? commentCount,
    int? shareCount,
    bool? isLiked,
    int? status,
    String? reviewReason,
  }) {
    return Moment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      videoThumbnail: videoThumbnail ?? this.videoThumbnail,
      topics: topics ?? this.topics,
      visibility: visibility ?? this.visibility,
      selectedContacts: selectedContacts ?? this.selectedContacts,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      isLiked: isLiked ?? this.isLiked,
      status: status ?? this.status,
      reviewReason: reviewReason ?? this.reviewReason,
    );
  }

  /// 从 JSON 创建
  factory Moment.fromJson(Map<String, dynamic> json) {
    MomentContentType contentType = MomentContentType.text;
    if (json['content_type'] == 2) {
      contentType = MomentContentType.image;
    } else if (json['content_type'] == 3) {
      contentType = MomentContentType.video;
    }

    // 转换头像 URL
    String? avatarUrl = json['user_avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    // 转换媒体 URL
    final rawMediaUrls = List<String>.from(json['media_urls'] ?? []);
    final mediaUrls = rawMediaUrls
        .map((url) => ApiConfig.getMediaUrl(url) ?? url)
        .toList();

    // 转换视频缩略图
    String? videoThumb = json['video_thumbnail'];
    if (videoThumb != null && videoThumb.isNotEmpty) {
      videoThumb = ApiConfig.getMediaUrl(videoThumb);
    }

    return Moment(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name'] ?? '',
      userAvatar: avatarUrl,
      content: json['content'] ?? '',
      contentType: contentType,
      mediaUrls: mediaUrls,
      videoThumbnail: videoThumb,
      topics: List<String>.from(json['topics'] ?? []),
      visibility: MomentVisibilityX.fromValue(json['visibility'] ?? 1),
      selectedContacts: json['selected_contacts'] != null
          ? List<String>.from(json['selected_contacts'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
      likeCount: json['like_count'] ?? 0,
      commentCount: json['comment_count'] ?? 0,
      shareCount: json['share_count'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      status: json['status'] ?? 1,
      reviewReason: json['review_reason'],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    int contentTypeValue = 1;
    if (contentType == MomentContentType.image) {
      contentTypeValue = 2;
    } else if (contentType == MomentContentType.video) {
      contentTypeValue = 3;
    }

    return {
      'content': content,
      'content_type': contentTypeValue,
      'media_urls': mediaUrls,
      'video_thumbnail': videoThumbnail,
      'topics': topics,
      'visibility': visibility.value,
      'selected_contacts': selectedContacts,
    };
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    return '${createdAt.month}月${createdAt.day}日';
  }

  bool get isPendingReview => status == 0;
  bool get isHidden => status == 2;
  String? get moderationHint {
    if (reviewReason == null || reviewReason!.trim().isEmpty) return null;
    return reviewReason!.trim();
  }
}

/// 热门话题
class Topic {
  final String id;
  final String name;
  final int postCount;
  final bool isHot;

  const Topic({
    required this.id,
    required this.name,
    this.postCount = 0,
    this.isHot = false,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      postCount: json['post_count'] ?? 0,
      isHot: json['is_hot'] ?? false,
    );
  }
}

/// 动态状态
class MomentState {
  final List<Moment> moments;
  final List<Topic> hotTopics;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final String? successMessage;
  final bool hasMore;
  final bool isInitialized;
  final int unreadCount; // 未读动态数

  const MomentState({
    this.moments = const [],
    this.hotTopics = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.successMessage,
    this.hasMore = true,
    this.isInitialized = false,
    this.unreadCount = 0,
  });

  MomentState copyWith({
    List<Moment>? moments,
    List<Topic>? hotTopics,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    String? successMessage,
    bool clearSuccessMessage = false,
    bool? hasMore,
    bool? isInitialized,
    int? unreadCount,
  }) {
    return MomentState(
      moments: moments ?? this.moments,
      hotTopics: hotTopics ?? this.hotTopics,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      successMessage: clearSuccessMessage
          ? null
          : (successMessage ?? this.successMessage),
      hasMore: hasMore ?? this.hasMore,
      isInitialized: isInitialized ?? this.isInitialized,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

/// 动态管理 Notifier
class MomentNotifier extends StateNotifier<MomentState> {
  final ApiClient _api;
  final Ref _ref;
  int _page = 1;
  bool _isDisposed = false;

  /// 当前话题过滤（null 表示全站）
  String? _currentTopic;

  // 保存 WebSocket handler ID，用于清理
  String? _momentLikeHandlerId;
  String? _momentCommentHandlerId;
  String? _momentReplyHandlerId;
  WebSocketService? _wsService;

  MomentNotifier(this._api, this._ref) : super(const MomentState()) {
    _setupWebSocketHandlers();
  }

  /// 设置 WebSocket 消息处理
  void _setupWebSocketHandlers() {
    try {
      _wsService = _ref.read(webSocketServiceProvider.notifier);

      // 监听动态点赞通知
      _momentLikeHandlerId = _wsService!.registerHandler('moment_like', (data) {
        if (_isDisposed) return;
        _handleMomentNotification(NotificationType.momentLike);
      });

      // 监听动态评论通知
      _momentCommentHandlerId = _wsService!.registerHandler('moment_comment', (
        data,
      ) {
        if (_isDisposed) return;
        _handleMomentNotification(NotificationType.momentComment);
      });

      // 监听动态回复通知
      _momentReplyHandlerId = _wsService!.registerHandler('moment_reply', (
        data,
      ) {
        if (_isDisposed) return;
        _handleMomentNotification(NotificationType.momentReply);
      });
    } catch (e) {
      debugPrint('设置动态 WebSocket 处理器失败: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 清理 WebSocket handlers
    if (_wsService != null) {
      if (_momentLikeHandlerId != null) {
        _wsService!.unregisterHandler(_momentLikeHandlerId!);
        _momentLikeHandlerId = null;
      }
      if (_momentCommentHandlerId != null) {
        _wsService!.unregisterHandler(_momentCommentHandlerId!);
        _momentCommentHandlerId = null;
      }
      if (_momentReplyHandlerId != null) {
        _wsService!.unregisterHandler(_momentReplyHandlerId!);
        _momentReplyHandlerId = null;
      }
    }
    _likingMoments.clear();
    super.dispose();
  }

  /// 处理动态通知
  void _handleMomentNotification(NotificationType type) {
    // 增加未读计数
    incrementUnreadCount();

    // 播放通知音效
    try {
      final soundService = _ref.read(notificationSoundServiceProvider.notifier);
      soundService.playNotification(type, isInApp: true);
    } catch (e) {
      debugPrint('[Moment] Play notification sound failed: $e');
    }
  }

  /// 增加未读计数
  void incrementUnreadCount() {
    state = state.copyWith(unreadCount: state.unreadCount + 1);
  }

  /// 清除未读计数
  void clearUnreadCount() {
    state = state.copyWith(unreadCount: 0);
  }

  void clearPublishFeedback() {
    state = state.copyWith(clearError: true, clearSuccessMessage: true);
  }

  /// 重置状态（登出时调用）
  void reset() {
    _page = 1;
    _currentTopic = null;
    _likingMoments.clear();
    state = const MomentState();
  }

  /// 初始化
  Future<void> initialize() async {
    if (state.isInitialized) return;
    await loadMoments();
    await loadHotTopics();
  }

  /// 从服务器加载动态
  Future<void> loadMoments() async {
    if (_isDisposed) return;
    state = state.copyWith(isLoading: true, error: null);
    _page = 1;

    try {
      final response = await _api.get(
        '/moment/list',
        queryParameters: {'page': _page, 'page_size': 20},
      );
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final list =
            (response.data['list'] as List?)
                ?.map((e) => Moment.fromJson(e))
                .toList() ??
            [];

        state = state.copyWith(
          moments: list,
          isLoading: false,
          hasMore: list.length >= 20,
          isInitialized: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.message,
          isInitialized: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        isInitialized: true,
      );
    }
  }

  /// 加载更多动态
  Future<void> loadMoreMoments() async {
    // 首次加载或话题切换仍在进行时，不允许触发加载更多
    if (_isDisposed || state.isLoadingMore || !state.hasMore || state.isLoading)
      return;

    state = state.copyWith(isLoadingMore: true);
    _page++;

    try {
      final params = <String, dynamic>{'page': _page, 'page_size': 20};
      // 保持当前话题过滤一致
      if (_currentTopic != null) {
        params['topic'] = _currentTopic;
      }
      final response = await _api.get('/moment/list', queryParameters: params);
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final list =
            (response.data['list'] as List?)
                ?.map((e) => Moment.fromJson(e))
                .toList() ??
            [];

        state = state.copyWith(
          moments: [...state.moments, ...list],
          isLoadingMore: false,
          hasMore: list.length >= 20,
        );
      } else {
        _page--;
        state = state.copyWith(isLoadingMore: false);
      }
    } catch (e) {
      _page--;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// 刷新动态
  Future<void> refresh() async {
    await loadMoments();
  }

  /// 清除话题过滤，恢复全站动态
  Future<void> clearTopicFilter() async {
    _currentTopic = null;
    await loadMoments();
  }

  /// 按话题加载动态（点击话题标签时调用）
  Future<void> loadMomentsByTopic(String topicName) async {
    if (_isDisposed) return;
    _currentTopic = topicName;
    state = state.copyWith(isLoading: true, error: null);
    _page = 1;

    try {
      final response = await _api.get(
        '/moment/list',
        queryParameters: {'page': _page, 'page_size': 20, 'topic': topicName},
      );
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final list =
            (response.data['list'] as List?)
                ?.map((e) => Moment.fromJson(e))
                .toList() ??
            [];
        state = state.copyWith(
          moments: list,
          isLoading: false,
          hasMore: list.length >= 20,
          isInitialized: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.message,
          isInitialized: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        isInitialized: true,
      );
    }
  }

  /// 加载热门话题
  Future<void> loadHotTopics() async {
    try {
      final response = await _api.get('/moment/topics/hot');

      if (response.isSuccess && response.data != null) {
        final list =
            (response.data['list'] as List?)
                ?.map((e) => Topic.fromJson(e))
                .toList() ??
            [];

        state = state.copyWith(hotTopics: list);
      }
    } catch (e) {
      debugPrint('[Moment] Load hot topics failed: $e');
    }
  }

  /// 发布动态（调用API）
  Future<bool> publishMoment({
    required String content,
    MomentContentType contentType = MomentContentType.text,
    List<String> mediaUrls = const [],
    String? videoThumbnail,
    List<String> topics = const [],
    MomentVisibility visibility = MomentVisibility.public,
    List<String>? selectedContacts,
  }) async {
    int contentTypeValue = 1;
    if (contentType == MomentContentType.image) {
      contentTypeValue = 2;
    } else if (contentType == MomentContentType.video) {
      contentTypeValue = 3;
    }

    try {
      debugPrint(
        '[Moment] Publishing: type=$contentTypeValue, urlCount=${mediaUrls?.length ?? 0}',
      );

      final response = await _api.post(
        '/moment/publish',
        data: {
          'content': content,
          'content_type': contentTypeValue,
          'media_urls': mediaUrls,
          if (videoThumbnail != null) 'video_thumbnail': videoThumbnail,
          'topics': topics,
          'visibility': visibility.value,
          if (selectedContacts != null) 'selected_contacts': selectedContacts,
        },
      );

      debugPrint(
        '[Moment] Publish response: code=${response.code}, success=${response.isSuccess}',
      );

      if (response.isSuccess) {
        final data = response.data;
        final publishedStatus = data is Map<String, dynamic>
            ? (data['status'] as int? ?? 1)
            : 1;
        final isPendingReview = publishedStatus == 0;
        final successMessage = isPendingReview
            ? ((response.message.isNotEmpty && response.message != 'success')
                  ? response.message
                  : '动态已提交审核')
            : '发布成功';

        state = state.copyWith(
          clearError: true,
          successMessage: successMessage,
        );
        if (!isPendingReview) {
          await loadMoments();
        }
        return true;
      }

      final errMsg = response.message.isNotEmpty
          ? response.message
          : '发布失败，请重试';
      debugPrint('[Moment] Publish failed: $errMsg');
      state = state.copyWith(error: errMsg);
      return false;
    } catch (e) {
      debugPrint('[Moment] Publish error: $e');
      state = state.copyWith(error: '发布失败，请检查网络连接');
      return false;
    }
  }

  /// 删除动态（调用API）
  Future<bool> deleteMoment(String momentId) async {
    final response = await _api.delete('/moment/$momentId');

    if (response.isSuccess) {
      state = state.copyWith(
        moments: state.moments.where((m) => m.id != momentId).toList(),
      );
      return true;
    }

    return false;
  }

  /// 设为私密（调用API）
  Future<bool> setPrivate(String momentId) async {
    final response = await _api.put(
      '/moment/$momentId',
      data: {'visibility': MomentVisibility.private.value},
    );

    if (response.isSuccess) {
      state = state.copyWith(
        moments: state.moments.map((m) {
          if (m.id == momentId) {
            return m.copyWith(visibility: MomentVisibility.private);
          }
          return m;
        }).toList(),
      );
      return true;
    }

    return false;
  }

  /// 本地移除单条动态（用于屏蔽）
  void removeMomentLocally(String momentId) {
    state = state.copyWith(
      moments: state.moments.where((m) => m.id != momentId).toList(),
    );
  }

  /// 本地移除某用户的所有动态（用于屏蔽用户）
  void removeUserMomentsLocally(String? userId) {
    if (userId == null) return;
    state = state.copyWith(
      moments: state.moments.where((m) => m.userId != userId).toList(),
    );
  }

  /// 屏蔽动态（调用API）
  Future<bool> blockMoment(String momentId) async {
    try {
      final response = await _api.post('/moment/$momentId/block');

      if (response.isSuccess) {
        // 本地移除该动态
        removeMomentLocally(momentId);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Moment] Block moment error: $e');
      return false;
    }
  }

  /// 屏蔽用户动态（调用API）
  Future<bool> blockUser(String userId) async {
    try {
      final response = await _api.post('/moment/block-user/$userId');

      if (response.isSuccess) {
        // 本地移除该用户的所有动态
        removeUserMomentsLocally(userId);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Moment] Block user error: $e');
      return false;
    }
  }

  // 防抖：正在处理的点赞请求
  final Set<String> _likingMoments = {};

  /// 点赞（调用API）
  Future<void> toggleLike(String momentId) async {
    // 防抖：如果正在处理该动态的点赞请求，直接返回
    if (_likingMoments.contains(momentId)) return;
    _likingMoments.add(momentId);

    try {
      // 找到当前动态
      final momentIndex = state.moments.indexWhere((m) => m.id == momentId);
      if (momentIndex == -1) {
        // 动态不在列表中（如从详情页打开），仍需调用 API
        try {
          // 先查询当前点赞状态
          final detailResp = await _api.get('/moment/$momentId');
          if (!detailResp.isSuccess || detailResp.data == null) {
            _likingMoments.remove(momentId);
            return;
          }
          final momentData = detailResp.data as Map<String, dynamic>;
          final wasLiked = momentData['is_liked'] as bool? ?? false;
          final endpoint = wasLiked
              ? '/moment/$momentId/unlike'
              : '/moment/$momentId/like';
          await _api.post(endpoint);
        } finally {
          _likingMoments.remove(momentId);
        }
        return;
      }

      final currentMoment = state.moments[momentIndex];
      final wasLiked = currentMoment.isLiked;

      // 乐观更新
      state = state.copyWith(
        moments: state.moments.map((m) {
          if (m.id == momentId) {
            return m.copyWith(
              isLiked: !wasLiked,
              likeCount: wasLiked ? m.likeCount - 1 : m.likeCount + 1,
            );
          }
          return m;
        }).toList(),
      );

      // 调用API
      final endpoint = wasLiked
          ? '/moment/$momentId/unlike'
          : '/moment/$momentId/like';

      final response = await _api.post(endpoint);

      // 如果失败，回滚
      if (!response.isSuccess) {
        state = state.copyWith(
          moments: state.moments.map((m) {
            if (m.id == momentId) {
              return m.copyWith(
                isLiked: wasLiked,
                likeCount: wasLiked ? m.likeCount + 1 : m.likeCount - 1,
              );
            }
            return m;
          }).toList(),
        );
      }
    } finally {
      _likingMoments.remove(momentId);
    }
  }

  /// 点赞（带当前状态参数，用于详情页）
  Future<bool> toggleLikeWithState(String momentId, bool currentIsLiked) async {
    // 防抖
    if (_likingMoments.contains(momentId)) return currentIsLiked;
    _likingMoments.add(momentId);

    try {
      // 调用API
      final endpoint = currentIsLiked
          ? '/moment/$momentId/unlike'
          : '/moment/$momentId/like';
      final response = await _api.post(endpoint);

      if (response.isSuccess) {
        // 同时更新主列表（如果存在）
        final momentIndex = state.moments.indexWhere((m) => m.id == momentId);
        if (momentIndex != -1) {
          state = state.copyWith(
            moments: state.moments.map((m) {
              if (m.id == momentId) {
                return m.copyWith(
                  isLiked: !currentIsLiked,
                  likeCount: currentIsLiked ? m.likeCount - 1 : m.likeCount + 1,
                );
              }
              return m;
            }).toList(),
          );
        }
        return !currentIsLiked;
      }
      return currentIsLiked;
    } finally {
      _likingMoments.remove(momentId);
    }
  }

  /// 获取评论列表
  Future<List<Comment>> getComments(String momentId, {int page = 1}) async {
    try {
      final response = await _api.get(
        '/moment/$momentId/comments',
        queryParameters: {'page': page, 'page_size': 20},
      );

      if (response.isSuccess && response.data != null) {
        final list =
            (response.data['list'] as List?)
                ?.map((e) => Comment.fromJson(e))
                .toList() ??
            [];
        return list;
      }
      return [];
    } catch (e) {
      debugPrint('[Moment] Get comments error: $e');
      return [];
    }
  }

  /// 发布评论
  Future<Comment?> addComment(
    String momentId,
    String content, {
    String? parentId,
    String? replyToId,
  }) async {
    try {
      final response = await _api.post(
        '/moment/$momentId/comment',
        data: {
          'content': content,
          if (parentId != null) 'parent_id': int.tryParse(parentId),
          if (replyToId != null) 'reply_to_id': int.tryParse(replyToId),
        },
      );

      if (response.isSuccess && response.data != null) {
        // 更新评论数
        state = state.copyWith(
          moments: state.moments.map((m) {
            if (m.id == momentId) {
              return m.copyWith(commentCount: m.commentCount + 1);
            }
            return m;
          }).toList(),
        );

        return Comment.fromJson(response.data as Map<String, dynamic>);
      }
      debugPrint('[Moment] Add comment failed: ${response.message}');
      state = state.copyWith(error: response.message ?? '评论失败');
      return null;
    } catch (e) {
      debugPrint('[Moment] Add comment error: $e');
      state = state.copyWith(error: '评论失败，请检查网络连接');
      return null;
    }
  }
}

/// 评论数据模型
class Comment {
  final String id;
  final String momentId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String content;
  final String? parentId;
  final String? replyToId;
  final String? replyToName;
  final int likeCount;
  final bool isLiked;
  final DateTime createdAt;
  final List<Comment> replies;

  const Comment({
    required this.id,
    required this.momentId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.content,
    this.parentId,
    this.replyToId,
    this.replyToName,
    this.likeCount = 0,
    this.isLiked = false,
    required this.createdAt,
    this.replies = const [],
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    // 转换头像 URL
    String? avatarUrl = json['user_avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return Comment(
      id: json['id']?.toString() ?? '',
      momentId: json['moment_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name'] ?? '',
      userAvatar: avatarUrl,
      content: json['content'] ?? '',
      parentId: json['parent_id']?.toString(),
      replyToId: json['reply_to_id']?.toString(),
      replyToName: json['reply_to_name'],
      likeCount: json['like_count'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
      replies:
          (json['replies'] as List?)
              ?.map((e) => Comment.fromJson(e))
              .toList() ??
          [],
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${createdAt.month}月${createdAt.day}日';
  }
}

final momentProvider = StateNotifierProvider<MomentNotifier, MomentState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return MomentNotifier(api, ref);
});
