import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

const String kDefaultAppDisplayName = '易信';
const String kSystemSettingsCacheKey = 'system_settings_cache';

enum MessageCryptoMode {
  plain('plain'),
  compatible('compatible'),
  strict('strict');

  const MessageCryptoMode(this.value);

  final String value;

  bool get isPlain => this == MessageCryptoMode.plain;
  bool get isCompatible => this == MessageCryptoMode.compatible;
  bool get isStrict => this == MessageCryptoMode.strict;

  static MessageCryptoMode fromRaw(dynamic raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'compatible':
        return MessageCryptoMode.compatible;
      case 'strict':
        return MessageCryptoMode.strict;
      default:
        return MessageCryptoMode.plain;
    }
  }
}

Future<SystemSettings?> loadCachedSystemSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(kSystemSettingsCacheKey);
    if (cached != null && cached.isNotEmpty) {
      return SystemSettings.fromJson(
        jsonDecode(cached) as Map<String, dynamic>,
      );
    }
  } catch (e) {
    if (kDebugMode)
      debugPrint('[SystemSettings] Failed to load cached settings: $e');
  }
  return null;
}

class SystemSettings {
  final String appVersionIOS;
  final String appVersionAndroid;
  final String systemName;
  final String systemVersion;
  final String registerBaseUrl;
  final bool appForceUpdate;
  final String appUpdateUrl;
  final String appUpdateMessage;
  final bool allowRegister;
  final bool requireInviteCode;
  final bool requirePhoneBind;
  final bool smsBindReady;
  final bool enableMomentPost;
  final bool momentPostReviewEnabled;
  final bool newUserFollowOfficial;
  final bool newUserJoinGroup;
  final bool newUserJoinChannel;
  final bool groupInviteRequireFriend;
  final bool customPortalEnabled;
  final String customPortalTitle;
  final String customPortalUrl;
  final String customerServiceUrl;
  final String logoImageUrl;
  final String discoverTopImageUrl;
  final String customPortalIconUrl;
  final bool burnAfterReadEnabled;
  final MessageCryptoMode messageCryptoMode;
  final List<String> officialUsers;
  final List<String> officialGroups;
  final List<String> officialChannels;
  final int groupMaxMembers;
  final int channelMaxMembers;
  final int maxImageSize;
  final int maxVideoSize;
  final int maxFileSize;
  final int maxVoiceSize;
  final int revokeMessageMinutes;
  final bool checkinEnabled;
  final bool redPacketEnabled;
  final bool walletEnabled;
  final bool allowStrangerMessage;

  /// ServerDiscovery api.txt 拉取地址（后台数据库配置，管理后台只读）。
  /// 空字符串表示由 App 使用源码内硬编码的 fallback。
  final String apiTxtUrl;

  const SystemSettings({
    this.appVersionIOS = '',
    this.appVersionAndroid = '',
    this.systemName = '',
    this.systemVersion = '',
    this.registerBaseUrl = '',
    this.appForceUpdate = false,
    this.appUpdateUrl = '',
    this.appUpdateMessage = '',
    this.allowRegister = true,
    this.requireInviteCode = false,
    this.requirePhoneBind = false,
    this.smsBindReady = false,
    this.enableMomentPost = true,
    this.momentPostReviewEnabled = false,
    this.newUserFollowOfficial = false,
    this.newUserJoinGroup = false,
    this.newUserJoinChannel = false,
    this.groupInviteRequireFriend = false,
    this.customPortalEnabled = false,
    this.customPortalTitle = '',
    this.customPortalUrl = '',
    this.customerServiceUrl = '',
    this.logoImageUrl = '',
    this.discoverTopImageUrl = '',
    this.customPortalIconUrl = '',
    this.burnAfterReadEnabled = true,
    this.messageCryptoMode = MessageCryptoMode.plain,
    this.officialUsers = const [],
    this.officialGroups = const [],
    this.officialChannels = const [],
    this.groupMaxMembers = 200000,
    this.channelMaxMembers = 0,
    this.maxImageSize = 10,
    this.maxVideoSize = 100,
    this.maxFileSize = 100,
    this.maxVoiceSize = 20,
    this.revokeMessageMinutes = 2,
    this.checkinEnabled = false,
    this.redPacketEnabled = false,
    this.walletEnabled = false,
    this.allowStrangerMessage = false,
    this.apiTxtUrl = '',
  });

  factory SystemSettings.fromJson(Map<String, dynamic> json) {
    return SystemSettings(
      appVersionIOS: json['app_version_ios']?.toString() ?? '',
      appVersionAndroid: json['app_version_android']?.toString() ?? '',
      systemName: json['system_name']?.toString() ?? '',
      systemVersion: json['system_version']?.toString() ?? '',
      registerBaseUrl: json['register_base_url']?.toString() ?? '',
      appForceUpdate: json['app_force_update'] == true,
      appUpdateUrl: json['app_update_url']?.toString() ?? '',
      appUpdateMessage: json['app_update_message']?.toString() ?? '',
      allowRegister: json['allow_register'] != false,
      requireInviteCode: json['require_invite_code'] == true,
      requirePhoneBind: json['require_phone_bind'] == true,
      smsBindReady: json['sms_bind_ready'] == true,
      enableMomentPost: json['enable_moment_post'] != false,
      momentPostReviewEnabled: json['moment_post_review_enabled'] == true,
      newUserFollowOfficial: json['new_user_follow_official'] == true,
      newUserJoinGroup: json['new_user_join_group'] == true,
      newUserJoinChannel: json['new_user_join_channel'] == true,
      groupInviteRequireFriend: json['group_invite_require_friend'] == true,
      customPortalEnabled: json['custom_portal_enabled'] == true,
      customPortalTitle: json['custom_portal_title']?.toString() ?? '',
      customPortalUrl: json['custom_portal_url']?.toString() ?? '',
      customerServiceUrl: json['customer_service_url']?.toString() ?? '',
      logoImageUrl: json['logo_image_url']?.toString() ?? '',
      discoverTopImageUrl: json['discover_top_image_url']?.toString() ?? '',
      customPortalIconUrl: json['custom_portal_icon_url']?.toString() ?? '',
      burnAfterReadEnabled: json['burn_after_read_enabled'] != false,
      messageCryptoMode: MessageCryptoMode.fromRaw(json['message_crypto_mode']),
      officialUsers:
          (json['official_users'] as List<dynamic>?)?.cast<String>() ??
              const [],
      officialGroups:
          (json['official_groups'] as List<dynamic>?)?.cast<String>() ??
              const [],
      officialChannels:
          (json['official_channels'] as List<dynamic>?)?.cast<String>() ??
              const [],
      groupMaxMembers: json['group_max_members'] as int? ?? 200000,
      channelMaxMembers: json['channel_max_members'] as int? ?? 0,
      maxImageSize: json['max_image_size'] as int? ?? 10,
      maxVideoSize: json['max_video_size'] as int? ?? 100,
      maxFileSize: json['max_file_size'] as int? ?? 100,
      maxVoiceSize: json['max_voice_size'] as int? ?? 20,
      revokeMessageMinutes: json['revoke_message_minutes'] as int? ?? 2,
      checkinEnabled: json['checkin_enabled'] == true,
      redPacketEnabled: json['red_packet_enabled'] == true,
      walletEnabled: json['wallet_enabled'] == true,
      allowStrangerMessage: json['allow_stranger_message'] == true,
      apiTxtUrl: json['api_txt_url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'app_version_ios': appVersionIOS,
        'app_version_android': appVersionAndroid,
        'system_name': systemName,
        'system_version': systemVersion,
        'register_base_url': registerBaseUrl,
        'app_force_update': appForceUpdate,
        'app_update_url': appUpdateUrl,
        'app_update_message': appUpdateMessage,
        'allow_register': allowRegister,
        'require_invite_code': requireInviteCode,
        'require_phone_bind': requirePhoneBind,
        'sms_bind_ready': smsBindReady,
        'enable_moment_post': enableMomentPost,
        'moment_post_review_enabled': momentPostReviewEnabled,
        'new_user_follow_official': newUserFollowOfficial,
        'new_user_join_group': newUserJoinGroup,
        'new_user_join_channel': newUserJoinChannel,
        'group_invite_require_friend': groupInviteRequireFriend,
        'custom_portal_enabled': customPortalEnabled,
        'custom_portal_title': customPortalTitle,
        'custom_portal_url': customPortalUrl,
        'custom_portal_icon_url': customPortalIconUrl,
        'logo_image_url': logoImageUrl,
        'discover_top_image_url': discoverTopImageUrl,
        'burn_after_read_enabled': burnAfterReadEnabled,
        'message_crypto_mode': messageCryptoMode.value,
        'official_users': officialUsers,
        'official_groups': officialGroups,
        'official_channels': officialChannels,
        'group_max_members': groupMaxMembers,
        'channel_max_members': channelMaxMembers,
        'max_image_size': maxImageSize,
        'max_video_size': maxVideoSize,
        'max_file_size': maxFileSize,
        'max_voice_size': maxVoiceSize,
        'revoke_message_minutes': revokeMessageMinutes,
        'checkin_enabled': checkinEnabled,
        'red_packet_enabled': redPacketEnabled,
        'wallet_enabled': walletEnabled,
        'api_txt_url': apiTxtUrl,
      };

  String get displayName {
    final name = systemName.trim();
    return name.isNotEmpty ? name : kDefaultAppDisplayName;
  }

  String get portalTitle {
    final title = customPortalTitle.trim();
    return title.isNotEmpty ? title : '网站';
  }

  String get portalUrl => customPortalUrl.trim();

  String buildInviteLink(String username) {
    final cleanBaseUrl =
        registerBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (cleanBaseUrl.isEmpty) {
      return '';
    }
    return '$cleanBaseUrl/invite/${Uri.encodeComponent(username)}';
  }

  String? get portalIconUrl {
    final icon = customPortalIconUrl.trim();
    if (icon.isEmpty) {
      return null;
    }
    return ApiConfig.getMediaUrl(icon);
  }

  bool get hasCustomPortal => customPortalEnabled && portalUrl.isNotEmpty;

  bool isOfficialUser(String userUUID) {
    return officialUsers.contains(userUUID);
  }

  bool isOfficialGroup(String chatUUID) {
    return officialGroups.contains(chatUUID);
  }

  bool isOfficialChannel(String chatUUID) {
    return officialChannels.contains(chatUUID);
  }

  bool isOfficialChat(String chatUUID) {
    return officialGroups.contains(chatUUID) ||
        officialChannels.contains(chatUUID);
  }
}

class SystemSettingsService {
  SystemSettingsService(this._apiClient);

  final ApiClient _apiClient;

  static const String _cacheKey = kSystemSettingsCacheKey;
  static const String _cacheTimeKey = 'system_settings_cache_time';
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// ServerDiscovery 冷启动时读取的 api.txt 地址缓存键。
  /// 这里独立成一个 top-level key（而不是嵌在 systemSettingsCache 里），
  /// 是因为 ServerDiscovery 在拿到 API 服务器之前就要用它，读单值最省事。
  static const String kApiTxtUrlPrefsKey = 'svc_disc_api_txt_url';

  SystemSettings? _cachedSettings;

  SystemSettings? get cachedSettings => _cachedSettings;

  Future<SystemSettings> getSettings({bool forceRefresh = false}) async {
    if (_cachedSettings != null && !forceRefresh) {
      return _cachedSettings!;
    }

    if (!forceRefresh) {
      final cached = await _loadFromCache();
      if (cached != null) {
        _cachedSettings = cached;
        return cached;
      }
    }

    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/app/settings',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final settings = SystemSettings.fromJson(response.data!);
        _cachedSettings = settings;
        await _saveToCache(settings);
        await _persistApiTxtUrl(settings.apiTxtUrl);
        return settings;
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[SystemSettings] Error fetching settings: $e');
    }

    final cachedFallback = _cachedSettings ?? await loadCachedSystemSettings();
    if (cachedFallback != null) {
      _cachedSettings = cachedFallback;
      return cachedFallback;
    }

    return const SystemSettings();
  }

  Future<SystemSettings?> getCachedSettings({
    bool allowExpired = true,
  }) async {
    if (_cachedSettings != null) {
      return _cachedSettings;
    }

    final cached = await _loadFromCache(ignoreExpiry: allowExpired);
    if (cached != null) {
      _cachedSettings = cached;
    }
    return cached;
  }

  Future<bool> hasFreshCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheTime = prefs.getInt(_cacheTimeKey) ?? 0;
      if (cacheTime <= 0) {
        return false;
      }
      final age = DateTime.now().millisecondsSinceEpoch - cacheTime;
      return age <= _cacheDuration.inMilliseconds;
    } catch (e) {
      if (kDebugMode)
        debugPrint('[SystemSettings] Error reading cache freshness: $e');
      return false;
    }
  }

  Future<SystemSettings?> _loadFromCache({bool ignoreExpiry = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheTime = prefs.getInt(_cacheTimeKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (!ignoreExpiry && now - cacheTime > _cacheDuration.inMilliseconds) {
        return null;
      }

      final jsonStr = prefs.getString(_cacheKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        return SystemSettings.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[SystemSettings] Error loading from cache: $e');
    }
    return null;
  }

  Future<void> _saveToCache(SystemSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(settings.toJson()));
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) debugPrint('[SystemSettings] Error saving to cache: $e');
    }
  }

  /// 把最新拿到的 api.txt 地址持久化到 SharedPreferences，供下次冷启动
  /// ServerDiscovery 直接读取（不必等 /app/settings 二次拉取才能拿到）。
  /// 空字符串主动清除缓存，让 ServerDiscovery 回落到源码内硬编码 fallback。
  Future<void> _persistApiTxtUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = url.trim();
      if (trimmed.isEmpty) {
        await prefs.remove(kApiTxtUrlPrefsKey);
      } else {
        await prefs.setString(kApiTxtUrlPrefsKey, trimmed);
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[SystemSettings] Error persisting api_txt_url: $e');
    }
  }

  Future<void> clearCache() async {
    _cachedSettings = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);
  }

  Future<bool> isOfficialUser(String userUUID) async {
    final settings = await getSettings();
    return settings.isOfficialUser(userUUID);
  }

  Future<bool> isOfficialChat(String chatUUID) async {
    final settings = await getSettings();
    return settings.isOfficialChat(chatUUID);
  }

  Future<int> syncOfficialContacts() async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/user-settings/sync-official-contacts',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return response.data!['added'] as int? ?? 0;
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[SystemSettings] Error syncing official contacts: $e');
    }
    return 0;
  }
}

final systemSettingsServiceProvider = Provider<SystemSettingsService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return SystemSettingsService(apiClient);
});

// 防止多次 invalidateSelf 造成无限循环
bool _settingsRefreshing = false;

final systemSettingsProvider = FutureProvider<SystemSettings>((ref) async {
  final service = ref.watch(systemSettingsServiceProvider);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
  });

  // 始终先尝试从 API 获取最新设置（带本地缓存兜底）
  // 第一次加载直接拉 API，之后利用 _cacheDuration 控制频率
  final hasFresh = await service.hasFreshCache();

  if (hasFresh) {
    // 缓存新鲜：直接返回缓存，异步不刷新（避免循环）
    final cached = await service.getCachedSettings();
    if (cached != null) return cached;
  }

  // 缓存过期或不存在：强制从 API 拉取
  if (!_settingsRefreshing) {
    _settingsRefreshing = true;
    try {
      final fresh = await service.getSettings(forceRefresh: true);
      _settingsRefreshing = false;
      return fresh;
    } catch (e) {
      _settingsRefreshing = false;
      if (kDebugMode) debugPrint('[SystemSettings] Fetch failed: $e');
    }
  }

  // 兜底：返回任何可用缓存
  final fallback = await service.getCachedSettings(allowExpired: true);
  return fallback ?? const SystemSettings();
});

final officialUsersProvider = FutureProvider<Set<String>>((ref) async {
  final settings = await ref.watch(systemSettingsProvider.future);
  return settings.officialUsers.toSet();
});

final officialChatsProvider = FutureProvider<Set<String>>((ref) async {
  final settings = await ref.watch(systemSettingsProvider.future);
  return {...settings.officialGroups, ...settings.officialChannels};
});
