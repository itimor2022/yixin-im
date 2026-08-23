// 文件用途：封装 MessageCryptoMode 对应的后端 API 请求、响应模型与错误处理。
// 核心逻辑：把 MessageCryptoMode 相关请求集中到 API 层，负责参数编码、响应解析、鉴权错误和分页/游标边界。
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/app_localizations.dart';
import '../background_keep_alive_policy.dart';
import 'api_client.dart';

const String kDefaultAppDisplayName = '通用IM';
const String kSystemSettingsCacheKey = 'system_settings_cache';

const String kDefaultAppDisplayNameEn = '通用IM';

// 流程逻辑：`defaultAppDisplayName` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
String defaultAppDisplayName({AppLanguage? language}) {
  switch (language ?? AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return kDefaultAppDisplayNameEn;
    case AppLanguage.zhTW:
    case AppLanguage.zhCN:
      return kDefaultAppDisplayName;
  }
}

String _systemSettingsText({
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

String _firstNonEmpty(String? primary, String? fallback) {
  final value = primary?.trim() ?? '';
  return value.isNotEmpty ? value : (fallback?.trim() ?? '');
}

// 关键声明：system settings service 负责请求参数和响应模型的转换，统一处理鉴权错误、分页边界和服务端字段兼容。
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
    debugPrint('[SystemSettings] Failed to load cached settings: $e');
  }
  return null;
}

class ChatAttachmentMenuSettings {
  final bool enabled;
  final bool album;
  final bool camera;
  final bool call;
  final bool location;
  final bool redPacket;
  final bool transfer;
  final bool favorite;
  final bool file;

  const ChatAttachmentMenuSettings({
    this.enabled = true,
    this.album = true,
    this.camera = true,
    this.call = true,
    this.location = true,
    this.redPacket = true,
    this.transfer = true,
    this.favorite = true,
    this.file = true,
  });

  factory ChatAttachmentMenuSettings.fromJson(dynamic raw) {
    if (raw is! Map) return const ChatAttachmentMenuSettings();
    late final Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(raw);
    } catch (_) {
      return const ChatAttachmentMenuSettings();
    }
    return ChatAttachmentMenuSettings(
      enabled: json['enabled'] != false,
      album: json['album'] != false,
      camera: json['camera'] != false,
      call: json['call'] != false,
      location: json['location'] != false,
      redPacket: json['red_packet'] != false,
      transfer: json['transfer'] != false,
      favorite: json['favorite'] != false,
      file: json['file'] != false,
    );
  }

  bool get hasEnabledItem =>
      album ||
      camera ||
      call ||
      location ||
      redPacket ||
      transfer ||
      favorite ||
      file;

  bool hasAvailableItem({
    required bool isPrivateChat,
    required bool isGroupChat,
    required bool burnAfterReadEnabled,
  }) {
    if (!enabled) return false;
    return album ||
        camera ||
        (call && (isPrivateChat || isGroupChat)) ||
        location ||
        (redPacket && (isPrivateChat || isGroupChat)) ||
        (transfer && isPrivateChat) ||
        favorite ||
        file ||
        burnAfterReadEnabled;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'album': album,
        'camera': camera,
        'call': call,
        'location': location,
        'red_packet': redPacket,
        'transfer': transfer,
        'favorite': favorite,
        'file': file,
      };
}

class IOSComplianceSettings {
  final bool enabled;
  final bool vipEnabled;
  final bool walletEnabled;
  final bool walletRechargeEnabled;
  final bool momentVideoEnabled;
  final bool customPortalEnabled;
  final bool checkinEnabled;

  const IOSComplianceSettings({
    this.enabled = true,
    this.vipEnabled = false,
    this.walletEnabled = false,
    this.walletRechargeEnabled = false,
    this.momentVideoEnabled = false,
    this.customPortalEnabled = false,
    this.checkinEnabled = false,
  });

  factory IOSComplianceSettings.fromJson(dynamic raw) {
    if (raw is! Map) return const IOSComplianceSettings();
    final json = Map<String, dynamic>.from(raw);
    final walletEnabled = json['wallet_enabled'] == true;
    return IOSComplianceSettings(
      enabled: json['enabled'] != false,
      vipEnabled: json['vip_enabled'] == true,
      walletEnabled: walletEnabled,
      walletRechargeEnabled:
          walletEnabled && json['wallet_recharge_enabled'] == true,
      momentVideoEnabled: json['moment_video_enabled'] == true,
      customPortalEnabled: json['custom_portal_enabled'] == true,
      checkinEnabled: json['checkin_enabled'] == true,
    );
  }

  bool get allowsVIP => !enabled || vipEnabled;
  bool get allowsWallet => !enabled || walletEnabled;
  bool get allowsWalletRecharge =>
      !enabled || (walletEnabled && walletRechargeEnabled);
  bool get allowsMomentVideo => !enabled || momentVideoEnabled;
  bool get allowsCustomPortal => !enabled || customPortalEnabled;
  bool get allowsCheckin => checkinEnabled;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'vip_enabled': vipEnabled,
        'wallet_enabled': walletEnabled,
        'wallet_recharge_enabled': walletRechargeEnabled,
        'moment_video_enabled': momentVideoEnabled,
        'custom_portal_enabled': customPortalEnabled,
        'checkin_enabled': checkinEnabled,
      };
}

enum FriendAddMode {
  direct('direct'),
  approval('approval'),
  disabled('disabled');

  const FriendAddMode(this.value);

  final String value;

  static FriendAddMode fromRaw(dynamic value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'direct':
        return FriendAddMode.direct;
      case 'disabled':
        return FriendAddMode.disabled;
      default:
        return FriendAddMode.approval;
    }
  }
}

class ChatImageDirectUploadSettings {
  const ChatImageDirectUploadSettings({
    this.enabled = false,
    this.platforms = const <String>['android', 'ios'],
    this.rolloutPercent = 0,
    this.maxConcurrency = 3,
  });

  final bool enabled;
  final List<String> platforms;
  final int rolloutPercent;
  final int maxConcurrency;

  factory ChatImageDirectUploadSettings.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const ChatImageDirectUploadSettings();
    }
    final json = Map<String, dynamic>.from(raw);
    final platforms = (json['platforms'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>['android', 'ios'];
    return ChatImageDirectUploadSettings(
      enabled: json['enabled'] == true,
      platforms:
          platforms.isEmpty ? const <String>['android', 'ios'] : platforms,
      rolloutPercent:
          int.tryParse(json['rollout_percent']?.toString() ?? '') ?? 0,
      maxConcurrency:
          int.tryParse(json['max_concurrency']?.toString() ?? '') ?? 3,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'platforms': platforms,
        'rollout_percent': rolloutPercent,
        'max_concurrency': maxConcurrency,
      };
}

class SystemSettings {
  final String appVersionIOS;
  final String appVersionAndroid;
  final String appUpdateUrlIOS;
  final String appUpdateUrlAndroid;
  final String minSupportedVersionIOS;
  final String minSupportedVersionAndroid;
  final String systemName;
  final String systemVersion;
  final String registerBaseUrl;
  final String supportOnlineUrl;
  final String supportQQ;
  final bool appForceUpdate;
  final bool forceKeepAliveEnabled;
  final String appUpdateUrl;
  final String appUpdateMessage;
  final bool splashEnabled;
  final String splashImageUrl;
  final int splashDurationMs;
  final bool allowRegister;
  final bool allowQuickRegister;
  final bool requireInviteCode;
  final bool requireGenderOnRegister;
  final bool requirePhoneBind;
  final String usernameType;
  final bool smsBindReady;
  final bool emailRegistrationReady;
  final bool enableMomentPost;
  final bool momentPostReviewEnabled;
  final IOSComplianceSettings iosCompliance;
  final bool newUserFollowOfficial;
  final bool newUserJoinGroup;
  final bool newUserJoinChannel;
  final bool groupInviteRequireFriend;
  final FriendAddMode friendAddMode;
  final bool customPortalEnabled;
  final String customPortalTitle;
  final String customPortalUrl;
  final String customPortalIconUrl;
  final ChatAttachmentMenuSettings chatAttachmentMenu;
  final bool burnAfterReadEnabled;
  final bool voiceTranscriptionEnabled;
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
  final ChatImageDirectUploadSettings chatImageDirectUpload;

  const SystemSettings({
    this.appVersionIOS = '',
    this.appVersionAndroid = '',
    this.appUpdateUrlIOS = '',
    this.appUpdateUrlAndroid = '',
    this.minSupportedVersionIOS = '',
    this.minSupportedVersionAndroid = '',
    this.systemName = '',
    this.systemVersion = '',
    this.registerBaseUrl = '',
    this.supportOnlineUrl = '',
    this.supportQQ = '',
    this.appForceUpdate = false,
    this.forceKeepAliveEnabled = false,
    this.appUpdateUrl = '',
    this.appUpdateMessage = '',
    this.splashEnabled = false,
    this.splashImageUrl = '',
    this.splashDurationMs = 3000,
    this.allowRegister = true,
    this.allowQuickRegister = false,
    this.requireInviteCode = false,
    this.requireGenderOnRegister = true,
    this.requirePhoneBind = false,
    this.usernameType = 'phone',
    this.smsBindReady = false,
    this.emailRegistrationReady = false,
    this.enableMomentPost = true,
    this.momentPostReviewEnabled = false,
    this.iosCompliance = const IOSComplianceSettings(),
    this.newUserFollowOfficial = false,
    this.newUserJoinGroup = false,
    this.newUserJoinChannel = false,
    this.groupInviteRequireFriend = false,
    this.friendAddMode = FriendAddMode.approval,
    this.customPortalEnabled = false,
    this.customPortalTitle = '',
    this.customPortalUrl = '',
    this.customPortalIconUrl = '',
    this.chatAttachmentMenu = const ChatAttachmentMenuSettings(),
    this.burnAfterReadEnabled = true,
    this.voiceTranscriptionEnabled = false,
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
    this.chatImageDirectUpload = const ChatImageDirectUploadSettings(),
  });

  factory SystemSettings.fromJson(Map<String, dynamic> json) {
    return SystemSettings(
      appVersionIOS: _firstNonEmpty(
        json['latest_version_ios']?.toString(),
        json['app_version_ios']?.toString(),
      ),
      appVersionAndroid: _firstNonEmpty(
        json['latest_version_android']?.toString(),
        json['app_version_android']?.toString(),
      ),
      appUpdateUrlIOS: _firstNonEmpty(
        json['app_update_url_ios']?.toString(),
        json['app_update_url']?.toString(),
      ),
      appUpdateUrlAndroid: _firstNonEmpty(
        json['app_update_url_android']?.toString(),
        json['app_update_url']?.toString(),
      ),
      minSupportedVersionIOS:
          json['min_supported_version_ios']?.toString() ?? '',
      minSupportedVersionAndroid:
          json['min_supported_version_android']?.toString() ?? '',
      systemName: json['system_name']?.toString() ?? '',
      systemVersion: json['system_version']?.toString() ?? '',
      registerBaseUrl: json['register_base_url']?.toString() ?? '',
      supportOnlineUrl: json['support_online_url']?.toString() ?? '',
      supportQQ: json['support_qq']?.toString() ?? '',
      appForceUpdate: json['app_force_update'] == true,
      forceKeepAliveEnabled: json['force_keep_alive_enabled'] == true,
      appUpdateUrl: json['app_update_url']?.toString() ?? '',
      appUpdateMessage: json['app_update_message']?.toString() ?? '',
      splashEnabled: json['splash_enabled'] == true,
      splashImageUrl: json['splash_image_url']?.toString() ?? '',
      splashDurationMs:
          int.tryParse(json['splash_duration_ms']?.toString() ?? '') ?? 3000,
      allowRegister: json['allow_register'] != false,
      allowQuickRegister: json['allow_quick_register'] == true,
      requireInviteCode: json['require_invite_code'] == true,
      requireGenderOnRegister: json['require_gender_on_register'] != false,
      requirePhoneBind: json['require_phone_bind'] == true,
      // 注册用户名类型：phone=仅中国手机号 / alphanumeric=英文和数字。
      // 默认回退为 phone，兼容未配置或异常值。
      usernameType:
          json['username_type']?.toString().toLowerCase() == 'alphanumeric'
              ? 'alphanumeric'
              : 'phone',
      smsBindReady: json['sms_bind_ready'] == true,
      emailRegistrationReady: json['email_registration_ready'] == true,
      enableMomentPost: json['enable_moment_post'] != false,
      momentPostReviewEnabled: json['moment_post_review_enabled'] == true,
      iosCompliance: IOSComplianceSettings.fromJson(json['ios_compliance']),
      newUserFollowOfficial: json['new_user_follow_official'] == true,
      newUserJoinGroup: json['new_user_join_group'] == true,
      newUserJoinChannel: json['new_user_join_channel'] == true,
      groupInviteRequireFriend: json['group_invite_require_friend'] == true,
      friendAddMode: FriendAddMode.fromRaw(json['friend_add_mode']),
      customPortalEnabled: json['custom_portal_enabled'] == true,
      customPortalTitle: json['custom_portal_title']?.toString() ?? '',
      customPortalUrl: json['custom_portal_url']?.toString() ?? '',
      customPortalIconUrl: json['custom_portal_icon_url']?.toString() ?? '',
      chatAttachmentMenu:
          ChatAttachmentMenuSettings.fromJson(json['chat_attachment_menu']),
      burnAfterReadEnabled: json['burn_after_read_enabled'] != false,
      voiceTranscriptionEnabled: json['voice_transcription_enabled'] == true,
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
      chatImageDirectUpload: ChatImageDirectUploadSettings.fromJson(
          json['chat_image_direct_upload']),
    );
  }

  Map<String, dynamic> toJson() => {
        'app_version_ios': appVersionIOS,
        'app_version_android': appVersionAndroid,
        'latest_version_ios': appVersionIOS,
        'latest_version_android': appVersionAndroid,
        'app_update_url_ios': appUpdateUrlIOS,
        'app_update_url_android': appUpdateUrlAndroid,
        'min_supported_version_ios': minSupportedVersionIOS,
        'min_supported_version_android': minSupportedVersionAndroid,
        'system_name': systemName,
        'system_version': systemVersion,
        'register_base_url': registerBaseUrl,
        'support_online_url': supportOnlineUrl,
        'support_qq': supportQQ,
        'app_force_update': appForceUpdate,
        'force_keep_alive_enabled': forceKeepAliveEnabled,
        'app_update_url': appUpdateUrl,
        'app_update_message': appUpdateMessage,
        'splash_enabled': splashEnabled,
        'splash_image_url': splashImageUrl,
        'splash_duration_ms': splashDurationMs,
        'allow_register': allowRegister,
        'allow_quick_register': allowQuickRegister,
        'require_invite_code': requireInviteCode,
        'require_gender_on_register': requireGenderOnRegister,
        'require_phone_bind': requirePhoneBind,
        'username_type': usernameType,
        'sms_bind_ready': smsBindReady,
        'email_registration_ready': emailRegistrationReady,
        'enable_moment_post': enableMomentPost,
        'moment_post_review_enabled': momentPostReviewEnabled,
        'ios_compliance': iosCompliance.toJson(),
        'new_user_follow_official': newUserFollowOfficial,
        'new_user_join_group': newUserJoinGroup,
        'new_user_join_channel': newUserJoinChannel,
        'group_invite_require_friend': groupInviteRequireFriend,
        'friend_add_mode': friendAddMode.value,
        'custom_portal_enabled': customPortalEnabled,
        'custom_portal_title': customPortalTitle,
        'custom_portal_url': customPortalUrl,
        'custom_portal_icon_url': customPortalIconUrl,
        'chat_attachment_menu': chatAttachmentMenu.toJson(),
        'burn_after_read_enabled': burnAfterReadEnabled,
        'voice_transcription_enabled': voiceTranscriptionEnabled,
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
        'chat_image_direct_upload': chatImageDirectUpload.toJson(),
      };

  String get displayName {
    final name = systemName.trim();
    return name.isNotEmpty ? name : defaultAppDisplayName();
  }

  String appUpdateUrlFor({required bool ios}) =>
      (ios ? appUpdateUrlIOS : appUpdateUrlAndroid).trim().isNotEmpty
          ? (ios ? appUpdateUrlIOS : appUpdateUrlAndroid).trim()
          : appUpdateUrl.trim();

  String minSupportedVersionFor({required bool ios}) =>
      (ios ? minSupportedVersionIOS : minSupportedVersionAndroid).trim();

  String get portalTitle {
    final title = customPortalTitle.trim();
    return title.isNotEmpty
        ? title
        : _systemSettingsText(
            zhCN: '网站',
            zhTW: '網站',
            en: 'Website',
          );
  }

  String get portalUrl => customPortalUrl.trim();
  bool get checkinEnabled => iosCompliance.allowsCheckin;

  String get onlineSupportUrl => supportOnlineUrl.trim();
  String get qqSupportNumber => supportQQ.trim();

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

  // 进程内缓存优先，其次读取 30 分钟有效的持久化缓存，最后才请求服务端。
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
        await _applyRuntimeSettings(cached);
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
        await _applyRuntimeSettings(settings);
        await _saveToCache(settings);
        return settings;
      }
    } catch (e) {
      debugPrint('[SystemSettings] Error fetching settings: $e');
    }

    final cachedFallback = _cachedSettings ?? await loadCachedSystemSettings();
    if (cachedFallback != null) {
      _cachedSettings = cachedFallback;
      await _applyRuntimeSettings(cachedFallback);
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
      debugPrint('[SystemSettings] Error saving to cache: $e');
    }
  }

  Future<void> _applyRuntimeSettings(SystemSettings settings) async {
    // 当前仅保活策略需要立即落到运行时；其他配置由各业务消费者按需读取。
    try {
      await BackgroundKeepAlivePolicyStore.instance.save(
        settings.forceKeepAliveEnabled
            ? BackgroundKeepAliveMode.enhanced
            : BackgroundKeepAliveMode.balanced,
      );
    } catch (e) {
      debugPrint('[SystemSettings] Error applying keep-alive settings: $e');
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
      debugPrint('[SystemSettings] Error syncing official contacts: $e');
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
    // 过期缓存先用于首屏展示，再后台刷新并使 Provider 自身重新求值。
    final hasFreshCache = await service.hasFreshCache();
    if (!hasFreshCache) {
      Future<void>(() async {
        try {
          await service.getSettings(forceRefresh: true);
          if (!disposed) {
            ref.invalidateSelf();
          }
        } catch (e) {
          debugPrint('[SystemSettings] Background refresh failed: $e');
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
