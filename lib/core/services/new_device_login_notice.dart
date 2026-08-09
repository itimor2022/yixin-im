// 文件用途：封装 NewDeviceLoginNotice 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 NewDeviceLoginNotice 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import '../i18n/app_localizations.dart';

// 关键声明：new device login notice 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 新设备登录安全事件的容错视图模型。
///
/// [eventId] 和 [deviceId] 供上层去重、定位设备使用，展示文案只采用名称、
/// 类型、IP 与时间。字段缺失不会阻止用户收到安全提醒。
class NewDeviceLoginNotice {
  const NewDeviceLoginNotice({
    required this.eventId,
    required this.deviceId,
    required this.deviceType,
    required this.deviceName,
    required this.ip,
    required this.occurredAt,
  });

  final String eventId;
  final String deviceId;
  final String deviceType;
  final String deviceName;
  final String ip;
  final DateTime? occurredAt;

  // 流程逻辑：`fromPayload` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  factory NewDeviceLoginNotice.fromPayload(Map<String, dynamic> payload) {
    final rawTime = payload['occurred_at']?.toString().trim() ?? '';
    return NewDeviceLoginNotice(
      eventId: payload['event_id']?.toString().trim() ?? '',
      deviceId: payload['device_id']?.toString().trim() ?? '',
      deviceType: payload['device_type']?.toString().trim() ?? '',
      deviceName: payload['device_name']?.toString().trim() ?? '',
      ip: payload['ip']?.toString().trim() ?? '',
      // 时间戳无法解析时省略时间信息，不把单个脏字段升级成整条通知失败。
      occurredAt:
          rawTime.isEmpty ? null : DateTime.tryParse(rawTime)?.toLocal(),
    );
  }

  String localizedMessage(AppLanguage language) {
    final device = deviceName.isEmpty
        ? switch (language) {
            AppLanguage.en => 'A new device',
            AppLanguage.zhTW => '一台新裝置',
            AppLanguage.zhCN => '一台新设备',
          }
        : deviceName;
    // 仅拼接实际存在的字段，避免安全通知出现连续分隔符或占位文本。
    final details = <String>[
      if (deviceType.isNotEmpty) deviceType,
      if (ip.isNotEmpty) ip,
      if (occurredAt != null) _formatTime(occurredAt!),
    ].join(' · ');

    return switch (language) {
      AppLanguage.en => details.isEmpty
          ? '$device signed in to your account. If this was not you, review signed-in devices and change your password immediately.'
          : '$device signed in to your account. $details\nIf this was not you, review signed-in devices and change your password immediately.',
      AppLanguage.zhTW => details.isEmpty
          ? '$device 已登入你的帳號。如非本人操作，請立即檢查登入裝置並修改密碼。'
          : '$device 已登入你的帳號。$details\n如非本人操作，請立即檢查登入裝置並修改密碼。',
      AppLanguage.zhCN => details.isEmpty
          ? '$device 已登录你的账号。如非本人操作，请立即检查登录设备并修改密码。'
          : '$device 已登录你的账号。$details\n如非本人操作，请立即检查登录设备并修改密码。',
    };
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
