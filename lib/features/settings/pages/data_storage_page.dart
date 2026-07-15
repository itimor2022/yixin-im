import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../shared/widgets/settings_ui.dart';

const Color _kDataPrimary = Color(0xFFFF6B6B);

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
        wifiDownloadMode: prefs.getString('storage_wifi_mode') ?? '下载所有媒体',
        mobileDownloadMode: prefs.getString('storage_mobile_mode') ?? '仅下载图片',
        roamingDownloadMode: prefs.getString('storage_roaming_mode') ?? '不下载',
        networkUsageSent: prefs.getInt('storage_network_sent') ?? 0,
        networkUsageReceived: prefs.getInt('storage_network_received') ?? 0,
        networkUsageLastReset: prefs.getString('storage_network_reset_date'),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[DataStorage] Error loading: $e');
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
    state = state.copyWith(wifiDownloadMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_wifi_mode', value);
  }
  
  Future<void> updateMobileDownloadMode(String value) async {
    state = state.copyWith(mobileDownloadMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_mobile_mode', value);
  }
  
  Future<void> updateRoamingDownloadMode(String value) async {
    state = state.copyWith(roamingDownloadMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_roaming_mode', value);
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
    this.wifiDownloadMode = '下载所有媒体',
    this.mobileDownloadMode = '仅下载图片',
    this.roamingDownloadMode = '不下载',
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
      networkUsageLastReset: networkUsageLastReset ?? this.networkUsageLastReset,
    );
  }
}

final dataStorageProvider = StateNotifierProvider<DataStorageService, DataStorageSettings>((ref) {
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
  
  @override
  void initState() {
    super.initState();
    _calculateStorage();
  }
  
  Future<void> _calculateStorage() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = await getTemporaryDirectory();
      
      int imageSize = 0;
      int videoSize = 0;
      int fileSize = 0;
      int cacheSize = 0;
      
      // 计算应用目录大小
      await _calculateDirSize(appDir, (path, size) {
        final lower = path.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || 
            lower.endsWith('.png') || lower.endsWith('.gif') ||
            lower.endsWith('.webp')) {
          imageSize += size;
        } else if (lower.endsWith('.mp4') || lower.endsWith('.mov') || 
                   lower.endsWith('.avi') || lower.endsWith('.mkv')) {
          videoSize += size;
        } else {
          fileSize += size;
        }
      });
      
      // 计算缓存目录大小
      cacheSize = await _getDirSize(cacheDir);
      
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
      if (kDebugMode) debugPrint('[DataStorage] Calculate error: $e');
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
  
  Future<void> _calculateDirSize(Directory dir, Function(String, int) onFile) async {
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final size = await entity.length();
              onFile(entity.path, size);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DataStorage] Dir size error: $e');
    }
  }
  
  Future<int> _getDirSize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              size += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DataStorage] Dir size error: $e');
    }
    return size;
  }
  
  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    
    try {
      final cacheDir = await getTemporaryDirectory();
      
      if (await cacheDir.exists()) {
        await for (var entity in cacheDir.list(followLinks: false)) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
      
      // 清除图片缓存
      imageCache.clear();
      imageCache.clearLiveImages();
      
      // 重新计算存储
      await _calculateStorage();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存已清除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    } finally {
      setState(() => _isClearing = false);
    }
  }
  
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(dataStorageProvider);
    final service = ref.read(dataStorageProvider.notifier);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    return SettingsScaffold(
      title: l10n.dataAndStorage,
      isDesktopPanel: widget.isDesktopPanel,
      children: _buildIslands(isDark, settings, service, l10n),
    );
  }

  List<Widget> _buildIslands(bool isDark, DataStorageSettings settings,
      DataStorageService service, AppLocalizations l10n) {
    return [
      // 存储使用
      SettingsSection(l10n.storage),
      SettingsLooseCard(
        padding: const EdgeInsets.all(16),
        child: _StorageOverview(
          isDark: isDark,
          storageInfo: _storageInfo,
          isLoading: _isLoading,
          formatSize: _formatSize,
          l10n: l10n,
        ),
      ),
      SettingsChoiceIsland(
        icon: Icons.folder_open_outlined,
        iconColor: _kDataPrimary,
        label: l10n.manageStorageSpace,
        onTap: () => _showManageStorageSheet(l10n),
      ),
      SettingsChoiceIsland(
        icon: Icons.cleaning_services_outlined,
        iconColor: const Color(0xFFFF9500),
        label: l10n.clearCache,
        value: _isLoading
            ? l10n.calculating
            : _formatSize(_storageInfo?.cacheSize ?? 0),
        loading: _isClearing,
        onTap: () => _showClearCacheConfirm(l10n),
      ),

      // 自动下载媒体
      SettingsSection(l10n.autoDownloadMedia),
      SettingsSwitchIsland(
        icon: Icons.image_outlined,
        iconColor: _kDataPrimary,
        label: l10n.images,
        value: settings.autoDownloadPhoto,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          service.updateAutoDownloadPhoto(v);
        },
      ),
      SettingsSwitchIsland(
        icon: Icons.videocam_outlined,
        iconColor: const Color(0xFF34C759),
        label: l10n.videos,
        value: settings.autoDownloadVideo,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          service.updateAutoDownloadVideo(v);
        },
      ),
      SettingsSwitchIsland(
        icon: Icons.insert_drive_file_outlined,
        iconColor: const Color(0xFFFF9500),
        label: l10n.files,
        value: settings.autoDownloadFile,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          service.updateAutoDownloadFile(v);
        },
      ),
      SettingsNote(l10n.autoDownloadHint),

      // 网络设置
      SettingsSection(l10n.network),
      SettingsChoiceIsland(
        icon: Icons.wifi_rounded,
        iconColor: _kDataPrimary,
        label: l10n.whenUsingWifi,
        value: settings.wifiDownloadMode,
        onTap: () => _showNetworkPicker(
            'Wi-Fi', settings.wifiDownloadMode, service.updateWifiDownloadMode, l10n),
      ),
      SettingsChoiceIsland(
        icon: Icons.signal_cellular_alt_rounded,
        iconColor: const Color(0xFF5AC8FA),
        label: l10n.whenUsingMobile,
        value: settings.mobileDownloadMode,
        onTap: () => _showNetworkPicker(l10n.get('mobile_network'),
            settings.mobileDownloadMode, service.updateMobileDownloadMode, l10n),
      ),
      SettingsChoiceIsland(
        icon: Icons.public_rounded,
        iconColor: const Color(0xFFAF52DE),
        label: l10n.whenRoaming,
        value: settings.roamingDownloadMode,
        onTap: () => _showNetworkPicker(l10n.get('roaming'),
            settings.roamingDownloadMode, service.updateRoamingDownloadMode, l10n),
      ),

      // 保存到相册
      SettingsSection(l10n.saveSettings),
      SettingsSwitchIsland(
        icon: Icons.photo_library_outlined,
        iconColor: const Color(0xFFFF2D55),
        label: l10n.saveToGallery,
        subtitle: l10n.autoSaveToGallery,
        value: settings.saveToGallery,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          service.updateSaveToGallery(v);
        },
      ),

      // 数据使用
      SettingsSection(l10n.dataUsage),
      SettingsChoiceIsland(
        icon: Icons.data_saver_off_rounded,
        iconColor: _kDataPrimary,
        label: l10n.networkUsageStats,
        subtitle:
            '${l10n.sent}: ${_formatSize(settings.networkUsageSent)} / ${l10n.received}: ${_formatSize(settings.networkUsageReceived)}',
        onTap: () => _showNetworkUsageDetail(settings, l10n),
      ),
      SettingsChoiceIsland(
        icon: Icons.restart_alt_rounded,
        iconColor: AppColors.error,
        label: l10n.resetNetworkUsage,
        labelColor: AppColors.error,
        onTap: () => _showResetDataConfirm(service, l10n),
      ),
    ];
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
            child: Text(l10n.get('clear'), style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showNetworkPicker(String network, String current, Function(String) onSelect, AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [l10n.downloadAllMedia, l10n.downloadImagesOnly, l10n.downloadSmallFilesOnly, l10n.noDownload];
    
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
                title: Text(option),
                trailing: option == current ? Icon(Icons.check, color: AppColors.primary) : null,
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

  void _showNetworkUsageDetail(DataStorageSettings settings, AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    String lastReset = l10n.neverReset;
    if (settings.networkUsageLastReset != null) {
      try {
        final date = DateTime.parse(settings.networkUsageLastReset!);
        lastReset = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
                        Text(l10n.sentData, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                        Text(_formatSize(settings.networkUsageSent), style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.receivedData, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                        Text(_formatSize(settings.networkUsageReceived), style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.total, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                        Text(_formatSize(settings.networkUsageSent + settings.networkUsageReceived), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDark ? Colors.white10 : Colors.black12),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.lastReset, style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38)),
                        Text(lastReset, style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38)),
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

  void _showResetDataConfirm(DataStorageService service, AppLocalizations l10n) {
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
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

class _StorageOverview extends StatelessWidget {
  final bool isDark;
  final StorageInfo? storageInfo;
  final bool isLoading;
  final String Function(int) formatSize;
  final AppLocalizations l10n;

  const _StorageOverview({
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
    
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Text(
                l10n.usedStorageSpace,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                )
              else
                Text(
                  formatSize(allUsed),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
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
                    flex: allUsed > 0 ? (allUsed * 4).clamp(1, allUsed * 10).toInt() : 1,
                    child: Container(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
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
                  label: '图片',
                  size: formatSize(image),
                  color: Colors.blue,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _StorageItem(
                  label: '视频',
                  size: formatSize(video),
                  color: Colors.green,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _StorageItem(
                  label: '文件',
                  size: formatSize(file),
                  color: Colors.orange,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _StorageItem(
                  label: '缓存',
                  size: formatSize(cache),
                  color: Colors.grey,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            Text(
              size,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
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
          color: isDark ? Colors.white38 : Colors.black38,
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
          color: isDark ? Colors.white38 : Colors.black38,
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
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
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
    return InkWell(
      onTap: isLoading ? null : () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: titleColor ?? (isDark ? Colors.white : Colors.black),
                ),
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              )
            else if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            if (titleColor == null && !isLoading) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
