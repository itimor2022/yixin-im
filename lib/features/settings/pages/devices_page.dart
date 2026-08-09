// 文件用途：实现 DeviceInfo 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 DeviceInfo 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../../shared/widgets/web_safe_lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/e2ee/e2ee_recovery_models.dart';
import '../../../core/services/e2ee/e2ee_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';

// 关键声明：devices page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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
  // 服务端历史记录可能包含相同 deviceId；当前会话优先，其次保留最近活跃、
  // 服务端记录 ID 更新的一条，避免同一设备被重复展示和重复终止。
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

String _devicesText(
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
  bool _isRecoveryBusy = false;
  bool _isRecoveryCapabilityLoading = true;
  bool _isRecoverySupported = false;
  List<DeviceInfo> _devices = [];
  List<E2EERecoveryRequest> _recoveryRequests = [];
  DeviceInfo? _currentDevice;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _loadDevices();
    _loadRecoveryCapability();
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
      debugPrint('获取设备信息失败: $e');
    }
  }

  Future<void> _loadDevices() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      // 当前设备标识和有效会话列表均以服务端返回为准，本机型号仅用于展示兜底。
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
      debugPrint('获取设备列表失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecoveryRequests() async {
    if (!_isRecoverySupported) {
      if (mounted && _recoveryRequests.isNotEmpty) {
        setState(() => _recoveryRequests = []);
      }
      return;
    }
    try {
      final requests =
          await ref.read(e2eeServiceProvider).listRecoveryRequests();
      if (!mounted) return;
      setState(() => _recoveryRequests = requests);
    } catch (error) {
      debugPrint('[Devices] Load E2EE recovery requests failed: $error');
    }
  }

  Future<void> _loadRecoveryCapability() async {
    try {
      // 先由服务端声明协议能力，避免旧后端上展示无法完成的恢复入口。
      final response = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>('/message/recovery-capabilities');
      final supported = response.isSuccess &&
          supportsTrustedDeviceE2EERecovery(response.data);
      if (!mounted) return;
      setState(() {
        _isRecoveryCapabilityLoading = false;
        _isRecoverySupported = supported;
        if (!supported) _recoveryRequests = [];
      });
      if (supported) await _loadRecoveryRequests();
    } catch (error) {
      debugPrint('[Devices] Load recovery capability failed: $error');
      if (!mounted) return;
      setState(() {
        _isRecoveryCapabilityLoading = false;
        _isRecoverySupported = false;
        _recoveryRequests = [];
      });
    }
  }

  Future<void> _createRecoveryRequest() async {
    if (_isRecoveryBusy || !_isRecoverySupported) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_devicesText(
          context,
          zhCN: '申请恢复加密消息',
          zhTW: '申請復原加密訊息',
          en: 'Request encrypted history recovery',
        )),
        content: Text(_devicesText(
          context,
          zhCN: '请求发出后，需要在仍能阅读旧加密消息的已登录设备上批准。服务器不会获得明文私钥。',
          zhTW: '請求送出後，需要在仍能閱讀舊加密訊息的已登入裝置上批准。伺服器不會取得明文私鑰。',
          en: 'Approve this request on a signed-in device that can still read the old encrypted messages. The server never receives the private key in plaintext.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_devicesText(
              context,
              zhCN: '取消',
              zhTW: '取消',
              en: 'Cancel',
            )),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_devicesText(
              context,
              zhCN: '发出请求',
              zhTW: '送出請求',
              en: 'Send Request',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRecoveryBusy = true);
    try {
      // E2EEService 负责在可信设备间加密恢复材料；页面不接触明文私钥。
      await ref.read(e2eeServiceProvider).createRecoveryRequest();
      await _loadRecoveryRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_devicesText(
            context,
            zhCN: '恢复请求已发出，请在旧设备上批准',
            zhTW: '復原請求已送出，請在舊裝置上批准',
            en: 'Recovery request sent. Approve it on the old device.',
          )),
        ));
      }
    } catch (error) {
      _showRecoveryError(error);
    } finally {
      if (mounted) setState(() => _isRecoveryBusy = false);
    }
  }

  Future<void> _approveRecoveryRequest(E2EERecoveryRequest request) async {
    if (_isRecoveryBusy) return;
    final requesterName = request.requesterDeviceName.isNotEmpty
        ? request.requesterDeviceName
        : _getDeviceTypeName(context, request.requesterDeviceType);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_devicesText(
          context,
          zhCN: '批准加密消息恢复？',
          zhTW: '批准加密訊息復原？',
          en: 'Approve encrypted history recovery?',
        )),
        content: Text(_devicesText(
          context,
          zhCN: '仅在确认“$requesterName”是你刚登录的新设备时批准。当前设备会将历史解密身份端到端加密后发送给该设备。',
          zhTW: '僅在確認「$requesterName」是你剛登入的新裝置時批准。目前裝置會將歷史解密身分端對端加密後傳送給該裝置。',
          en: 'Approve only if "$requesterName" is the new device you just signed in. This device will end-to-end encrypt the historical decryption identity for it.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_devicesText(
              context,
              zhCN: '取消',
              zhTW: '取消',
              en: 'Cancel',
            )),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_devicesText(
              context,
              zhCN: '批准',
              zhTW: '批准',
              en: 'Approve',
            )),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRecoveryBusy = true);
    try {
      // 批准动作只授权指定请求，恢复身份仍以端到端加密形式交付给新设备。
      await ref.read(e2eeServiceProvider).approveRecoveryRequest(request);
      await _loadRecoveryRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_devicesText(
            context,
            zhCN: '已安全批准，新设备可以导入历史解密身份',
            zhTW: '已安全批准，新裝置可以匯入歷史解密身分',
            en: 'Approved securely. The new device can import the historical identity.',
          )),
        ));
      }
    } catch (error) {
      _showRecoveryError(error);
    } finally {
      if (mounted) setState(() => _isRecoveryBusy = false);
    }
  }

  Future<void> _importApprovedRecovery() async {
    if (_isRecoveryBusy) return;
    setState(() => _isRecoveryBusy = true);
    try {
      final imported =
          await ref.read(e2eeServiceProvider).importApprovedRecovery();
      await _loadRecoveryRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(imported
              ? _devicesText(
                  context,
                  zhCN: '历史加密消息解密身份已恢复',
                  zhTW: '歷史加密訊息解密身分已復原',
                  en: 'Historical encrypted-message identity restored.',
                )
              : _devicesText(
                  context,
                  zhCN: '暂时没有已批准的恢复结果',
                  zhTW: '暫時沒有已批准的復原結果',
                  en: 'No approved recovery result is available yet.',
                )),
        ));
      }
    } catch (error) {
      _showRecoveryError(error);
    } finally {
      if (mounted) setState(() => _isRecoveryBusy = false);
    }
  }

  void _showRecoveryError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error.toString()),
      backgroundColor: AppColors.error,
    ));
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
        title: Text(
          _devicesText(
            context,
            zhCN: '终止设备会话',
            zhTW: '終止裝置工作階段',
            en: 'End Device Session',
          ),
        ),
        content: Text(
          _devicesText(
            context,
            zhCN:
                '确定要终止 ${device.deviceName.isNotEmpty ? device.deviceName : _getDeviceTypeName(context, device.deviceType)} 的会话吗？',
            zhTW:
                '確定要終止 ${device.deviceName.isNotEmpty ? device.deviceName : _getDeviceTypeName(context, device.deviceType)} 的工作階段嗎？',
            en: 'End the session for ${device.deviceName.isNotEmpty ? device.deviceName : _getDeviceTypeName(context, device.deviceType)}?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _devicesText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(
              _devicesText(
                context,
                zhCN: '终止',
                zhTW: '終止',
                en: 'End',
              ),
            ),
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
        // 会话终止是服务端安全状态，确认成功后才同步移除页面条目。
        setState(() {
          _devices.removeWhere((d) => d.deviceId == device.deviceId);
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _devicesText(
                  context,
                  zhCN: '已终止该设备会话',
                  zhTW: '已終止該裝置工作階段',
                  en: 'Device session ended',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _devicesText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _getDeviceTypeName(BuildContext context, String type) {
    switch (type.toLowerCase()) {
      case 'ios':
        return 'iPhone';
      case 'android':
        return 'Android';
      case 'web':
        return _devicesText(
          context,
          zhCN: '网页版',
          zhTW: '網頁版',
          en: 'Web',
        );
      case 'desktop':
        return _devicesText(
          context,
          zhCN: '桌面版',
          zhTW: '桌面版',
          en: 'Desktop',
        );
      default:
        return _devicesText(
          context,
          zhCN: '未知设备',
          zhTW: '未知裝置',
          en: 'Unknown Device',
        );
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

  String _formatLastActive(BuildContext context, DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 5) {
      return _devicesText(context, zhCN: '刚刚', zhTW: '剛剛', en: 'Just now');
    }
    if (diff.inHours < 1) {
      return _devicesText(
        context,
        zhCN: '${diff.inMinutes} 分钟前',
        zhTW: '${diff.inMinutes} 分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inDays < 1) {
      return _devicesText(
        context,
        zhCN: '${diff.inHours} 小时前',
        zhTW: '${diff.inHours} 小時前',
        en: '${diff.inHours}h ago',
      );
    }
    if (diff.inDays < 7) {
      return _devicesText(
        context,
        zhCN: '${diff.inDays} 天前',
        zhTW: '${diff.inDays} 天前',
        en: '${diff.inDays}d ago',
      );
    }
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
            defaultAppDisplayName();

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
            onRefresh: () async {
              await Future.wait([_loadDevices(), _loadRecoveryCapability()]);
            },
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
                      iconBgColor: AppColors.primaryFor(context),
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
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ),

                const SizedBox(height: 35),

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
                      color: AppColors.textTertiaryFor(context),
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

                const SizedBox(height: 35),

                _buildSectionHeader(
                  _devicesText(
                    context,
                    zhCN: '加密消息恢复',
                    zhTW: '加密訊息復原',
                    en: 'Encrypted History Recovery',
                  ),
                  isDark,
                ),

                _buildSettingsCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  children: [
                    _buildTapTile(
                      icon: _isRecoverySupported
                          ? Icons.enhanced_encryption_outlined
                          : Icons.cloud_off_outlined,
                      iconBgColor: _isRecoverySupported
                          ? AppColors.info
                          : AppColors.textTertiaryFor(context),
                      title: _devicesText(
                        context,
                        zhCN: _isRecoveryCapabilityLoading
                            ? '正在检查服务端恢复能力'
                            : _isRecoverySupported
                                ? '申请从旧设备恢复'
                                : '加密消息恢复暂不可用',
                        zhTW: _isRecoveryCapabilityLoading
                            ? '正在檢查伺服器復原能力'
                            : _isRecoverySupported
                                ? '申請從舊裝置復原'
                                : '加密訊息復原暫不可用',
                        en: _isRecoveryCapabilityLoading
                            ? 'Checking Server Recovery Support'
                            : _isRecoverySupported
                                ? 'Request Recovery from Old Device'
                                : 'Encrypted History Recovery Unavailable',
                      ),
                      subtitle: _devicesText(
                        context,
                        zhCN: _isRecoveryCapabilityLoading
                            ? '请稍候'
                            : _isRecoverySupported
                                ? '需要另一台仍可阅读旧加密消息的设备批准'
                                : '当前服务器版本不支持，请先升级服务端',
                        zhTW: _isRecoveryCapabilityLoading
                            ? '請稍候'
                            : _isRecoverySupported
                                ? '需要另一台仍可閱讀舊加密訊息的裝置批准'
                                : '目前伺服器版本不支援，請先升級伺服器',
                        en: _isRecoveryCapabilityLoading
                            ? 'Please wait'
                            : _isRecoverySupported
                                ? 'Requires approval from another device that can read old messages'
                                : 'Upgrade the server before using this feature',
                      ),
                      isDark: isDark,
                      onTap: _isRecoveryBusy || !_isRecoverySupported
                          ? () {}
                          : _createRecoveryRequest,
                    ),
                    if (_isRecoverySupported)
                      ..._recoveryRequests
                          .where((item) => item.isRequester && item.isPending)
                          .map((item) => _buildTapTile(
                                icon: Icons.hourglass_top_rounded,
                                iconBgColor: AppColors.warning,
                                title: _devicesText(
                                  context,
                                  zhCN: '等待旧设备批准',
                                  zhTW: '等待舊裝置批准',
                                  en: 'Waiting for Old Device Approval',
                                ),
                                subtitle: _devicesText(
                                  context,
                                  zhCN: '点击刷新恢复状态',
                                  zhTW: '點擊重新整理復原狀態',
                                  en: 'Tap to refresh recovery status',
                                ),
                                isDark: isDark,
                                onTap: _loadRecoveryRequests,
                              )),
                    if (_isRecoverySupported)
                      ..._recoveryRequests
                          .where((item) => item.isRequester && item.isApproved)
                          .map((item) => _buildTapTile(
                                icon: Icons.download_done_rounded,
                                iconBgColor: AppColors.success,
                                title: _devicesText(
                                  context,
                                  zhCN: '导入已批准的恢复身份',
                                  zhTW: '匯入已批准的復原身分',
                                  en: 'Import Approved Recovery Identity',
                                ),
                                subtitle: _devicesText(
                                  context,
                                  zhCN: '恢复后可尝试解密该旧设备收到的历史消息',
                                  zhTW: '復原後可嘗試解密該舊裝置收到的歷史訊息',
                                  en: 'Restores access to history encrypted for that old device',
                                ),
                                isDark: isDark,
                                onTap: _importApprovedRecovery,
                              )),
                    if (_isRecoverySupported)
                      ..._recoveryRequests
                          .where((item) => !item.isRequester && item.isPending)
                          .map((item) => _buildTapTile(
                                icon: Icons.phonelink_lock_rounded,
                                iconBgColor: AppColors.primaryFor(context),
                                title: _devicesText(
                                  context,
                                  zhCN:
                                      '批准 ${item.requesterDeviceName.isNotEmpty ? item.requesterDeviceName : "新设备"}',
                                  zhTW:
                                      '批准 ${item.requesterDeviceName.isNotEmpty ? item.requesterDeviceName : "新裝置"}',
                                  en: 'Approve ${item.requesterDeviceName.isNotEmpty ? item.requesterDeviceName : "New Device"}',
                                ),
                                subtitle: _devicesText(
                                  context,
                                  zhCN: '请先核对这是否是你刚登录的设备',
                                  zhTW: '請先核對這是否是你剛登入的裝置',
                                  en: 'Verify that this is the device you just signed in',
                                ),
                                isDark: isDark,
                                onTap: () => _approveRecoveryRequest(item),
                              )),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _devicesText(
                      context,
                      zhCN: '没有可用旧设备、没有备份或旧密钥已重置时，历史密文无法恢复。',
                      zhTW: '沒有可用舊裝置、沒有備份或舊金鑰已重設時，歷史密文無法復原。',
                      en: 'Old encrypted history cannot be recovered without an available trusted device or backup, or after the old key was reset.',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ),

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
                      color: AppColors.textTertiaryFor(context),
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
              color: AppColors.textTertiaryFor(context),
              letterSpacing: 0.3,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiaryFor(context),
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
            : _getDeviceTypeName(
                context,
                Platform.isIOS ? 'ios' : 'android',
              ));

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
              color: AppColors.emphasisSoftFor(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Platform.isIOS ? Icons.phone_iphone : Icons.phone_android,
              color: AppColors.linkFor(context),
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
                    color: AppColors.textSecondaryFor(context),
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
                  _devicesText(
                    context,
                    zhCN: '在线',
                    zhTW: '在線',
                    en: 'Online',
                  ),
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
                        color: AppColors.linkFor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondaryFor(context),
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
            color: AppColors.textTertiaryFor(context).withOpacity(0.72),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noOtherDevices,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondaryFor(context),
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
        : _getDeviceTypeName(context, device.deviceType);

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
                      '${device.ip.isNotEmpty ? device.ip : _devicesText(context, zhCN: "未知IP", zhTW: "未知 IP", en: "Unknown IP")} · ${_formatLastActive(context, device.lastActive)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),

              // 终止按钮
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: AppColors.textTertiaryFor(context),
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
        // 服务端按当前会话执行批量终止；页面只保留服务端标记的当前设备。
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
            content: Text(
              _devicesText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed. Please try again.',
              ),
            ),
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
    final credentialsPending =
        ref.read(authServiceProvider).user?.credentialsInitialized == false;

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
                          child: WebSafeLottie.asset(
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
                          credentialsPending
                              ? _devicesText(
                                  context,
                                  zhCN: '当前账号尚未设置登录账号和密码，退出后可能无法找回。确定继续退出吗？',
                                  zhTW: '目前帳號尚未設定登入帳號和密碼，登出後可能無法找回。確定繼續登出嗎？',
                                  en: 'This account has no sign-in credentials yet and may be unrecoverable after logout. Continue?',
                                )
                              : l10n.logoutHint,
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
      // 先隔离当前账号的内存态，再由 AuthService 完成令牌撤销和持久化清理，
      // 避免退出过程中旧聊天或联系人短暂显示给后续账号。
      ref.read(chatListProvider.notifier).reset();
      ref.read(contactListProvider.notifier).reset();

      await ref.read(authServiceProvider.notifier).logout();

      if (!mounted) return;

      // 只有认证清理完成后才离开当前账号页面。
      context.go('/login');
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoggingOut = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _devicesText(
              context,
              zhCN: '退出失败，请重试',
              zhTW: '登出失敗，請重試',
              en: 'Logout failed. Please try again.',
            ),
          ),
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
