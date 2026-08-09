// 文件用途：封装 AppLockState 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AppLockState 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/auth_service.dart';

const _privacyBiometricKey = 'privacy_biometric';
const _privacyAppLockKey = 'privacy_app_lock';
const _privacyAutoLockKey = 'privacy_auto_lock';
const _appLockPasscodeHashKey = 'app_lock_passcode_hash';
const _appLockLastBackgroundAtKey = 'app_lock_last_background_at';

// 流程逻辑：`isValidAppLockPasscode` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
bool isValidAppLockPasscode(String passcode) {
  return RegExp(r'^\d{6}$').hasMatch(passcode);
}

String hashAppLockPasscode(String passcode) {
  return sha256.convert(utf8.encode(passcode)).toString();
}

bool verifyAppLockPasscode({
  required String passcode,
  required String? expectedHash,
}) {
  if (expectedHash == null || !isValidAppLockPasscode(passcode)) return false;
  final inputHash = hashAppLockPasscode(passcode);
  if (inputHash.length != expectedHash.length) return false;

  var difference = 0;
  for (var index = 0; index < inputHash.length; index++) {
    difference |= inputHash.codeUnitAt(index) ^ expectedHash.codeUnitAt(index);
  }
  return difference == 0;
}

bool shouldInitializeAppLockForAuthTransition({
  required AuthStatus? previousStatus,
  required AuthStatus nextStatus,
  required bool initialized,
}) {
  return nextStatus == AuthStatus.authenticated &&
      (!initialized || previousStatus != AuthStatus.authenticated);
}

bool resolveInitializedAppLockState({
  required bool wasInitialized,
  required bool wasLocked,
  required bool lockOnStart,
  required bool shouldLock,
}) {
  if (wasInitialized && wasLocked) return true;
  return lockOnStart && shouldLock;
}

bool shouldSuppressAppLockLifecycleForBiometric({
  required bool authenticationInProgress,
  required DateTime? unlockGraceUntil,
  required DateTime now,
}) {
  return authenticationInProgress ||
      (unlockGraceUntil != null && now.isBefore(unlockGraceUntil));
}

// 关键声明：app lock service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AppLockState {
  final bool initialized;
  final bool isLocked;
  final bool isUnlocking;
  final bool biometricEnabled;
  final bool appLockEnabled;
  final bool biometricAvailable;
  final bool hasPasscode;
  final String? errorMessage;

  const AppLockState({
    this.initialized = false,
    this.isLocked = false,
    this.isUnlocking = false,
    this.biometricEnabled = false,
    this.appLockEnabled = false,
    this.biometricAvailable = false,
    this.hasPasscode = false,
    this.errorMessage,
  });

  bool get canUseBiometric => biometricEnabled && biometricAvailable;

  AppLockState copyWith({
    bool? initialized,
    bool? isLocked,
    bool? isUnlocking,
    bool? biometricEnabled,
    bool? appLockEnabled,
    bool? biometricAvailable,
    bool? hasPasscode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AppLockState(
      initialized: initialized ?? this.initialized,
      isLocked: isLocked ?? this.isLocked,
      isUnlocking: isUnlocking ?? this.isUnlocking,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      hasPasscode: hasPasscode ?? this.hasPasscode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AppLockService extends StateNotifier<AppLockState> {
  AppLockService(this._ref) : super(const AppLockState());

  final Ref _ref;
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _biometricAuthenticationInProgress = false;
  DateTime? _biometricUnlockGraceUntil;

  Future<void> initialize({bool lockOnStart = false}) async {
    // 应用锁配置属于当前设备，不随服务端账号隐私设置同步。
    if (!_isAuthenticated) {
      await reset();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool(_privacyBiometricKey) ?? false;
    final appLockEnabled = prefs.getBool(_privacyAppLockKey) ?? false;
    final passcodeHash = prefs.getString(_appLockPasscodeHashKey);
    final biometricAvailable = await _hasAvailableBiometric();
    final shouldLock = (appLockEnabled || biometricEnabled) &&
        (passcodeHash != null || biometricAvailable);
    final initializedLockState = resolveInitializedAppLockState(
      wasInitialized: state.initialized,
      wasLocked: state.isLocked,
      lockOnStart: lockOnStart,
      shouldLock: shouldLock,
    );

    state = state.copyWith(
      initialized: true,
      biometricEnabled: biometricEnabled,
      appLockEnabled: appLockEnabled,
      biometricAvailable: biometricAvailable,
      hasPasscode: passcodeHash != null,
      isLocked: initializedLockState,
      clearError: true,
    );
  }

  Future<void> reset() async {
    _biometricAuthenticationInProgress = false;
    _biometricUnlockGraceUntil = null;
    state = const AppLockState(initialized: true);
  }

  Future<void> handleLifecycleChange(AppLifecycleState lifecycleState) async {
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.hidden) {
      if (_biometricAuthenticationInProgress) return;
      // 生物识别结束后的真实后台切换仍需遵守自动锁定时长。
      _biometricUnlockGraceUntil = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _appLockLastBackgroundAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    if (lifecycleState != AppLifecycleState.resumed || !_isAuthenticated) {
      return;
    }

    if (shouldSuppressAppLockLifecycleForBiometric(
      authenticationInProgress: _biometricAuthenticationInProgress,
      unlockGraceUntil: _biometricUnlockGraceUntil,
      now: DateTime.now(),
    )) {
      // local_auth 会短暂切走 Activity；忽略这次伪后台，避免刚解锁就再次锁定。
      await _clearBiometricPromptBackgroundMarker();
      return;
    }

    _biometricUnlockGraceUntil = null;
    await refreshSettings();
    if (!state.appLockEnabled && !state.biometricEnabled) return;
    if (!state.hasPasscode && !state.canUseBiometric) return;

    final prefs = await SharedPreferences.getInstance();
    final backgroundAt = prefs.getInt(_appLockLastBackgroundAtKey);
    if (backgroundAt == null) return;

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(backgroundAt),
    );
    final autoLock = prefs.getString(_privacyAutoLockKey) ?? 'immediately';
    if (_shouldLock(autoLock, elapsed)) {
      state = state.copyWith(isLocked: true, clearError: true);
    }
  }

  Future<void> refreshSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final passcodeHash = prefs.getString(_appLockPasscodeHashKey);
    state = state.copyWith(
      biometricEnabled: prefs.getBool(_privacyBiometricKey) ?? false,
      appLockEnabled: prefs.getBool(_privacyAppLockKey) ?? false,
      biometricAvailable: await _hasAvailableBiometric(),
      hasPasscode: passcodeHash != null,
    );
  }

  Future<bool> unlockWithBiometric({required String reason}) async {
    if (state.isUnlocking) return false;
    _biometricAuthenticationInProgress = true;
    _biometricUnlockGraceUntil = null;
    state = state.copyWith(isUnlocking: true, clearError: true);
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (authenticated) {
        // 给生物识别弹窗产生的 resumed 事件留出宽限期，避免立即重新上锁。
        _biometricUnlockGraceUntil = DateTime.now().add(
          const Duration(seconds: 2),
        );
        state = state.copyWith(
          isLocked: false,
          isUnlocking: false,
          clearError: true,
        );
        await _clearBiometricPromptBackgroundMarker();
        return true;
      }
      state = state.copyWith(isUnlocking: false);
      return false;
    } on PlatformException catch (e) {
      state = state.copyWith(
        isUnlocking: false,
        errorMessage: biometricErrorMessage(e.code),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isUnlocking: false,
        errorMessage: '生物识别验证失败',
      );
      return false;
    } finally {
      _biometricAuthenticationInProgress = false;
    }
  }

  Future<bool> unlockWithPasscode(String passcode) async {
    final prefs = await SharedPreferences.getInstance();
    final expectedHash = prefs.getString(_appLockPasscodeHashKey);
    if (verifyAppLockPasscode(
      passcode: passcode,
      expectedHash: expectedHash,
    )) {
      state = state.copyWith(isLocked: false, clearError: true);
      return true;
    }
    state = state.copyWith(errorMessage: '锁定密码不正确');
    return false;
  }

  Future<bool> matchesStoredPasscode(String passcode) async {
    final prefs = await SharedPreferences.getInstance();
    return verifyAppLockPasscode(
      passcode: passcode,
      expectedHash: prefs.getString(_appLockPasscodeHashKey),
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  bool get _isAuthenticated {
    return _ref.read(authServiceProvider).status == AuthStatus.authenticated;
  }

  Future<bool> _hasAvailableBiometric() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) return false;
      final biometrics = await _localAuth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearBiometricPromptBackgroundMarker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_appLockLastBackgroundAtKey);
    } catch (_) {
      // Unlock success must not be reversed by a best-effort marker cleanup.
    }
  }

  bool _shouldLock(String autoLock, Duration elapsed) {
    switch (autoLock) {
      case '1_minute':
        return elapsed >= const Duration(minutes: 1);
      case '5_minutes':
        return elapsed >= const Duration(minutes: 5);
      case '1_hour':
        return elapsed >= const Duration(hours: 1);
      case '5_hours':
        return elapsed >= const Duration(hours: 5);
      case 'immediately':
      default:
        return true;
    }
  }
}

String biometricErrorMessage(String code) {
  switch (code) {
    case auth_error.notAvailable:
      return '当前设备不支持生物识别';
    case auth_error.notEnrolled:
      return '请先在系统设置中录入面容或指纹';
    case auth_error.passcodeNotSet:
      return '请先设置系统锁屏密码';
    case auth_error.lockedOut:
      return '尝试次数过多，请稍后再试';
    case auth_error.permanentlyLockedOut:
      return '生物识别已被系统锁定，请先使用系统密码解锁';
    case auth_error.biometricOnlyNotSupported:
      return '当前平台不支持仅使用生物识别';
    case auth_error.otherOperatingSystem:
      return '当前系统不支持生物识别解锁';
    default:
      return '生物识别验证失败';
  }
}

final appLockServiceProvider =
    StateNotifierProvider<AppLockService, AppLockState>((ref) {
  return AppLockService(ref);
});
