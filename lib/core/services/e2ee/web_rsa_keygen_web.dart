import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// JS interop 类型声明
@JS('Object.fromEntries')
external JSObject _objectFromEntries(JSArray entries);

extension type _CryptoKey._(JSObject _) implements JSObject {}
extension type _CryptoKeyPair._(JSObject _) implements JSObject {
  external _CryptoKey get publicKey;
  external _CryptoKey get privateKey;
}

Future<Map<String, String>?> tryGenerateWebRsaJwkKeyPair() async {
  final subtle = web.window.crypto.subtle;

  final algorithm = {
    'name': 'RSA-OAEP',
    'modulusLength': 2048,
    'publicExponent': Uint8List.fromList(const [0x01, 0x00, 0x01]),
    'hash': {'name': 'SHA-256'},
  }.jsify();

  final keyUsages = ['encrypt', 'decrypt'].jsify();

  try {
    final keyPairObj = await subtle
        .generateKey(algorithm!, true, keyUsages! as JSArray<JSString>)
        .toDart;

    final keyPair = keyPairObj as _CryptoKeyPair;

    final publicJwkObj =
        await subtle.exportKey('jwk', keyPair.publicKey as web.CryptoKey).toDart;
    final privateJwkObj =
        await subtle.exportKey('jwk', keyPair.privateKey as web.CryptoKey).toDart;

    final publicJwk = (publicJwkObj.dartify() as Map<Object?, Object?>)
        .map((k, v) => MapEntry(k.toString(), v))
      ..removeWhere((k, v) => v == null);
    final privateJwk = (privateJwkObj.dartify() as Map<Object?, Object?>)
        .map((k, v) => MapEntry(k.toString(), v))
      ..removeWhere((k, v) => v == null);

    return {
      'publicJwk': jsonEncode(publicJwk),
      'privateJwk': jsonEncode(privateJwk),
    };
  } catch (e) {
    return null;
  }
}
