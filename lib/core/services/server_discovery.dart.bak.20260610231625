import 'dart:async';
import 'dart:io';
import 'package:dio/io.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';

/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// ServerDiscovery — DNS TXT + OSS 双轨并行服务发现
///
/// 架构:
///   轨道1: 多个 DNS TXT 域名 × 多个 DoH 服务商（全并行）
///   轨道2: 多个 OSS/CDN 静态加密文件（全并行）
///   兜底:  内置保底节点列表
///
/// 加密格式: AES-256-CBC, Base64 编码
/// 明文格式: {"nodes":["https://api1.com","https://api2.com"]}
///
/// 加密工具命令（openssl）:
///   echo -n '{"nodes":["https://api.your.com"]}' | \
///   openssl enc -aes-256-cbc -K <hex_key> -iv <hex_iv> | base64
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class ServerDiscovery {
  ServerDiscovery._();
  static final ServerDiscovery instance = ServerDiscovery._();

  // ── 部署配置区（上线前必须替换所有占位值） ──────────────

  /// 多个 DNS TXT 查询域名
  /// 建议: 注册在不同域名服务商，同一 TXT 值（加密节点列表）
  /// 示例: 阿里云 + Cloudflare + Namecheap 各一个
  static const List<String> _dnsDomains = [
    'cfg.qa853.com',
  ];

  /// DoH 服务商列表（每个 DNS 域名都会被所有 DoH 并行查询）
  static const List<String> _dohProviders = [
    'https://doh.pub/dns-query',          // 腾讯DNSPod，国内最快
    'https://dns.alidns.com/resolve',     // 阿里云DoH
    'https://doh.360.cn/resolve',         // 360 DoH
    'https://cloudflare-dns.com/dns-query', // 海外兜底
  ];

  /// 多个 OSS/CDN 加密配置文件地址
  /// 建议: 阿里云OSS + 腾讯COS + Cloudflare R2，各自独立
  static const List<String> _ossUrls = [
    'https://xv.t39m0.icu/yx/nodes.enc',
    'https://uk.t39m0.icu/yx/nodes.enc',
  ];

  /// AES-256-CBC 密钥（32字节 UTF-8，与加密端一致）
  static const String _aesKey = 'YiXin2024Secure!AppNodeKey@Qa853';

  /// AES IV（16字节 UTF-8，与加密端一致）
  static const String _aesIv = 'YiXinIV@2024Qa85';

  /// 内置保底节点（所有轨道失败时的最后防线）
  static const List<String> _fallbackNodes = [
    'https://vvs.unf58.icu',
    'https://vvs.jbwsj.icu',
    'https://vvs.r1grv.icu',
  ];

  // ── 内部常量 ────────────────────────────────────────────

  static const String _pingPath       = '/api/v1/ping';
  static const Duration _probeTimeout = Duration(seconds: 10);
  static const Duration _fetchTimeout = Duration(seconds: 5);
  static const Duration _cacheValid   = Duration(hours: 6);
  static const String _cacheNodeKey   = 'svc_disc_node';
  static const String _cacheTimeKey   = 'svc_disc_time';

  String? _currentNode;
  String? get currentNode => _currentNode;

  // ── 公开接口 ────────────────────────────────────────────

  /// App 启动时调用，阻塞直到选定节点
  Future<String> initialize() async {
    final cached = await _loadCache();
    if (cached != null) {
      if (kDebugMode) debugPrint('[Discovery] Cache hit: $cached');
      _applyNode(cached);
      _refreshInBackground();
      return cached;
    }
    return _discover();
  }

  /// 强制重新发现（网络错误后调用）
  Future<String> forceRefresh() async {
    await _clearCache();
    return _discover();
  }

  // ── 发现主流程 ──────────────────────────────────────────

  Future<String> _discover() async {
    final t0 = DateTime.now();
    if (kDebugMode) debugPrint('[Discovery] ═══ Starting discovery at $t0 ═══');
    final nodes = await _fetchNodeList();
    if (kDebugMode) debugPrint('[Discovery] Candidates: $nodes');
    final best = await _probeFastest(nodes);
    if (best == null) {
      if (kDebugMode) debugPrint('[Discovery] ❌ All nodes unreachable: $nodes');
      throw Exception('No reachable server node. Please check your network.');
    }
    final selected = best;
    if (kDebugMode) debugPrint('[Discovery] Selected: $selected');
    _applyNode(selected);
    await _saveCache(selected);
    return selected;
  }

  void _applyNode(String node) {
    if (kDebugMode) debugPrint('[Discovery] ✅ Applying node: $node');
    _currentNode = node;
    ApiConfig.updateServer(node);
    if (kDebugMode) debugPrint('[Discovery] ✅ ApiConfig updated → $node');
  }

  void _refreshInBackground() {
    Future<void>.delayed(const Duration(seconds: 5), () async {
      try {
        await _clearCache();
        final node = await _discover();
        if (node != _currentNode) {
          if (kDebugMode) debugPrint('[Discovery] BG switched to $node');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Discovery] BG refresh error: $e');
      }
    });
  }

  // ── 双轨并行获取节点列表 ────────────────────────────────

  Future<List<String>> _fetchNodeList() async {
    final completer = Completer<List<String>>();
    int failures = 0;
    const total = 2; // DNS 轨道 + OSS 轨道

    void onResult(List<String>? nodes) {
      if (nodes != null && nodes.isNotEmpty && !completer.isCompleted) {
        completer.complete(nodes);
      } else {
        failures++;
        if (failures >= total && !completer.isCompleted) {
          if (kDebugMode) debugPrint('[Discovery] Both tracks failed, using fallback');
          completer.complete(List<String>.from(_fallbackNodes));
        }
      }
    }

    // 两轨并行启动
    if (kDebugMode) debugPrint('[Discovery] Track-DNS starting...');
    if (kDebugMode) debugPrint('[Discovery] Track-OSS starting...');
    _fetchFromDns().then(onResult);
    _fetchFromOss().then(onResult);

    return completer.future.timeout(
      _fetchTimeout + const Duration(seconds: 2),
      onTimeout: () {
        if (kDebugMode) debugPrint('[Discovery] Fetch timeout, fallback');
        return List<String>.from(_fallbackNodes);
      },
    );
  }

  // ── 轨道1: 多域名 × 多DoH 全并行 ───────────────────────

  Future<List<String>?> _fetchFromDns() async {
    if (_dnsDomains.isEmpty || _dohProviders.isEmpty) return null;

    // 所有域名 × 所有DoH 服务商 = N×M 个并行请求
    // 任一返回有效节点即完成
    final completer = Completer<List<String>?>();
    int total = _dnsDomains.length * _dohProviders.length;
    int failed = 0;

    for (final domain in _dnsDomains) {
      for (final doh in _dohProviders) {
        _queryDohTxt(doh, domain).then((nodes) {
          if (nodes != null && nodes.isNotEmpty
              && !completer.isCompleted) {
            if (kDebugMode) debugPrint('[Discovery] DNS hit: $doh → $domain');
            completer.complete(nodes);
          } else {
            failed++;
            if (failed >= total && !completer.isCompleted) {
              completer.complete(null);
            }
          }
        }).catchError((_) {
          failed++;
          if (failed >= total && !completer.isCompleted) {
            completer.complete(null);
          }
        });
      }
    }

    return completer.future.timeout(
      _fetchTimeout,
      onTimeout: () => null,
    );
  }

  Future<List<String>?> _queryDohTxt(String dohUrl, String domain) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _fetchTimeout,
        receiveTimeout: _fetchTimeout,
        headers: {'Accept': 'application/dns-json'},
      ));
      if (kDebugMode) debugPrint('[Discovery] DoH→ $dohUrl ?name=$domain');
      final resp = await dio.get<Map<String, dynamic>>(
        dohUrl,
        queryParameters: {'name': domain, 'type': 'TXT'},
      );
      if (kDebugMode) debugPrint('[Discovery] DoH← $dohUrl status=${resp.statusCode}');
      if (resp.statusCode != 200 || resp.data == null) {
        if (kDebugMode) debugPrint('[Discovery] DoH no data: $dohUrl');
        return null;
      }

      final answers = resp.data!['Answer'] as List<dynamic>?;
      if (answers == null || answers.isEmpty) return null;

      if (kDebugMode) debugPrint('[Discovery] DoH answers count: ${answers.length}');
      for (final ans in answers) {
        final raw = (ans as Map<String, dynamic>)['data']
            ?.toString() ?? '';
        final cipher = raw.replaceAll('"', '').trim();
        if (cipher.isEmpty) continue;
        final nodes = _decryptNodes(cipher);
        if (nodes != null && nodes.isNotEmpty) return nodes;
      }
    } catch (_) {}
    return null;
  }

  // ── 轨道2: 多OSS全并行 ──────────────────────────────────

  Future<List<String>?> _fetchFromOss() async {
    if (_ossUrls.isEmpty) return null;

    final completer = Completer<List<String>?>();
    int failed = 0;

    for (final url in _ossUrls) {
      _fetchOssUrl(url).then((nodes) {
        if (nodes != null && nodes.isNotEmpty
            && !completer.isCompleted) {
          if (kDebugMode) debugPrint('[Discovery] OSS hit: $url');
          completer.complete(nodes);
        } else {
          failed++;
          if (failed >= _ossUrls.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        failed++;
        if (failed >= _ossUrls.length && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future.timeout(
      _fetchTimeout,
      onTimeout: () => null,
    );
  }

  Future<List<String>?> _fetchOssUrl(String url) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _fetchTimeout,
        receiveTimeout: _fetchTimeout,
      ));
      if (kDebugMode) debugPrint('[Discovery] OSS→ $url');
      final resp = await dio.get<String>(url);
      if (kDebugMode) debugPrint('[Discovery] OSS← status=${resp.statusCode}');
      if (resp.statusCode != 200 || resp.data == null) {
        if (kDebugMode) debugPrint('[Discovery] OSS no data: $url');
        return null;
      }
      return _decryptNodes(resp.data!.trim());
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] OSS error: $url → $e');
      return null;
    }
  }

  // ── AES-256-CBC 解密 ────────────────────────────────────

  List<String>? _decryptNodes(String base64Cipher) {
    if (kDebugMode) debugPrint('[Discovery] Decrypting: ${base64Cipher.length > 20 ? base64Cipher.substring(0,20) : base64Cipher}...');
    try {
      final key = enc.Key.fromUtf8(_aesKey);
      final iv  = enc.IV.fromUtf8(_aesIv);
      final encrypter = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.cbc),
      );
      final plain = encrypter.decrypt64(base64Cipher, iv: iv);
      final json  = jsonDecode(plain) as Map<String, dynamic>;
      final nodes = (json['nodes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((e) => e.startsWith('http'))
          .toList();
      if (kDebugMode) debugPrint('[Discovery] Decrypted nodes: $nodes');
      return (nodes?.isNotEmpty == true) ? nodes : null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] Decrypt error: $e');
      return null;
    }
  }

  // ── 并发探测最快节点 ────────────────────────────────────

  Future<String?> _probeFastest(List<String> nodes) async {
    if (nodes.isEmpty) return null;
    if (nodes.length == 1) {
      return await _probeNode(nodes.first) ? nodes.first : null;
    }

    final completer = Completer<String?>();
    int failed = 0;

    for (final node in nodes) {
      if (kDebugMode) debugPrint('[Discovery] Probing: $node');
      _probeNode(node).then((ok) {
        if (ok && !completer.isCompleted) {
          completer.complete(node);
        } else {
          failed++;
          if (failed == nodes.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      });
    }

    return completer.future.timeout(
      _probeTimeout + const Duration(seconds: 1),
      onTimeout: () => null,
    );
  }

  Future<bool> _probeNode(String node) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
      ));
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
      final url = '$node$_pingPath';
      if (kDebugMode) debugPrint('[Discovery] Probe URL: $url');
      final resp = await dio.get<dynamic>(
        url,
        options: Options(
          validateStatus: (s) => s == 200,
          sendTimeout: _probeTimeout,
        ),
      );
      final ok = (resp.statusCode ?? 0) == 200;
      if (kDebugMode) debugPrint('[Discovery] Probe $node: ${ok ? "✓" : "✗"} (${resp.statusCode})');
      return ok;
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] Probe $node FAILED: ${e.runtimeType} → $e');
      return false;
    }
  }

  // ── 缓存管理 ────────────────────────────────────────────

  Future<String?> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final node = p.getString(_cacheNodeKey);
      final ms   = p.getInt(_cacheTimeKey);
      if (node == null || ms == null) return null;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms));
      return age < _cacheValid ? node : null;
    } catch (_) { return null; }
  }

  Future<void> _saveCache(String node) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheNodeKey, node);
      await p.setInt(_cacheTimeKey,
          DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cacheNodeKey);
      await p.remove(_cacheTimeKey);
    } catch (_) {}
  }
}
