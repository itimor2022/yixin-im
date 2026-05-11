import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:js/js_util.dart' as js_util;

Future<Map<String, String>?> tryGenerateWebRsaJwkKeyPair() async {
  final crypto = html.window.crypto;
  final subtle = js_util.getProperty<Object?>(crypto as Object, 'subtle');
  if (subtle == null) {
    return null;
  }

  final hash = js_util.newObject();
  js_util.setProperty(hash, 'name', 'SHA-256');

  final algorithm = js_util.newObject();
  js_util.setProperty(algorithm, 'name', 'RSA-OAEP');
  js_util.setProperty(algorithm, 'modulusLength', 2048);
  js_util.setProperty(
    algorithm,
    'publicExponent',
    Uint8List.fromList(const [0x01, 0x00, 0x01]),
  );
  js_util.setProperty(algorithm, 'hash', hash);

  final keyPair = await js_util.promiseToFuture<Object>(
    js_util.callMethod(
      subtle,
      'generateKey',
      [
        algorithm,
        true,
        ['encrypt', 'decrypt'],
      ],
    ),
  );

  final publicKey = js_util.getProperty<Object>(keyPair, 'publicKey');
  final privateKey = js_util.getProperty<Object>(keyPair, 'privateKey');

  final publicJwkObject = await js_util.promiseToFuture<Object>(
    js_util.callMethod(subtle, 'exportKey', ['jwk', publicKey]),
  );
  final privateJwkObject = await js_util.promiseToFuture<Object>(
    js_util.callMethod(subtle, 'exportKey', ['jwk', privateKey]),
  );

  final publicJwk = Map<String, dynamic>.from(
    js_util.dartify(publicJwkObject)! as Map,
  )..removeWhere((key, value) => value == null);
  final privateJwk = Map<String, dynamic>.from(
    js_util.dartify(privateJwkObject)! as Map,
  )..removeWhere((key, value) => value == null);

  return {
    'publicJwk': jsonEncode(publicJwk),
    'privateJwk': jsonEncode(privateJwk),
  };
}
