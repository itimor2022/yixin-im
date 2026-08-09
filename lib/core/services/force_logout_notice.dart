// 文件用途：封装 ForceLogoutNotice 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 ForceLogoutNotice 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import '../i18n/app_localizations.dart';

// 关键声明：force logout notice 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 强制下线事件的容错视图模型。
///
/// WebSocket/推送载荷可能来自不同服务版本，因此缺失字段保留为空，非法时间
/// 降级为 null；展示层仍能给出安全提示，而不因解析异常丢失下线通知。
class ForceLogoutNotice {
  const ForceLogoutNotice({
    required this.reason,
    required this.actorDeviceName,
    required this.occurredAt,
  });

  final String reason;
  final String actorDeviceName;
  final DateTime? occurredAt;

  // 流程逻辑：`fromPayload` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  factory ForceLogoutNotice.fromPayload(Map<String, dynamic> payload) {
    final rawTime = payload['occurred_at']?.toString().trim() ?? '';
    return ForceLogoutNotice(
      reason: payload['reason']?.toString().trim() ?? '',
      actorDeviceName: payload['actor_device_name']?.toString().trim() ?? '',
      // 服务端时间解析后转为本地时区，确保安全提示与设备当前时间一致。
      occurredAt:
          rawTime.isEmpty ? null : DateTime.tryParse(rawTime)?.toLocal(),
    );
  }

  String localizedMessage(AppLanguage language) {
    // 设备名缺失时使用明确的泛化文案，避免输出空白的操作来源。
    final device = actorDeviceName.isEmpty
        ? switch (language) {
            AppLanguage.en => 'another device',
            AppLanguage.zhTW => '另一台裝置',
            AppLanguage.zhCN => '另一台设备',
          }
        : actorDeviceName;
    final time = occurredAt == null ? '' : _formatTime(occurredAt!);

    return switch (language) {
      AppLanguage.en => time.isEmpty
          ? 'This device was signed out by $device. Sign in again. If this was not you, change your password immediately.'
          : 'This device was signed out by $device at $time. Sign in again. If this was not you, change your password immediately.',
      AppLanguage.zhTW => time.isEmpty
          ? '此裝置已被 $device 下線，請重新登入。如非本人操作，請立即修改密碼。'
          : '此裝置已於 $time 被 $device 下線，請重新登入。如非本人操作，請立即修改密碼。',
      AppLanguage.zhCN => time.isEmpty
          ? '此设备已被 $device 下线，请重新登录。如非本人操作，请立即修改密码。'
          : '此设备已于 $time 被 $device 下线，请重新登录。如非本人操作，请立即修改密码。',
    };
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
