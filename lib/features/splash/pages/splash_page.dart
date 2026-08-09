// 文件用途：实现 SplashPage 页面及其交互流程，属于splash。
// 核心逻辑：维护 SplashPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_io/io.dart';

import '../../../core/services/android_notification_settings_service.dart';
import '../../../core/config/runtime_flags.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/hot_update_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/hot_update_install_tracker.dart';
import '../../../core/services/hot_update_sdk_adapter.dart';
import '../../../core/services/performance_trace_service.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/router/redirect_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_version.dart';

// 关键声明：splash page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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
  bool _splashSkipped = false;

  AuthStatus? _resolvedAuthStatus;
  SystemSettings? _splashSettings;
  DateTime? _customSplashActivatedAt;
  DateTime? _customSplashImageVisibleAt;
  String? _customSplashImageUrl;
  Completer<void>? _customSplashImageReadyCompleter;
  Timer? _customSplashCountdownTimer;
  int? _customSplashCountdownSeconds;
  late final DateTime _splashStartedAt;
  late final Future<void> _splashSettingsReady;
  final Completer<void> _skipSplashCompleter = Completer<void>();

  String _updateMessage = '';
  String _updateUrl = '';
  String _targetVersion = '';
  String _currentVersion = '';
  String _hotUpdateApplyingMessage = '';
  String _hotUpdateProgressDetail = '';
  double? _hotUpdateProgressValue;

  ValueNotifier<_HotUpdateProgressDialogState>? _hotUpdateProgressNotifier;
  bool _hotUpdateProgressDialogVisible = false;

  String _text({
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _splashStartedAt = DateTime.now();
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
    _splashSettingsReady = RuntimeFlags.disableSplashImage
        ? Future<void>.value()
        : _loadSplashSettings();

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

    if (!kIsWeb && !RuntimeFlags.smokeTest) {
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
          await AndroidNotificationSettingsService.request();
        }
      }
    } catch (e) {
      debugPrint('[Splash] Permission request error: $e');
    }
  }

  void _triggerNetworkPermission() {
    try {
      unawaited(ref.read(apiClientProvider).get('/ping'));
    } catch (_) {}
  }

  Future<void> _loadSplashSettings() async {
    if (RuntimeFlags.disableSplashImage) return;
    try {
      final service = ref.read(systemSettingsServiceProvider);
      final cached = await service.getCachedSettings();
      if (cached != null && mounted) {
        _applySplashSettings(cached);
      }
      final settings = await service.getSettings(forceRefresh: true);
      if (mounted) {
        _applySplashSettings(settings);
      }
    } catch (e) {
      debugPrint('[Splash] Load splash settings failed: $e');
    }
  }

  void _applySplashSettings(SystemSettings settings) {
    final wasCustomSplashActive = _splashSettings?.splashEnabled == true &&
        (_splashSettings?.splashImageUrl.trim().isNotEmpty ?? false);
    final isCustomSplashActive =
        settings.splashEnabled && settings.splashImageUrl.trim().isNotEmpty;
    final nextImageUrl = ApiConfig.getMediaUrl(settings.splashImageUrl);
    setState(() {
      _splashSettings = settings;
      if (isCustomSplashActive && _customSplashImageUrl != nextImageUrl) {
        _customSplashImageUrl = nextImageUrl;
        _customSplashImageVisibleAt = null;
        _customSplashImageReadyCompleter = Completer<void>();
        _stopCustomSplashCountdown(notify: false);
      }
      if (isCustomSplashActive && !wasCustomSplashActive) {
        _customSplashActivatedAt = DateTime.now();
      }
      if (!isCustomSplashActive) {
        _customSplashActivatedAt = null;
        _customSplashImageVisibleAt = null;
        _customSplashImageUrl = null;
        _customSplashImageReadyCompleter = null;
        _stopCustomSplashCountdown(notify: false);
      }
    });
  }

  void _markCustomSplashImageVisible(String imageUrl) {
    final normalizedUrl = ApiConfig.getMediaUrl(imageUrl);
    if (normalizedUrl.isEmpty || normalizedUrl != _customSplashImageUrl) {
      return;
    }
    if (_customSplashImageVisibleAt != null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _customSplashImageVisibleAt != null) return;
      setState(() => _customSplashImageVisibleAt = DateTime.now());
      _startCustomSplashCountdown();
      final completer = _customSplashImageReadyCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    });
  }

  void _startCustomSplashCountdown() {
    _customSplashCountdownTimer?.cancel();
    _updateCustomSplashCountdown();
    _customSplashCountdownTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _updateCustomSplashCountdown(),
    );
  }

  void _stopCustomSplashCountdown({bool notify = true}) {
    _customSplashCountdownTimer?.cancel();
    _customSplashCountdownTimer = null;
    if (notify && _customSplashCountdownSeconds != null && mounted) {
      setState(() => _customSplashCountdownSeconds = null);
    } else {
      _customSplashCountdownSeconds = null;
    }
  }

  void _updateCustomSplashCountdown() {
    if (!mounted || _splashSkipped) {
      _stopCustomSplashCountdown();
      return;
    }
    final settings = _splashSettings;
    final visibleAt = _customSplashImageVisibleAt;
    if (settings == null ||
        !settings.splashEnabled ||
        settings.splashImageUrl.trim().isEmpty ||
        visibleAt == null) {
      return;
    }

    final durationMs = settings.splashDurationMs.clamp(800, 8000);
    final elapsedMs = DateTime.now().difference(visibleAt).inMilliseconds;
    final remainingMs = (durationMs - elapsedMs).clamp(0, durationMs);
    final seconds = (remainingMs / 1000).ceil();
    if (_customSplashCountdownSeconds != seconds) {
      setState(() => _customSplashCountdownSeconds = seconds);
    }
    if (remainingMs <= 0) {
      _customSplashCountdownTimer?.cancel();
      _customSplashCountdownTimer = null;
    }
  }

  Future<void> _waitForCustomSplashImageVisible() async {
    if (_customSplashImageVisibleAt != null) return;

    final completer = _customSplashImageReadyCompleter;
    if (completer == null || completer.isCompleted) return;

    try {
      await Future.any<void>([
        completer.future,
        _skipSplashCompleter.future,
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      if (_customSplashImageVisibleAt == null) {
        if (mounted) {
          setState(() => _customSplashImageVisibleAt = DateTime.now());
          _startCustomSplashCountdown();
        } else {
          _customSplashImageVisibleAt = DateTime.now();
        }
      }
    }
  }

  Future<void> _waitForSplashMinimumDisplay() async {
    if (_splashSkipped) return;

    if (_splashSettings == null) {
      try {
        await _splashSettingsReady.timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    final settings = _splashSettings;
    if (settings == null ||
        !settings.splashEnabled ||
        settings.splashImageUrl.trim().isEmpty) {
      return;
    }
    await _waitForCustomSplashImageVisible();
    if (_splashSkipped) return;

    final durationMs = settings.splashDurationMs.clamp(800, 8000);
    final displayStartedAt = _customSplashImageVisibleAt ??
        _customSplashActivatedAt ??
        _splashStartedAt;
    final elapsed = DateTime.now().difference(displayStartedAt).inMilliseconds;
    final remaining = durationMs - elapsed;
    if (remaining > 0) {
      await Future.any<void>([
        Future<void>.delayed(Duration(milliseconds: remaining)),
        _skipSplashCompleter.future,
      ]);
    }
  }

  void _skipSplash() {
    if (_splashSkipped) return;
    setState(() => _splashSkipped = true);
    _stopCustomSplashCountdown();
    if (!_skipSplashCompleter.isCompleted) {
      _skipSplashCompleter.complete();
    }
    if (_resolvedAuthStatus != null) {
      unawaited(_ensureUpdateGateThenNavigate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _customSplashCountdownTimer?.cancel();
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
    PerformanceTraceService.mark('splash.navigate.${status.name}');

    final redirect = GoRouterState.of(
      context,
    ).uri.queryParameters['redirect'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PerformanceTraceService.mark('splash.route_go.${status.name}');

      final target = safeInAppRedirect(
        redirect,
      );
      if (status == AuthStatus.authenticated) {
        context.go(target ?? '/home');
      } else {
        context.go(target == null
            ? '/login'
            : loginLocationWithRedirect(
                Uri.parse(target),
              ));
      }
    });
  }

  void _onAuthStatusResolved(AuthStatus status) {
    _resolvedAuthStatus = status;
    PerformanceTraceService.mark('splash.auth_resolved.${status.name}');
    unawaited(_ensureUpdateGateThenNavigate());
  }

  Future<void> _ensureUpdateGateThenNavigate() async {
    if (_forceUpdateRequired) return;

    if (kIsWeb || RuntimeFlags.smokeTest) {
      _updateCheckCompleted = true;
      if (_resolvedAuthStatus != null) {
        await _waitForSplashMinimumDisplay();
        if (!mounted) return;
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
    if (_resolvedAuthStatus != AuthStatus.authenticated) {
      await _waitForSplashMinimumDisplay();
    }
    if (!mounted) return;
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

    final sdkAdapter = ref.read(hotUpdateSdkAdapterProvider);
    final shorebirdAvailable = await sdkAdapter.supportsShorebird();
    if (shorebirdAvailable) {
      // Do not gate splash navigation on a network request. The foreground
      // check is a reliable fallback for platforms where background execution
      // may be delayed or suspended; a downloaded patch applies next launch.
      unawaited(_downloadLatestShorebirdPatch(sdkAdapter));
    } else if (Platform.isAndroid) {
      await _runHotUpdatePatchFlow();
    }
  }

  Future<void> _downloadLatestShorebirdPatch(
    HotUpdateSdkAdapter sdkAdapter,
  ) async {
    const foregroundCheckMarker = 'shorebird-foreground-check-v1';
    try {
      final result = await sdkAdapter.downloadLatestShorebirdPatch();
      debugPrint(
        '[Splash] Shorebird foreground update ($foregroundCheckMarker): '
        'success=${result.success}, restart=${result.requiresRestart}, '
        'message=${result.message}',
      );
    } catch (e) {
      debugPrint('[Splash] Shorebird foreground update failed: $e');
    }
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
          debugPrint(
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

      _setHotUpdateApplyingState(
        true,
        message: _text(
          zhCN: '正在准备热更新...',
          zhTW: '正在準備熱更新...',
          en: 'Preparing hot update...',
        ),
      );
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
        debugPrint(
          '[Splash] Hot update bridge unavailable: ${supportStatus.message}',
        );
        if (patch.isMandatory) {
          _setMandatoryPatchGate(
            patch: patch,
            appVersion: appVersion,
            buildNumber: buildNumber,
            message: _text(
              zhCN: '检测到必须更新，但当前设备不支持所需的安装通道。',
              zhTW: '偵測到必須更新，但目前裝置不支援所需的安裝通道。',
              en: 'A required update was detected, but this device does not support the required install channel.',
            ),
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: _text(
              zhCN: '热更新不可用',
              zhTW: '熱更新不可用',
              en: 'Hot Update Unavailable',
            ),
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
        debugPrint(
          '[Splash] Hot update SDK not integrated yet: ${supportStatus.message}',
        );
        if (patch.isMandatory) {
          _setMandatoryPatchGate(
            patch: patch,
            appVersion: appVersion,
            buildNumber: buildNumber,
            message: _text(
              zhCN: '检测到必须更新，但当前安装包未集成所需的热更新能力。',
              zhTW: '偵測到必須更新，但目前安裝包未整合所需的熱更新能力。',
              en: 'A required update was detected, but this build does not include the required hot update capability.',
            ),
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: _text(
              zhCN: '热更新不可用',
              zhTW: '熱更新不可用',
              en: 'Hot Update Unavailable',
            ),
            message: _friendlyPatchApplyMessageV2(supportStatus.message),
          );
        }
        return;
      }

      _setHotUpdateApplyingState(
        true,
        message: _text(
          zhCN: '正在下载并安装更新...',
          zhTW: '正在下載並安裝更新...',
          en: 'Downloading and installing update...',
        ),
      );

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
        debugPrint(
          '[Splash] Hot update available but apply failed: ${applyResult.message}',
        );
        if (patch.isMandatory) {
          _setMandatoryPatchGate(
            patch: patch,
            appVersion: appVersion,
            buildNumber: buildNumber,
            message: _text(
              zhCN: '必须更新安装失败，请稍后重试。',
              zhTW: '必須更新安裝失敗，請稍後重試。',
              en: 'Required update installation failed. Please try again later.',
            ),
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: _text(
              zhCN: '热更新失败',
              zhTW: '熱更新失敗',
              en: 'Hot Update Failed',
            ),
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

      debugPrint(
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
      debugPrint('[Splash] Hot update check/apply failed: $e');
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
        title: _text(
          zhCN: '热更新失败',
          zhTW: '熱更新失敗',
          en: 'Hot Update Failed',
        ),
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
      return _text(
        zhCN: '当前暂时无法获取补丁，请稍后再试。',
        zhTW: '目前暫時無法取得補丁，請稍後再試。',
        en: 'Unable to fetch the patch right now. Please try again later.',
      );
    }

    final normalized = message.toLowerCase();
    if (normalized.contains('shorebird_no_update_available_after_retry')) {
      return _text(
        zhCN:
            '补丁已命中，但 Shorebird 补丁还在同步到设备。请等待 1-2 分钟后，完全退出应用再重试。若仍失败，请确认当前安装的是支持补丁通道的基线包。',
        zhTW:
            '補丁已命中，但 Shorebird 補丁仍在同步到裝置。請等待 1-2 分鐘後，完全退出應用再重試。若仍失敗，請確認目前安裝的是支援補丁通道的基線包。',
        en: 'The patch matched, but the Shorebird patch is still syncing to the device. Wait 1-2 minutes, fully close the app, and try again. If it still fails, confirm the installed build supports the patch channel.',
      );
    }
    if (normalized.contains('shorebird_no_update_available') ||
        normalized.contains('no_update_available') ||
        normalized.contains('no patch') ||
        normalized.contains('no update')) {
      return _text(
        zhCN: '当前暂时没有可安装的补丁。若后台刚发布补丁，请等待 1-2 分钟后完全退出应用再重试。',
        zhTW: '目前暫時沒有可安裝的補丁。若後台剛發布補丁，請等待 1-2 分鐘後完全退出應用再重試。',
        en: 'There is no installable patch available right now. If a patch was just published, wait 1-2 minutes, fully close the app, and try again.',
      );
    }
    if (normalized.contains('shorebird_restart_required') ||
        normalized.contains('shorebird_update_downloaded')) {
      return _text(
        zhCN: '补丁已下载完成，请重启应用后生效。',
        zhTW: '補丁已下載完成，請重新啟動應用後生效。',
        en: 'The patch has been downloaded. Restart the app to apply it.',
      );
    }
    if (normalized.contains('shorebird_download_failed')) {
      return _text(
        zhCN: '补丁下载失败，请检查网络后重试。',
        zhTW: '補丁下載失敗，請檢查網路後重試。',
        en: 'Patch download failed. Check your network and try again.',
      );
    }
    if (normalized.contains('shorebird_install_failed')) {
      return _text(
        zhCN: '补丁安装失败，请重启应用后重试。',
        zhTW: '補丁安裝失敗，請重新啟動應用後重試。',
        en: 'Patch installation failed. Restart the app and try again.',
      );
    }
    if (normalized.contains('shorebird_update_failed')) {
      return _text(
        zhCN: '补丁更新失败，请稍后再试。',
        zhTW: '補丁更新失敗，請稍後再試。',
        en: 'Patch update failed. Please try again later.',
      );
    }
    if (normalized.contains('hot_update_sdk_not_available') ||
        normalized.contains('bridge unavailable') ||
        normalized.contains('sdk not available') ||
        normalized.contains('not available')) {
      return _text(
        zhCN: '当前设备暂不支持热更新通道。',
        zhTW: '目前裝置暫不支援熱更新通道。',
        en: 'This device does not currently support the hot update channel.',
      );
    }
    if (normalized.contains('hot_update_sdk_not_integrated') ||
        normalized.contains('sdk not integrated') ||
        normalized.contains('not integrated')) {
      return _text(
        zhCN: '当前安装包未集成所需的热更新能力。',
        zhTW: '目前安裝包未整合所需的熱更新能力。',
        en: 'This build does not include the required hot update capability.',
      );
    }
    if (normalized.contains('hot_update_platform_not_supported')) {
      return _text(
        zhCN: '当前平台不支持热更新。',
        zhTW: '目前平台不支援熱更新。',
        en: 'This platform does not support hot updates.',
      );
    }
    if (normalized.contains('patch_hash_invalid')) {
      return _text(
        zhCN: '补丁哈希格式无效，请使用 sha256、sha1 或 md5。',
        zhTW: '補丁雜湊格式無效，請使用 sha256、sha1 或 md5。',
        en: 'The patch hash format is invalid. Use sha256, sha1, or md5.',
      );
    }
    if (normalized.contains('patch_hash_mismatch')) {
      return _text(
        zhCN: '补丁校验失败，下载文件与后台配置不一致。',
        zhTW: '補丁校驗失敗，下載檔案與後台配置不一致。',
        en: 'Patch verification failed. The downloaded file does not match the admin configuration.',
      );
    }
    if (normalized.contains('patch_download_failed')) {
      return _text(
        zhCN: '补丁下载失败，请检查补丁地址和网络后重试。',
        zhTW: '補丁下載失敗，請檢查補丁地址和網路後重試。',
        en: 'Patch download failed. Check the patch URL and network, then try again.',
      );
    }
    if (normalized.contains('patch_file_missing')) {
      return _text(
        zhCN: '已下载的补丁文件不存在，请重新下载。',
        zhTW: '已下載的補丁檔案不存在，請重新下載。',
        en: 'The downloaded patch file does not exist. Download it again.',
      );
    }
    if (normalized.contains('patch_url_invalid')) {
      return _text(
        zhCN: '补丁地址无效，请检查后台配置。',
        zhTW: '補丁地址無效，請檢查後台配置。',
        en: 'The patch URL is invalid. Check the admin configuration.',
      );
    }
    if (normalized.contains('android_install_permission_required')) {
      return _text(
        zhCN: '请先允许安装未知来源应用，然后返回重试。',
        zhTW: '請先允許安裝未知來源應用，然後返回重試。',
        en: 'Allow installation from unknown sources first, then return and try again.',
      );
    }
    if (normalized.contains('android_install_permission_settings_failed')) {
      return _text(
        zhCN: '无法打开安装权限设置页，请手动授权后重试。',
        zhTW: '無法打開安裝權限設定頁，請手動授權後重試。',
        en: 'Unable to open the install permission settings page. Grant permission manually and try again.',
      );
    }
    if (normalized.contains('android_installer_not_found')) {
      return _text(
        zhCN: '当前设备未找到可用安装器。',
        zhTW: '目前裝置未找到可用安裝器。',
        en: 'No available installer was found on this device.',
      );
    }
    if (normalized.contains('android_installer_launch_failed')) {
      return _text(
        zhCN: '无法启动安装器，请检查系统安装权限。',
        zhTW: '無法啟動安裝器，請檢查系統安裝權限。',
        en: 'Unable to start the installer. Check system install permissions.',
      );
    }
    if (normalized.contains('android_installer_opened') ||
        normalized.contains('android_external_update_opened')) {
      return _text(
        zhCN: '已打开安装器，请按系统提示完成安装。',
        zhTW: '已打開安裝器，請依系統提示完成安裝。',
        en: 'The installer has been opened. Follow the system prompts to finish installation.',
      );
    }
    if (normalized.contains('ios_install_url_invalid')) {
      return _text(
        zhCN: 'iOS 补丁地址必须是 manifest.plist 或 itms-services 链接。',
        zhTW: 'iOS 補丁地址必須是 manifest.plist 或 itms-services 連結。',
        en: 'The iOS patch URL must be a manifest.plist or itms-services link.',
      );
    }
    if (normalized.contains('ios_manifest_package_url_missing')) {
      return _text(
        zhCN: 'iOS manifest 中未找到可下载的安装包地址。',
        zhTW: 'iOS manifest 中未找到可下載的安裝包地址。',
        en: 'No downloadable package URL was found in the iOS manifest.',
      );
    }
    if (normalized.contains('ios_install_open_failed')) {
      return _text(
        zhCN: '无法打开 iOS 安装流程，请检查 manifest 地址。',
        zhTW: '無法打開 iOS 安裝流程，請檢查 manifest 地址。',
        en: 'Unable to open the iOS installation flow. Check the manifest URL.',
      );
    }
    if (normalized.contains('ios_install_started')) {
      return _text(
        zhCN: '已打开 iOS 安装页面，请按系统提示完成安装。',
        zhTW: '已打開 iOS 安裝頁面，請依系統提示完成安裝。',
        en: 'The iOS installation page has been opened. Follow the system prompts to finish installation.',
      );
    }
    if (normalized.contains('patch_apply_result_invalid')) {
      return _text(
        zhCN: '未收到有效的原生安装结果。',
        zhTW: '未收到有效的原生安裝結果。',
        en: 'No valid native installation result was received.',
      );
    }
    if (normalized.contains('timeout') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return _text(
        zhCN: '网络不稳定导致补丁安装失败，请稍后再试。',
        zhTW: '網路不穩定導致補丁安裝失敗，請稍後再試。',
        en: 'Patch installation failed due to an unstable network. Please try again later.',
      );
    }
    return message;
  }

  Future<void> _showMandatoryPatchPromptV2(HotUpdatePatch patch) async {
    if (!mounted) return;

    final notes = patch.releaseNotes.trim().isNotEmpty
        ? patch.releaseNotes.trim()
        : (patch.description.trim().isNotEmpty
            ? patch.description.trim()
            : _text(
                zhCN: '当前设备有一个必须安装的热更新。',
                zhTW: '目前裝置有一個必須安裝的熱更新。',
                en: 'This device has a required hot update that must be installed.',
              ));

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _text(
              zhCN: '必须更新',
              zhTW: '必須更新',
              en: 'Required Update',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notes),
              const SizedBox(height: 10),
              if (patch.patchVersion.trim().isNotEmpty)
                Text(
                  _text(
                    zhCN: '补丁版本：${patch.patchVersion.trim()}',
                    zhTW: '補丁版本：${patch.patchVersion.trim()}',
                    en: 'Patch version: ${patch.patchVersion.trim()}',
                  ),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _text(
                  zhCN: '立即更新',
                  zhTW: '立即更新',
                  en: 'Update Now',
                ),
              ),
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
            : _text(
                zhCN: '检测到新的热更新，您可以现在安装，也可以稍后处理。',
                zhTW: '偵測到新的熱更新，您可以現在安裝，也可以稍後處理。',
                en: 'A new hot update is available. You can install it now or handle it later.',
              ));

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _text(
              zhCN: '检测到更新',
              zhTW: '偵測到更新',
              en: 'Update Available',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notes),
              const SizedBox(height: 10),
              if (patch.patchVersion.trim().isNotEmpty)
                Text(
                  _text(
                    zhCN: '补丁版本：${patch.patchVersion.trim()}',
                    zhTW: '補丁版本：${patch.patchVersion.trim()}',
                    en: 'Patch version: ${patch.patchVersion.trim()}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                _text(
                  zhCN: '稍后',
                  zhTW: '稍後',
                  en: 'Later',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                _text(
                  zhCN: '立即更新',
                  zhTW: '立即更新',
                  en: 'Update Now',
                ),
              ),
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
          title: Text(
            _text(
              zhCN: '需要重启',
              zhTW: '需要重新啟動',
              en: 'Restart Required',
            ),
          ),
          content: Text(
            version.isEmpty
                ? _text(
                    zhCN: '更新包已准备完成，请重启应用后生效。',
                    zhTW: '更新包已準備完成，請重新啟動應用後生效。',
                    en: 'The update package is ready. Restart the app to apply it.',
                  )
                : _text(
                    zhCN: '补丁 $version 已准备完成，请重启应用后生效。',
                    zhTW: '補丁 $version 已準備完成，請重新啟動應用後生效。',
                    en: 'Patch $version is ready. Restart the app to apply it.',
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _text(
                  zhCN: '我知道了',
                  zhTW: '我知道了',
                  en: 'OK',
                ),
              ),
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
            message.trim().isEmpty
                ? _text(
                    zhCN: '当前无法完成更新，请稍后重试。',
                    zhTW: '目前無法完成更新，請稍後重試。',
                    en: 'Unable to complete the update right now. Please try again later.',
                  )
                : message,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _text(
                  zhCN: '我知道了',
                  zhTW: '我知道了',
                  en: 'OK',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _normalizeHotUpdateDialogTitle(String raw) {
    final title = raw.trim();
    if (title.isEmpty) {
      return _text(
        zhCN: '热更新不可用',
        zhTW: '熱更新不可用',
        en: 'Hot Update Unavailable',
      );
    }
    if (title.contains('failed') || title.contains('Failed')) {
      return _text(
        zhCN: '热更新失败',
        zhTW: '熱更新失敗',
        en: 'Hot Update Failed',
      );
    }
    if (title.contains('unavailable') || title.contains('Unavailable')) {
      return _text(
        zhCN: '热更新不可用',
        zhTW: '熱更新不可用',
        en: 'Hot Update Unavailable',
      );
    }
    return title;
  }

  String _normalizeMandatoryPatchGateMessage(String raw) {
    final message = raw.trim();
    final lower = message.toLowerCase();
    if (message.isEmpty) {
      return _text(
        zhCN: '必须先完成热更新后，才可继续使用应用。',
        zhTW: '必須先完成熱更新後，才可繼續使用應用。',
        en: 'You must complete the hot update before continuing to use the app.',
      );
    }
    if (message.contains('device') && lower.contains('support')) {
      return _text(
        zhCN: '检测到必须更新，但当前设备不支持所需的安装通道。',
        zhTW: '偵測到必須更新，但目前裝置不支援所需的安裝通道。',
        en: 'A required update was detected, but this device does not support the required install channel.',
      );
    }
    if (message.contains('client') && lower.contains('sdk')) {
      return _text(
        zhCN: '检测到必须更新，但当前安装包未集成所需的热更新能力。',
        zhTW: '偵測到必須更新，但目前安裝包未整合所需的熱更新能力。',
        en: 'A required update was detected, but this build does not include the required hot update capability.',
      );
    }
    if (lower.contains('install failed')) {
      return _text(
        zhCN: '必须更新安装失败，请稍后重试。',
        zhTW: '必須更新安裝失敗，請稍後重試。',
        en: 'Required update installation failed. Please try again later.',
      );
    }
    if (lower.contains('downloaded') || lower.contains('installer')) {
      return _text(
        zhCN: '必须更新包已准备完成，请重启应用或按系统提示完成安装后继续。',
        zhTW: '必須更新包已準備完成，請重新啟動應用或依系統提示完成安裝後繼續。',
        en: 'The required update package is ready. Restart the app or follow the system prompt to finish installation before continuing.',
      );
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
      debugPrint(
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
      debugPrint('[Splash] Save pending hot update install failed: $e');
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
    final message = progress.message.trim().isEmpty
        ? _text(
            zhCN: '正在处理更新...',
            zhTW: '正在處理更新...',
            en: 'Processing update...',
          )
        : progress.message.trim();
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
      return _text(
        zhCN: '已下载：${_formatBytes(progress.receivedBytes)}',
        zhTW: '已下載：${_formatBytes(progress.receivedBytes)}',
        en: 'Downloaded: ${_formatBytes(progress.receivedBytes)}',
      );
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
      _HotUpdateProgressDialogState(
        message: _text(
          zhCN: '正在准备更新...',
          zhTW: '正在準備更新...',
          en: 'Preparing update...',
        ),
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
              title: Text(
                _text(
                  zhCN: '正在安装更新',
                  zhTW: '正在安裝更新',
                  en: 'Installing Update',
                ),
              ),
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
                                  AppColors.primaryFor(context)
                                      .withValues(alpha: 0.9),
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
        ? _text(
            zhCN: '正在安装更新，请稍候...',
            zhTW: '正在安裝更新，請稍候...',
            en: 'Installing update. Please wait...',
          )
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
                          AppColors.primaryFor(context).withValues(alpha: 0.9),
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
          .getSettings(forceRefresh: true)
          .timeout(const Duration(seconds: 8));

      final latestVersion =
          (Platform.isIOS ? settings.appVersionIOS : settings.appVersionAndroid)
              .trim();
      final minSupportedVersion =
          settings.minSupportedVersionFor(ios: Platform.isIOS);
      if (latestVersion.isEmpty && minSupportedVersion.isEmpty) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _composeCurrentVersion(
        packageInfo.version.trim(),
        packageInfo.buildNumber.trim(),
      );

      final belowMinimum = minSupportedVersion.isNotEmpty &&
          compareAppVersions(minSupportedVersion, currentVersion) > 0;
      final latestAvailable = latestVersion.isNotEmpty &&
          compareAppVersions(latestVersion, currentVersion) > 0;
      final needsUpdate = latestAvailable || belowMinimum;
      if (!needsUpdate) return null;

      final targetVersion = belowMinimum &&
              compareAppVersions(minSupportedVersion, latestVersion) > 0
          ? minSupportedVersion
          : (latestAvailable ? latestVersion : minSupportedVersion);

      final updateUrl = settings.appUpdateUrlFor(ios: Platform.isIOS);
      if (updateUrl.isEmpty) {
        debugPrint(
            '[Splash] New version detected but platform update URL is empty');
        return null;
      }

      if (Platform.isIOS && !_isOfficialAppStoreUrl(updateUrl)) {
        debugPrint('[Splash] Ignoring non-App-Store iOS update URL');
        return null;
      }

      // Once a platform minimum is configured it is the sole force-update
      // source. The legacy boolean remains only for older backend configs.
      final forceUpdate = minSupportedVersion.isNotEmpty
          ? belowMinimum
          : settings.appForceUpdate;
      final message = settings.appUpdateMessage.trim().isNotEmpty
          ? settings.appUpdateMessage.trim()
          : _text(
              zhCN: '检测到新版本（$targetVersion），请更新后继续使用。',
              zhTW: '偵測到新版本（$targetVersion），請更新後繼續使用。',
              en: 'A new version ($targetVersion) is available. Please update to continue.',
            );

      return _UpdateInfo(
        isForceUpdate: forceUpdate,
        targetVersion: targetVersion,
        currentVersion: currentVersion,
        updateUrl: updateUrl,
        message: message,
      );
    } catch (e) {
      debugPrint('[Splash] Update check failed: $e');
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
              title: Text(
                _text(
                  zhCN: '检测到新版本',
                  zhTW: '偵測到新版本',
                  en: 'New Version Available',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(updateInfo.message),
                  const SizedBox(height: 10),
                  Text(
                    _text(
                      zhCN: '当前版本：${updateInfo.currentVersion}',
                      zhTW: '目前版本：${updateInfo.currentVersion}',
                      en: 'Current version: ${updateInfo.currentVersion}',
                    ),
                  ),
                  Text(
                    _text(
                      zhCN: '目标版本：${updateInfo.targetVersion}',
                      zhTW: '目標版本：${updateInfo.targetVersion}',
                      en: 'Target version: ${updateInfo.targetVersion}',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    _text(
                      zhCN: '稍后',
                      zhTW: '稍後',
                      en: 'Later',
                    ),
                  ),
                ),
                if (updateInfo.updateUrl.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      _text(
                        zhCN: '立即更新',
                        zhTW: '立即更新',
                        en: 'Update Now',
                      ),
                    ),
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
        title: _text(
          zhCN: '更新失败',
          zhTW: '更新失敗',
          en: 'Update Failed',
        ),
        message: _text(
          zhCN: '未配置有效的更新地址，请先在后台填写安装包下载链接。',
          zhTW: '未配置有效的更新地址，請先在後台填寫安裝包下載連結。',
          en: 'No valid update URL is configured. Add the package download URL in the admin panel first.',
        ),
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
        title: _text(
          zhCN: '更新失败',
          zhTW: '更新失敗',
          en: 'Update Failed',
        ),
        message: _text(
          zhCN: '更新地址格式不正确，请检查后台配置。',
          zhTW: '更新地址格式不正確，請檢查後台配置。',
          en: 'The update URL format is invalid. Check the admin configuration.',
        ),
      );
      return;
    }

    if (!_shouldUseInAppPackageUpdater(uri)) {
      final opened = await _openUpdateUrl(normalized);
      if (!opened) {
        await _showPatchApplyHintPromptV2(
          title: _text(
            zhCN: '打开更新链接失败',
            zhTW: '打開更新連結失敗',
            en: 'Failed to Open Update Link',
          ),
          message: _text(
            zhCN: '系统未能打开更新链接，请检查更新地址或设备默认浏览器设置。',
            zhTW: '系統未能打開更新連結，請檢查更新地址或裝置預設瀏覽器設定。',
            en: 'The system could not open the update link. Check the URL or your device default browser settings.',
          ),
        );
      } else {
        await _showPatchApplyHintPromptV2(
          title: _text(
            zhCN: '已打开更新链接',
            zhTW: '已打開更新連結',
            en: 'Update Link Opened',
          ),
          message: _text(
            zhCN: '系统已尝试打开更新链接，请按页面提示完成下载或安装。',
            zhTW: '系統已嘗試打開更新連結，請依頁面提示完成下載或安裝。',
            en: 'The system has tried to open the update link. Follow the prompts to download or install it.',
          ),
        );
      }
      return;
    }

    final sdkAdapter = ref.read(hotUpdateSdkAdapterProvider);
    final syntheticPatch = HotUpdatePatch(
      name: _text(
        zhCN: '应用安装包更新',
        zhTW: '應用安裝包更新',
        en: 'App Package Update',
      ),
      description: _text(
        zhCN: '通过应用内更新器安装新的安装包。',
        zhTW: '透過應用內更新器安裝新的安裝包。',
        en: 'Install a new app package through the in-app updater.',
      ),
      platform: 'android',
      targetAppVersion: targetVersion,
      patchVersion: targetVersion.isNotEmpty ? targetVersion : currentVersion,
      patchUrl: normalized,
    );

    try {
      debugPrint('[Splash] Start in-app package update: $normalized');
      _setHotUpdateApplyingState(
        true,
        message: _text(
          zhCN: '正在准备安装包更新...',
          zhTW: '正在準備安裝包更新...',
          en: 'Preparing package update...',
        ),
      );
      await _showHotUpdateProgressDialog();

      final supportStatus = await sdkAdapter.getSupportStatus();
      if (!supportStatus.available || !supportStatus.sdkIntegrated) {
        debugPrint(
          '[Splash] In-app package updater unavailable, fallback to external: ${supportStatus.message}',
        );
        await _closeHotUpdateProgressDialog();
        _setHotUpdateApplyingState(false);
        final opened = await _openUpdateUrl(normalized);
        if (!opened) {
          await _showPatchApplyHintPromptV2(
            title: _text(
              zhCN: '打开更新链接失败',
              zhTW: '打開更新連結失敗',
              en: 'Failed to Open Update Link',
            ),
            message: _text(
              zhCN: '当前设备无法拉起系统安装流程，请检查下载地址和系统权限。',
              zhTW: '目前裝置無法喚起系統安裝流程，請檢查下載地址和系統權限。',
              en: 'This device cannot start the system installation flow. Check the download URL and system permissions.',
            ),
          );
        } else {
          await _showPatchApplyHintPromptV2(
            title: _text(
              zhCN: '已打开更新链接',
              zhTW: '已打開更新連結',
              en: 'Update Link Opened',
            ),
            message: _text(
              zhCN: '当前设备不支持应用内安装，已切换为系统下载/安装流程。',
              zhTW: '目前裝置不支援應用內安裝，已切換為系統下載/安裝流程。',
              en: 'This device does not support in-app installation. Switched to the system download/install flow.',
            ),
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
          title: _text(
            zhCN: '安装包更新失败',
            zhTW: '安裝包更新失敗',
            en: 'Package Update Failed',
          ),
          message: _friendlyAppUpdateMessage(applyResult.message),
        );
        return;
      }

      if (applyResult.requiresRestart) {
        await _showPatchApplyHintPromptV2(
          title: _text(
            zhCN: '需要重启',
            zhTW: '需要重新啟動',
            en: 'Restart Required',
          ),
          message: _text(
            zhCN: '更新包已安装完成，请重启应用后生效。',
            zhTW: '更新包已安裝完成，請重新啟動應用後生效。',
            en: 'The update package has been installed. Restart the app to apply it.',
          ),
        );
        return;
      }

      await _showPatchApplyHintPromptV2(
        title: _text(
          zhCN: '更新已准备完成',
          zhTW: '更新已準備完成',
          en: 'Update Ready',
        ),
        message: _text(
          zhCN: '更新包已准备完成，可稍后重启应用生效。',
          zhTW: '更新包已準備完成，可稍後重新啟動應用生效。',
          en: 'The update package is ready. You can restart the app later to apply it.',
        ),
      );
    } catch (e) {
      debugPrint('[Splash] Start in-app package update failed: $e');
      await _closeHotUpdateProgressDialog();
      _setHotUpdateApplyingState(false);
      await _showPatchApplyHintPromptV2(
        title: _text(
          zhCN: '安装包更新失败',
          zhTW: '安裝包更新失敗',
          en: 'Package Update Failed',
        ),
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
      return _text(
        zhCN: '当前无法完成安装包更新，请稍后重试。',
        zhTW: '目前無法完成安裝包更新，請稍後重試。',
        en: 'Unable to complete the package update right now. Please try again later.',
      );
    }

    final normalized = message.toLowerCase();
    if (normalized.contains('patch_download_failed')) {
      return _text(
        zhCN: '安装包下载失败，请检查更新地址和网络后重试。',
        zhTW: '安裝包下載失敗，請檢查更新地址和網路後重試。',
        en: 'Package download failed. Check the update URL and network, then try again.',
      );
    }
    if (normalized.contains('patch_url_invalid')) {
      return _text(
        zhCN: '更新地址无效，请检查后台配置。',
        zhTW: '更新地址無效，請檢查後台配置。',
        en: 'The update URL is invalid. Check the admin configuration.',
      );
    }
    if (normalized.contains('patch_apply_result_invalid')) {
      return _text(
        zhCN: '更新器返回了无效结果，请检查原生热更新桥接。',
        zhTW: '更新器返回了無效結果，請檢查原生熱更新橋接。',
        en: 'The updater returned an invalid result. Check the native hot update bridge.',
      );
    }
    if (normalized.contains('patch_file_missing')) {
      return _text(
        zhCN: '已下载的更新包不存在，请重新下载。',
        zhTW: '已下載的更新包不存在，請重新下載。',
        en: 'The downloaded update package does not exist. Download it again.',
      );
    }
    if (normalized.contains('android_install_permission_required')) {
      return _text(
        zhCN: '请先允许安装未知来源应用，然后返回重试。',
        zhTW: '請先允許安裝未知來源應用，然後返回重試。',
        en: 'Allow installation from unknown sources first, then return and try again.',
      );
    }
    if (normalized.contains('android_install_permission_settings_failed')) {
      return _text(
        zhCN: '无法打开安装权限设置页，请手动授权后重试。',
        zhTW: '無法打開安裝權限設定頁，請手動授權後重試。',
        en: 'Unable to open the install permission settings page. Grant permission manually and try again.',
      );
    }
    if (normalized.contains('android_installer_not_found')) {
      return _text(
        zhCN: '当前设备未找到可用安装器。',
        zhTW: '目前裝置未找到可用安裝器。',
        en: 'No available installer was found on this device.',
      );
    }
    if (normalized.contains('android_installer_launch_failed')) {
      return _text(
        zhCN: '无法启动安装器，请检查系统安装权限后重试。',
        zhTW: '無法啟動安裝器，請檢查系統安裝權限後重試。',
        en: 'Unable to start the installer. Check system install permissions and try again.',
      );
    }
    if (normalized.contains('android_installer_opened')) {
      return _text(
        zhCN: '已打开安装器，请按系统提示完成安装。',
        zhTW: '已打開安裝器，請依系統提示完成安裝。',
        en: 'The installer has been opened. Follow the system prompts to finish installation.',
      );
    }
    if (normalized.contains('ios_install_url_invalid')) {
      return _text(
        zhCN: 'iOS 安装地址无效。',
        zhTW: 'iOS 安裝地址無效。',
        en: 'The iOS install URL is invalid.',
      );
    }
    if (normalized.contains('ios_manifest_package_url_missing')) {
      return _text(
        zhCN: 'iOS manifest 中未包含有效的安装包地址。',
        zhTW: 'iOS manifest 中未包含有效的安裝包地址。',
        en: 'The iOS manifest does not contain a valid package URL.',
      );
    }
    if (normalized.contains('ios_install_started')) {
      return _text(
        zhCN: '已打开 iOS 安装页面，请按系统提示完成安装。',
        zhTW: '已打開 iOS 安裝頁面，請依系統提示完成安裝。',
        en: 'The iOS installation page has been opened. Follow the system prompts to finish installation.',
      );
    }
    if (normalized.contains('timeout') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return _text(
        zhCN: '网络请求超时或失败，导致安装包无法下载。',
        zhTW: '網路請求逾時或失敗，導致安裝包無法下載。',
        en: 'The package could not be downloaded because the network request timed out or failed.',
      );
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
      debugPrint('[Splash] Open update url failed: $e');
      return false;
    }
  }

  bool _isOfficialAppStoreUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'apps.apple.com' ||
        host == 'itunes.apple.com' ||
        host == 'appstore.com';
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

  Widget _buildForceUpdateView({
    required bool isDark,
    required String appName,
  }) {
    final progressLabel = _hotUpdateProgressValue == null
        ? '--'
        : '${(_hotUpdateProgressValue! * 100).clamp(0, 100).round()}%';
    final progressMessage = _hotUpdateApplyingMessage.trim().isEmpty
        ? _text(
            zhCN: '正在安装更新，请稍候...',
            zhTW: '正在安裝更新，請稍候...',
            en: 'Installing update. Please wait...',
          )
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
                    _text(
                      zhCN: '当前版本：$_currentVersion  目标版本：$_targetVersion',
                      zhTW: '目前版本：$_currentVersion  目標版本：$_targetVersion',
                      en: 'Current version: $_currentVersion  Target version: $_targetVersion',
                    ),
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
                            AppColors.primaryFor(context)
                                .withValues(alpha: 0.9),
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
                      backgroundColor: AppColors.primaryFor(context),
                      foregroundColor: AppColors.onPrimaryFor(context),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _hotUpdateApplying
                          ? _text(
                              zhCN: '正在更新...',
                              zhTW: '正在更新...',
                              en: 'Updating...',
                            )
                          : (_updateUrl.isEmpty
                              ? _text(
                                  zhCN: '重新检查',
                                  zhTW: '重新檢查',
                                  en: 'Check Again',
                                )
                              : _text(
                                  zhCN: '立即更新',
                                  zhTW: '立即更新',
                                  en: 'Update Now',
                                )),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_updateUrl.isNotEmpty)
                  TextButton(
                    onPressed: _hotUpdateApplying ? null : _recheckAfterUpdate,
                    child: Text(
                      _text(
                        zhCN: '我已完成更新，重新检查',
                        zhTW: '我已完成更新，重新檢查',
                        en: 'I have updated, check again',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomSplashImage(String imageUrl) {
    final url = ApiConfig.getMediaUrl(imageUrl);
    if (url.isEmpty) {
      return Image.asset('assets/logo.png', width: 120, height: 120);
    }

    return Builder(
      builder: (context) {
        final screen = MediaQuery.sizeOf(context);
        final width = (screen.width * 0.72).clamp(180.0, 360.0).toDouble();
        final height = (screen.height * 0.48).clamp(260.0, 560.0).toDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.network(
            url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                _markCustomSplashImageVisible(imageUrl);
              }
              return child;
            },
            errorBuilder: (_, __, ___) => Builder(builder: (context) {
              _markCustomSplashImageVisible(imageUrl);
              return Image.asset('assets/logo.png', width: 120, height: 120);
            }),
          ),
        );
      },
    );
  }

  Widget _buildBundledSplashImage() {
    return Center(
      child: Image.asset(
        'assets/logo.png',
        width: 120,
        height: 120,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = RuntimeFlags.disableSplashImage
        ? null
        : _splashSettings ??
            ref.read(systemSettingsServiceProvider).cachedSettings;
    final appName = settings?.displayName ?? defaultAppDisplayName();
    final splashImageUrl = settings?.splashImageUrl.trim() ?? '';
    final hasCustomSplash =
        settings?.splashEnabled == true && splashImageUrl.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_forceUpdateRequired) {
      return _buildForceUpdateView(isDark: isDark, appName: appName);
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      body: Stack(
        children: [
          if (RuntimeFlags.disableSplashImage)
            const SizedBox.shrink()
          else if (!hasCustomSplash)
            Positioned.fill(
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
                child: _buildBundledSplashImage(),
              ),
            )
          else
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
                    _buildCustomSplashImage(splashImageUrl),
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
                      _text(
                        zhCN: '安全  ·  高速  ·  私密',
                        zhTW: '安全  ·  高速  ·  私密',
                        en: 'Secure  ·  Fast  ·  Private',
                      ),
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
                          AppColors.primaryFor(context).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (hasCustomSplash && !_hotUpdateApplying)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 16),
                  child: TextButton(
                    onPressed: _skipSplash,
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      backgroundColor: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      _customSplashCountdownSeconds == null
                          ? _text(
                              zhCN: '跳过',
                              zhTW: '跳過',
                              en: 'Skip',
                            )
                          : _text(
                              zhCN: '跳过 ${_customSplashCountdownSeconds}s',
                              zhTW: '跳過 ${_customSplashCountdownSeconds}s',
                              en: 'Skip ${_customSplashCountdownSeconds}s',
                            ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
