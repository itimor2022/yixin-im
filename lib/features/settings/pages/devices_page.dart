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
import '../../../shared/widgets/settings_ui.dart';
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
        _appVersion = version.isNotEmpty ? version : '1.0.0';
      });
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        setState(() {
          _deviceName = iosInfo.name;
          _osVersion = 'iOS ${iosInfo.systemVersion}';
        });
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _deviceName = androidInfo.model;
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
          SnackBar(content: Text('操作失败: $e')),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(ref.watch(languageProvider));

    return SettingsScaffold(
      title: l10n.devices,
      isDesktopPanel: widget.isDesktopPanel,
      children: _isLoading
          ? const [
              SizedBox(height: 60),
              Center(child: CircularProgressIndicator()),
            ]
          : _buildChildren(l10n),
    );
  }

  List<Widget> _buildChildren(AppLocalizations l10n) {
    final otherDevices = _devices
        .where((d) => d.deviceId != _currentDevice?.deviceId)
        .toList();

    return [
      // ================ 当前设备 Hero ================
      SettingsLooseCard(
        padding: const EdgeInsets.all(18),
        child: _buildCurrentDeviceHero(),
      ),

      // ================ 关联新设备 ================
      SettingsSection(l10n.linkNewDevice),
      SettingsChoiceIsland(
        icon: Icons.qr_code_scanner_rounded,
        iconColor: AppColors.primary,
        label: l10n.scanQrCode,
        subtitle: l10n.loginToOtherDevice,
        onTap: _showQRScanner,
      ),
      SettingsNote(l10n.scanQrCodeHint),

      // 活跃会话列表已根据需求 3 隐藏，原逻辑保留在 [_buildOtherDeviceIsland]
      // 中，需要恢复时把下面 `if (otherDevices.isNotEmpty)` 展开即可。

      // ================ 终止其他设备 ================
      if (otherDevices.isNotEmpty) ...[
        SettingsSection('其他设备'),
        SettingsChoiceIsland(
          icon: Icons.delete_sweep_rounded,
          iconColor: AppColors.warning,
          label: l10n.terminateAllOtherDevices,
          labelColor: AppColors.warning,
          onTap: () => _terminateAllOtherDevices(l10n),
        ),
      ],

      // ================ 退出登录 ================
      SettingsSection('账号'),
      SettingsChoiceIsland(
        icon: Icons.logout_rounded,
        iconColor: AppColors.error,
        label: _isLoggingOut ? l10n.loggingOut : l10n.logout,
        labelColor: AppColors.error,
        loading: _isLoggingOut,
        onTap: _isLoggingOut ? null : () => _showLogoutConfirm(l10n),
      ),
      SettingsNote(l10n.logoutHint),
    ];
  }

  /// 当前设备 Hero：极简纯文字（对齐"个人资料页"极简风）
  Widget _buildCurrentDeviceHero() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = (_currentDevice?.deviceName.isNotEmpty == true)
        ? _currentDevice!.deviceName
        : (_deviceName.isNotEmpty
            ? _deviceName
            : _getDeviceTypeName(Platform.isIOS ? 'ios' : 'android'));
    final ipInfo =
        _currentDevice?.ip.isNotEmpty == true ? ' · ${_currentDevice!.ip}' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
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
                  const SizedBox(width: 6),
                  Text(
                    '在线',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$_appVersion · $_osVersion$ipInfo',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white54 : const Color(0xFF6B7280),
          ),
        ),
      ],
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
          ),
        );
      }
    }
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}
