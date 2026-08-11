// 文件用途：实现 DeviceLoginConfirmPage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 DeviceLoginConfirmPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/themed_app_bar.dart';

String _deviceLoginText(
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

// 关键声明：device login confirm page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class DeviceLoginConfirmPage extends ConsumerStatefulWidget {
  final String ticket;

  const DeviceLoginConfirmPage({
    super.key,
    required this.ticket,
  });

  @override
  ConsumerState<DeviceLoginConfirmPage> createState() =>
      _DeviceLoginConfirmPageState();
}

class _DeviceLoginConfirmPageState
    extends ConsumerState<DeviceLoginConfirmPage> {
  bool _isLoading = true;
  bool _isConfirming = false;
  String _status = 'pending';
  String? _error;
  Map<String, dynamic>? _data;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadTicketInfo();
  }

  String _serverMessage({
    required String? raw,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    return localizeServerMessage(
      raw,
      fallbackZhCN: zhCN,
      fallbackZhTW: zhTW,
      fallbackEn: en,
    );
  }

  Future<void> _loadTicketInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      // 路由只携带不可信的票据字符串；设备信息、有效期和状态必须向服务端查询。
      final response = await api.get<Map<String, dynamic>>(
        '/auth/qr-login/status/${widget.ticket}',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        setState(() {
          _data = response.data!;
          // pending/confirmed/expired 等状态由服务端决定，页面只负责对应展示。
          _status = (_data!['status'] ?? 'expired').toString();
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _error = _serverMessage(
          raw: response.message,
          zhCN: '获取登录信息失败',
          zhTW: '取得登入資訊失敗',
          en: 'Failed to get login info',
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _deviceLoginText(
          context,
          zhCN: '获取登录信息失败',
          zhTW: '取得登入資訊失敗',
          en: 'Failed to get login info',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmLogin() async {
    // isConfirming 同时禁用确认与取消按钮，防止同一票据并发提交。
    setState(() {
      _isConfirming = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post<Map<String, dynamic>>(
        '/auth/qr-login/confirm/${widget.ticket}',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted) return;

      if (response.isSuccess) {
        // 仅服务端确认成功才返回 true，调用页不能把弹窗确认视为登录已生效。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _deviceLoginText(
                context,
                zhCN: '已确认登录桌面设备',
                zhTW: '已確認登入桌面裝置',
                en: 'Desktop device login confirmed',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _error = _serverMessage(
          raw: response.message,
          zhCN: '确认登录失败',
          zhTW: '確認登入失敗',
          en: 'Login confirmation failed',
        );
        _isConfirming = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _deviceLoginText(
          context,
          zhCN: '确认登录失败',
          zhTW: '確認登入失敗',
          en: 'Login confirmation failed',
        );
        _isConfirming = false;
      });
    }
  }

  String _formatDeviceName() {
    final name = (_data?['device_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return _formatDeviceType();
  }

  String _formatDeviceType() {
    switch ((_data?['device_type'] ?? '').toString().toLowerCase()) {
      case 'windows':
        return _deviceLoginText(
          context,
          zhCN: 'Windows 设备',
          zhTW: 'Windows 裝置',
          en: 'Windows Device',
        );
      case 'macos':
        return _deviceLoginText(
          context,
          zhCN: 'Mac 设备',
          zhTW: 'Mac 裝置',
          en: 'Mac Device',
        );
      case 'linux':
        return _deviceLoginText(
          context,
          zhCN: 'Linux 设备',
          zhTW: 'Linux 裝置',
          en: 'Linux Device',
        );
      default:
        return _deviceLoginText(
          context,
          zhCN: '桌面设备',
          zhTW: '桌面裝置',
          en: 'Desktop Device',
        );
    }
  }

  IconData _deviceIcon() {
    switch ((_data?['device_type'] ?? '').toString().toLowerCase()) {
      case 'windows':
      case 'macos':
      case 'linux':
        return Icons.computer_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0E0E) : const Color(0xFFF6F7FB);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
      appBar: ThemedAppBar(
        title: Text(
          _deviceLoginText(
            context,
            zhCN: '确认登录',
            zhTW: '確認登入',
            en: 'Confirm Login',
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: _buildBody(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 52, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loadTicketInfo,
            child: Text(
              _deviceLoginText(
                context,
                zhCN: '重试',
                zhTW: '重試',
                en: 'Retry',
              ),
            ),
          ),
        ],
      );
    }

    if (_status == 'expired') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_2_rounded, size: 52, color: Colors.orange),
          const SizedBox(height: 16),
          Text(
            _deviceLoginText(
              context,
              zhCN: '该二维码已过期，请在桌面端刷新后重新扫描',
              zhTW: '此 QR Code 已過期，請在桌面端重新整理後再掃描',
              en: 'This QR code has expired. Refresh it on desktop and scan again.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              _deviceLoginText(
                context,
                zhCN: '返回',
                zhTW: '返回',
                en: 'Back',
              ),
            ),
          ),
        ],
      );
    }

    if (_status == 'confirmed') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 56, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            _deviceLoginText(
              context,
              zhCN: '这台设备已经确认登录',
              zhTW: '這台裝置已確認登入',
              en: 'This device has already been confirmed',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              _deviceLoginText(
                context,
                zhCN: '关闭',
                zhTW: '關閉',
                en: 'Close',
              ),
            ),
          ),
        ],
      );
    }

    final deviceIp = (_data?['device_ip'] ?? '').toString().trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.emphasisSoftFor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            _deviceIcon(),
            size: 36,
            color: AppColors.linkFor(context),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _deviceLoginText(
            context,
            zhCN: '确认登录这台设备？',
            zhTW: '確認登入這台裝置？',
            en: 'Confirm login for this device?',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _deviceLoginText(
            context,
            zhCN: '请确认这是你本人正在操作的桌面设备',
            zhTW: '請確認這是你本人正在操作的桌面裝置',
            en: 'Please confirm that this is the desktop device you are currently using',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        _InfoTile(
          label: _deviceLoginText(
            context,
            zhCN: '设备名称',
            zhTW: '裝置名稱',
            en: 'Device Name',
          ),
          value: _formatDeviceName(),
        ),
        const SizedBox(height: 12),
        _InfoTile(
          label: _deviceLoginText(
            context,
            zhCN: '设备类型',
            zhTW: '裝置類型',
            en: 'Device Type',
          ),
          value: _formatDeviceType(),
        ),
        if (deviceIp.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoTile(
            label: _deviceLoginText(
              context,
              zhCN: '设备 IP',
              zhTW: '裝置 IP',
              en: 'Device IP',
            ),
            value: deviceIp,
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isConfirming
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(
                  _deviceLoginText(
                    context,
                    zhCN: '取消',
                    zhTW: '取消',
                    en: 'Cancel',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _isConfirming ? null : _confirmLogin,
                child: _isConfirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _deviceLoginText(
                          context,
                          zhCN: '确认登录',
                          zhTW: '確認登入',
                          en: 'Confirm Login',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondaryFor(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
