import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_io/io.dart';

import '../device_service.dart';
import 'api_client.dart';

class HotUpdatePatch {
  final int id;
  final String patchId;
  final String name;
  final String description;
  final String platform;
  final String channel;
  final String deliveryMode;
  final String targetAppVersion;
  final String patchVersion;
  final String patchUrl;
  final String patchHash;
  final String releaseNotes;
  final bool isMandatory;
  final int rolloutPercentage;

  const HotUpdatePatch({
    this.id = 0,
    this.patchId = '',
    this.name = '',
    this.description = '',
    this.platform = '',
    this.channel = 'stable',
    this.deliveryMode = 'self_hosted',
    this.targetAppVersion = '',
    this.patchVersion = '',
    this.patchUrl = '',
    this.patchHash = '',
    this.releaseNotes = '',
    this.isMandatory = false,
    this.rolloutPercentage = 0,
  });

  factory HotUpdatePatch.fromJson(Map<String, dynamic> json) {
    return HotUpdatePatch(
      id: json['id'] as int? ?? 0,
      patchId: json['patch_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      channel: json['channel']?.toString() ?? 'stable',
      deliveryMode: _normalizeDeliveryMode(json['delivery_mode']),
      targetAppVersion: json['target_app_version']?.toString() ?? '',
      patchVersion: json['patch_version']?.toString() ?? '',
      patchUrl: json['patch_url']?.toString() ?? '',
      patchHash: json['patch_hash']?.toString() ?? '',
      releaseNotes: json['release_notes']?.toString() ?? '',
      isMandatory: _parseBool(json['is_mandatory']),
      rolloutPercentage: json['rollout_percentage'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'patch_id': patchId,
        'name': name,
        'description': description,
        'platform': platform,
        'channel': channel,
        'delivery_mode': deliveryMode,
        'target_app_version': targetAppVersion,
        'patch_version': patchVersion,
        'patch_url': patchUrl,
        'patch_hash': patchHash,
        'release_notes': releaseNotes,
        'is_mandatory': isMandatory,
        'rollout_percentage': rolloutPercentage,
      };

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'y';
    }
    return false;
  }

  static String _normalizeDeliveryMode(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'shorebird') {
      return 'shorebird';
    }
    return 'self_hosted';
  }
}

class HotUpdateReportStatus {
  static const String checkHit = 'check_hit';
  static const String deferred = 'deferred';
  static const String applySuccess = 'apply_success';
  static const String installStarted = 'install_started';
  static const String installConfirmed = 'install_confirmed';
  static const String applyFailed = 'apply_failed';
  static const String sdkNotIntegrated = 'sdk_not_integrated';
  static const String sdkNotAvailable = 'sdk_not_available';
}

class HotUpdateService {
  final ApiClient _apiClient;

  HotUpdateService(this._apiClient);

  Future<HotUpdatePatch?> checkPatch({
    required String appVersion,
    required String buildNumber,
    String channel = 'stable',
    String userUUID = '',
    bool supportsShorebird = false,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }

    final normalizedVersion = appVersion.trim();
    final normalizedBuild = int.tryParse(buildNumber.trim()) ?? 0;
    if (normalizedVersion.isEmpty) {
      return null;
    }

    try {
      final deviceID = await DeviceService.getDeviceId();
      final platform = Platform.isIOS ? 'ios' : 'android';

      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/app/hot-update/check',
        queryParameters: {
          'platform': platform,
          'channel': channel.trim().isEmpty ? 'stable' : channel.trim(),
          'app_version': normalizedVersion,
          'build_number': normalizedBuild,
          'device_id': deviceID,
          'supports_shorebird': supportsShorebird ? '1' : '0',
          if (userUUID.trim().isNotEmpty) 'user_uuid': userUUID.trim(),
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!resp.isSuccess || resp.data == null) {
        return null;
      }

      final hasPatch = resp.data!['has_patch'] == true;
      if (!hasPatch) {
        return null;
      }

      final patchJson = resp.data!['patch'];
      if (patchJson is! Map<String, dynamic>) {
        return null;
      }
      return HotUpdatePatch.fromJson(patchJson);
    } catch (e) {
      debugPrint('[HotUpdate] check patch failed: $e');
      return null;
    }
  }

  Future<bool> reportPatchResult({
    required HotUpdatePatch patch,
    required String status,
    required String appVersion,
    required String buildNumber,
    String userUUID = '',
    String message = '',
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return false;
    }

    final normalizedStatus = status.trim();
    if (normalizedStatus.isEmpty) {
      return false;
    }

    try {
      final deviceID = await DeviceService.getDeviceId();
      final platform = Platform.isIOS ? 'ios' : 'android';
      final normalizedBuild = int.tryParse(buildNumber.trim()) ?? 0;

      final payload = <String, dynamic>{
        if (patch.id > 0) 'patch_id': patch.id,
        if (patch.patchId.trim().isNotEmpty)
          'patch_ref_id': patch.patchId.trim(),
        'platform': platform,
        'channel':
            patch.channel.trim().isEmpty ? 'stable' : patch.channel.trim(),
        'app_version': appVersion.trim(),
        'build_number': normalizedBuild,
        'device_id': deviceID,
        if (userUUID.trim().isNotEmpty) 'user_uuid': userUUID.trim(),
        'status': normalizedStatus,
        if (message.trim().isNotEmpty) 'message': message.trim(),
      };

      final resp = await _apiClient.post<Map<String, dynamic>>(
        '/app/hot-update/report',
        data: payload,
        fromJson: (data) => data as Map<String, dynamic>,
      );
      return resp.isSuccess;
    } catch (e) {
      debugPrint('[HotUpdate] report patch result failed: $e');
      return false;
    }
  }
}

final hotUpdateServiceProvider = Provider<HotUpdateService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return HotUpdateService(apiClient);
});
