// 文件用途：提供 web rsa keygen 在 Web 平台的实现，服务于业务服务。
// 核心逻辑：实现 web rsa keygen 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
// 关键声明：web rsa keygen web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
// ignore_for_file: avoid_web_libraries_in_flutter, undefined_function

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:js/js_util.dart' as js_util;

/// 使用浏览器 Web Crypto 生成可导出的 RSA-OAEP 密钥对。
///
/// 返回值是序列化 JWK，其中 privateJwk 属于敏感密钥材料，调用方必须立即交给
/// E2EE 安全存储流程，不能写入日志或普通缓存。浏览器缺少 SubtleCrypto 时返回
/// null；生成或导出失败则由异常交给上层统一降级。
Future<Map<String, String>?> tryGenerateWebRsaJwkKeyPair() async {
  final crypto = html.window.crypto;
  final subtle = js_util.getProperty<Object?>(crypto as Object, 'subtle');
  if (subtle == null) {
    return null;
  }

  final hash = js_util.newObject();
  js_util.setProperty(hash, 'name', 'SHA-256');

  // 公钥指数 65537 与 2048 位模数保持和其他平台 RSA-OAEP 实现一致。
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
        // 必须可导出，后续才能序列化为跨会话保存的 JWK。
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

  // dartify 后移除 JS 中的 null 字段，生成稳定、可编码的 JSON 对象。
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
