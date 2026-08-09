// 文件用途：管理 MomentVisibility 相关状态、异步加载与界面通知，属于朋友圈动态。
// 核心逻辑：以 Riverpod 暴露 MomentVisibility 状态，串联 API、本地缓存和生命周期事件，统一处理加载、刷新、失败与重试。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/notification_sound_service.dart';

String _momentText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _momentServerMessage(
  String? raw, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  return localizeServerMessage(
    raw,
    fallbackZhCN: zhCN,
    fallbackZhTW: zhTW,
    fallbackEn: en,
  );
}

// 关键声明：moment provider 是状态边界，统一管理加载、成功、失败和刷新状态，避免页面直接维护异步请求结果。
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
        return _momentText(zhCN: '公开', zhTW: '公開', en: 'Public');
      case MomentVisibility.contacts:
        return _momentText(zhCN: '联系人', zhTW: '聯絡人', en: 'Contacts');
      case MomentVisibility.selected:
        return _momentText(
          zhCN: '部分可见',
          zhTW: '部分可見',
          en: 'Selected Contacts',
        );
      case MomentVisibility.private:
        return _momentText(zhCN: '私密', zhTW: '私密', en: 'Private');
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
    final mediaUrls =
        rawMediaUrls.map((url) => ApiConfig.getMediaUrl(url) ?? url).toList();

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

    if (diff.inMinutes < 1) {
      return _momentText(zhCN: '刚刚', zhTW: '剛剛', en: 'Just now');
    }
    if (diff.inMinutes < 60) {
      return _momentText(
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inHours < 24) {
      return _momentText(
        zhCN: '${diff.inHours}小时前',
        zhTW: '${diff.inHours}小時前',
        en: '${diff.inHours}h ago',
      );
    }
    if (diff.inDays < 7) {
      return _momentText(
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays}d ago',
      );
    }
    if (diff.inDays < 30) {
      return _momentText(
        zhCN: '${diff.inDays ~/ 7}周前',
        zhTW: '${diff.inDays ~/ 7}週前',
        en: '${diff.inDays ~/ 7}w ago',
      );
    }
    return _momentText(
      zhCN: '${createdAt.month}月${createdAt.day}日',
      zhTW: '${createdAt.month}月${createdAt.day}日',
      en: '${createdAt.month}/${createdAt.day}',
    );
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
      successMessage:
          clearSuccessMessage ? null : (successMessage ?? this.successMessage),
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
  // Notifier 统一持有页码、游标和话题条件，页面只负责触发加载动作。
  int _page = 1;
  String? _nextCursor;
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

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
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
    // WebSocket 事件只更新未读通知投影，不直接修改动态列表；Feed 仍以列表接口为准。
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
    _nextCursor = null;
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
    // 首屏请求会重置两套分页标记；后续优先使用服务端游标，
    // 仅在旧接口未返回游标时回退到页码分页。
    _page = 1;
    _nextCursor = null;

    try {
      final response = await _api.get(
        '/moment/list',
        queryParameters: {'page_size': 20},
      );
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final list = (response.data['list'] as List?)
                ?.map((e) => Moment.fromJson(e))
                .toList() ??
            [];
        final data = response.data as Map;
        _nextCursor = (data['next_cursor'] ?? '').toString();
        if (_nextCursor != null && _nextCursor!.isEmpty) _nextCursor = null;
        final hasMore = data.containsKey('has_more')
            ? data['has_more'] == true
            : list.length >= 20;

        state = state.copyWith(
          moments: list,
          isLoading: false,
          hasMore: hasMore,
          isInitialized: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _momentServerMessage(
            response.message,
            zhCN: '加载动态失败，请稍后重试',
            zhTW: '載入動態失敗，請稍後重試',
            en: 'Failed to load moments. Please try again later.',
          ),
          isInitialized: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _momentText(
          zhCN: '加载动态失败，请检查网络后重试',
          zhTW: '載入動態失敗，請檢查網路後重試',
          en: 'Failed to load moments. Check your network and try again.',
        ),
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
    final nextPage = _page + 1;

    try {
      final params = <String, dynamic>{'page_size': 20};
      if (_nextCursor != null && _nextCursor!.isNotEmpty) {
        params['cursor'] = _nextCursor;
      } else {
        params['page'] = nextPage;
      }
      // 话题条件必须贯穿后续分页，否则第二页会混入全站动态。
      if (_currentTopic != null) {
        params['topic'] = _currentTopic;
      }
      final response = await _api.get('/moment/list', queryParameters: params);
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final list = (response.data['list'] as List?)
                ?.map((e) => Moment.fromJson(e))
                .toList() ??
            [];
        final data = response.data as Map;
        _nextCursor = (data['next_cursor'] ?? '').toString();
        if (_nextCursor != null && _nextCursor!.isEmpty) _nextCursor = null;
        final hasMore = data.containsKey('has_more')
            ? data['has_more'] == true
            : list.length >= 20;
        _page = nextPage;

        state = state.copyWith(
          moments: [...state.moments, ...list],
          isLoadingMore: false,
          hasMore: hasMore,
        );
      } else {
        state = state.copyWith(isLoadingMore: false);
      }
    } catch (e) {
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
    _nextCursor = null;

    try {
      final response = await _api.get(
        '/moment/list',
        queryParameters: {'page_size': 20, 'topic': topicName},
      );
      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        final list = (response.data['list'] as List?)
                ?.map((e) => Moment.fromJson(e))
                .toList() ??
            [];
        final data = response.data as Map;
        _nextCursor = (data['next_cursor'] ?? '').toString();
        if (_nextCursor != null && _nextCursor!.isEmpty) _nextCursor = null;
        final hasMore = data.containsKey('has_more')
            ? data['has_more'] == true
            : list.length >= 20;
        state = state.copyWith(
          moments: list,
          isLoading: false,
          hasMore: hasMore,
          isInitialized: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _momentServerMessage(
            response.message,
            zhCN: '加载动态失败，请稍后重试',
            zhTW: '載入動態失敗，請稍後重試',
            en: 'Failed to load moments. Please try again later.',
          ),
          isInitialized: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _momentText(
          zhCN: '加载动态失败，请检查网络后重试',
          zhTW: '載入動態失敗，請檢查網路後重試',
          en: 'Failed to load moments. Check your network and try again.',
        ),
        isInitialized: true,
      );
    }
  }

  /// 加载热门话题
  Future<void> loadHotTopics() async {
    try {
      final response = await _api.get('/moment/topics/hot');

      if (response.isSuccess && response.data != null) {
        final list = (response.data['list'] as List?)
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
        // 是否进入列表以服务端最终审核状态为准。待审核动态只反馈提交结果，
        // 不能提前刷新进公开列表。
        final publishedStatus =
            data is Map<String, dynamic> ? (data['status'] as int? ?? 1) : 1;
        final isPendingReview = publishedStatus == 0;
        final successMessage = isPendingReview
            ? ((response.message.isNotEmpty && response.message != 'success')
                ? _momentServerMessage(
                    response.message,
                    zhCN: '动态已提交审核',
                    zhTW: '動態已提交審核',
                    en: 'Post submitted for review',
                  )
                : _momentText(
                    zhCN: '动态已提交审核',
                    zhTW: '動態已提交審核',
                    en: 'Post submitted for review',
                  ))
            : _momentText(
                zhCN: '发布成功',
                zhTW: '發布成功',
                en: 'Posted successfully',
              );

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
          ? _momentServerMessage(
              response.message,
              zhCN: '发布失败，请重试',
              zhTW: '發布失敗，請重試',
              en: 'Post failed. Please try again.',
            )
          : _momentText(
              zhCN: '发布失败，请重试',
              zhTW: '發布失敗，請重試',
              en: 'Post failed, please try again',
            );
      debugPrint('[Moment] Publish failed: $errMsg');
      state = state.copyWith(error: errMsg);
      return false;
    } catch (e) {
      debugPrint('[Moment] Publish error: $e');
      state = state.copyWith(
        error: _momentText(
          zhCN: '发布失败，请检查网络连接',
          zhTW: '發布失敗，請檢查網路連線',
          en: 'Post failed. Check your network connection',
        ),
      );
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
        // 先等待服务端确认屏蔽成功，再从本地 Feed 投影移除，失败时保留原列表。
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
        // 用户屏蔽成功后再批量清理本地投影，避免接口失败造成误隐藏。
        removeUserMomentsLocally(userId);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Moment] Block user error: $e');
      return false;
    }
  }

  // 同一动态只允许一个点赞请求在途，避免连续点击让“当前状态”失去顺序。
  final Set<String> _likingMoments = {};

  /// 点赞（调用API）
  Future<void> toggleLike(String momentId) async {
    // 列表内先乐观更新以保证即时反馈；接口失败时必须按操作前状态回滚。
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
          final endpoint =
              wasLiked ? '/moment/$momentId/unlike' : '/moment/$momentId/like';
          await _api.post(endpoint);
        } finally {
          _likingMoments.remove(momentId);
        }
        return;
      }

      final currentMoment = state.moments[momentIndex];
      final wasLiked = currentMoment.isLiked;

      // 乐观更新：这里只改展示副本，服务端响应仍是最终结果。
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
      final endpoint =
          wasLiked ? '/moment/$momentId/unlike' : '/moment/$momentId/like';

      final response = await _api.post(endpoint);

      // 接口失败时同时恢复点赞标记和计数，避免两者不一致。
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
    // 详情可能由通知等入口直接打开，不一定存在于主列表；调用方传入其展示状态，
    // 返回服务端确认后的状态，并在能找到列表副本时同步更新。
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
        final list = (response.data['list'] as List?)
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
      state = state.copyWith(
        error: _momentServerMessage(
          response.message,
          zhCN: '评论失败',
          zhTW: '留言失敗',
          en: 'Comment failed',
        ),
      );
      return null;
    } catch (e) {
      debugPrint('[Moment] Add comment error: $e');
      state = state.copyWith(
        error: _momentText(
          zhCN: '评论失败，请检查网络连接',
          zhTW: '留言失敗，請檢查網路連線',
          en: 'Comment failed. Check your network connection',
        ),
      );
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
      replies: (json['replies'] as List?)
              ?.map((e) => Comment.fromJson(e))
              .toList() ??
          [],
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) {
      return _momentText(zhCN: '刚刚', zhTW: '剛剛', en: 'Just now');
    }
    if (diff.inMinutes < 60) {
      return _momentText(
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inHours < 24) {
      return _momentText(
        zhCN: '${diff.inHours}小时前',
        zhTW: '${diff.inHours}小時前',
        en: '${diff.inHours}h ago',
      );
    }
    if (diff.inDays < 7) {
      return _momentText(
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays}d ago',
      );
    }
    return _momentText(
      zhCN: '${createdAt.month}月${createdAt.day}日',
      zhTW: '${createdAt.month}月${createdAt.day}日',
      en: '${createdAt.month}/${createdAt.day}',
    );
  }
}

final momentProvider = StateNotifierProvider<MomentNotifier, MomentState>((
  ref,
) {
  ref.watch(currentAccountIdProvider);
  final api = ref.watch(apiClientProvider);
  return MomentNotifier(api, ref);
});
