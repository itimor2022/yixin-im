// 文件用途：实现 E2EERecoveryRequest 相关逻辑，服务于业务服务。
// 核心逻辑：围绕 E2EERecoveryRequest 组织，完成输入校验、核心处理和结果回传。
// 关键声明：E2EE recovery models 是密钥恢复数据边界，负责表达恢复请求、审批和消费阶段的状态。
/// 可信设备恢复请求的服务端视图。
///
/// 服务端只保存请求元数据、公钥和密文；恢复私钥由请求设备本地持有。
class E2EERecoveryRequest {
  final String requestId;
  final String status;
  final String requesterDeviceId;
  final String requesterDeviceName;
  final String requesterDeviceType;
  final String requesterPublicKey;
  final String requesterPublicKeyAlgo;
  final String sourceDeviceId;
  final String sourceKeyFingerprint;
  final int sourceKeyVersion;
  final String encryptedPayload;
  final String payloadAlgo;
  final bool isRequester;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const E2EERecoveryRequest({
    required this.requestId,
    required this.status,
    required this.requesterDeviceId,
    required this.requesterDeviceName,
    required this.requesterDeviceType,
    required this.requesterPublicKey,
    required this.requesterPublicKeyAlgo,
    required this.sourceDeviceId,
    required this.sourceKeyFingerprint,
    required this.sourceKeyVersion,
    required this.encryptedPayload,
    required this.payloadAlgo,
    required this.isRequester,
    this.expiresAt,
    this.createdAt,
  });

  // 请求状态和过期时间以服务端返回为准，本地不推演状态流转。
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory E2EERecoveryRequest.fromJson(Map<String, dynamic> json) {
    return E2EERecoveryRequest(
      requestId: json['request_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      requesterDeviceId: json['requester_device_id']?.toString() ?? '',
      requesterDeviceName: json['requester_device_name']?.toString() ?? '',
      requesterDeviceType: json['requester_device_type']?.toString() ?? '',
      requesterPublicKey: json['requester_public_key']?.toString() ?? '',
      requesterPublicKeyAlgo:
          json['requester_public_key_algo']?.toString() ?? '',
      sourceDeviceId: json['source_device_id']?.toString() ?? '',
      sourceKeyFingerprint: json['source_key_fingerprint']?.toString() ?? '',
      sourceKeyVersion: switch (json['source_key_version']) {
        int value => value,
        String value => int.tryParse(value) ?? 0,
        _ => 0,
      },
      encryptedPayload: json['encrypted_payload']?.toString() ?? '',
      payloadAlgo: json['payload_algo']?.toString() ?? '',
      isRequester: json['is_requester'] == true,
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

bool supportsTrustedDeviceE2EERecovery(Map<String, dynamic>? capabilities) {
  // 精确匹配协议模式，避免把未来不兼容的恢复方案误当作当前流程。
  return capabilities?['e2ee_recovery_mode']?.toString().trim() ==
      'trusted_device_rewrap';
}
