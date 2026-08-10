import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_io/io.dart';

import '../../../core/services/android_notification_settings_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/hot_update_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/hot_update_install_tracker.dart';
import '../../../core/services/hot_update_sdk_adapter.dart';
import '../../../core/theme/app_colors.dart';

/// Splash page that gates navigation behind auth, app update, and hot update checks.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _hasNavigated = false;
  bool _permissionsRequested = false;
  bool _updateCheckInProgress = false;
  bool _updateCheckCompleted = false;
  bool _forceUpdateRequired = false;
  bool _optionalUpdatePromptShown = false;
  bool _hotUpdateApplying = false;

  AuthStatus? _resolvedAuthStatus;

  String _updateMessage = '';
  String _updateUrl = '';
  String _targetVersion = '';
  String _currentVersion = '';
  String _hotUpdateApplyingMessage = '';
  String _hotUpdateProgressDetail = '';
  double? _hotUpdateProgressValue;

  ValueNotifier<_HotUpdateProgressDialogState>? _hotUpdateProgressNotifier;
  bool _hotUpdateProgressDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();

    ref.listenManual<AuthState>(authServiceProvider, (previous, next) {
      if (next.status != AuthStatus.initial &&
          next.status != AuthStatus.loading) {
        _onAuthStatusResolved(next.status);
      }
    });

    final authState = ref.read(authServiceProvider);
    if (authState.status != AuthStatus.initial &&
        authState.status != AuthStatus.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _onAuthStatusResolved(authState.status);
      });
    }

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(
          const Duration(milliseconds: 700),
          _requestPermissions,
        );
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;

    try {
      _triggerNetworkPermission();

      if (Platform.isIOS) {
        await Permission.notification.request();
      }

      if (Platform.isAndroid) {
        final status = await AndroidNotificationSettingsService.status();
        if (status.isDenied) {
          final granted = await AndroidNotificationSettingsService.request();
          if (!granted) {
            final afterRequest =
                await AndroidNotificationSettingsService.status();
            if (afterRequest.isPermanentlyDenied || afterRequest.isRestricted) {
              await AndroidNotificationSettingsService.open();
            }
          }
        } else if (status.isPermanentlyDenied || status.isRestricted) {
          await AndroidNotificationSettingsService.open();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] Permission request error: $e');
    }
  }

  void _triggerNetworkPermission() {
    try {
      unawaited(ref.read(apiClientProvider).get('/ping'));
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _hotUpdateProgressNotifier?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed && _forceUpdateRequired) {
      unawaited(_recheckAfterUpdate());
    }
  }

  void _navigate(AuthStatus status) {
    if (_hasNavigated) return;
    _hasNavigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (status == AuthStatus.authenticated) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    });
  }

  void _onAuthStatusResolved(AuthStatus status) {
    _resolvedAuthStatus = status;
    unawaited(_ensureUpdateGateThenNavigate());
  }

  Future<void> _ensureUpdateGateThenNavigate() async {
    if (_forceUpdateRequired) return;

    if (kIsWeb) {
      _updateCheckCompleted = true;
      if (_resolvedAuthStatus != null) {
        _navigate(_resolvedAuthStatus!);
      }
      return;
    }

    if (!_updateCheckCompleted) {
      if (_updateCheckInProgress) return;
      _updateCheckInProgress = true;
      await _runUpdateCheckFlow();
      _updateCheckInProgress = false;
      _updateCheckCompleted = true;
    }

    if (_forceUpdateRequired) return;
    if (_resolvedAuthStatus == null) return;
    _navigate(_resolvedAuthStatus!);
  }

  Future<void> _runUpdateCheckFlow() async {
    if (kIsWeb) return;

    final updateInfo = await _loadUpdateInfo();
    if (!mounted) return;

    if (updateInfo != null) {
      if (updateInfo.isForceUpdate) {
        setState(() {
          _forceUpdateRequired = true;
          _updateMessage = updateInfo.message;
          _updateUrl = updateInfo.updateUrl;
          _targetVersion = updateInfo.targetVersion;
          _currentVersion = updateInfo.currentVersion;
        });
        return;
      }

      if (!_optionalUpdatePromptShown) {
        _optionalUpdatePromptShown = true;
        final startedPackageUpdate =
            await _showOptionalUpdateDialog(updateInfo);
        if (startedPackageUpdate) {
          return;
        }
      }
    }

    await _runHotUpdatePatchFlow();
  }

  Future<void> _runHotUpdatePatchFlow() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    HotUpdatePatch? activePatch;
    String activeAppVersion = '';
    String activeBuildNumber = '';
    String activeUserUUID = '';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      final userUUID = ref.read(authServiceProvider).user?.uuid ?? '';
      final hotUpdateService = ref.read(hotUpdateServiceProvider);
      final sdkAdapter = ref.read(hotUpdateSdkAdapterProvider);
      final installTracker = ref.read(hotUpdateInstallTrackerProvider);

      await _reportPendingHotUpdateInstallIfNeeded(
        hotUpdateService: hotUpdateService,
        installTracker: installTracker,
        sdkAdapter: sdkAdapter,
        appVersion: appVersion,
        buildNumber: buildNumber,
        userUUID: userUUID,
      );

      final supportsShorebird = await sdkAdapter.supportsShorebird();
      final patch = await hotUpdateService.checkPatch(
        appVersion: appVersion,
        buildNumber: buildNumber,
        userUUID: userUUID,
        supportsShorebird: supportsShorebird,
      );
      if (patch == null) {
        return;
      }

      if (patch.isMandatory) {
        await _showMandatoryPatchPromptV2(patch);
        await _settleDialogTransition();
      }

      unawaited(
        hotUpdateService.reportPatchResult(
          patch: patch,
          status: HotUpdateReportStatus.checkHit,
          appVersion: appVersion,
          buildNumber: buildNumber,
          userUUID: userUUID,
          message: 'patch_hit',
        ),
      );

      if (!patch.isMandatory) {
        final shouldApply = await _showOptionalPatchPromptV2(patch);
        if (!shouldApply) {
          await hotUpdateService.reportPatchResult(
            patch: patch,
            status: HotUpdateReportStatus.deferred,
            appVersion: appVersion,
            buildNumber: buildNumber,
            userUUID: userUUID,
            message: 'deferred_by_user',
          );
          if (kDebugMode) debugPrint(
            '[Splash] Hot update deferred by user: ${patch.patchVersion}',
          );
          return;
        }
        await _settleDialogTransition();
      }

      activePatch = patch;
      activeAppVersion = appVersion;
      activeBuildNumber = buildNumber;
      activeUserUUID = userUUID;

      _setHotUpdateApplyingState(true, message: '正在准备热更新...');
      await _showHotUpdateProgressDialog();

      final supportStatus = await sdkAdapter.getSupportStatusForPatch(patch);
      if (!supportStatus.available) {
        await _closeHotUpdateProgressDialog();
        await hotUpdateService.reportPatchResult(
          patch: patch,
          status: HotUpdateReportStatus.sdkNotAvailable,
          appVersion: appVersion,
          buildNumber: buildNumber,
          userUUID: userUUID,
          message: supportStatus.message,
        );
        if (kDebugMode) debugPrint(
          '[Splash] Hot update bridge unavailable: ${supportStatus.message}',
        );
        if (patch.isMandatory) {
          _setMandatoryPatchGate(
            patch: patch,
            appVersion: appVersion,
            buildNumber: buildNumber,
            message: '检测到必须更新，但当前设备不支持所需的安装通道。',
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: '热更新不可用',
            message: _friendlyPatchApplyMessageV2(supportStatus.message),
          );
        }
        return;
      }

      if (!supportStatus.sdkIntegrated) {
        await _closeHotUpdateProgressDialog();
        await hotUpdateService.reportPatchResult(
          patch: patch,
          status: HotUpdateReportStatus.sdkNotIntegrated,
          appVersion: appVersion,
          buildNumber: buildNumber,
          userUUID: userUUID,
          message: supportStatus.message,
        );
        if (kDebugMode) debugPrint(
          '[Splash] Hot update SDK not integrated yet: ${supportStatus.message}',
        );
        if (patch.isMandatory) {
          _setMandatoryPatchGate(
            patch: patch,
            appVersion: appVersion,
            buildNumber: buildNumber,
            message: '检测到必须更新，但当前安装包未集成所需的热更新能力。',
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: '热更新不可用',
            message: _friendlyPatchApplyMessageV2(supportStatus.message),
          );
        }
        return;
      }

      _setHotUpdateApplyingState(true, message: '正在下载并安装更新...');

      final applyResult = await sdkAdapter.applyPatch(
        patch,
        onProgress: _handleHotUpdateProgress,
      );
      final failureMessage = _friendlyPatchApplyMessageV2(applyResult.message);
      if (!applyResult.success) {
        final failureStatus = _resolveHotUpdateFailureStatus(
          applyResult.message,
        );
        await _closeHotUpdateProgressDialog();
        await hotUpdateService.reportPatchResult(
          patch: patch,
          status: failureStatus,
          appVersion: appVersion,
          buildNumber: buildNumber,
          userUUID: userUUID,
          message: applyResult.message,
        );
        if (kDebugMode) debugPrint(
          '[Splash] Hot update available but apply failed: ${applyResult.message}',
        );
        if (patch.isMandatory) {
          _setMandatoryPatchGate(
            patch: patch,
            appVersion: appVersion,
            buildNumber: buildNumber,
            message: '必须更新安装失败，请稍后重试。',
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: '热更新失败',
            message: failureMessage,
          );
        }
        return;
      }

      final resultStatus = applyResult.requiresRestart
          ? HotUpdateReportStatus.installStarted
          : HotUpdateReportStatus.applySuccess;

      if (applyResult.requiresRestart) {
        await _persistPendingHotUpdateInstall(
          installTracker: installTracker,
          sdkAdapter: sdkAdapter,
          patch: patch,
          appVersion: appVersion,
          buildNumber: buildNumber,
          userUUID: userUUID,
        );
      }

      await hotUpdateService.reportPatchResult(
        patch: patch,
        status: resultStatus,
        appVersion: appVersion,
        buildNumber: buildNumber,
        userUUID: userUUID,
        message: applyResult.message.isEmpty ? 'ok' : applyResult.message,
      );

      if (kDebugMode) debugPrint(
        '[Splash] Hot update applied: ${patch.patchVersion}, requiresRestart=${applyResult.requiresRestart}',
      );
      _setHotUpdateApplyingState(false);
      await _closeHotUpdateProgressDialog();

      if (patch.isMandatory && applyResult.requiresRestart) {
        _setMandatoryPatchGate(
          patch: patch,
          appVersion: appVersion,
          buildNumber: buildNumber,
          message:
              'The mandatory update package is ready. Restart the app or finish the system install flow to continue.',
        );
      }
      if (!patch.isMandatory && applyResult.requiresRestart) {
        await _showPatchReadyPromptV2(patch);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] Hot update check/apply failed: $e');
      if (activePatch != null) {
        await ref.read(hotUpdateServiceProvider).reportPatchResult(
              patch: activePatch,
              status: HotUpdateReportStatus.applyFailed,
              appVersion: activeAppVersion,
              buildNumber: activeBuildNumber,
              userUUID: activeUserUUID,
              message: 'unexpected_exception:${e.toString()}',
            );
      }
      await _showPatchApplyHintPromptV2(
        title: '热更新失败',
        message: _friendlyPatchApplyMessageV2(e.toString()),
      );
    } finally {
      _setHotUpdateApplyingState(false);
      await _closeHotUpdateProgressDialog();
    }
  }

  String _friendlyPatchApplyMessageV2(String raw) {
    final message = raw.trim();
    if (message.isEmpty) {
      return '当前暂时无法获取补丁，请稍后再试。';
    }

    final normalized = message.toLowerCase();
    if (normalized.contains('shorebird_no_update_available_after_retry')) {
      return '补丁已命中，但 Shorebird 补丁还在同步到设备。请等待 1-2 分钟后，完全退出应用再重试。若仍失败，请确认当前安装的是 4.0.3+14 的补丁基线包。';
    }
    if (normalized.contains('shorebird_no_update_available') ||
        normalized.contains('no_update_available') ||
        normalized.contains('no patch') ||
        normalized.contains('no update')) {
      return '当前暂时没有可安装的补丁。若后台刚发布补丁，请等待 1-2 分钟后完全退出应用再重试。';
    }
    if (normalized.contains('shorebird_restart_required') ||
        normalized.contains('shorebird_update_downloaded')) {
      return '补丁已下载完成，请重启应用后生效。';
    }
    if (normalized.contains('shorebird_download_failed')) {
      return '补丁下载失败，请检查网络后重试。';
    }
    if (normalized.contains('shorebird_install_failed')) {
      return '补丁安装失败，请重启应用后重试。';
    }
    if (normalized.contains('shorebird_update_failed')) {
      return '补丁更新失败，请稍后再试。';
    }
    if (normalized.contains('hot_update_sdk_not_available') ||
        normalized.contains('bridge unavailable') ||
        normalized.contains('sdk not available') ||
        normalized.contains('not available')) {
      return '当前设备暂不支持热更新通道。';
    }
    if (normalized.contains('hot_update_sdk_not_integrated') ||
        normalized.contains('sdk not integrated') ||
        normalized.contains('not integrated')) {
      return '当前安装包未集成所需的热更新能力。';
    }
    if (normalized.contains('hot_update_platform_not_supported')) {
      return '当前平台不支持热更新。';
    }
    if (normalized.contains('patch_hash_invalid')) {
      return '补丁哈希格式无效，请使用 sha256、sha1 或 md5。';
    }
    if (normalized.contains('patch_hash_mismatch')) {
      return '补丁校验失败，下载文件与后台配置不一致。';
    }
    if (normalized.contains('patch_download_failed')) {
      return '补丁下载失败，请检查补丁地址和网络后重试。';
    }
    if (normalized.contains('patch_file_missing')) {
      return '已下载的补丁文件不存在，请重新下载。';
    }
    if (normalized.contains('patch_url_invalid')) {
      return '补丁地址无效，请检查后台配置。';
    }
    if (normalized.contains('android_install_permission_required')) {
      return '请先允许安装未知来源应用，然后返回重试。';
    }
    if (normalized.contains('android_install_permission_settings_failed')) {
      return '无法打开安装权限设置页，请手动授权后重试。';
    }
    if (normalized.contains('android_installer_not_found')) {
      return '当前设备未找到可用安装器。';
    }
    if (normalized.contains('android_installer_launch_failed')) {
      return '无法启动安装器，请检查系统安装权限。';
    }
    if (normalized.contains('android_installer_opened') ||
        normalized.contains('android_external_update_opened')) {
      return '已打开安装器，请按系统提示完成安装。';
    }
    if (normalized.contains('ios_install_url_invalid')) {
      return 'iOS 补丁地址必须是 manifest.plist 或 itms-services 链接。';
    }
    if (normalized.contains('ios_manifest_package_url_missing')) {
      return 'iOS manifest 中未找到可下载的安装包地址。';
    }
    if (normalized.contains('ios_install_open_failed')) {
      return '无法打开 iOS 安装流程，请检查 manifest 地址。';
    }
    if (normalized.contains('ios_install_started')) {
      return '已打开 iOS 安装页面，请按系统提示完成安装。';
    }
    if (normalized.contains('patch_apply_result_invalid')) {
      return '未收到有效的原生安装结果。';
    }
    if (normalized.contains('timeout') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return '网络不稳定导致补丁安装失败，请稍后再试。';
    }
    return message;
  }

  Future<void> _showMandatoryPatchPromptV2(HotUpdatePatch patch) async {
    if (!mounted) return;

    final notes = patch.releaseNotes.trim().isNotEmpty
        ? patch.releaseNotes.trim()
        : (patch.description.trim().isNotEmpty
            ? patch.description.trim()
            : '当前设备有一个必须安装的热更新。');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('必须更新'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notes),
              const SizedBox(height: 10),
              if (patch.patchVersion.trim().isNotEmpty)
                Text('补丁版本：${patch.patchVersion.trim()}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('立即更新'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showOptionalPatchPromptV2(HotUpdatePatch patch) async {
    if (!mounted) return false;

    final notes = patch.releaseNotes.trim().isNotEmpty
        ? patch.releaseNotes.trim()
        : (patch.description.trim().isNotEmpty
            ? patch.description.trim()
            : '检测到新的热更新，您可以现在安装，也可以稍后处理。');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('检测到更新'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notes),
              const SizedBox(height: 10),
              if (patch.patchVersion.trim().isNotEmpty)
                Text('补丁版本：${patch.patchVersion.trim()}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('立即更新'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _showPatchReadyPromptV2(HotUpdatePatch patch) async {
    if (!mounted) return;

    final version = patch.patchVersion.trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('需要重启'),
          content: Text(
            version.isEmpty
                ? '更新包已准备完成，请重启应用后生效。'
                : '补丁 $version 已准备完成，请重启应用后生效。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPatchApplyHintPromptV2({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    final normalizedTitle = _normalizeHotUpdateDialogTitle(title);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: Text(normalizedTitle),
          content: Text(
            message.trim().isEmpty ? '当前无法完成更新，请稍后重试。' : message,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  String _normalizeHotUpdateDialogTitle(String raw) {
    final title = raw.trim();
    if (title.isEmpty) {
      return '热更新不可用';
    }
    if (title.contains('failed') || title.contains('Failed')) {
      return '热更新失败';
    }
    if (title.contains('unavailable') || title.contains('Unavailable')) {
      return '热更新不可用';
    }
    return title;
  }

  String _normalizeMandatoryPatchGateMessage(String raw) {
    final message = raw.trim();
    final lower = message.toLowerCase();
    if (message.isEmpty) {
      return '必须先完成热更新后，才可继续使用应用。';
    }
    if (message.contains('device') && lower.contains('support')) {
      return '检测到必须更新，但当前设备不支持所需的安装通道。';
    }
    if (message.contains('client') && lower.contains('sdk')) {
      return '检测到必须更新，但当前安装包未集成所需的热更新能力。';
    }
    if (lower.contains('install failed')) {
      return '必须更新安装失败，请稍后重试。';
    }
    if (lower.contains('downloaded') || lower.contains('installer')) {
      return '必须更新包已准备完成，请重启应用或按系统提示完成安装后继续。';
    }
    return message;
  }

  Future<void> _reportPendingHotUpdateInstallIfNeeded({
    required HotUpdateService hotUpdateService,
    required HotUpdateInstallTracker installTracker,
    required HotUpdateSdkAdapter sdkAdapter,
    required String appVersion,
    required String buildNumber,
    required String userUUID,
  }) async {
    final pendingInstall = await installTracker.loadPendingInstall();
    if (pendingInstall == null) {
      return;
    }

    int? currentShorebirdPatchNumber;
    if (pendingInstall.patch.deliveryMode.trim().toLowerCase() == 'shorebird') {
      currentShorebirdPatchNumber =
          await sdkAdapter.readCurrentShorebirdPatchNumber();
    }

    if (!pendingInstall.isConfirmedBy(
      currentAppVersion: appVersion,
      currentBuildNumber: buildNumber,
      currentShorebirdPatchNumber: currentShorebirdPatchNumber,
    )) {
      return;
    }

    final reportOk = await hotUpdateService.reportPatchResult(
      patch: pendingInstall.patch,
      status: HotUpdateReportStatus.installConfirmed,
      appVersion: appVersion,
      buildNumber: buildNumber,
      userUUID: pendingInstall.resolveUserUUID(userUUID),
      message: 'installed:${_composeCurrentVersion(appVersion, buildNumber)}',
    );
    if (reportOk) {
      await installTracker.clearPendingInstall();
      if (kDebugMode) debugPrint(
        '[Splash] Hot update confirmed on launch: ${pendingInstall.patch.patchVersion}',
      );
    }
  }

  Future<void> _persistPendingHotUpdateInstall({
    required HotUpdateInstallTracker installTracker,
    required HotUpdateSdkAdapter sdkAdapter,
    required HotUpdatePatch patch,
    required String appVersion,
    required String buildNumber,
    required String userUUID,
  }) async {
    try {
      var previousShorebirdPatchNumber = 0;
      var expectedShorebirdPatchNumber = 0;
      if (patch.deliveryMode.trim().toLowerCase() == 'shorebird') {
        previousShorebirdPatchNumber =
            await sdkAdapter.readCurrentShorebirdPatchNumber() ?? 0;
        expectedShorebirdPatchNumber =
            await sdkAdapter.readNextShorebirdPatchNumber() ?? 0;
      }
      await installTracker.markInstallStarted(
        patch: patch,
        appVersion: appVersion,
        buildNumber: buildNumber,
        previousShorebirdPatchNumber: previousShorebirdPatchNumber,
        expectedShorebirdPatchNumber: expectedShorebirdPatchNumber,
        userUUID: userUUID,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] Save pending hot update install failed: $e');
    }
  }

  String _resolveHotUpdateFailureStatus(String rawMessage) {
    final normalized = rawMessage.trim().toLowerCase();
    if (normalized.contains('hot_update_sdk_not_available')) {
      return HotUpdateReportStatus.sdkNotAvailable;
    }
    if (normalized.contains('hot_update_sdk_not_integrated')) {
      return HotUpdateReportStatus.sdkNotIntegrated;
    }
    return HotUpdateReportStatus.applyFailed;
  }

  Future<void> _settleDialogTransition() async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
  }

  void _setHotUpdateApplyingState(bool active, {String message = ''}) {
    if (!mounted) return;
    setState(() {
      _hotUpdateApplying = active;
      _hotUpdateApplyingMessage = active ? message.trim() : '';
      _hotUpdateProgressValue =
          active ? (_hotUpdateProgressValue ?? 0.05) : null;
      _hotUpdateProgressDetail = active ? _hotUpdateProgressDetail : '';
      if (!active) {
        _hotUpdateProgressValue = null;
        _hotUpdateProgressDetail = '';
      }
    });
  }

  void _handleHotUpdateProgress(HotUpdateProgress progress) {
    if (!mounted) {
      return;
    }

    final detail = _buildHotUpdateProgressDetail(progress);
    final message =
        progress.message.trim().isEmpty ? '正在处理更新...' : progress.message.trim();
    final normalizedProgress = _resolveHotUpdateProgressValue(progress);

    _hotUpdateProgressNotifier?.value = _HotUpdateProgressDialogState(
      message: message,
      detail: detail,
      progress: normalizedProgress,
    );
    setState(() {
      _hotUpdateApplying = true;
      _hotUpdateApplyingMessage = message;
      _hotUpdateProgressValue = normalizedProgress;
      _hotUpdateProgressDetail = detail;
    });
  }

  double _resolveHotUpdateProgressValue(HotUpdateProgress progress) {
    final explicit = progress.progress;
    if (explicit != null) {
      if (explicit < 0) return 0;
      if (explicit > 1) return 1;
      return explicit.toDouble();
    }

    switch (progress.phase) {
      case HotUpdateProgressPhase.preparing:
        return 0.08;
      case HotUpdateProgressPhase.downloading:
        return 0.55;
      case HotUpdateProgressPhase.verifying:
        return 0.82;
      case HotUpdateProgressPhase.applyingPatch:
        return 0.92;
      case HotUpdateProgressPhase.launchingInstaller:
        return 0.96;
    }
  }

  String _buildHotUpdateProgressDetail(HotUpdateProgress progress) {
    if (progress.totalBytes > 0) {
      final percent = ((progress.progress ?? 0) * 100).clamp(0, 100).round();
      return '${_formatBytes(progress.receivedBytes)} / ${_formatBytes(progress.totalBytes)}  ($percent%)';
    }
    if (progress.receivedBytes > 0) {
      return '已下载：${_formatBytes(progress.receivedBytes)}';
    }
    return '';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final fractionDigits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  Future<void> _showHotUpdateProgressDialog() async {
    if (!mounted) return;

    await _closeHotUpdateProgressDialog();
    final notifier = ValueNotifier<_HotUpdateProgressDialogState>(
      const _HotUpdateProgressDialogState(
        message: '正在准备更新...',
        detail: '',
        progress: 0.05,
      ),
    );
    _hotUpdateProgressNotifier?.dispose();
    _hotUpdateProgressNotifier = notifier;
    _hotUpdateProgressDialogVisible = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              title: const Text('正在安装更新'),
              content: ValueListenableBuilder<_HotUpdateProgressDialogState>(
                valueListenable: notifier,
                builder: (context, state, _) {
                  final progressLabel = state.progress == null
                      ? '--'
                      : '${(state.progress! * 100).clamp(0, 100).round()}%';
                  return SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(999),
                                value: state.progress,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary.withValues(alpha: 0.9),
                                ),
                                backgroundColor: isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              progressLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.message,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        if (state.detail.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            state.detail,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ).whenComplete(() {
        _hotUpdateProgressDialogVisible = false;
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _closeHotUpdateProgressDialog() async {
    if (!_hotUpdateProgressDialogVisible || !mounted) {
      return;
    }
    await Navigator.of(context, rootNavigator: true).maybePop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Widget _buildHotUpdateApplyingOverlay(bool isDark) {
    final message = _hotUpdateApplyingMessage.trim().isEmpty
        ? '正在安装更新，请稍候...'
        : _hotUpdateApplyingMessage.trim();

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181818) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(999),
                        value: _hotUpdateProgressValue,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary.withValues(alpha: 0.9),
                        ),
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _hotUpdateProgressValue == null
                          ? '--'
                          : '${(_hotUpdateProgressValue! * 100).clamp(0, 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                if (_hotUpdateProgressDetail.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _hotUpdateProgressDetail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setMandatoryPatchGate({
    required HotUpdatePatch patch,
    required String appVersion,
    required String buildNumber,
    required String message,
  }) {
    if (!mounted) return;

    final patchVersion = patch.patchVersion.trim().isNotEmpty
        ? patch.patchVersion.trim()
        : patch.targetAppVersion.trim();
    setState(() {
      _forceUpdateRequired = true;
      _updateMessage = _normalizeMandatoryPatchGateMessage(message);
      _updateUrl = '';
      _targetVersion = patchVersion;
      _currentVersion = _composeCurrentVersion(appVersion, buildNumber);
    });
  }

  Future<_UpdateInfo?> _loadUpdateInfo() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }

    try {
      final settings = await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true);

      final targetVersion =
          (Platform.isIOS ? settings.appVersionIOS : settings.appVersionAndroid)
              .trim();
      if (targetVersion.isEmpty) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _composeCurrentVersion(
        packageInfo.version.trim(),
        packageInfo.buildNumber.trim(),
      );

      final needsUpdate = _compareVersion(targetVersion, currentVersion) > 0;
      if (!needsUpdate) return null;

      final updateUrl = settings.appUpdateUrl.trim();
      if (updateUrl.isEmpty) {
        if (kDebugMode) debugPrint('[Splash] New version detected but app_update_url is empty');
        return null;
      }

      final forceUpdate = settings.appForceUpdate;
      final message = settings.appUpdateMessage.trim().isNotEmpty
          ? settings.appUpdateMessage.trim()
          : '检测到新版本（$targetVersion），请更新后继续使用。';

      return _UpdateInfo(
        isForceUpdate: forceUpdate,
        targetVersion: targetVersion,
        currentVersion: currentVersion,
        updateUrl: updateUrl,
        message: message,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] Update check failed: $e');
      return null;
    }
  }

  Future<bool> _showOptionalUpdateDialog(_UpdateInfo updateInfo) async {
    if (!mounted) return false;

    final shouldUpdate = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              title: const Text('检测到新版本'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(updateInfo.message),
                  const SizedBox(height: 10),
                  Text('当前版本：${updateInfo.currentVersion}'),
                  Text('目标版本：${updateInfo.targetVersion}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('稍后'),
                ),
                if (updateInfo.updateUrl.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('立即更新'),
                  ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldUpdate) {
      return false;
    }

    await _settleDialogTransition();
    await _startAppUpdate(
      updateUrl: updateInfo.updateUrl,
      targetVersion: updateInfo.targetVersion,
      currentVersion: updateInfo.currentVersion,
    );
    return true;
  }

  Future<void> _startAppUpdate({
    required String updateUrl,
    String targetVersion = '',
    String currentVersion = '',
  }) async {
    final trimmed = updateUrl.trim();
    if (trimmed.isEmpty) {
      await _showPatchApplyHintPromptV2(
        title: '更新失败',
        message: '未配置有效的更新地址，请先在后台填写安装包下载链接。',
      );
      return;
    }

    final normalized =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'https://$trimmed';
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      await _showPatchApplyHintPromptV2(
        title: '更新失败',
        message: '更新地址格式不正确，请检查后台配置。',
      );
      return;
    }

    if (!_shouldUseInAppPackageUpdater(uri)) {
      final opened = await _openUpdateUrl(normalized);
      if (!opened) {
        await _showPatchApplyHintPromptV2(
          title: '打开更新链接失败',
          message: '系统未能打开更新链接，请检查更新地址或设备默认浏览器设置。',
        );
      } else {
        await _showPatchApplyHintPromptV2(
          title: '已打开更新链接',
          message: '系统已尝试打开更新链接，请按页面提示完成下载或安装。',
        );
      }
      return;
    }

    final sdkAdapter = ref.read(hotUpdateSdkAdapterProvider);
    final syntheticPatch = HotUpdatePatch(
      name: '应用安装包更新',
      description: '通过应用内更新器安装新的安装包。',
      platform: 'android',
      targetAppVersion: targetVersion,
      patchVersion: targetVersion.isNotEmpty ? targetVersion : currentVersion,
      patchUrl: normalized,
    );

    try {
      if (kDebugMode) debugPrint('[Splash] Start in-app package update: $normalized');
      _setHotUpdateApplyingState(true, message: '正在准备安装包更新...');
      await _showHotUpdateProgressDialog();

      final supportStatus = await sdkAdapter.getSupportStatus();
      if (!supportStatus.available || !supportStatus.sdkIntegrated) {
        if (kDebugMode) debugPrint(
          '[Splash] In-app package updater unavailable, fallback to external: ${supportStatus.message}',
        );
        await _closeHotUpdateProgressDialog();
        _setHotUpdateApplyingState(false);
        final opened = await _openUpdateUrl(normalized);
        if (!opened) {
          await _showPatchApplyHintPromptV2(
            title: '打开更新链接失败',
            message: '当前设备无法拉起系统安装流程，请检查下载地址和系统权限。',
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: '已打开更新链接',
            message: '当前设备不支持应用内安装，已切换为系统下载/安装流程。',
          );
        }
        return;
      }

      final applyResult = await sdkAdapter.applyPatch(
        syntheticPatch,
        onProgress: _handleHotUpdateProgress,
      );

      await _closeHotUpdateProgressDialog();
      _setHotUpdateApplyingState(false);

      if (!applyResult.success) {
        await _showPatchApplyHintPromptV2(
          title: '安装包更新失败',
          message: _friendlyAppUpdateMessage(applyResult.message),
        );
        return;
      }

      if (applyResult.requiresRestart) {
        await _showPatchApplyHintPromptV2(
          title: '需要重启',
          message: '更新包已安装完成，请重启应用后生效。',
        );
        return;
      }

      await _showPatchApplyHintPromptV2(
        title: '更新已准备完成',
        message: '更新包已准备完成，可稍后重启应用生效。',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] Start in-app package update failed: $e');
      await _closeHotUpdateProgressDialog();
      _setHotUpdateApplyingState(false);
      await _showPatchApplyHintPromptV2(
        title: '安装包更新失败',
        message: _friendlyAppUpdateMessage(e.toString()),
      );
    }
  }

  bool _shouldUseInAppPackageUpdater(Uri uri) {
    if (!Platform.isAndroid) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  String _friendlyAppUpdateMessage(String raw) {
    final message = raw.trim();
    if (message.isEmpty) {
      return '当前无法完成安装包更新，请稍后重试。';
    }

    final normalized = message.toLowerCase();
    if (normalized.contains('patch_download_failed')) {
      return '安装包下载失败，请检查更新地址和网络后重试。';
    }
    if (normalized.contains('patch_url_invalid')) {
      return '更新地址无效，请检查后台配置。';
    }
    if (normalized.contains('patch_apply_result_invalid')) {
      return '更新器返回了无效结果，请检查原生热更新桥接。';
    }
    if (normalized.contains('patch_file_missing')) {
      return '已下载的更新包不存在，请重新下载。';
    }
    if (normalized.contains('android_install_permission_required')) {
      return '请先允许安装未知来源应用，然后返回重试。';
    }
    if (normalized.contains('android_install_permission_settings_failed')) {
      return '无法打开安装权限设置页，请手动授权后重试。';
    }
    if (normalized.contains('android_installer_not_found')) {
      return '当前设备未找到可用安装器。';
    }
    if (normalized.contains('android_installer_launch_failed')) {
      return '无法启动安装器，请检查系统安装权限后重试。';
    }
    if (normalized.contains('android_installer_opened')) {
      return '已打开安装器，请按系统提示完成安装。';
    }
    if (normalized.contains('ios_install_url_invalid')) {
      return 'iOS 安装地址无效。';
    }
    if (normalized.contains('ios_manifest_package_url_missing')) {
      return 'iOS manifest 中未包含有效的安装包地址。';
    }
    if (normalized.contains('ios_install_started')) {
      return '已打开 iOS 安装页面，请按系统提示完成安装。';
    }
    if (normalized.contains('timeout') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return '网络请求超时或失败，导致安装包无法下载。';
    }
    return message;
  }

  Future<bool> _openUpdateUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;

    final normalized =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'https://$trimmed';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return false;

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] Open update url failed: $e');
      return false;
    }
  }

  Future<void> _recheckAfterUpdate() async {
    if (_updateCheckInProgress) return;
    setState(() {
      _forceUpdateRequired = false;
      _updateCheckCompleted = false;
    });
    await _ensureUpdateGateThenNavigate();
  }

  String _composeCurrentVersion(String version, String buildNumber) {
    final normalizedVersion = version.isEmpty ? '0.0.0' : version;
    if (buildNumber.isEmpty) return normalizedVersion;
    return '$normalizedVersion+$buildNumber';
  }

  int _compareVersion(String left, String right) {
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

  List<int> _extractVersionParts(String input) {
    final matches = RegExp(r'\d+')
        .allMatches(input)
        .map((m) => int.tryParse(m.group(0) ?? '0') ?? 0)
        .toList();
    if (matches.isEmpty) return const [0];
    return matches;
  }

  Widget _buildForceUpdateView({
    required bool isDark,
    required String appName,
  }) {
    final progressLabel = _hotUpdateProgressValue == null
        ? '--'
        : '${(_hotUpdateProgressValue! * 100).clamp(0, 100).round()}%';
    final progressMessage = _hotUpdateApplyingMessage.trim().isEmpty
        ? '正在安装更新，请稍候...'
        : _hotUpdateApplyingMessage.trim();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo.png', width: 96, height: 96),
                const SizedBox(height: 20),
                Text(
                  appName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _updateMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                if (_currentVersion.isNotEmpty ||
                    _targetVersion.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '当前版本：$_currentVersion  目标版本：$_targetVersion',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
                if (_hotUpdateApplying) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                progressMessage,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              progressLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(999),
                          value: _hotUpdateProgressValue,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary.withValues(alpha: 0.9),
                          ),
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                        ),
                        if (_hotUpdateProgressDetail.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _hotUpdateProgressDetail,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hotUpdateApplying
                        ? null
                        : (_updateUrl.isEmpty
                            ? _recheckAfterUpdate
                            : () => _startAppUpdate(
                                  updateUrl: _updateUrl,
                                  targetVersion: _targetVersion,
                                  currentVersion: _currentVersion,
                                )),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _hotUpdateApplying
                          ? '正在更新...'
                          : (_updateUrl.isEmpty ? '重新检查' : '立即更新'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_updateUrl.isNotEmpty)
                  TextButton(
                    onPressed: _hotUpdateApplying ? null : _recheckAfterUpdate,
                    child: const Text('我已完成更新，重新检查'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);
    final appName =
        ref.read(systemSettingsServiceProvider).cachedSettings?.displayName ??
            kDefaultAppDisplayName;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<AuthState>(authServiceProvider, (previous, next) {
      if (next.status != AuthStatus.initial &&
          next.status != AuthStatus.loading) {
        _onAuthStatusResolved(next.status);
      }
    });

    if (authState.status != AuthStatus.initial &&
        authState.status != AuthStatus.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _onAuthStatusResolved(authState.status);
      });
    }

    if (_forceUpdateRequired) {
      return _buildForceUpdateView(isDark: isDark, appName: appName);
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', width: 120, height: 120),
                  const SizedBox(height: 24),
                  Text(
                    appName,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Secure  ·  Fast  ·  Private',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black45,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 60),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hotUpdateApplying) _buildHotUpdateApplyingOverlay(isDark),
        ],
      ),
    );
  }
}

class _UpdateInfo {
  final bool isForceUpdate;
  final String targetVersion;
  final String currentVersion;
  final String updateUrl;
  final String message;

  const _UpdateInfo({
    required this.isForceUpdate,
    required this.targetVersion,
    required this.currentVersion,
    required this.updateUrl,
    required this.message,
  });
}

class _HotUpdateProgressDialogState {
  final String message;
  final String detail;
  final double? progress;

  const _HotUpdateProgressDialogState({
    required this.message,
    required this.detail,
    required this.progress,
  });
}
