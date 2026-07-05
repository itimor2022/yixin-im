import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

const String kDefaultAppDisplayName = '壹信IM';
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
    if (kDebugMode) debugPrint('[SystemSettings] Failed to load cached settings: $e');
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
  final bool allowStrangerMessage;

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
    this.allowStrangerMessage = false,
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
      allowStrangerMessage: json['allow_stranger_message'] == true,
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
  static const Duration _cacheDuration = Duration(minutes: 30);

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
        return settings;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SystemSettings] Error fetching settings: $e');
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
      if (kDebugMode) debugPrint('[SystemSettings] Error reading cache freshness: $e');
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
      if (kDebugMode) debugPrint('[SystemSettings] Error loading from cache: $e');
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
      if (kDebugMode) debugPrint('[SystemSettings] Error syncing official contacts: $e');
    }
    return 0;
  }
}

final systemSettingsServiceProvider = Provider<SystemSettingsService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return SystemSettingsService(apiClient);
});

final systemSettingsProvider = FutureProvider<SystemSettings>((ref) async {
  final service = ref.watch(systemSettingsServiceProvider);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
  });
  final cached = await service.getCachedSettings();

  if (cached != null) {
    final hasFreshCache = await service.hasFreshCache();
    if (!hasFreshCache) {
      Future<void>(() async {
        try {
          await service.getSettings(forceRefresh: true);
          if (!disposed) {
            ref.invalidateSelf();
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[SystemSettings] Background refresh failed: $e');
        }
      });
    }
    return cached;
  }

  return service.getSettings(forceRefresh: true);
});

final officialUsersProvider = FutureProvider<Set<String>>((ref) async {
  final settings = await ref.watch(systemSettingsProvider.future);
  return settings.officialUsers.toSet();
});

final officialChatsProvider = FutureProvider<Set<String>>((ref) async {
  final settings = await ref.watch(systemSettingsProvider.future);
  return {...settings.officialGroups, ...settings.officialChannels};
});
