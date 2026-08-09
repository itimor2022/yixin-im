// 文件用途：封装 HotUpdateSupportStatus 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 HotUpdateSupportStatus 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart' as shorebird;
import 'package:universal_io/io.dart';
import 'package:xml/xml.dart' as xml;

import '../i18n/app_localizations.dart';
import 'api/hot_update_service.dart';

String _hotUpdateText({
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

// 关键声明：hot update sdk adapter 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 当前平台热更新能力的探测结果。
///
/// [available] 表示平台或原生桥具备能力，[sdkIntegrated] 表示当前构建已实际
/// 集成可调用的更新引擎；调用方必须同时检查二者才能开始更新。
class HotUpdateSupportStatus {
  final bool available;
  final bool sdkIntegrated;
  final String platform;
  final String message;

  const HotUpdateSupportStatus({
    required this.available,
    required this.sdkIntegrated,
    this.platform = '',
    this.message = '',
  });
}

/// 一次更新尝试的结果；[requiresRestart] 只表示补丁已准备好且需重启生效。
class HotUpdateApplyResult {
  final bool success;
  final bool requiresRestart;
  final String message;

  const HotUpdateApplyResult({
    required this.success,
    this.requiresRestart = false,
    this.message = '',
  });
}

/// 更新进度所处阶段。并非所有下载源都能提供确定的字节总数。
enum HotUpdateProgressPhase {
  preparing,
  downloading,
  verifying,
  applyingPatch,
  launchingInstaller,
}

/// 面向 UI 的更新进度快照，[progress] 为 null 时应展示不确定进度。
class HotUpdateProgress {
  final HotUpdateProgressPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final double? progress;
  final String message;

  const HotUpdateProgress({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.progress,
    this.message = '',
  });
}

typedef HotUpdateProgressCallback = void Function(HotUpdateProgress progress);

/// 统一 Shorebird 补丁与自托管安装包的更新入口。
///
/// Android/iOS 的 Shorebird 路径直接调用 SDK；自托管 Android APK 先在 Dart
/// 层下载和校验，再通过 MethodChannel 启动原生安装器。iOS 自托管入口当前禁用，
/// 避免绕过受控的 Shorebird 发布链路。
class HotUpdateSdkAdapter {
  static const MethodChannel _channel = MethodChannel(
    'com.genericim/hot_update',
  );
  static const int _shorebirdAvailabilityRetryAttempts = 4;
  final Dio _downloadClient;
  final shorebird.ShorebirdUpdater _shorebirdUpdater;
  final bool _platformSupportsShorebird;

  HotUpdateSdkAdapter({
    Dio? downloadClient,
    shorebird.ShorebirdUpdater? shorebirdUpdater,
    bool? platformSupportsShorebird,
  })  : _shorebirdUpdater = shorebirdUpdater ?? shorebird.ShorebirdUpdater(),
        _platformSupportsShorebird =
            platformSupportsShorebird ?? (Platform.isAndroid || Platform.isIOS),
        _downloadClient = downloadClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 20),
                sendTimeout: const Duration(minutes: 5),
                followRedirects: true,
                responseType: ResponseType.bytes,
                validateStatus: (status) => status != null && status < 400,
              ),
            );

  // 流程逻辑：`getSupportStatus` 先校验账号、分页或连接状态，再读取远端/本地数据并合并结果；失败只更新错误状态，不覆盖已有可用数据。
  Future<HotUpdateSupportStatus> getSupportStatus() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_platform_not_supported',
      );
    }

    // 优先使用进程内 SDK 能力；只有 SDK 不可用时才探测兼容的原生自托管桥。
    if (_shorebirdUpdater.isAvailable) {
      return HotUpdateSupportStatus(
        available: true,
        sdkIntegrated: true,
        platform: Platform.isIOS ? 'ios' : 'android',
        message: 'shorebird_engine_ready',
      );
    }

    try {
      final result = await _channel.invokeMethod<dynamic>('isSupported');
      if (result is bool) {
        return HotUpdateSupportStatus(
          available: result,
          sdkIntegrated: result,
          platform: Platform.isIOS ? 'ios' : 'android',
          message: result ? 'self_hosted_updater_ready' : 'sdk_not_available',
        );
      }

      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        return HotUpdateSupportStatus(
          available: map['available'] == true,
          sdkIntegrated: map['sdkIntegrated'] == true,
          platform: map['platform']?.toString() ?? '',
          message: map['message']?.toString() ?? '',
        );
      }

      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_sdk_not_available',
      );
    } on MissingPluginException {
      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_sdk_not_available',
      );
    } catch (e) {
      debugPrint('[HotUpdateSDK] getSupportStatus error: $e');
      return HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: e.toString(),
      );
    }
  }

  Future<bool> isSupported() async {
    final status = await getSupportStatus();
    return status.available && status.sdkIntegrated;
  }

  Future<bool> supportsShorebird() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return false;
    }
    return _shorebirdUpdater.isAvailable;
  }

  Future<HotUpdateSupportStatus> getSupportStatusForPatch(
    HotUpdatePatch patch,
  ) async {
    // Shorebird 补丁不能退回自托管安装器，否则会混淆发布渠道和完整性校验链路。
    if (patch.deliveryMode != 'shorebird') {
      return getSupportStatus();
    }

    if (!(Platform.isAndroid || Platform.isIOS)) {
      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_platform_not_supported',
      );
    }

    if (_shorebirdUpdater.isAvailable) {
      return HotUpdateSupportStatus(
        available: true,
        sdkIntegrated: true,
        platform: Platform.isIOS ? 'ios' : 'android',
        message: 'shorebird_engine_ready',
      );
    }

    return HotUpdateSupportStatus(
      available: true,
      sdkIntegrated: false,
      platform: Platform.isIOS ? 'ios' : 'android',
      message: 'hot_update_sdk_not_integrated',
    );
  }

  Future<int?> readCurrentShorebirdPatchNumber() async {
    if (!_shorebirdUpdater.isAvailable) {
      return null;
    }

    try {
      final patch = await _shorebirdUpdater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('[HotUpdateSDK] readCurrentShorebirdPatchNumber error: $e');
      return null;
    }
  }

  Future<int?> readNextShorebirdPatchNumber() async {
    if (!_shorebirdUpdater.isAvailable) {
      return null;
    }

    try {
      final patch = await _shorebirdUpdater.readNextPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('[HotUpdateSDK] readNextShorebirdPatchNumber error: $e');
      return null;
    }
  }

  /// 不依赖业务后端补丁记录，直接检查并下载 Shorebird 最新补丁。
  ///
  /// 该操作适合在后台执行，不应阻塞页面导航；下载成功的补丁在下次启动时生效。
  Future<HotUpdateApplyResult> downloadLatestShorebirdPatch({
    HotUpdateProgressCallback? onProgress,
  }) async {
    if (!_platformSupportsShorebird || !_shorebirdUpdater.isAvailable) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'hot_update_sdk_not_integrated',
      );
    }

    // null track 使用 Shorebird 构建时嵌入的渠道：生产默认 stable，
    // `shorebird preview --track` 仍可按预览渠道测试。
    return _applyShorebirdUpdate(
      track: null,
      onProgress: onProgress,
    );
  }

  Future<HotUpdateApplyResult> applyPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    // deliveryMode 是更新执行器的路由权威，不能根据 URL 后缀猜测更新类型。
    if (patch.deliveryMode == 'shorebird') {
      if ((Platform.isAndroid || Platform.isIOS) &&
          _shorebirdUpdater.isAvailable) {
        return _applyShorebirdPatch(patch, onProgress: onProgress);
      }

      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'hot_update_sdk_not_integrated',
      );
    }

    if (Platform.isIOS) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'ios_self_hosted_updater_disabled',
      );
    }

    final supportStatus = await getSupportStatus();
    if (!supportStatus.available) {
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: supportStatus.message.isEmpty
            ? 'hot_update_sdk_not_available'
            : supportStatus.message,
      );
    }
    if (!supportStatus.sdkIntegrated) {
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: supportStatus.message.isEmpty
            ? 'hot_update_sdk_not_integrated'
            : supportStatus.message,
      );
    }

    if (Platform.isAndroid) {
      return _applyAndroidPatch(patch, onProgress: onProgress);
    }
    return const HotUpdateApplyResult(
      success: false,
      requiresRestart: false,
      message: 'hot_update_platform_not_supported',
    );
  }

  Future<HotUpdateApplyResult> _applyShorebirdPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    final track = _resolveShorebirdTrack(patch.channel);

    return _applyShorebirdUpdate(
      track: track,
      onProgress: onProgress,
    );
  }

  Future<HotUpdateApplyResult> _applyShorebirdUpdate({
    required shorebird.UpdateTrack? track,
    HotUpdateProgressCallback? onProgress,
  }) async {
    _emitProgress(
      onProgress,
      HotUpdateProgress(
        phase: HotUpdateProgressPhase.preparing,
        progress: null,
        message: _hotUpdateText(
          zhCN: '正在检查补丁...',
          zhTW: '正在檢查補丁...',
          en: 'Checking patch...',
        ),
      ),
    );

    try {
      // 先探测状态再下载；restartRequired 表示先前下载已完成，无需重复请求。
      final status = await _waitForShorebirdUpdateAvailability(
        track: track,
        onProgress: onProgress,
      );
      if (status == shorebird.UpdateStatus.upToDate) {
        return const HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'shorebird_no_update_available_after_retry',
        );
      }

      if (status == shorebird.UpdateStatus.restartRequired) {
        return const HotUpdateApplyResult(
          success: true,
          requiresRestart: true,
          message: 'shorebird_restart_required',
        );
      }

      if (status == shorebird.UpdateStatus.unavailable) {
        return const HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'hot_update_sdk_not_integrated',
        );
      }

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.downloading,
          progress: null,
          message: _hotUpdateText(
            zhCN: '正在下载补丁...',
            zhTW: '正在下載補丁...',
            en: 'Downloading patch...',
          ),
        ),
      );

      final updateResult = await _downloadShorebirdPatchWithRetry(
        track: track,
        onProgress: onProgress,
      );
      if (updateResult != null) {
        return updateResult;
      }

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.applyingPatch,
          progress: 1,
          message: _hotUpdateText(
            zhCN: '补丁已下载完成，重启应用后生效。',
            zhTW: '補丁已下載完成，重啟應用後生效。',
            en: 'Patch downloaded. Restart the app to apply it.',
          ),
        ),
      );

      return const HotUpdateApplyResult(
        success: true,
        requiresRestart: true,
        message: 'shorebird_update_downloaded',
      );
    } on shorebird.UpdateException catch (e) {
      switch (e.reason) {
        case shorebird.UpdateFailureReason.noUpdate:
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_no_update_available_after_retry',
          );
        case shorebird.UpdateFailureReason.downloadFailed:
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_download_failed',
          );
        case shorebird.UpdateFailureReason.installFailed:
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_install_failed',
          );
        case shorebird.UpdateFailureReason.unknown:
          return HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_update_failed:${e.message}',
          );
      }
    } catch (e) {
      debugPrint('[HotUpdateSDK] Shorebird applyPatch error: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'shorebird_update_failed:$e',
      );
    }
  }

  Future<shorebird.UpdateStatus> _waitForShorebirdUpdateAvailability({
    required shorebird.UpdateTrack? track,
    required HotUpdateProgressCallback? onProgress,
  }) async {
    // 发布后边缘节点可能短暂返回 upToDate，有限重试用于跨过同步窗口。
    for (var attempt = 1;
        attempt <= _shorebirdAvailabilityRetryAttempts;
        attempt++) {
      final status = await _shorebirdUpdater.checkForUpdate(track: track);
      if (status != shorebird.UpdateStatus.upToDate) {
        return status;
      }

      if (attempt >= _shorebirdAvailabilityRetryAttempts) {
        return status;
      }

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.preparing,
          progress: null,
          message: _hotUpdateText(
            zhCN:
                '补丁正在同步，正在自动重试 (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
            zhTW:
                '補丁正在同步，正在自動重試 (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
            en: 'Patch is syncing. Retrying automatically (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
          ),
        ),
      );
      await Future<void>.delayed(Duration(seconds: attempt < 3 ? 2 : 3));
    }

    return shorebird.UpdateStatus.upToDate;
  }

  Future<HotUpdateApplyResult?> _downloadShorebirdPatchWithRetry({
    required shorebird.UpdateTrack? track,
    required HotUpdateProgressCallback? onProgress,
  }) async {
    // 仅 noUpdate 视为发布同步竞态并重试；下载或安装失败立即向上层报告。
    for (var attempt = 1;
        attempt <= _shorebirdAvailabilityRetryAttempts;
        attempt++) {
      try {
        await _shorebirdUpdater.update(track: track);
        return null;
      } on shorebird.UpdateException catch (e) {
        if (e.reason == shorebird.UpdateFailureReason.noUpdate) {
          if (attempt >= _shorebirdAvailabilityRetryAttempts) {
            return const HotUpdateApplyResult(
              success: false,
              requiresRestart: false,
              message: 'shorebird_no_update_available_after_retry',
            );
          }

          _emitProgress(
            onProgress,
            HotUpdateProgress(
              phase: HotUpdateProgressPhase.downloading,
              progress: null,
              message: _hotUpdateText(
                zhCN:
                    '补丁正在同步，正在重新拉取 (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
                zhTW:
                    '補丁正在同步，正在重新拉取 (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
                en: 'Patch is syncing. Fetching again (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
              ),
            ),
          );
          await Future<void>.delayed(
            Duration(seconds: attempt < 3 ? 2 : 3),
          );
          continue;
        }

        if (e.reason == shorebird.UpdateFailureReason.downloadFailed) {
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_download_failed',
          );
        }
        if (e.reason == shorebird.UpdateFailureReason.installFailed) {
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_install_failed',
          );
        }
        return HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'shorebird_update_failed:${e.message}',
        );
      }
    }

    return const HotUpdateApplyResult(
      success: false,
      requiresRestart: false,
      message: 'shorebird_no_update_available_after_retry',
    );
  }

  Future<HotUpdateApplyResult> _applyAndroidPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    // 自托管 APK 只接受无用户信息的 HTTPS 地址，并要求服务端提供完整性哈希。
    final uri = _normalizeUri(patch.patchUrl);
    if (uri == null ||
        !_isSecureHttpUri(uri) ||
        !uri.path.toLowerCase().endsWith('.apk')) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_url_invalid',
      );
    }
    if (patch.patchHash.trim().isEmpty) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_hash_required',
      );
    }

    try {
      File? descriptorFile;
      File? packageFile;

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.preparing,
          progress: null,
          message: _hotUpdateText(
            zhCN: '正在准备下载更新包...',
            zhTW: '正在準備下載更新包...',
            en: 'Preparing update package...',
          ),
        ),
      );
      final downloadDir = await _ensureHotUpdateDirectory();
      final fileName = _buildDownloadFileName(
        uri,
        fallbackExtension: '.apk',
        fallbackStem: _fallbackStem(patch),
      );
      final file =
          File('${downloadDir.path}${Platform.pathSeparator}$fileName');
      if (await file.exists()) {
        await file.delete();
      }

      await _downloadClient.download(
        uri.toString(),
        file.path,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : null;
          _emitProgress(
            onProgress,
            HotUpdateProgress(
              phase: HotUpdateProgressPhase.downloading,
              receivedBytes: received,
              totalBytes: total > 0 ? total : 0,
              progress: progress,
              message: total > 0
                  ? _hotUpdateText(
                      zhCN: '正在下载更新包...',
                      zhTW: '正在下載更新包...',
                      en: 'Downloading update package...',
                    )
                  : _hotUpdateText(
                      zhCN: '正在下载更新包，等待获取进度...',
                      zhTW: '正在下載更新包，等待獲取進度...',
                      en: 'Downloading update package. Waiting for progress...',
                    ),
            ),
          );
        },
      );
      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.verifying,
          progress: 1,
          message: _hotUpdateText(
            zhCN: '下载完成，正在校验文件...',
            zhTW: '下載完成，正在校驗文件...',
            en: 'Download complete. Verifying file...',
          ),
        ),
      );
      final verifyError = await _verifyDownloadedFile(
        file: file,
        expectedHash: patch.patchHash,
      );
      if (verifyError != null) {
        await _safeDelete(file);
        return HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: verifyError,
        );
      }

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.launchingInstaller,
          progress: 1,
          message: _hotUpdateText(
            zhCN: '校验完成，正在启动安装器...',
            zhTW: '校驗完成，正在啟動安裝器...',
            en: 'Verification complete. Launching installer...',
          ),
        ),
      );
      final result = await _channel.invokeMethod<dynamic>('applyPatch', {
        'platform': 'android',
        'local_file_path': file.path,
        'file_name': fileName,
        'patch_url': uri.toString(),
      });

      // 启动外部安装器后不能立即删除 APK，原生侧仍需通过 FileProvider 读取它。
      return _parseApplyResult(
        result,
        defaultMessage: 'android_installer_opened',
        defaultRequiresRestart: true,
      );
    } on DioException catch (e) {
      debugPrint('[HotUpdateSDK] Android patch download failed: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_download_failed:${e.message ?? 'unknown'}',
      );
    } catch (e) {
      debugPrint('[HotUpdateSDK] Android applyPatch error: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: e.toString(),
      );
    }
  }

  Future<HotUpdateApplyResult> _applyIOSPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    // 保留自托管 iOS 描述文件校验实现供兼容构建使用；公开入口目前明确禁用此路径。
    final normalizedPatchUri = _normalizeUri(patch.patchUrl);
    if (normalizedPatchUri == null) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_url_invalid',
      );
    }
    if (patch.patchHash.trim().isEmpty) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_hash_required',
      );
    }

    File? descriptorFile;
    File? packageFile;

    try {
      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.preparing,
          progress: null,
          message: _hotUpdateText(
            zhCN: '正在准备更新...',
            zhTW: '正在準備更新...',
            en: 'Preparing update...',
          ),
        ),
      );
      final descriptorUri = _resolveIOSDescriptorUri(normalizedPatchUri);
      if (descriptorUri == null) {
        return const HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'ios_install_url_invalid',
        );
      }
      if (patch.patchHash.trim().isNotEmpty) {
        final downloadDir = await _ensureHotUpdateDirectory();
        final fileName = _buildDownloadFileName(
          descriptorUri,
          fallbackExtension: '.plist',
          fallbackStem: _fallbackStem(patch),
        );
        descriptorFile = File(
          '${downloadDir.path}${Platform.pathSeparator}$fileName',
        );
        if (await descriptorFile.exists()) {
          await descriptorFile.delete();
        }

        await _downloadClient.download(
          descriptorUri.toString(),
          descriptorFile.path,
          onReceiveProgress: (received, total) {
            final progress = total > 0 ? received / total : null;
            _emitProgress(
              onProgress,
              HotUpdateProgress(
                phase: HotUpdateProgressPhase.downloading,
                receivedBytes: received,
                totalBytes: total > 0 ? total : 0,
                progress: progress,
                message: _hotUpdateText(
                  zhCN: '正在下载更新描述文件...',
                  zhTW: '正在下載更新描述文件...',
                  en: 'Downloading update manifest...',
                ),
              ),
            );
          },
        );

        // plist 本身只负责定位 IPA；真正的完整性校验针对下载后的安装包。
        final descriptorText = await descriptorFile.readAsString();
        final packageUri = _extractIOSPackageUri(descriptorText, descriptorUri);
        if (packageUri == null) {
          await _safeDelete(descriptorFile);
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'ios_manifest_package_url_missing',
          );
        }

        packageFile = File(
          '${downloadDir.path}${Platform.pathSeparator}'
          '${_buildDownloadFileName(packageUri, fallbackExtension: '.ipa', fallbackStem: _fallbackStem(patch))}',
        );
        if (await packageFile.exists()) {
          await packageFile.delete();
        }

        await _downloadClient.download(
          packageUri.toString(),
          packageFile.path,
          onReceiveProgress: (received, total) {
            final progress = total > 0 ? received / total : null;
            _emitProgress(
              onProgress,
              HotUpdateProgress(
                phase: HotUpdateProgressPhase.downloading,
                receivedBytes: received,
                totalBytes: total > 0 ? total : 0,
                progress: progress,
                message: _hotUpdateText(
                  zhCN: '正在下载 iOS 安装包...',
                  zhTW: '正在下載 iOS 安裝包...',
                  en: 'Downloading iOS package...',
                ),
              ),
            );
          },
        );
        _emitProgress(
          onProgress,
          HotUpdateProgress(
            phase: HotUpdateProgressPhase.verifying,
            progress: 1,
            message: _hotUpdateText(
              zhCN: '下载完成，正在校验安装包...',
              zhTW: '下載完成，正在校驗安裝包...',
              en: 'Download complete. Verifying package...',
            ),
          ),
        );
        final verifyError = await _verifyDownloadedFile(
          file: packageFile,
          expectedHash: patch.patchHash,
        );
        if (verifyError != null) {
          await _safeDelete(packageFile);
          await _safeDelete(descriptorFile);
          return HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: verifyError,
          );
        }

        await _safeDelete(packageFile);
        await _safeDelete(descriptorFile);
      }

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.launchingInstaller,
          progress: 1,
          message: _hotUpdateText(
            zhCN: '校验完成，正在打开安装页面...',
            zhTW: '校驗完成，正在打開安裝頁面...',
            en: 'Verification complete. Opening the install page...',
          ),
        ),
      );
      final result = await _channel.invokeMethod<dynamic>('applyPatch', {
        'platform': 'ios',
        'patch_url': normalizedPatchUri.toString(),
      });

      return _parseApplyResult(
        result,
        defaultMessage: 'ios_install_started',
        defaultRequiresRestart: true,
      );
    } on DioException catch (e) {
      debugPrint('[HotUpdateSDK] iOS patch descriptor download failed: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_download_failed:${e.message ?? 'unknown'}',
      );
    } catch (e) {
      debugPrint('[HotUpdateSDK] iOS applyPatch error: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: e.toString(),
      );
    } finally {
      // iOS 原生侧只接收远程安装 URL，本地校验副本无须跨越方法调用生命周期。
      if (packageFile != null) {
        await _safeDelete(packageFile);
      }
      if (descriptorFile != null) {
        await _safeDelete(descriptorFile);
      }
    }
  }

  Future<Directory> _ensureHotUpdateDirectory() async {
    // 更新产物属于可重建数据，统一放在系统临时目录而非用户文档目录。
    final root = await getTemporaryDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}hot_update',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String?> _verifyDownloadedFile({
    required File file,
    required String expectedHash,
  }) async {
    // 先严格解析算法和摘要格式，再流式计算文件哈希，避免整包载入内存。
    final normalizedHash = expectedHash.trim();
    if (normalizedHash.isEmpty) {
      return 'patch_hash_required';
    }

    final parsed = _ParsedHash.parse(normalizedHash);
    if (parsed == null) {
      return 'patch_hash_invalid';
    }

    final actualHash = await parsed.compute(file);
    if (actualHash != parsed.hash) {
      return 'patch_hash_mismatch';
    }

    return null;
  }

  String _buildDownloadFileName(
    Uri uri, {
    required String fallbackStem,
    required String fallbackExtension,
  }) {
    // 服务端文件名只作为提示，落盘前必须剔除各桌面/移动文件系统的保留字符。
    final path = uri.path.trim();
    var fileName = path.isEmpty ? '' : path.split('/').last.trim();
    if (fileName.isEmpty) {
      fileName = fallbackStem + fallbackExtension;
    }

    final hasExtension = fileName.contains('.') && !fileName.endsWith('.');
    if (!hasExtension) {
      fileName += fallbackExtension;
    }

    return _sanitizeFileName(fileName);
  }

  String _sanitizeFileName(String input) {
    final sanitized = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty) {
      return 'hot_update.bin';
    }
    return sanitized;
  }

  String _fallbackStem(HotUpdatePatch patch) {
    final candidates = [
      patch.patchVersion.trim(),
      patch.targetAppVersion.trim(),
      patch.patchId.trim(),
      patch.name.trim(),
    ];
    for (final item in candidates) {
      if (item.isNotEmpty) {
        return item.replaceAll(RegExp(r'\s+'), '_');
      }
    }
    return 'hot_update_${DateTime.now().millisecondsSinceEpoch}';
  }

  Uri? _normalizeUri(String raw) {
    // 缺少 scheme 的配置按 HTTPS 补全；安全性仍由后续平台专用校验确认。
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      if (trimmed.startsWith('itms-services://')) {
        return Uri.parse(trimmed);
      }
      if (trimmed.contains('://')) {
        return Uri.parse(trimmed);
      }
      return Uri.parse('https://$trimmed');
    } catch (_) {
      return null;
    }
  }

  bool _isSecureHttpUri(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host.trim().isNotEmpty &&
        uri.userInfo.trim().isEmpty;
  }

  Uri? _resolveIOSDescriptorUri(Uri patchUri) {
    if (_isIOSManifestUri(patchUri)) {
      return patchUri;
    }
    if (patchUri.scheme != 'itms-services') {
      return null;
    }
    if (patchUri.queryParameters['action']?.trim() != 'download-manifest') {
      return null;
    }
    final embeddedUrl = patchUri.queryParameters['url']?.trim();
    if (embeddedUrl == null || embeddedUrl.isEmpty) {
      return null;
    }
    final normalizedEmbeddedUri = _normalizeUri(Uri.decodeFull(embeddedUrl));
    if (normalizedEmbeddedUri == null ||
        !_isIOSManifestUri(normalizedEmbeddedUri)) {
      return null;
    }
    return normalizedEmbeddedUri;
  }

  bool _isIOSManifestUri(Uri uri) {
    if (!_isSecureHttpUri(uri)) {
      return false;
    }
    return uri.path.toLowerCase().endsWith('.plist');
  }

  Uri? _extractIOSPackageUri(String plistContent, Uri descriptorUri) {
    // XML 来自远程端，只查找 software-package 节点并再次限制为 HTTPS IPA。
    xml.XmlDocument document;
    try {
      document = xml.XmlDocument.parse(plistContent);
    } catch (e) {
      debugPrint('[HotUpdateSDK] Invalid iOS manifest plist: $e');
      return null;
    }

    final rawValue = _findIOSSoftwarePackageURL(document.rootElement);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(rawValue.trim());
    if (parsed == null) {
      return null;
    }
    final resolved =
        parsed.hasScheme ? parsed : descriptorUri.resolveUri(parsed);
    if (!_isSecureHttpUri(resolved) ||
        !resolved.path.toLowerCase().endsWith('.ipa')) {
      return null;
    }
    return resolved;
  }

  String? _findIOSSoftwarePackageURL(xml.XmlElement element) {
    if (element.name.local.toLowerCase() == 'dict') {
      final entries = _plistDictEntries(element);
      final kind = entries['kind']?.innerText.trim();
      final packageURL = entries['url']?.innerText.trim();
      if (kind == 'software-package' &&
          packageURL != null &&
          packageURL.isNotEmpty) {
        return packageURL;
      }
    }

    for (final child in element.childElements) {
      final found = _findIOSSoftwarePackageURL(child);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  Map<String, xml.XmlElement> _plistDictEntries(xml.XmlElement dictElement) {
    final entries = <String, xml.XmlElement>{};
    String? currentKey;
    for (final child in dictElement.childElements) {
      final name = child.name.local.toLowerCase();
      if (name == 'key') {
        currentKey = child.innerText.trim();
        continue;
      }
      if (currentKey != null && currentKey.isNotEmpty) {
        entries[currentKey] = child;
      }
      currentKey = null;
    }
    return entries;
  }

  void _emitProgress(
    HotUpdateProgressCallback? callback,
    HotUpdateProgress progress,
  ) {
    if (callback == null) {
      return;
    }
    // 回调同步执行，阶段顺序与当前更新任务的异步执行顺序保持一致。
    callback(progress);
  }

  shorebird.UpdateTrack _resolveShorebirdTrack(String rawChannel) {
    final channel = rawChannel.trim().toLowerCase();
    switch (channel) {
      case '':
      case 'stable':
        return shorebird.UpdateTrack.stable;
      case 'beta':
        return shorebird.UpdateTrack.beta;
      case 'staging':
        return shorebird.UpdateTrack.staging;
      default:
        return shorebird.UpdateTrack(channel);
    }
  }

  HotUpdateApplyResult _parseApplyResult(
    dynamic result, {
    required String defaultMessage,
    required bool defaultRequiresRestart,
  }) {
    if (result is Map) {
      final map = Map<String, dynamic>.from(result);
      return HotUpdateApplyResult(
        success: map['success'] == true,
        requiresRestart: map['requires_restart'] == true,
        message: map['message']?.toString() ?? defaultMessage,
      );
    }

    if (result is bool) {
      return HotUpdateApplyResult(
        success: result,
        requiresRestart: result && defaultRequiresRestart,
        message: result ? defaultMessage : 'patch_apply_failed',
      );
    }

    return HotUpdateApplyResult(
      success: false,
      requiresRestart: false,
      message: 'patch_apply_result_invalid',
    );
  }

  Future<void> _safeDelete(File file) async {
    // 临时文件清理采用尽力而为策略，失败不能覆盖原始更新结果。
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

final hotUpdateSdkAdapterProvider = Provider<HotUpdateSdkAdapter>((ref) {
  return HotUpdateSdkAdapter();
});

/// 当前 Shorebird 引擎正在运行的补丁编号；未集成 SDK 或尚无补丁时为 null。
final shorebirdCurrentPatchNumberProvider = FutureProvider<int?>((ref) async {
  return ref
      .read(hotUpdateSdkAdapterProvider)
      .readCurrentShorebirdPatchNumber();
});

/// 已通过格式校验的文件摘要，目前只接受 SHA-256。
class _ParsedHash {
  final String algorithm;
  final String hash;

  const _ParsedHash({
    required this.algorithm,
    required this.hash,
  });

  static _ParsedHash? parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('sha256:')) {
      final hash = normalized.substring('sha256:'.length);
      return _build('sha256', hash);
    }

    if (RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
      return _ParsedHash(algorithm: 'sha256', hash: normalized);
    }

    return null;
  }

  static _ParsedHash? _build(String algorithm, String hash) {
    final cleaned = hash.trim().toLowerCase();
    if (cleaned.isEmpty) {
      return null;
    }
    final pattern = switch (algorithm) {
      'sha256' => RegExp(r'^[a-f0-9]{64}$'),
      _ => null,
    };
    if (pattern == null || !pattern.hasMatch(cleaned)) {
      return null;
    }
    return _ParsedHash(algorithm: algorithm, hash: cleaned);
  }

  Future<String> compute(File file) async {
    final stream = file.openRead();
    switch (algorithm) {
      case 'sha256':
        return (await crypto.sha256.bind(stream).first)
            .toString()
            .toLowerCase();
      default:
        throw UnsupportedError('Unsupported hash algorithm: $algorithm');
    }
  }
}
