import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/theme/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _loadTicketInfo();
  }

  Future<void> _loadTicketInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get<Map<String, dynamic>>(
        '/auth/qr-login/status/${widget.ticket}',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        setState(() {
          _data = response.data!;
          _status = (_data!['status'] ?? 'expired').toString();
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _error = response.message.isNotEmpty ? response.message : '获取登录信息失败';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '获取登录信息失败';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmLogin() async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已确认登录桌面设备'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _error = response.message.isNotEmpty ? response.message : '确认登录失败';
        _isConfirming = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '确认登录失败';
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
        return 'Windows 设备';
      case 'macos':
        return 'Mac 设备';
      case 'linux':
        return 'Linux 设备';
      default:
        return '桌面设备';
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
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('确认登录'),
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
            child: const Text('重试'),
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
            '该二维码已过期，请在桌面端刷新后重新扫描',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('返回'),
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
            '这台设备已经确认登录',
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
            child: const Text('关闭'),
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
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            _deviceIcon(),
            size: 36,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '确认登录这台设备？',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '请确认这是你本人正在操作的桌面设备',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        _InfoTile(
          label: '设备名称',
          value: _formatDeviceName(),
        ),
        const SizedBox(height: 12),
        _InfoTile(
          label: '设备类型',
          value: _formatDeviceType(),
        ),
        if (deviceIp.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoTile(
            label: '设备 IP',
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
                child: const Text('取消'),
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
                    : const Text('确认登录'),
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
        color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
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
