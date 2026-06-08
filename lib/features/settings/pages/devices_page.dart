import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';

/// 设备数据模型
class DeviceInfo {
  final int id;
  final String deviceId;
  final String deviceType;
  final String deviceName;
  final String ip;
  final String location;
  final bool isCurrent;
  final DateTime lastActive;
  final DateTime createdAt;

  DeviceInfo({
    required this.id,
    required this.deviceId,
    required this.deviceType,
    required this.deviceName,
    required this.ip,
    required this.location,
    required this.isCurrent,
    required this.lastActive,
    required this.createdAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] ?? 0,
      deviceId: json['device_id'] ?? '',
      deviceType: json['device_type'] ?? '',
      deviceName: json['device_name'] ?? '',
      ip: json['ip'] ?? '',
      location: json['location'] ?? '',
      isCurrent: json['is_current'] ?? false,
      lastActive:
          DateTime.tryParse(json['last_active'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

List<DeviceInfo> _dedupeDevices(Iterable<DeviceInfo> devices) {
  final deduped = <String, DeviceInfo>{};
  for (final device in devices) {
    final key = device.deviceId.trim();
    if (key.isEmpty) {
      continue;
    }
    final existing = deduped[key];
    if (existing == null ||
        device.isCurrent && !existing.isCurrent ||
        device.lastActive.isAfter(existing.lastActive) ||
        (device.lastActive.isAtSameMomentAs(existing.lastActive) &&
            device.id > existing.id)) {
      deduped[key] = device;
    }
  }

  final result = deduped.values.toList()
    ..sort((a, b) {
      if (a.isCurrent != b.isCurrent) {
        return a.isCurrent ? -1 : 1;
      }
      final activeCompare = b.lastActive.compareTo(a.lastActive);
      if (activeCompare != 0) return activeCompare;
      return b.id.compareTo(a.id);
    });
  return result;
}

/// 设备管理页面 -
class DevicesPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const DevicesPage({super.key, this.isDesktopPanel = false});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  String _deviceName = '';
  String _deviceModel = '';
  String _osVersion = '';
  String _appVersion = '';
  bool _isLoggingOut = false;
  bool _isLoading = true;
  List<DeviceInfo> _devices = [];
  DeviceInfo? _currentDevice;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _loadDevices();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final settings =
          await ref.read(systemSettingsServiceProvider).getSettings();
      final version = settings.systemVersion.trim();
      setState(() {
        _appVersion = version.isNotEmpty ? '$version' : '1.0.0';
      });
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        setState(() {
          _deviceName = iosInfo.name;
          _deviceModel = iosInfo.utsname.machine;
          _osVersion = 'iOS ${iosInfo.systemVersion}';
        });
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _deviceName = androidInfo.model;
          _deviceModel = androidInfo.device;
          _osVersion = 'Android ${androidInfo.version.release}';
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('获取设备信息失败: $e');
    }
  }

  Future<void> _loadDevices() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get<Map<String, dynamic>>(
        '/user/devices',
      );

      if (response.isSuccess && response.data != null) {
        final devicesList = response.data!['devices'] as List? ?? [];
        final normalizedDevices = _dedupeDevices(
          devicesList.map((d) => DeviceInfo.fromJson(d)),
        );
        setState(() {
          _devices = normalizedDevices;
          _currentDevice = _devices.firstWhere(
            (d) => d.isCurrent,
            orElse: () =>
                _devices.isNotEmpty ? _devices.first : _createDefaultDevice(),
          );
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('获取设备列表失败: $e');
      setState(() => _isLoading = false);
    }
  }

  DeviceInfo _createDefaultDevice() {
    return DeviceInfo(
      id: 0,
      deviceId: '',
      deviceType: Platform.isIOS ? 'ios' : 'android',
      deviceName: _deviceName,
      ip: '',
      location: '',
      isCurrent: true,
      lastActive: DateTime.now(),
      createdAt: DateTime.now(),
    );
  }

  Future<void> _terminateDevice(DeviceInfo device) async {
    HapticFeedback.mediumImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终止设备会话'),
        content: Text(
          '确定要终止 ${device.deviceName.isNotEmpty ? device.deviceName : _getDeviceTypeName(device.deviceType)} 的会话吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('终止'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.delete<Map<String, dynamic>>(
        '/user/devices/${device.deviceId}',
      );

      if (response.isSuccess) {
        setState(() {
          _devices.removeWhere((d) => d.deviceId == device.deviceId);
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已终止该设备会话')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _getDeviceTypeName(String type) {
    switch (type.toLowerCase()) {
      case 'ios':
        return 'iPhone';
      case 'android':
        return 'Android';
      case 'web':
        return '网页版';
      case 'desktop':
        return '桌面版';
      default:
        return '未知设备';
    }
  }

  IconData _getDeviceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'ios':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      case 'web':
        return Icons.language;
      case 'desktop':
        return Icons.computer;
      default:
        return Icons.devices;
    }
  }

  String _formatLastActive(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 5) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}/${time.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final appName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
            kDefaultAppDisplayName;

    // 桌面端面板模式：只返回内容，不需要 Scaffold 和 AppBar
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, cardColor, l10n);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.devices,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark, cardColor, l10n),
    );
  }

  Widget _buildBody(bool isDark, Color cardColor, AppLocalizations l10n) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadDevices,
            child: ListView(
              children: [
                const SizedBox(height: 35),

                // 当前设备标题
                _buildSectionHeader(l10n.currentDevice, isDark),

                // 当前设备卡片
                _buildSettingsCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  children: [_buildCurrentDeviceTile(isDark)],
                ),

                const SizedBox(height: 35),

                // 链接新设备
                _buildSectionHeader(l10n.linkNewDevice, isDark),

                _buildSettingsCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  children: [
                    _buildTapTile(
                      icon: Icons.qr_code_scanner_rounded,
                      iconBgColor: AppColors.primary,
                      title: l10n.scanQrCode,
                      subtitle: l10n.loginToOtherDevice,
                      isDark: isDark,
                      onTap: _showQRScanner,
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    l10n.scanQrCodeHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                // 活跃会话/其他设备 已隐藏(需求3)
                if (false) ...[
                // 活跃会话（其他设备）
                _buildSectionHeader(
                  l10n.activeSessions,
                  isDark,
                  trailing:
                      '${_devices.where((d) => d.deviceId != _currentDevice?.deviceId).length} ${l10n.devicesCount}',
                ),

                _buildSettingsCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  children: _devices
                          .where((d) => d.deviceId != _currentDevice?.deviceId)
                          .isEmpty
                      ? [_buildEmptySessionTile(isDark, l10n)]
                      : _devices
                          .where((d) => d.deviceId != _currentDevice?.deviceId)
                          .map(
                            (device) =>
                                _buildOtherDeviceTile(device, isDark, l10n),
                          )
                          .toList(),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    l10n.suspiciousDeviceHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),

                // 终止所有其他设备按钮（仅当有其他设备时显示）
                if (_devices
                    .where((d) => d.deviceId != _currentDevice?.deviceId)
                    .isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSettingsCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    children: [_buildTerminateAllTile(isDark, l10n)],
                  ),
                ],
                ],

                const SizedBox(height: 35),

                // 退出登录
                _buildSettingsCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  children: [_buildLogoutTile(isDark, l10n)],
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    l10n.logoutHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),

                const SizedBox(height: 50),
              ],
            ),
          );
  }

  Widget _buildSectionHeader(String title, bool isDark, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.3,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required bool isDark,
    required Color cardColor,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 1,
              indent: 60,
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }

  Widget _buildCurrentDeviceTile(bool isDark) {
    // 优先使用后端返回的设备名称
    final displayName = (_currentDevice?.deviceName.isNotEmpty == true)
        ? _currentDevice!.deviceName
        : (_deviceName.isNotEmpty
            ? _deviceName
            : _getDeviceTypeName(Platform.isIOS ? 'ios' : 'android'));

    // 显示 IP 信息（如果有）
    final ipInfo =
        _currentDevice?.ip.isNotEmpty == true ? ' · ${_currentDevice!.ip}' : '';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 设备图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Platform.isIOS ? Icons.phone_iphone : Icons.phone_android,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // 设备信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_appVersion · $_osVersion$ipInfo',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),

          // 在线状态
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '在线',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconBgColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySessionTile(bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.devices_other_rounded,
            size: 48,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noOtherDevices,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherDeviceTile(
    DeviceInfo device,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final deviceName = device.deviceName.isNotEmpty
        ? device.deviceName
        : _getDeviceTypeName(device.deviceType);

    return Dismissible(
      key: Key(device.deviceId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.terminateDeviceSession),
            content: Text(l10n.confirmTerminateDevice),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: Text(l10n.terminate),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        _terminateDevice(device);
      },
      child: InkWell(
        onTap: () => _terminateDevice(device),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 设备图标
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getDeviceIcon(device.deviceType),
                  color: AppColors.info,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // 设备信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.ip.isNotEmpty ? device.ip : "未知IP"} · ${_formatLastActive(device.lastActive)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),

              // 终止按钮
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                  size: 20,
                ),
                onPressed: () => _terminateDevice(device),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTerminateAllTile(bool isDark, AppLocalizations l10n) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _terminateAllOtherDevices(l10n),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.delete_sweep_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.terminateAllOtherDevices,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _terminateAllOtherDevices(AppLocalizations l10n) async {
    HapticFeedback.mediumImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.terminateAllOtherDevices),
        content: Text(l10n.confirmTerminateAll),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.terminateAll),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post<Map<String, dynamic>>(
        '/user/devices/terminate-others',
      );

      if (response.isSuccess) {
        setState(() {
          _devices.removeWhere((d) => d.deviceId != _currentDevice?.deviceId);
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.allDevicesTerminated)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.operationFailed}: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildLogoutTile(bool isDark, AppLocalizations l10n) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoggingOut ? null : () => _showLogoutConfirm(l10n),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoggingOut)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.error,
                  ),
                )
              else
                Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              Text(
                _isLoggingOut ? l10n.loggingOut : l10n.logout,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQRScanner() {
    context.push('/scan');
  }

  void _showLogoutConfirm(AppLocalizations l10n) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.logout,
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.78,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.white.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.2)
                          : Colors.white.withOpacity(0.8),
                      width: 0.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 小鸡动画
                        SizedBox(
                          width: 90,
                          height: 90,
                          child: Lottie.asset(
                            'assets/emoji/lottie/hatched_chick.json',
                            repeat: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 标题
                        Text(
                          l10n.confirmLogout,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 内容
                        Text(
                          l10n.logoutHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 按钮 - 现代圆角样式
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    l10n.cancel,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  _performLogout();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    l10n.logout,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _performLogout() async {
    if (_isLoggingOut) return;

    setState(() => _isLoggingOut = true);
    HapticFeedback.mediumImpact();

    try {
      // 重置聊天和联系人状态
      ref.read(chatListProvider.notifier).reset();
      ref.read(contactListProvider.notifier).reset();

      // 调用 AuthService 的 logout 方法
      await ref.read(authServiceProvider.notifier).logout();

      if (!mounted) return;

      // 跳转到登录页面
      context.go('/login');
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoggingOut = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('退出失败: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}
