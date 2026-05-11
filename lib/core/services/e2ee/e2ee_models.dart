class E2EEKeyEnvelope {
  final String userId;
  final String deviceId;
  final String algo;
  final String encryptedKey;

  const E2EEKeyEnvelope({
    required this.userId,
    required this.deviceId,
    required this.algo,
    required this.encryptedKey,
  });

  factory E2EEKeyEnvelope.fromJson(Map<String, dynamic> json) {
    return E2EEKeyEnvelope(
      userId: json['user_id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      algo: json['algo']?.toString() ?? '',
      encryptedKey: json['encrypted_key']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'device_id': deviceId,
        'algo': algo,
        'encrypted_key': encryptedKey,
      };
}

class E2EEPayload {
  final int version;
  final String algo;
  final String ciphertext;
  final String iv;
  final String mac;
  final List<E2EEKeyEnvelope> envelopes;

  const E2EEPayload({
    required this.version,
    required this.algo,
    required this.ciphertext,
    required this.iv,
    required this.mac,
    required this.envelopes,
  });

  bool get isValid =>
      ciphertext.isNotEmpty && iv.isNotEmpty && mac.isNotEmpty && envelopes.isNotEmpty;

  factory E2EEPayload.fromJson(Map<String, dynamic> json) {
    return E2EEPayload(
      version: (json['version'] as num?)?.toInt() ?? 1,
      algo: json['algo']?.toString() ?? '',
      ciphertext: json['ciphertext']?.toString() ?? '',
      iv: json['iv']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      envelopes: (json['envelopes'] as List? ?? const [])
          .map((item) => E2EEKeyEnvelope.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'algo': algo,
        'ciphertext': ciphertext,
        'iv': iv,
        'mac': mac,
        'envelopes': envelopes.map((item) => item.toJson()).toList(),
      };
}

class ChatDeviceKey {
  final String userId;
  final String deviceId;
  final String deviceType;
  final String algo;
  final String publicKey;

  const ChatDeviceKey({
    required this.userId,
    required this.deviceId,
    required this.deviceType,
    required this.algo,
    required this.publicKey,
  });

  factory ChatDeviceKey.fromJson(Map<String, dynamic> json) {
    return ChatDeviceKey(
      userId: json['user_id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      deviceType: json['device_type']?.toString() ?? '',
      algo: json['algo']?.toString() ?? '',
      publicKey: json['public_key']?.toString() ?? '',
    );
  }
}

class ChatDeviceKeyBundle {
  final List<String> members;
  final List<ChatDeviceKey> devices;

  const ChatDeviceKeyBundle({
    required this.members,
    required this.devices,
  });

  factory ChatDeviceKeyBundle.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
    final devices = (json['devices'] as List? ?? const [])
        .map((item) => ChatDeviceKey.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    return ChatDeviceKeyBundle(members: members, devices: devices);
  }
}

class E2EEEncryptResult {
  final E2EEPayload payload;

  const E2EEEncryptResult({required this.payload});
}

class E2EEDecryptResult {
  final Map<String, dynamic> content;
  final Map<String, dynamic>? replyTo;
  final List<String>? mentions;

  const E2EEDecryptResult({
    required this.content,
    this.replyTo,
    this.mentions,
  });
}
