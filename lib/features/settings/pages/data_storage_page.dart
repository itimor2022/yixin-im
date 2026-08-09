// 文件用途：实现 DataStorageService 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 DataStorageService 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/account_data_cleanup_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/e2ee/e2ee_service.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../shared/widgets/adaptive_settings_tile.dart';

const _downloadModeAllMedia = 'all_media';
const _downloadModeImagesOnly = 'images_only';
const _downloadModeSmallFilesOnly = 'small_files_only';
const _downloadModeNone = 'no_download';

String _dataStorageText(
  BuildContext context, {
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

String _normalizeDownloadMode(String value) {
  switch (value.trim()) {
    case _downloadModeAllMedia:
    case 'Download All Media':
    case '下载所有媒体':
    case '下載所有媒體':
      return _downloadModeAllMedia;
    case _downloadModeImagesOnly:
    case 'Download Images Only':
    case '仅下载图片':
    case '僅下載圖片':
      return _downloadModeImagesOnly;
    case _downloadModeSmallFilesOnly:
    case 'Download Small Files Only':
    case '仅下载小文件':
    case '僅下載小檔案':
      return _downloadModeSmallFilesOnly;
    case _downloadModeNone:
    case 'No Download':
    case '不下载':
    case '不下載':
      return _downloadModeNone;
    default:
      return value.trim();
  }
}

String _downloadModeLabel(BuildContext context, String value) {
  final l10n = AppLocalizations.of(context);
  switch (_normalizeDownloadMode(value)) {
    case _downloadModeAllMedia:
      return l10n.downloadAllMedia;
    case _downloadModeImagesOnly:
      return l10n.downloadImagesOnly;
    case _downloadModeSmallFilesOnly:
      return l10n.downloadSmallFilesOnly;
    case _downloadModeNone:
      return l10n.noDownload;
    default:
      return value;
  }
}

// 关键声明：data storage page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 数据存储设置服务
class DataStorageService extends StateNotifier<DataStorageSettings> {
  DataStorageService() : super(const DataStorageSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      state = DataStorageSettings(
        autoDownloadPhoto: prefs.getBool('storage_auto_photo') ?? true,
        autoDownloadVideo: prefs.getBool('storage_auto_video') ?? false,
        autoDownloadFile: prefs.getBool('storage_auto_file') ?? false,
        saveToGallery: prefs.getBool('storage_save_gallery') ?? false,
        wifiDownloadMode: _normalizeDownloadMode(
          prefs.getString('storage_wifi_mode') ?? _downloadModeAllMedia,
        ),
        mobileDownloadMode: _normalizeDownloadMode(
          prefs.getString('storage_mobile_mode') ?? _downloadModeImagesOnly,
        ),
        roamingDownloadMode: _normalizeDownloadMode(
          prefs.getString('storage_roaming_mode') ?? _downloadModeNone,
        ),
        networkUsageSent: prefs.getInt('storage_network_sent') ?? 0,
        networkUsageReceived: prefs.getInt('storage_network_received') ?? 0,
        networkUsageLastReset: prefs.getString('storage_network_reset_date'),
      );
    } catch (e) {
      debugPrint('[DataStorage] Error loading: $e');
    }
  }

  Future<void> updateAutoDownloadPhoto(bool value) async {
    state = state.copyWith(autoDownloadPhoto: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('storage_auto_photo', value);
  }

  Future<void> updateAutoDownloadVideo(bool value) async {
    state = state.copyWith(autoDownloadVideo: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('storage_auto_video', value);
  }

  Future<void> updateAutoDownloadFile(bool value) async {
    state = state.copyWith(autoDownloadFile: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('storage_auto_file', value);
  }

  Future<void> updateSaveToGallery(bool value) async {
    state = state.copyWith(saveToGallery: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('storage_save_gallery', value);
  }

  Future<void> updateWifiDownloadMode(String value) async {
    final normalized = _normalizeDownloadMode(value);
    state = state.copyWith(wifiDownloadMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_wifi_mode', normalized);
  }

  Future<void> updateMobileDownloadMode(String value) async {
    final normalized = _normalizeDownloadMode(value);
    state = state.copyWith(mobileDownloadMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_mobile_mode', normalized);
  }

  Future<void> updateRoamingDownloadMode(String value) async {
    final normalized = _normalizeDownloadMode(value);
    state = state.copyWith(roamingDownloadMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_roaming_mode', normalized);
  }

  Future<void> resetNetworkUsage() async {
    final now = DateTime.now().toIso8601String();
    state = state.copyWith(
      networkUsageSent: 0,
      networkUsageReceived: 0,
      networkUsageLastReset: now,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('storage_network_sent', 0);
    await prefs.setInt('storage_network_received', 0);
    await prefs.setString('storage_network_reset_date', now);
  }

  // 添加网络使用量（供其他地方调用）
  Future<void> addNetworkUsage({int sent = 0, int received = 0}) async {
    state = state.copyWith(
      networkUsageSent: state.networkUsageSent + sent,
      networkUsageReceived: state.networkUsageReceived + received,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('storage_network_sent', state.networkUsageSent);
    await prefs.setInt('storage_network_received', state.networkUsageReceived);
  }
}

class DataStorageSettings {
  final bool autoDownloadPhoto;
  final bool autoDownloadVideo;
  final bool autoDownloadFile;
  final bool saveToGallery;
  final String wifiDownloadMode;
  final String mobileDownloadMode;
  final String roamingDownloadMode;
  final int networkUsageSent;
  final int networkUsageReceived;
  final String? networkUsageLastReset;

  const DataStorageSettings({
    this.autoDownloadPhoto = true,
    this.autoDownloadVideo = false,
    this.autoDownloadFile = false,
    this.saveToGallery = false,
    this.wifiDownloadMode = _downloadModeAllMedia,
    this.mobileDownloadMode = _downloadModeImagesOnly,
    this.roamingDownloadMode = _downloadModeNone,
    this.networkUsageSent = 0,
    this.networkUsageReceived = 0,
    this.networkUsageLastReset,
  });

  DataStorageSettings copyWith({
    bool? autoDownloadPhoto,
    bool? autoDownloadVideo,
    bool? autoDownloadFile,
    bool? saveToGallery,
    String? wifiDownloadMode,
    String? mobileDownloadMode,
    String? roamingDownloadMode,
    int? networkUsageSent,
    int? networkUsageReceived,
    String? networkUsageLastReset,
  }) {
    return DataStorageSettings(
      autoDownloadPhoto: autoDownloadPhoto ?? this.autoDownloadPhoto,
      autoDownloadVideo: autoDownloadVideo ?? this.autoDownloadVideo,
      autoDownloadFile: autoDownloadFile ?? this.autoDownloadFile,
      saveToGallery: saveToGallery ?? this.saveToGallery,
      wifiDownloadMode: wifiDownloadMode ?? this.wifiDownloadMode,
      mobileDownloadMode: mobileDownloadMode ?? this.mobileDownloadMode,
      roamingDownloadMode: roamingDownloadMode ?? this.roamingDownloadMode,
      networkUsageSent: networkUsageSent ?? this.networkUsageSent,
      networkUsageReceived: networkUsageReceived ?? this.networkUsageReceived,
      networkUsageLastReset:
          networkUsageLastReset ?? this.networkUsageLastReset,
    );
  }
}

final dataStorageProvider =
    StateNotifierProvider<DataStorageService, DataStorageSettings>((ref) {
  return DataStorageService();
});

/// 存储信息
class StorageInfo {
  final int totalSize;
  final int imageSize;
  final int videoSize;
  final int fileSize;
  final int cacheSize;

  StorageInfo({
    required this.totalSize,
    required this.imageSize,
    required this.videoSize,
    required this.fileSize,
    required this.cacheSize,
  });
}

/// 数据和存储设置页面
class DataStoragePage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const DataStoragePage({
    super.key,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<DataStoragePage> createState() => _DataStoragePageState();
}

class _DataStoragePageState extends ConsumerState<DataStoragePage> {
  StorageInfo? _storageInfo;
  bool _isLoading = true;
  bool _isClearing = false;
  bool _isPurgingAccount = false;
  bool _isResettingEncryption = false;
  int? _messageRetentionMonths;
  String _e2eeRecoveryMode = '';

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _calculateStorage();
    _loadRecoveryCapabilities();
  }

  Future<void> _loadRecoveryCapabilities() async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>('/message/recovery-capabilities');
      if (!mounted || !response.isSuccess || response.data == null) return;
      final rawMonths = response.data!['retention_months'];
      setState(() {
        _messageRetentionMonths = rawMonths is int
            ? rawMonths
            : int.tryParse(rawMonths?.toString() ?? '');
        _e2eeRecoveryMode =
            response.data!['e2ee_recovery_mode']?.toString() ?? '';
      });
    } catch (error) {
      debugPrint('[DataStorage] Load recovery capabilities failed: $error');
    }
  }

  Future<void> _calculateStorage() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final accountId = ref.read(currentAccountIdProvider);

      int imageSize = 0;
      int videoSize = 0;
      int fileSize = 0;
      int cacheSize = 0;

      // 计算应用目录大小
      await _calculateDirSize(appDir, (path, size) {
        final lower = path.toLowerCase();
        if (lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.webp')) {
          imageSize += size;
        } else if (lower.endsWith('.mp4') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.avi') ||
            lower.endsWith('.mkv')) {
          videoSize += size;
        } else {
          fileSize += size;
        }
      });

      // 只统计当前账号明确可再次下载的缓存，不把草稿、录音和待上传
      // 临时文件混入“可清除缓存”。
      cacheSize = await ChatMediaCacheManager.inspectRedownloadableCacheBytes(
        accountId,
      );

      setState(() {
        _storageInfo = StorageInfo(
          totalSize: imageSize + videoSize + fileSize,
          imageSize: imageSize,
          videoSize: videoSize,
          fileSize: fileSize,
          cacheSize: cacheSize,
        );
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[DataStorage] Calculate error: $e');
      setState(() {
        _storageInfo = StorageInfo(
          totalSize: 0,
          imageSize: 0,
          videoSize: 0,
          fileSize: 0,
          cacheSize: 0,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _calculateDirSize(
      Directory dir, Function(String, int) onFile) async {
    try {
      if (await dir.exists()) {
        await for (var entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final size = await entity.length();
              onFile(entity.path, size);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[DataStorage] Dir size error: $e');
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);

    try {
      final accountId = ref.read(currentAccountIdProvider);
      if (accountId.isEmpty) return;
      await ref
          .read(accountDataCleanupServiceProvider)
          .clearRedownloadableCache(accountId);

      // 重新计算存储
      await _calculateStorage();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _dataStorageText(
                context,
                zhCN: '缓存已清除',
                zhTW: '快取已清除',
                en: 'Cache cleared',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _dataStorageText(
                context,
                zhCN: '清除失败，请重试',
                zhTW: '清除失敗，請重試',
                en: 'Clear failed. Please try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(dataStorageProvider);
    final service = ref.read(dataStorageProvider.notifier);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 桌面端面板模式：只返回内容，不需要 Scaffold 和 AppBar
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, settings, service, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.dataAndStorage,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark, settings, service, l10n),
    );
  }

  Widget _buildBody(bool isDark, DataStorageSettings settings,
      DataStorageService service, AppLocalizations l10n) {
    return ListView(
      children: [
        const SizedBox(height: 24),

        // 存储使用
        _SectionTitle(title: l10n.storage, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _StorageTile(
              isDark: isDark,
              storageInfo: _storageInfo,
              isLoading: _isLoading,
              formatSize: _formatSize,
              l10n: l10n,
            ),
            _TapTile(
              title: l10n.manageStorageSpace,
              isDark: isDark,
              onTap: () => _showManageStorageSheet(l10n),
            ),
            _TapTile(
              title: l10n.clearCache,
              subtitle: _isLoading
                  ? l10n.calculating
                  : _formatSize(_storageInfo?.cacheSize ?? 0),
              isDark: isDark,
              isLoading: _isClearing,
              onTap: () => _showClearCacheConfirm(l10n),
            ),
          ],
        ),

        const SizedBox(height: 24),

        _SectionTitle(
          title: _dataStorageText(
            context,
            zhCN: '本机账号数据',
            zhTW: '本機帳號資料',
            en: 'Local Account Data',
          ),
          isDark: isDark,
        ),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: _dataStorageText(
                context,
                zhCN: '清除本机数据',
                zhTW: '清除本機帳號資料',
                en: 'Clear Local Account Data',
              ),
              subtitle: _dataStorageText(
                context,
                zhCN: '删除聊天、草稿、离线消息和私有媒体；保留密钥',
                zhTW: '刪除目前帳號聊天、草稿、離線訊息和私人媒體；保留加密金鑰',
                en: 'Delete this account’s chats, drafts, offline messages and private media; keep encryption keys',
              ),
              titleColor: AppColors.error,
              isDark: isDark,
              isLoading: _isPurgingAccount,
              onTap: _showClearAccountDataConfirm,
            ),
            _TapTile(
              title: _dataStorageText(
                context,
                zhCN: '重置加密身份',
                zhTW: '重設加密身分',
                en: 'Reset Encryption Identity',
              ),
              subtitle: _dataStorageText(
                context,
                zhCN: '更换本机密钥；旧加密消息可能无法解密',
                zhTW: '輪換本裝置金鑰；舊加密訊息可能永久無法解密',
                en: 'Rotate this device key; old encrypted messages may become permanently unreadable',
              ),
              titleColor: AppColors.error,
              isDark: isDark,
              isLoading: _isResettingEncryption,
              onTap: _showResetEncryptionIdentityConfirm,
            ),
          ],
        ),
        _SectionNote(
          text: _dataStorageText(
            context,
            zhCN: '以上是两个独立操作。清除缓存不会删除聊天、草稿、离线消息或 E2EE 私钥。',
            zhTW: '以上是兩個獨立操作。清除快取不會刪除聊天、草稿、離線訊息或 E2EE 私鑰。',
            en: 'These are separate operations. Clearing cache never deletes chats, drafts, offline messages, or E2EE private keys.',
          ),
          isDark: isDark,
        ),
        if (_messageRetentionMonths != null)
          _SectionNote(
            text: _dataStorageText(
              context,
              zhCN:
                  '服务器消息查询覆盖最近 $_messageRetentionMonths 个月。新设备恢复旧 E2EE 消息${_e2eeRecoveryMode == "trusted_device_rewrap" ? "需要在可信旧设备上批准" : "取决于可用密钥"}；已删除、过期或无密钥内容不能保证恢复。',
              zhTW:
                  '伺服器訊息查詢涵蓋最近 $_messageRetentionMonths 個月。新裝置復原舊 E2EE 訊息${_e2eeRecoveryMode == "trusted_device_rewrap" ? "需要在可信舊裝置上批准" : "取決於可用金鑰"}；已刪除、過期或無金鑰內容無法保證復原。',
              en: 'Server message queries cover the latest $_messageRetentionMonths months. Recovering old E2EE messages on a new device ${_e2eeRecoveryMode == "trusted_device_rewrap" ? "requires approval on a trusted old device" : "depends on an available key"}. Deleted, expired, or keyless content is not guaranteed.',
            ),
            isDark: isDark,
          ),

        const SizedBox(height: 24),

        // 自动下载媒体
        _SectionTitle(title: l10n.autoDownloadMedia, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.images,
              value: settings.autoDownloadPhoto,
              isDark: isDark,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                service.updateAutoDownloadPhoto(v);
              },
            ),
            _SwitchTile(
              title: l10n.videos,
              value: settings.autoDownloadVideo,
              isDark: isDark,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                service.updateAutoDownloadVideo(v);
              },
            ),
            _SwitchTile(
              title: l10n.files,
              value: settings.autoDownloadFile,
              isDark: isDark,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                service.updateAutoDownloadFile(v);
              },
            ),
          ],
        ),

        _SectionNote(
          text: l10n.autoDownloadHint,
          isDark: isDark,
        ),

        const SizedBox(height: 24),

        // 网络设置
        _SectionTitle(title: l10n.network, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.whenUsingWifi,
              subtitle: _downloadModeLabel(context, settings.wifiDownloadMode),
              isDark: isDark,
              onTap: () => _showNetworkPicker('Wi-Fi',
                  settings.wifiDownloadMode, service.updateWifiDownloadMode),
            ),
            _TapTile(
              title: l10n.whenUsingMobile,
              subtitle:
                  _downloadModeLabel(context, settings.mobileDownloadMode),
              isDark: isDark,
              onTap: () => _showNetworkPicker(
                  l10n.get('mobile_network'),
                  settings.mobileDownloadMode,
                  service.updateMobileDownloadMode),
            ),
            _TapTile(
              title: l10n.whenRoaming,
              subtitle:
                  _downloadModeLabel(context, settings.roamingDownloadMode),
              isDark: isDark,
              onTap: () => _showNetworkPicker(
                  l10n.get('roaming'),
                  settings.roamingDownloadMode,
                  service.updateRoamingDownloadMode),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 保存到相册
        _SectionTitle(title: l10n.saveSettings, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.saveToGallery,
              subtitle: l10n.autoSaveToGallery,
              value: settings.saveToGallery,
              isDark: isDark,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                service.updateSaveToGallery(v);
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 数据使用
        _SectionTitle(title: l10n.dataUsage, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.networkUsageStats,
              subtitle:
                  '${l10n.sent}: ${_formatSize(settings.networkUsageSent)} / ${l10n.received}: ${_formatSize(settings.networkUsageReceived)}',
              isDark: isDark,
              onTap: () => _showNetworkUsageDetail(settings, l10n),
            ),
            _TapTile(
              title: l10n.resetNetworkUsage,
              titleColor: AppColors.error,
              isDark: isDark,
              onTap: () => _showResetDataConfirm(service, l10n),
            ),
          ],
        ),

        const SizedBox(height: 100),
      ],
    );
  }

  void _showManageStorageSheet(AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                l10n.manageStorageSpace,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 24),
              if (_storageInfo != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _StorageRow(
                        icon: Icons.image_outlined,
                        color: Colors.blue,
                        title: l10n.images,
                        size: _formatSize(_storageInfo!.imageSize),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),
                      _StorageRow(
                        icon: Icons.videocam_outlined,
                        color: Colors.green,
                        title: l10n.videos,
                        size: _formatSize(_storageInfo!.videoSize),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),
                      _StorageRow(
                        icon: Icons.insert_drive_file_outlined,
                        color: Colors.orange,
                        title: l10n.otherFiles,
                        size: _formatSize(_storageInfo!.fileSize),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),
                      _StorageRow(
                        icon: Icons.cached,
                        color: Colors.grey,
                        title: l10n.cache,
                        size: _formatSize(_storageInfo!.cacheSize),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showClearCacheConfirm(l10n);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n.clearAllCache),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearCacheConfirm(AppLocalizations l10n) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearCache),
        content: Text(l10n.confirmClearCache),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearCache();
            },
            child: Text(l10n.get('clear'),
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearAccountDataConfirm() async {
    if (_isPurgingAccount || _isResettingEncryption) return;
    final accountId = ref.read(currentAccountIdProvider);
    if (accountId.isEmpty) return;

    AccountDataSnapshot snapshot;
    try {
      snapshot = await ref
          .read(accountDataCleanupServiceProvider)
          .inspectAccount(accountId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return;
    }
    if (!mounted || ref.read(currentAccountIdProvider) != accountId) return;

    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            _dataStorageText(
              context,
              zhCN: '清除本机账号数据？',
              zhTW: '清除本機帳號資料？',
              en: 'Clear local account data?',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dataStorageText(
                    context,
                    zhCN: '此操作只删除当前账号在本机的数据，不会删除服务器账号，也不会删除 E2EE 私钥。完成后将退出登录。',
                    zhTW: '此操作只刪除目前帳號在本機的資料，不會刪除伺服器帳號，也不會刪除 E2EE 私鑰。完成後將登出。',
                    en: 'This deletes only this account’s local data. It does not delete the server account or E2EE private key. You will be signed out.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _dataStorageText(
                    context,
                    zhCN:
                        '聊天 ${snapshot.chatCount} 个 · 消息 ${snapshot.messageCount} 条 · 联系人 ${snapshot.contactCount} 个\n草稿 ${snapshot.draftCount} 个 · 待发消息 ${snapshot.offlineMessageCount} 条\n私有媒体 ${snapshot.privateMediaFileCount} 个（${_formatSize(snapshot.privateMediaBytes)}）',
                    zhTW:
                        '聊天 ${snapshot.chatCount} 個 · 訊息 ${snapshot.messageCount} 條 · 聯絡人 ${snapshot.contactCount} 個\n草稿 ${snapshot.draftCount} 個 · 待傳訊息 ${snapshot.offlineMessageCount} 條\n私人媒體 ${snapshot.privateMediaFileCount} 個（${_formatSize(snapshot.privateMediaBytes)}）',
                    en: '${snapshot.chatCount} chats · ${snapshot.messageCount} messages · ${snapshot.contactCount} contacts\n${snapshot.draftCount} drafts · ${snapshot.offlineMessageCount} queued messages\n${snapshot.privateMediaFileCount} private media files (${_formatSize(snapshot.privateMediaBytes)})',
                  ),
                ),
                if (snapshot.localUniqueItemCount > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    _dataStorageText(
                      context,
                      zhCN: '警告：草稿、待发消息和未同步的本地媒体可能无法从服务器恢复。',
                      zhTW: '警告：草稿、待傳訊息和未同步的本機媒體可能無法從伺服器恢復。',
                      en: 'Warning: drafts, queued messages, and unsynced local media may not be recoverable from the server.',
                    ),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: _dataStorageText(
                      context,
                      zhCN: '输入 CLEAR 确认',
                      zhTW: '輸入 CLEAR 確認',
                      en: 'Type CLEAR to confirm',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            TextButton(
              onPressed: confirmController.text.trim() == 'CLEAR'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(
                _dataStorageText(
                  context,
                  zhCN: '清除并退出',
                  zhTW: '清除並登出',
                  en: 'Clear and Sign Out',
                ),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    confirmController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isPurgingAccount = true);
    try {
      final cleanup = ref.read(accountDataCleanupServiceProvider);
      await cleanup.scheduleAccountPurge(accountId);
      if (ref.read(currentAccountIdProvider) != accountId) {
        throw StateError('Account changed before local data cleanup');
      }
      await ref.read(authServiceProvider.notifier).logout(
            reason: SessionExitReason.accountDataCleared,
            notifyServer: true,
          );
      final result = await cleanup.resumePendingPurge();
      if (!result.success) {
        throw StateError(result.errors.join('; '));
      }
    } catch (error) {
      debugPrint('[DataStorage] Account purge failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurgingAccount = false);
    }
  }

  Future<void> _showResetEncryptionIdentityConfirm() async {
    if (_isPurgingAccount || _isResettingEncryption) return;
    final accountId = ref.read(currentAccountIdProvider);
    if (accountId.isEmpty) return;
    final hasIdentity =
        await ref.read(e2eeServiceProvider).hasLocalIdentity(accountId);
    if (!mounted || ref.read(currentAccountIdProvider) != accountId) return;

    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            _dataStorageText(
              context,
              zhCN: '重置加密身份？',
              zhTW: '重設加密身分？',
              en: 'Reset encryption identity?',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dataStorageText(
                  context,
                  zhCN: hasIdentity
                      ? '将为当前账号和本设备生成新密钥，并更新服务器公钥。旧私钥会被替换，旧加密消息可能永久无法解密。完成后将退出登录。'
                      : '当前未检测到完整的本机密钥。继续后会创建新的加密身份并更新服务器，完成后将退出登录。',
                  zhTW: hasIdentity
                      ? '將為目前帳號和本裝置產生新金鑰，並更新伺服器公鑰。舊私鑰會被取代，舊加密訊息可能永久無法解密。完成後將登出。'
                      : '目前未偵測到完整的本機金鑰。繼續後會建立新的加密身分並更新伺服器，完成後將登出。',
                  en: hasIdentity
                      ? 'A new key will be generated for this account and device, and the server public key will be replaced. The old private key will be lost, so old encrypted messages may become permanently unreadable. You will be signed out.'
                      : 'No complete local identity was detected. Continuing creates a new identity, updates the server, and signs you out.',
                ),
                style: const TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: _dataStorageText(
                    context,
                    zhCN: '输入 RESET 确认',
                    zhTW: '輸入 RESET 確認',
                    en: 'Type RESET to confirm',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            TextButton(
              onPressed: confirmController.text.trim() == 'RESET'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(
                _dataStorageText(
                  context,
                  zhCN: '重置并退出',
                  zhTW: '重設並登出',
                  en: 'Reset and Sign Out',
                ),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    confirmController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isResettingEncryption = true);
    try {
      if (ref.read(currentAccountIdProvider) != accountId) {
        throw StateError('Account changed before encryption reset');
      }
      await ref.read(e2eeServiceProvider).rotateDeviceIdentity(accountId);
      if (ref.read(currentAccountIdProvider) != accountId) return;
      await ref.read(authServiceProvider.notifier).logout(
            reason: SessionExitReason.encryptionIdentityReset,
            notifyServer: true,
          );
    } catch (error) {
      debugPrint('[DataStorage] Encryption identity reset failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isResettingEncryption = false);
    }
  }

  void _showNetworkPicker(
    String network,
    String current,
    Function(String) onSelect,
  ) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final normalizedCurrent = _normalizeDownloadMode(current);
    final options = [
      _downloadModeAllMedia,
      _downloadModeImagesOnly,
      _downloadModeSmallFilesOnly,
      _downloadModeNone,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                network,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((option) => ListTile(
                    title: Text(_downloadModeLabel(context, option)),
                    trailing: option == normalizedCurrent
                        ? Icon(
                            Icons.check,
                            color: AppColors.controlActiveFor(context),
                          )
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(option);
                      Navigator.pop(context);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showNetworkUsageDetail(
      DataStorageSettings settings, AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String lastReset = l10n.neverReset;
    if (settings.networkUsageLastReset != null) {
      try {
        final date = DateTime.parse(settings.networkUsageLastReset!);
        lastReset =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                l10n.networkUsageStats,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.sentData,
                            style: TextStyle(
                                color:
                                    isDark ? Colors.white70 : Colors.black87)),
                        Text(_formatSize(settings.networkUsageSent),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.receivedData,
                            style: TextStyle(
                                color:
                                    isDark ? Colors.white70 : Colors.black87)),
                        Text(_formatSize(settings.networkUsageReceived),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.total,
                            style: TextStyle(
                                color:
                                    isDark ? Colors.white70 : Colors.black87)),
                        Text(
                            _formatSize(settings.networkUsageSent +
                                settings.networkUsageReceived),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.linkFor(context))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white10 : Colors.black12),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.lastReset,
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiaryFor(context))),
                        Text(lastReset,
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiaryFor(context))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetDataConfirm(
      DataStorageService service, AppLocalizations l10n) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resetDataStats),
        content: Text(l10n.confirmResetStats),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              service.resetNetworkUsage();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.statsReset)),
              );
            },
            child: Text(l10n.reset, style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String size;
  final bool isDark;

  const _StorageRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.size,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        Text(
          size,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondaryFor(context),
          ),
        ),
      ],
    );
  }
}

class _StorageTile extends StatelessWidget {
  final bool isDark;
  final StorageInfo? storageInfo;
  final bool isLoading;
  final String Function(int) formatSize;
  final AppLocalizations l10n;

  const _StorageTile({
    required this.isDark,
    required this.storageInfo,
    required this.isLoading,
    required this.formatSize,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final total = storageInfo?.totalSize ?? 0;
    final image = storageInfo?.imageSize ?? 0;
    final video = storageInfo?.videoSize ?? 0;
    final file = storageInfo?.fileSize ?? 0;
    final cache = storageInfo?.cacheSize ?? 0;
    final allUsed = total + cache;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.usedStorageSpace,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondaryFor(context),
                  ),
                )
              else
                Text(
                  formatSize(allUsed),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.linkFor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 分段进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (image > 0)
                    Flexible(
                      flex: image,
                      child: Container(color: Colors.blue),
                    ),
                  if (video > 0)
                    Flexible(
                      flex: video,
                      child: Container(color: Colors.green),
                    ),
                  if (file > 0)
                    Flexible(
                      flex: file,
                      child: Container(color: Colors.orange),
                    ),
                  if (cache > 0)
                    Flexible(
                      flex: cache,
                      child: Container(color: Colors.grey),
                    ),
                  // 剩余空间
                  Flexible(
                    flex: allUsed > 0
                        ? (allUsed * 4).clamp(1, allUsed * 10).toInt()
                        : 1,
                    child: Container(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withOpacity(0.06),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 存储类型说明 - 两行布局
          Row(
            children: [
              Expanded(
                child: _StorageItem(
                  label: l10n.images,
                  size: formatSize(image),
                  color: Colors.blue,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _StorageItem(
                  label: l10n.videos,
                  size: formatSize(video),
                  color: Colors.green,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _StorageItem(
                  label: l10n.files,
                  size: formatSize(file),
                  color: Colors.orange,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _StorageItem(
                  label: l10n.cache,
                  size: formatSize(cache),
                  color: Colors.grey,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageItem extends StatelessWidget {
  final String label;
  final String size;
  final Color color;
  final bool isDark;

  const _StorageItem({
    required this.label,
    required this.size,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
              Text(
                size,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textTertiaryFor(context),
        ),
      ),
    );
  }
}

class _SectionNote extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionNote({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textTertiaryFor(context),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 1,
              indent: 16,
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.controlActiveFor(context),
          ),
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool isDark;
  final bool isLoading;
  final VoidCallback onTap;

  const _TapTile({
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.isDark,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsTapTile(
      title: title,
      subtitle: subtitle,
      titleStyle: TextStyle(
        fontSize: 16,
        color: titleColor ?? (isDark ? Colors.white : Colors.black),
      ),
      subtitleStyle: TextStyle(
        fontSize: 14,
        height: 1.3,
        color: AppColors.textSecondaryFor(context),
      ),
      chevronColor: isDark ? Colors.white24 : Colors.black26,
      onTap: onTap,
      isLoading: isLoading,
      showChevron: titleColor == null,
    );
  }
}
