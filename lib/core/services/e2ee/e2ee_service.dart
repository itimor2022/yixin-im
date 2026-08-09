// 文件用途：实现 E2EEService 相关逻辑，服务于业务服务。
// 核心逻辑：管理设备密钥、会话密钥和消息加解密，处理密钥恢复、轮换及缺少密钥时的可恢复错误。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import '../../i18n/app_localizations.dart';
import '../api/api_client.dart';
import '../device_service.dart';
import 'e2ee_models.dart';
import 'e2ee_recovery_models.dart';
import 'web_rsa_keygen_stub.dart'
    if (dart.library.html) 'web_rsa_keygen_web.dart';

String _e2eeText({
  required String zhCN,
  required String zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _localizeE2eeServerMessage(String message) {
  final normalized = message.trim();
  if (normalized.isEmpty) {
    return normalized;
  }

  if (normalized.contains('注册设备密钥失败') ||
      normalized.toLowerCase().contains('register device key')) {
    return _e2eeText(
      zhCN: '注册设备密钥失败',
      zhTW: '註冊裝置金鑰失敗',
      en: 'Failed to register the device key',
    );
  }
  if (normalized.contains('读取会话密钥失败') ||
      normalized.toLowerCase().contains('read session key')) {
    return _e2eeText(
      zhCN: '读取会话密钥失败',
      zhTW: '讀取會話金鑰失敗',
      en: 'Failed to read the conversation key',
    );
  }

  return normalized;
}

final e2eeServiceProvider = Provider<E2EEService>((ref) {
  final api = ref.watch(apiClientProvider);
  return E2EEService(api);
});

// 关键声明：E2EE 服务把设备身份、会话密钥和消息加解密串成完整链路，任何密钥校验失败都禁止降级成明文。
class E2EEService {
  static const _algo = 'rsa-oaep-2048+aes-256-cbc+hmac-sha256';
  static const _publicAlgo = 'rsa-jwk-oaep-2048';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final ApiClient _api;

  Future<void>? _ensureFuture;

  E2EEService(this._api);

  // 流程逻辑：`hasLocalIdentity` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
  Future<bool> hasLocalIdentity(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return false;
    final namespace = await _deviceStorageNamespaceFor(normalized);
    final publicKey = await _storage.read(key: 'e2ee_public_key_$namespace');
    final privateKey = await _storage.read(key: 'e2ee_private_key_$namespace');
    return (publicKey ?? '').isNotEmpty && (privateKey ?? '').isNotEmpty;
  }

  /// 轮换当前账号在本设备上的加密身份。
  ///
  /// 新私钥先持久化为待提交状态，再向服务端发布对应公钥；操作中断后会复用
  /// 同一待提交密钥继续执行，避免服务端公钥与本地私钥失配。
  Future<void> rotateDeviceIdentity(String accountId) async {
    final normalized = accountId.trim();
    final storedAccountId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (normalized.isEmpty || storedAccountId != normalized) {
      throw StateError('The active account changed before key rotation');
    }

    final namespace = await _deviceStorageNamespaceFor(normalized);
    var pendingPublic = await _storage.read(
      key: 'e2ee_rotation_public_$namespace',
    );
    var pendingPrivate = await _storage.read(
      key: 'e2ee_rotation_private_$namespace',
    );
    if ((pendingPublic ?? '').isEmpty || (pendingPrivate ?? '').isEmpty) {
      final generated = await _generateJwkPair();
      pendingPublic = generated.publicJwk;
      pendingPrivate = generated.privateJwk;
      await _storage.write(
        key: 'e2ee_rotation_public_$namespace',
        value: pendingPublic,
      );
      await _storage.write(
        key: 'e2ee_rotation_private_$namespace',
        value: pendingPrivate,
      );
    }

    await _commitPendingRotation(
      accountId: normalized,
      namespace: namespace,
      publicJwk: pendingPublic!,
      privateJwk: pendingPrivate!,
    );
  }

  Future<E2EERecoveryRequest> createRecoveryRequest() async {
    final accountId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (accountId.isEmpty) {
      throw StateError('Sign in before requesting encrypted history recovery');
    }
    final namespace = await _deviceStorageNamespaceFor(accountId);
    final transferKey = await _generateJwkPair();
    // 恢复传输私钥只保存在请求设备；服务端仅接收一次性公钥。
    await _storage.write(
      key: 'e2ee_recovery_pending_private_$namespace',
      value: transferKey.privateJwk,
    );
    await _storage.write(
      key: 'e2ee_recovery_pending_public_$namespace',
      value: transferKey.publicJwk,
    );

    final response = await _api.post<Map<String, dynamic>>(
      '/user/e2ee/recovery/requests',
      data: {'public_key': transferKey.publicJwk, 'algo': _publicAlgo},
    );
    if (!response.isSuccess || response.data == null) {
      throw Exception(response.message.isNotEmpty
          ? response.message
          : _e2eeText(
              zhCN: '创建加密消息恢复请求失败',
              zhTW: '建立加密訊息復原請求失敗',
              en: 'Failed to create encrypted history recovery request',
            ));
    }
    final requestId = response.data!['request_id']?.toString() ?? '';
    if (requestId.isEmpty) {
      throw StateError('Recovery request did not return an id');
    }
    await _storage.write(
      key: 'e2ee_recovery_request_id_$namespace',
      value: requestId,
    );
    return E2EERecoveryRequest.fromJson({
      ...response.data!,
      'requester_device_id': await DeviceService.getDeviceId(),
      'requester_public_key': transferKey.publicJwk,
      'requester_public_key_algo': _publicAlgo,
      'is_requester': true,
    });
  }

  Future<List<E2EERecoveryRequest>> listRecoveryRequests() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/user/e2ee/recovery/requests',
    );
    if (!response.isSuccess || response.data == null) {
      throw Exception(response.message.isNotEmpty
          ? response.message
          : _e2eeText(
              zhCN: '读取加密消息恢复请求失败',
              zhTW: '讀取加密訊息復原請求失敗',
              en: 'Failed to load encrypted history recovery requests',
            ));
    }
    final raw = response.data!['requests'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => E2EERecoveryRequest.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.requestId.isNotEmpty)
        .toList();
  }

  Future<void> approveRecoveryRequest(E2EERecoveryRequest request) async {
    if (!request.isPending || request.isRequester) {
      throw StateError('Only another trusted device can approve this request');
    }
    final accountId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (accountId.isEmpty) {
      throw StateError('The active account is missing');
    }
    await ensureDeviceKeyRegistered();
    final keyPair = await _loadOrCreateKeyPair();
    final fingerprint = crypto.sha256.convert(utf8.encode(keyPair.publicJwk));
    final recoveryPayload = utf8.encode(jsonEncode({
      'version': 1,
      'account_id': accountId,
      'source_device_id': keyPair.deviceId,
      'source_public_jwk': keyPair.publicJwk,
      'source_private_jwk': keyPair.privateJwk,
      'source_key_fingerprint': fingerprint.toString(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }));
    final requesterKey = _publicKeyFromJwk(request.requesterPublicKey);
    // 历史私钥只存在于用请求设备公钥加密后的载荷中，服务端无法读取明文。
    final encrypted = _rsaEncrypt(
      Uint8List.fromList(recoveryPayload),
      requesterKey,
    );
    final response = await _api.post<Map<String, dynamic>>(
      '/user/e2ee/recovery/requests/${request.requestId}/approve',
      data: {
        'encrypted_payload': _b64(encrypted),
        'payload_algo': _publicAlgo,
      },
    );
    if (!response.isSuccess) {
      throw Exception(response.message.isNotEmpty
          ? response.message
          : _e2eeText(
              zhCN: '批准加密消息恢复失败',
              zhTW: '批准加密訊息復原失敗',
              en: 'Failed to approve encrypted history recovery',
            ));
    }
  }

  Future<bool> importApprovedRecovery() async {
    final accountId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (accountId.isEmpty) return false;
    final namespace = await _deviceStorageNamespaceFor(accountId);
    final requestId = await _storage.read(
      key: 'e2ee_recovery_request_id_$namespace',
    );
    final transferPrivateJwk = await _storage.read(
      key: 'e2ee_recovery_pending_private_$namespace',
    );
    if ((requestId ?? '').isEmpty || (transferPrivateJwk ?? '').isEmpty) {
      return false;
    }
    final requests = await listRecoveryRequests();
    final approved = requests.cast<E2EERecoveryRequest?>().firstWhere(
          (item) =>
              item?.requestId == requestId &&
              item?.isRequester == true &&
              item?.isApproved == true,
          orElse: () => null,
        );
    if (approved == null || approved.encryptedPayload.isEmpty) return false;

    final transferPrivateKey = _privateKeyFromJwk(transferPrivateJwk!);
    final decrypted = _rsaDecrypt(
      _b64d(approved.encryptedPayload),
      transferPrivateKey,
    );
    final decoded = jsonDecode(utf8.decode(decrypted));
    if (decoded is! Map) {
      throw StateError('Invalid encrypted history recovery payload');
    }
    final payload = Map<String, dynamic>.from(decoded);
    // 解密成功仍不足以信任载荷，先绑定当前账号，再核对指纹和公私钥配对。
    if (payload['version'] != 1 ||
        payload['account_id']?.toString() != accountId) {
      throw StateError(
          'Encrypted history recovery payload belongs to another account');
    }
    final sourceDeviceId = payload['source_device_id']?.toString() ?? '';
    final publicJwk = payload['source_public_jwk']?.toString() ?? '';
    final privateJwk = payload['source_private_jwk']?.toString() ?? '';
    final fingerprint = payload['source_key_fingerprint']?.toString() ?? '';
    if (sourceDeviceId.isEmpty || publicJwk.isEmpty || privateJwk.isEmpty) {
      throw StateError('Encrypted history recovery payload is incomplete');
    }
    final calculatedFingerprint =
        crypto.sha256.convert(utf8.encode(publicJwk)).toString();
    if (fingerprint != calculatedFingerprint ||
        (approved.sourceKeyFingerprint.isNotEmpty &&
            approved.sourceKeyFingerprint != calculatedFingerprint)) {
      throw StateError('Encrypted history recovery key fingerprint mismatch');
    }
    final publicKey = _publicKeyFromJwk(publicJwk);
    final privateKey = _privateKeyFromJwk(privateJwk);
    if (publicKey.modulus != privateKey.modulus) {
      throw StateError('Encrypted history recovery key pair mismatch');
    }

    await _storeRecoveredIdentity(
      namespace: namespace,
      sourceDeviceId: sourceDeviceId,
      publicJwk: publicJwk,
      privateJwk: privateJwk,
      fingerprint: calculatedFingerprint,
      keyVersion: approved.sourceKeyVersion,
    );
    final consume = await _api.post<Map<String, dynamic>>(
      '/user/e2ee/recovery/requests/${approved.requestId}/consume',
    );
    if (!consume.isSuccess) {
      // 本地身份已安全落盘，消费回执失败不回滚密钥；后续请求列表可能重复显示。
      debugPrint('[E2EE] Recovery imported but consume acknowledgement failed');
    }
    await _storage.delete(key: 'e2ee_recovery_request_id_$namespace');
    await _storage.delete(key: 'e2ee_recovery_pending_private_$namespace');
    await _storage.delete(key: 'e2ee_recovery_pending_public_$namespace');
    return true;
  }

  bool supportsMessageType(int type) {
    switch (type) {
      case 1:
      case 2:
      case 3:
      case 4:
      case 5:
      case 6:
      case 10:
        return true;
      default:
        return false;
    }
  }

  Future<void> ensureDeviceKeyRegistered() {
    // 同一实例内共享注册 Future，避免并发发消息时重复生成或上传设备公钥。
    return _ensureFuture ??=
        _ensureDeviceKeyRegisteredInternal().whenComplete(() {
      _ensureFuture = null;
    });
  }

  Future<E2EEEncryptResult?> encryptMessage({
    required String chatId,
    required int type,
    required Map<String, dynamic> content,
    Map<String, dynamic>? replyTo,
    List<String>? mentions,
  }) async {
    if (!supportsMessageType(type)) {
      return null;
    }

    await ensureDeviceKeyRegistered();
    final keyPair = await _loadOrCreateKeyPair();
    final deviceBundle = await _fetchChatDeviceKeys(chatId);
    if (deviceBundle.devices.isEmpty) {
      throw Exception(
        _e2eeText(
          zhCN: '当前会话没有可用的加密设备',
          zhTW: '目前會話沒有可用的加密裝置',
          en: 'No encryption-capable devices are available in this conversation',
        ),
      );
    }

    // 每条消息生成独立的内容密钥和 MAC 密钥，内容只加密一次。
    final secret = _randomBytes(64);
    final aesKey = Uint8List.sublistView(secret, 0, 32);
    final macKey = Uint8List.sublistView(secret, 32, 64);
    final iv = _randomBytes(16);

    final plainJson = jsonEncode({
      'version': 1,
      'content': content,
      if (replyTo != null) 'reply_to': replyTo,
      if (mentions != null && mentions.isNotEmpty) 'mentions': mentions,
    });
    final plainBytes = Uint8List.fromList(utf8.encode(plainJson));
    final cipherBytes = _encryptAesCbc(plainBytes, aesKey, iv);
    final macBytes =
        _hmacSha256(macKey, Uint8List.fromList([...iv, ...cipherBytes]));

    // 内容密钥只在本地生成一次，然后为会话内每台设备分别封装一份；
    // 这样消息正文只上传一份密文，接收端用属于自己的 RSA 信封取回同一密钥。
    final envelopes = <E2EEKeyEnvelope>[];
    final validDeviceCountByUser = <String, int>{};
    final seen = <String>{};
    for (final device in deviceBundle.devices) {
      if (device.userId.isEmpty ||
          device.deviceId.isEmpty ||
          device.publicKey.isEmpty) {
        continue;
      }
      final key = '${device.userId}:${device.deviceId}';
      if (!seen.add(key)) {
        continue;
      }
      try {
        final publicKey = _publicKeyFromJwk(device.publicKey);
        final wrappedKey = _rsaEncrypt(secret, publicKey);
        envelopes.add(
          E2EEKeyEnvelope(
            userId: device.userId,
            deviceId: device.deviceId,
            algo: device.algo.isNotEmpty ? device.algo : _publicAlgo,
            encryptedKey: _b64(wrappedKey),
          ),
        );
        validDeviceCountByUser.update(
          device.userId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      } catch (e) {
        debugPrint(
            '[E2EE] Skip invalid public key for ${device.userId}/${device.deviceId}: $e');
      }
    }

    final missingUsers = deviceBundle.members
        .where((userId) => (validDeviceCountByUser[userId] ?? 0) == 0)
        .toList();
    if (missingUsers.isNotEmpty) {
      // 每位成员至少要有一个有效设备信封，且发送者当前设备也必须可解密；
      // 条件不满足时拒绝降级为明文。
      throw Exception(
        _e2eeText(
          zhCN: '会话内仍有设备未升级到加密版本，请先更新客户端后再发送',
          zhTW: '會話內仍有裝置尚未升級到加密版本，請先更新客戶端後再發送',
          en: 'Some devices in this conversation have not been upgraded for encryption yet. Update the clients first and try again',
        ),
      );
    }

    final myEnvelopeFound =
        envelopes.any((item) => item.deviceId == keyPair.deviceId);
    if (!myEnvelopeFound || envelopes.isEmpty) {
      throw Exception(
        _e2eeText(
          zhCN: '加密封装失败，请稍后重试',
          zhTW: '加密封裝失敗，請稍後重試',
          en: 'Failed to package the encrypted message. Please try again later',
        ),
      );
    }

    return E2EEEncryptResult(
      payload: E2EEPayload(
        version: 1,
        algo: _algo,
        ciphertext: _b64(cipherBytes),
        iv: _b64(iv),
        mac: _b64(macBytes),
        envelopes: envelopes,
      ),
    );
  }

  Future<E2EEDecryptResult?> decryptPayload(E2EEPayload payload) async {
    if (!payload.isValid) {
      return null;
    }

    await ensureDeviceKeyRegistered();
    final keyPair = await _loadOrCreateKeyPair();
    var envelope = payload.envelopes.cast<E2EEKeyEnvelope?>().firstWhere(
          (item) => item?.deviceId == keyPair.deviceId,
          orElse: () => null,
        );
    var decryptionPrivateKey = keyPair.privateKey;
    if (envelope == null) {
      final recovered = await _findRecoveredIdentityForPayload(payload);
      if (recovered == null) return null;
      envelope = recovered.envelope;
      decryptionPrivateKey = recovered.privateKey;
    }

    final wrappedSecret = _b64d(envelope.encryptedKey);
    final secret = _rsaDecrypt(wrappedSecret, decryptionPrivateKey);
    if (secret.length < 64) {
      return null;
    }

    final aesKey = Uint8List.sublistView(secret, 0, 32);
    final macKey = Uint8List.sublistView(secret, 32, 64);
    final iv = _b64d(payload.iv);
    final cipherBytes = _b64d(payload.ciphertext);
    final expectedMac =
        _hmacSha256(macKey, Uint8List.fromList([...iv, ...cipherBytes]));
    final actualMac = _b64d(payload.mac);
    // 必须先以常量时间比较校验 IV 和密文，再执行 CBC 解密。
    if (!_constantTimeEquals(expectedMac, actualMac)) {
      throw Exception(
        _e2eeText(
          zhCN: '消息签名校验失败',
          zhTW: '訊息簽章校驗失敗',
          en: 'Message signature verification failed',
        ),
      );
    }

    final plainBytes = _decryptAesCbc(cipherBytes, aesKey, iv);
    final decoded = jsonDecode(utf8.decode(plainBytes));
    if (decoded is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(decoded as Map);
    final content = map['content'];
    return E2EEDecryptResult(
      content: content is Map
          ? Map<String, dynamic>.from(content)
          : <String, dynamic>{},
      replyTo: map['reply_to'] is Map
          ? Map<String, dynamic>.from(map['reply_to'] as Map)
          : null,
      mentions: map['mentions'] is List
          ? (map['mentions'] as List).map((item) => item.toString()).toList()
          : null,
    );
  }

  Future<void> _ensureDeviceKeyRegisteredInternal() async {
    await _resumePendingRotationIfAny();
    final keyPair = await _loadOrCreateKeyPair();
    final registeredDeviceKey = await _registeredDeviceStorageKey();
    final registeredDevice = await _storage.read(key: registeredDeviceKey);
    if (registeredDevice == keyPair.deviceId) {
      return;
    }

    final response = await _api.put(
      '/user/e2ee/device-key',
      data: {
        'public_key': keyPair.publicJwk,
        'algo': _publicAlgo,
      },
    );
    if (!response.isSuccess) {
      final localizedMessage = _localizeE2eeServerMessage(response.message);
      throw Exception(
        localizedMessage.isNotEmpty
            ? localizedMessage
            : _e2eeText(
                zhCN: '注册设备密钥失败',
                zhTW: '註冊裝置金鑰失敗',
                en: 'Failed to register the device key',
              ),
      );
    }
    // 仅服务端确认成功后写注册标记，本地标记只是避免重复上传的缓存。
    await _storage.write(key: registeredDeviceKey, value: keyPair.deviceId);
  }

  Future<void> _resumePendingRotationIfAny() async {
    final accountId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (accountId.isEmpty) return;
    final namespace = await _deviceStorageNamespaceFor(accountId);
    final pendingPublic = await _storage.read(
      key: 'e2ee_rotation_public_$namespace',
    );
    final pendingPrivate = await _storage.read(
      key: 'e2ee_rotation_private_$namespace',
    );
    if ((pendingPublic ?? '').isEmpty || (pendingPrivate ?? '').isEmpty) {
      return;
    }
    await _commitPendingRotation(
      accountId: accountId,
      namespace: namespace,
      publicJwk: pendingPublic!,
      privateJwk: pendingPrivate!,
    );
  }

  Future<void> _commitPendingRotation({
    required String accountId,
    required String namespace,
    required String publicJwk,
    required String privateJwk,
  }) async {
    if ((await TokenStorage.getUserId())?.trim() != accountId) {
      throw StateError('The active account changed during key rotation');
    }
    final response = await _api.put(
      '/user/e2ee/device-key',
      data: {'public_key': publicJwk, 'algo': _publicAlgo},
    );
    if (!response.isSuccess) {
      throw StateError(
        _localizeE2eeServerMessage(response.message).isNotEmpty
            ? _localizeE2eeServerMessage(response.message)
            : 'Failed to rotate the device key',
      );
    }

    // 服务端公钥更新成功后再切换正式本地身份；待提交副本保留到全部写入完成，
    // 进程中断时可继续提交同一密钥对。
    final deviceId = await DeviceService.getDeviceId();
    await _storage.write(key: 'e2ee_public_key_$namespace', value: publicJwk);
    await _storage.write(key: 'e2ee_private_key_$namespace', value: privateJwk);
    await _storage.write(
      key: 'e2ee_registered_device_$namespace',
      value: deviceId,
    );
    await _storage.delete(key: 'e2ee_rotation_public_$namespace');
    await _storage.delete(key: 'e2ee_rotation_private_$namespace');
    _ensureFuture = null;
  }

  Future<({String publicJwk, String privateJwk})> _generateJwkPair() async {
    if (kIsWeb) {
      // Web 优先使用浏览器 WebCrypto；不可用时回退到 Dart RSA 实现。
      try {
        final webKeyPair = await tryGenerateWebRsaJwkKeyPair();
        final publicJwk = webKeyPair?['publicJwk'] ?? '';
        final privateJwk = webKeyPair?['privateJwk'] ?? '';
        if (publicJwk.isNotEmpty && privateJwk.isNotEmpty) {
          return (publicJwk: publicJwk, privateJwk: privateJwk);
        }
      } catch (error) {
        debugPrint('[E2EE] WebCrypto rotation generation failed: $error');
      }
    }

    final pair = _generateRsaKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;
    return (
      publicJwk: _publicKeyToJwk(publicKey),
      privateJwk: _privateKeyToJwk(publicKey, privateKey),
    );
  }

  Future<ChatDeviceKeyBundle> _fetchChatDeviceKeys(String chatId) async {
    final response = await _api.get(
      '/message/e2ee/device-keys',
      queryParameters: {'chat_id': chatId},
    );
    if (!response.isSuccess || response.data == null) {
      final localizedMessage = _localizeE2eeServerMessage(response.message);
      throw Exception(
        localizedMessage.isNotEmpty
            ? localizedMessage
            : _e2eeText(
                zhCN: '读取会话密钥失败',
                zhTW: '讀取會話金鑰失敗',
                en: 'Failed to read the conversation key',
              ),
      );
    }
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      return ChatDeviceKeyBundle.fromJson(raw);
    }
    return ChatDeviceKeyBundle(members: const [], devices: const []);
  }

  Future<_StoredKeyPair> _loadOrCreateKeyPair() async {
    final deviceId = await DeviceService.getDeviceId();
    final publicKeyStorageKey = await _publicKeyStorageKey();
    final privateKeyStorageKey = await _privateKeyStorageKey();

    // 正式身份以安全存储中成对存在的公私钥为准，缺任一项都重新生成整对密钥。
    final publicJwk = await _storage.read(key: publicKeyStorageKey);
    final privateJwk = await _storage.read(key: privateKeyStorageKey);
    if (publicJwk != null &&
        publicJwk.isNotEmpty &&
        privateJwk != null &&
        privateJwk.isNotEmpty) {
      return _StoredKeyPair(
        deviceId: deviceId,
        publicJwk: publicJwk,
        privateJwk: privateJwk,
        publicKey: _publicKeyFromJwk(publicJwk),
        privateKey: _privateKeyFromJwk(privateJwk),
      );
    }

    String? newPublicJwk;
    String? newPrivateJwk;

    if (kIsWeb) {
      try {
        final webKeyPair = await tryGenerateWebRsaJwkKeyPair();
        newPublicJwk = webKeyPair?['publicJwk'];
        newPrivateJwk = webKeyPair?['privateJwk'];
      } catch (e) {
        debugPrint('[E2EE] WebCrypto key generation failed, fallback: $e');
      }
    }

    RSAPublicKey publicKey;
    RSAPrivateKey privateKey;

    if ((newPublicJwk ?? '').isNotEmpty && (newPrivateJwk ?? '').isNotEmpty) {
      publicKey = _publicKeyFromJwk(newPublicJwk!);
      privateKey = _privateKeyFromJwk(newPrivateJwk!);
    } else {
      final pair = _generateRsaKeyPair();
      publicKey = pair.publicKey as RSAPublicKey;
      privateKey = pair.privateKey as RSAPrivateKey;
      newPublicJwk = _publicKeyToJwk(publicKey);
      newPrivateJwk = _privateKeyToJwk(publicKey, privateKey);
    }

    await _storage.write(key: publicKeyStorageKey, value: newPublicJwk);
    await _storage.write(key: privateKeyStorageKey, value: newPrivateJwk);

    return _StoredKeyPair(
      deviceId: deviceId,
      publicJwk: newPublicJwk,
      privateJwk: newPrivateJwk,
      publicKey: publicKey,
      privateKey: privateKey,
    );
  }

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair() {
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(_randomBytes(32)));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          secureRandom,
        ),
      );
    return generator.generateKeyPair();
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  Uint8List _encryptAesCbc(
      Uint8List plainBytes, Uint8List keyBytes, Uint8List ivBytes) {
    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(keyBytes),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
    final encryptedValue =
        encrypter.encryptBytes(plainBytes, iv: encrypt.IV(ivBytes));
    return Uint8List.fromList(encryptedValue.bytes);
  }

  Uint8List _decryptAesCbc(
      Uint8List cipherBytes, Uint8List keyBytes, Uint8List ivBytes) {
    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(keyBytes),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
    final decryptedValue = encrypter.decryptBytes(
      encrypt.Encrypted(cipherBytes),
      iv: encrypt.IV(ivBytes),
    );
    return Uint8List.fromList(decryptedValue);
  }

  Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final hmac = crypto.Hmac(crypto.sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }

  Uint8List _rsaEncrypt(Uint8List data, RSAPublicKey key) {
    final cipher = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    return _processRsa(cipher, data);
  }

  Uint8List _rsaDecrypt(Uint8List data, RSAPrivateKey key) {
    final cipher = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
    return _processRsa(cipher, data);
  }

  Uint8List _processRsa(AsymmetricBlockCipher cipher, Uint8List data) {
    final output = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < data.length) {
      final chunkSize = min(cipher.inputBlockSize, data.length - offset);
      output.add(cipher
          .process(Uint8List.sublistView(data, offset, offset + chunkSize)));
      offset += chunkSize;
    }
    return output.toBytes();
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  RSAPublicKey _publicKeyFromJwk(String jwkText) {
    final data = Map<String, dynamic>.from(jsonDecode(jwkText) as Map);
    return RSAPublicKey(
      _bigIntFromBase64Url(data['n']?.toString() ?? ''),
      _bigIntFromBase64Url(data['e']?.toString() ?? ''),
    );
  }

  RSAPrivateKey _privateKeyFromJwk(String jwkText) {
    final data = Map<String, dynamic>.from(jsonDecode(jwkText) as Map);
    return RSAPrivateKey(
      _bigIntFromBase64Url(data['n']?.toString() ?? ''),
      _bigIntFromBase64Url(data['d']?.toString() ?? ''),
      _bigIntFromBase64Url(data['p']?.toString() ?? ''),
      _bigIntFromBase64Url(data['q']?.toString() ?? ''),
    );
  }

  String _publicKeyToJwk(RSAPublicKey key) {
    return jsonEncode({
      'kty': 'RSA',
      'n': _bigIntToBase64Url(key.modulus ?? BigInt.zero),
      'e': _bigIntToBase64Url(key.exponent ?? BigInt.zero),
    });
  }

  String _privateKeyToJwk(RSAPublicKey publicKey, RSAPrivateKey privateKey) {
    return jsonEncode({
      'kty': 'RSA',
      'n': _bigIntToBase64Url(publicKey.modulus ?? BigInt.zero),
      'e': _bigIntToBase64Url(publicKey.exponent ?? BigInt.zero),
      'd': _bigIntToBase64Url(privateKey.privateExponent ?? BigInt.zero),
      'p': _bigIntToBase64Url(privateKey.p ?? BigInt.zero),
      'q': _bigIntToBase64Url(privateKey.q ?? BigInt.zero),
    });
  }

  BigInt _bigIntFromBase64Url(String value) {
    final bytes = _b64d(value);
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  String _bigIntToBase64Url(BigInt value) {
    if (value == BigInt.zero) return '';
    var current = value;
    final result = <int>[];
    while (current > BigInt.zero) {
      result.insert(0, (current & BigInt.from(0xff)).toInt());
      current >>= 8;
    }
    return _b64(Uint8List.fromList(result));
  }

  String _b64(Uint8List bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  Uint8List _b64d(String value) {
    final normalized =
        value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
    return Uint8List.fromList(base64Url.decode(normalized));
  }

  Future<String> _publicKeyStorageKey() async {
    return 'e2ee_public_key_${await _deviceStorageNamespace()}';
  }

  Future<String> _privateKeyStorageKey() async {
    return 'e2ee_private_key_${await _deviceStorageNamespace()}';
  }

  Future<String> _registeredDeviceStorageKey() async {
    return 'e2ee_registered_device_${await _deviceStorageNamespace()}';
  }

  Future<String> _deviceStorageNamespace() async {
    final userId = (await TokenStorage.getUserId()) ?? 'anonymous';
    return _deviceStorageNamespaceFor(userId);
  }

  Future<String> _deviceStorageNamespaceFor(String userId) async {
    final deviceId = await DeviceService.getDeviceId();
    // 账号与设备共同构成命名空间，同一设备切号或同一账号换设备都不会共用私钥。
    return crypto.sha256
        .convert(utf8.encode('$userId\u0000$deviceId'))
        .toString();
  }

  Future<List<_RecoveredIdentityRef>> _readRecoveredIdentityIndex(
      String namespace) async {
    final raw = await _storage.read(
      key: 'e2ee_recovered_identity_index_$namespace',
    );
    if ((raw ?? '').isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw!);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => _RecoveredIdentityRef.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.deviceId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _storeRecoveredIdentity({
    required String namespace,
    required String sourceDeviceId,
    required String publicJwk,
    required String privateJwk,
    required String fingerprint,
    required int keyVersion,
  }) async {
    final keySuffix = crypto.sha256.convert(utf8.encode(sourceDeviceId));
    await _storage.write(
      key: 'e2ee_recovered_public_${namespace}_$keySuffix',
      value: publicJwk,
    );
    await _storage.write(
      key: 'e2ee_recovered_private_${namespace}_$keySuffix',
      value: privateJwk,
    );
    final refs = (await _readRecoveredIdentityIndex(namespace)).toList();
    refs.removeWhere((item) => item.deviceId == sourceDeviceId);
    refs.add(_RecoveredIdentityRef(
      deviceId: sourceDeviceId,
      keySuffix: keySuffix.toString(),
      fingerprint: fingerprint,
      keyVersion: keyVersion,
    ));
    await _storage.write(
      key: 'e2ee_recovered_identity_index_$namespace',
      value: jsonEncode(refs.map((item) => item.toJson()).toList()),
    );
  }

  Future<_RecoveredDecryptionIdentity?> _findRecoveredIdentityForPayload(
      E2EEPayload payload) async {
    final accountId = (await TokenStorage.getUserId())?.trim() ?? '';
    if (accountId.isEmpty) return null;
    final namespace = await _deviceStorageNamespaceFor(accountId);
    final refs = await _readRecoveredIdentityIndex(namespace);
    for (final ref in refs) {
      final envelope = payload.envelopes.cast<E2EEKeyEnvelope?>().firstWhere(
            (item) => item?.deviceId == ref.deviceId,
            orElse: () => null,
          );
      if (envelope == null) continue;
      final privateJwk = await _storage.read(
        key: 'e2ee_recovered_private_${namespace}_${ref.keySuffix}',
      );
      if ((privateJwk ?? '').isEmpty) continue;
      try {
        return _RecoveredDecryptionIdentity(
          envelope: envelope,
          privateKey: _privateKeyFromJwk(privateJwk!),
        );
      } catch (error) {
        debugPrint('[E2EE] Skip invalid recovered identity: $error');
      }
    }
    return null;
  }
}

class _RecoveredIdentityRef {
  final String deviceId;
  final String keySuffix;
  final String fingerprint;
  final int keyVersion;

  const _RecoveredIdentityRef({
    required this.deviceId,
    required this.keySuffix,
    required this.fingerprint,
    required this.keyVersion,
  });

  factory _RecoveredIdentityRef.fromJson(Map<String, dynamic> json) {
    return _RecoveredIdentityRef(
      deviceId: json['device_id']?.toString() ?? '',
      keySuffix: json['key_suffix']?.toString() ?? '',
      fingerprint: json['fingerprint']?.toString() ?? '',
      keyVersion: json['key_version'] is int
          ? json['key_version'] as int
          : int.tryParse(json['key_version']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'key_suffix': keySuffix,
        'fingerprint': fingerprint,
        'key_version': keyVersion,
      };
}

class _RecoveredDecryptionIdentity {
  final E2EEKeyEnvelope envelope;
  final RSAPrivateKey privateKey;

  const _RecoveredDecryptionIdentity({
    required this.envelope,
    required this.privateKey,
  });
}

class _StoredKeyPair {
  final String deviceId;
  final String publicJwk;
  final String privateJwk;
  final RSAPublicKey publicKey;
  final RSAPrivateKey privateKey;

  const _StoredKeyPair({
    required this.deviceId,
    required this.publicJwk,
    required this.privateJwk,
    required this.publicKey,
    required this.privateKey,
  });
}
