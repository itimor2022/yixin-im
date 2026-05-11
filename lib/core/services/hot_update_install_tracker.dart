import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/hot_update_service.dart';

class PendingHotUpdateInstall {
  final HotUpdatePatch patch;
  final String previousAppVersion;
  final String previousBuildNumber;
  final int previousShorebirdPatchNumber;
  final int expectedShorebirdPatchNumber;
  final String userUUID;
  final DateTime createdAt;

  const PendingHotUpdateInstall({
    required this.patch,
    required this.previousAppVersion,
    required this.previousBuildNumber,
    this.previousShorebirdPatchNumber = 0,
    this.expectedShorebirdPatchNumber = 0,
    required this.userUUID,
    required this.createdAt,
  });

  factory PendingHotUpdateInstall.fromJson(Map<String, dynamic> json) {
    final patchJson = json['patch'];
    if (patchJson is! Map<String, dynamic>) {
      throw const FormatException('pending_hot_update_patch_invalid');
    }

    return PendingHotUpdateInstall(
      patch: HotUpdatePatch.fromJson(patchJson),
      previousAppVersion: json['previous_app_version']?.toString() ?? '',
      previousBuildNumber: json['previous_build_number']?.toString() ?? '',
      previousShorebirdPatchNumber: int.tryParse(
            json['previous_shorebird_patch_number']?.toString() ?? '',
          ) ??
          0,
      expectedShorebirdPatchNumber: int.tryParse(
            json['expected_shorebird_patch_number']?.toString() ?? '',
          ) ??
          0,
      userUUID: json['user_uuid']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'patch': patch.toMap(),
        'previous_app_version': previousAppVersion,
        'previous_build_number': previousBuildNumber,
        'previous_shorebird_patch_number': previousShorebirdPatchNumber,
        'expected_shorebird_patch_number': expectedShorebirdPatchNumber,
        'user_uuid': userUUID,
        'created_at': createdAt.toIso8601String(),
      };

  String resolveUserUUID(String fallbackUserUUID) {
    final normalizedFallback = fallbackUserUUID.trim();
    if (normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }
    return userUUID.trim();
  }

  bool isConfirmedBy({
    required String currentAppVersion,
    required String currentBuildNumber,
    int? currentShorebirdPatchNumber,
  }) {
    if (patch.deliveryMode.trim().toLowerCase() == 'shorebird') {
      if (currentShorebirdPatchNumber == null ||
          currentShorebirdPatchNumber <= 0) {
        return false;
      }
      if (expectedShorebirdPatchNumber > 0) {
        return currentShorebirdPatchNumber >= expectedShorebirdPatchNumber;
      }
      if (previousShorebirdPatchNumber > 0) {
        return currentShorebirdPatchNumber > previousShorebirdPatchNumber;
      }
      return false;
    }

    final currentComposite = _composeVersion(
      currentAppVersion,
      currentBuildNumber,
    );
    final previousComposite = _composeVersion(
      previousAppVersion,
      previousBuildNumber,
    );
    final targetAppVersion = patch.targetAppVersion.trim();

    if (targetAppVersion.isNotEmpty &&
        _compareVersion(currentComposite, targetAppVersion) >= 0) {
      return true;
    }

    return _compareVersion(currentComposite, previousComposite) > 0;
  }

  static String _composeVersion(String version, String buildNumber) {
    final normalizedVersion = version.trim().isEmpty ? '0.0.0' : version.trim();
    final normalizedBuild = buildNumber.trim();
    if (normalizedBuild.isEmpty) {
      return normalizedVersion;
    }
    return '$normalizedVersion+$normalizedBuild';
  }

  static int _compareVersion(String left, String right) {
    final leftParts = _extractVersionParts(left);
    final rightParts = _extractVersionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue > rightValue ? 1 : -1;
      }
    }
    return 0;
  }

  static List<int> _extractVersionParts(String input) {
    final matches = RegExp(r'\d+')
        .allMatches(input)
        .map((m) => int.tryParse(m.group(0) ?? '0') ?? 0)
        .toList();
    if (matches.isEmpty) {
      return const [0];
    }
    return matches;
  }
}

class HotUpdateInstallTracker {
  static const String _prefsKey = 'hot_update_pending_install_v1';
  static const Duration _maxPendingInstallAge = Duration(days: 7);
  static const Duration _futureClockSkewTolerance = Duration(minutes: 5);

  Future<PendingHotUpdateInstall?> loadPendingInstall() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey)?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        await clearPendingInstall();
        return null;
      }
      final pending = PendingHotUpdateInstall.fromJson(json);
      final now = DateTime.now();
      final createdAt = pending.createdAt;
      final isInvalidTimestamp = createdAt.millisecondsSinceEpoch <= 0 ||
          createdAt.isAfter(now.add(_futureClockSkewTolerance));
      final isExpired = !isInvalidTimestamp &&
          now.difference(createdAt) > _maxPendingInstallAge;
      if (isInvalidTimestamp || isExpired) {
        await clearPendingInstall();
        return null;
      }
      return pending;
    } catch (_) {
      await clearPendingInstall();
      return null;
    }
  }

  Future<void> markInstallStarted({
    required HotUpdatePatch patch,
    required String appVersion,
    required String buildNumber,
    int previousShorebirdPatchNumber = 0,
    int expectedShorebirdPatchNumber = 0,
    String userUUID = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = PendingHotUpdateInstall(
      patch: patch,
      previousAppVersion: appVersion.trim(),
      previousBuildNumber: buildNumber.trim(),
      previousShorebirdPatchNumber: previousShorebirdPatchNumber,
      expectedShorebirdPatchNumber: expectedShorebirdPatchNumber,
      userUUID: userUUID.trim(),
      createdAt: DateTime.now(),
    );
    await prefs.setString(_prefsKey, jsonEncode(pending.toJson()));
  }

  Future<void> clearPendingInstall() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

final hotUpdateInstallTrackerProvider =
    Provider<HotUpdateInstallTracker>((ref) {
  return HotUpdateInstallTracker();
});
