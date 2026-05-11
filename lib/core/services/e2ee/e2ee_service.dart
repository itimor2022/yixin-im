import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import '../api/api_client.dart';
import '../device_service.dart';
import 'e2ee_models.dart';
import 'web_rsa_keygen_stub.dart'
    if (dart.library.html) 'web_rsa_keygen_web.dart';

final e2eeServiceProvider = Provider<E2EEService>((ref) {
  final api = ref.watch(apiClientProvider);
  return E2EEService(api);
});

class E2EEService {
  static const _algo = 'rsa-oaep-2048+aes-256-cbc+hmac-sha256';
  static const _publicAlgo = 'rsa-jwk-oaep-2048';
  static const _storage = FlutterSecureStorage();

  final ApiClient _api;

  Future<void>? _ensureFuture;

  E2EEService(this._api);

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
      throw Exception('当前会话没有可用的加密设备');
    }

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
      throw Exception('会话内仍有设备未升级到加密版本，请先更新客户端后再发送');
    }

    final myEnvelopeFound =
        envelopes.any((item) => item.deviceId == keyPair.deviceId);
    if (!myEnvelopeFound || envelopes.isEmpty) {
      throw Exception('加密封装失败，请稍后重试');
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
    final envelope = payload.envelopes.cast<E2EEKeyEnvelope?>().firstWhere(
          (item) => item?.deviceId == keyPair.deviceId,
          orElse: () => null,
        );
    if (envelope == null) {
      return null;
    }

    final wrappedSecret = _b64d(envelope.encryptedKey);
    final secret = _rsaDecrypt(wrappedSecret, keyPair.privateKey);
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
    if (!_constantTimeEquals(expectedMac, actualMac)) {
      throw Exception('消息签名校验失败');
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
      throw Exception(
          response.message.isNotEmpty ? response.message : '注册设备密钥失败');
    }
    await _storage.write(key: registeredDeviceKey, value: keyPair.deviceId);
  }

  Future<ChatDeviceKeyBundle> _fetchChatDeviceKeys(String chatId) async {
    final response = await _api.get(
      '/message/e2ee/device-keys',
      queryParameters: {'chat_id': chatId},
    );
    if (!response.isSuccess || response.data == null) {
      throw Exception(
          response.message.isNotEmpty ? response.message : '读取会话密钥失败');
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
    final userId = (await TokenStorage.getUserId()) ?? 'anonymous';
    return 'e2ee_public_key_$userId';
  }

  Future<String> _privateKeyStorageKey() async {
    final userId = (await TokenStorage.getUserId()) ?? 'anonymous';
    return 'e2ee_private_key_$userId';
  }

  Future<String> _registeredDeviceStorageKey() async {
    final userId = (await TokenStorage.getUserId()) ?? 'anonymous';
    return 'e2ee_registered_device_$userId';
  }
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
