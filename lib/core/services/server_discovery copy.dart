import 'dart:async';
//import 'dart:io';
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
    //'cfg.qa853.com',
  ];

  /// DoH 服务商列表（每个 DNS 域名都会被所有 DoH 并行查询）
  static const List<String> _dohProviders = [
    'https://doh.pub/dns-query', // 腾讯DNSPod，国内最快
    'https://dns.alidns.com/resolve', // 阿里云DoH
    'https://doh.360.cn/resolve', // 360 DoH
    'https://cloudflare-dns.com/dns-query', // 海外兜底
  ];

  /// 多个 OSS/CDN 加密配置文件地址（源码内硬编码 fallback）
  ///
  /// 上线运行时的真实 api.txt 地址是从后台数据库 `system_settings.api_txt_url`
  /// 拿到的（首次连上服务端后由 SystemSettingsService 缓存到 SharedPreferences
  /// key = `svc_disc_api_txt_url`），冷启动时 `_effectiveOssUrls()` 会优先读
  /// 该缓存并把这里的常量当作最后的兜底。
  ///
  /// 保持这里非空是为了：
  ///   1. 全新安装、SharedPreferences 还是空的场景仍能引导起来；
  ///   2. 缓存值失效（返回 4xx/超时）时可以自动回落。
  ///
  /// 建议: 阿里云OSS + 腾讯COS + Cloudflare R2，各自独立
  static const List<String> _ossUrls = [
    'https://admin.aopwx.icu/api.txt',
  ];

  /// 与 `SystemSettingsService.kApiTxtUrlPrefsKey` 保持一致。
  /// 单独复制一份常量是为了避免 ServerDiscovery 反向 import ApiClient/Riverpod 相关
  /// 依赖（ServerDiscovery 在应用最早期启动，必须保持零业务依赖）。
  static const String _apiTxtUrlPrefsKey = 'svc_disc_api_txt_url';

  /// AES-256-CBC 密钥（32字节 UTF-8，与加密端一致）
  static const String _aesKey = 'YiXin2024Secure!AppNodeKey@Qa853';

  /// AES IV（16字节 UTF-8，与加密端一致）
  static const String _aesIv = 'YiXinIV@2024Qa85';

  /// 内置保底节点（所有轨道失败时的最后防线）
  static const List<String> _fallbackNodes = [];

  // ── 内部常量 ────────────────────────────────────────────

  static const String _pingPath = '/api/v1/ping';
  static const Duration _probeTimeout = Duration(seconds: 10);
  static const Duration _fetchTimeout = Duration(seconds: 5);
  static const Duration _cacheValid = Duration(hours: 6);
  static const String _cacheNodeKey = 'svc_disc_node';
  static const String _cacheTimeKey = 'svc_disc_time';

  String? _currentNode;
  String? get currentNode => _currentNode;

  /// 最近一次发现的候选节点列表（OSS/DNS 解析结果）
  List<String> _lastCandidates = [];

  /// 所有已知节点：**按 api.txt 原始顺序** + 当前节点（如果不在候选池里）+ 兜底节点
  ///
  /// ⚠️ 顺序策略非常关键，之前实现是把 `_currentNode` 放最前面：
  ///
  /// ```
  /// final set = { _currentNode, ..._lastCandidates, ..._fallbackNodes };
  /// ```
  ///
  /// Set 去重保留"首次插入的位置"，所以用户切了线路 2 (IP) 后，
  /// `_currentNode` 变成 IP，下次进"网络线路"页 IP 会被顶到列表第一条，
  /// UI 上 `"线路 1"` 的槽位就变成了 IP。用户看到"线路 1 被选中"，
  /// 误以为选择又回到了第一条 —— 就是本次要修的 bug。
  ///
  /// 现在的顺序：
  ///   1) `_lastCandidates`（严格按 api.txt 里的行序），
  ///   2) `_currentNode`（仅当它已经不在 api.txt 里时才追加，覆盖"运营刚从
  ///      api.txt 删除了用户正在用的节点"这种极少见的边缘场景），
  ///   3) 兜底节点。
  List<String> get allKnownNodes {
    final result = <String>[];
    final seen = <String>{};
    for (final url in _lastCandidates) {
      if (seen.add(url)) result.add(url);
    }
    final current = _currentNode;
    if (current != null && seen.add(current)) {
      result.add(current);
    }
    for (final url in _fallbackNodes) {
      if (seen.add(url)) result.add(url);
    }
    return result;
  }

  // ── 公开接口 ────────────────────────────────────────────

  /// App 启动时调用，阻塞直到选定节点
  Future<String> initialize() async {
    final cached = await _loadCache();
    if (cached != null) {
      if (kDebugMode) debugPrint('[Discovery] Cache hit: $cached');
      _applyNode(cached);
      // ⭐ Bug fix：缓存命中时也要在后台拉一次 api.txt，把候选池填上，
      //   否则「网络线路」页首次进入 allKnownNodes 只有 1 条（缓存那条），
      //   用户必须点"重新发现"才能看到全部线路。
      unawaited(_refreshCandidatesInBackground());
      return cached;
    }
    return _discover();
  }

  /// 手动指定节点并缓存（来自用户手动选择）
  Future<void> clearCacheAndSet(String node) async {
    await _saveCache(node);
    _applyNode(node);
  }

  /// 强制重新发现（网络错误后调用）
  ///
  /// ⚠️ 这个方法会重跑完整发现流程，并按"用户是否已经手动选过一个仍然有效的节点"
  /// 决定要不要覆盖 _currentNode：
  ///   - 用户选过 IP 且 IP 仍在新列表里 → 保留 IP，不覆盖
  ///   - 用户没有选过 / 之前选的节点已经从 api.txt 里删了 → 走默认（最快节点）
  /// 这样"用户明确切到 IP 后点重新发现，又被自动切回域名"的老 bug 就消失了。
  Future<String> forceRefresh() async {
    await _clearCache();
    return _discover();
  }

  /// 只刷新"候选节点池"，**不**改变当前正在使用的节点。
  /// 网络线路页的"重新发现"按钮走这一路，而不是 forceRefresh —— 后者会
  /// 覆盖 _currentNode，让用户手动选的 IP 被最快节点顶掉。
  Future<void> refreshCandidatesOnly() async {
    try {
      final nodes = await _fetchNodeList();
      if (nodes.isEmpty) return;
      _lastCandidates = List<String>.from(nodes);
      if (kDebugMode) {
        debugPrint('[Discovery] refreshCandidatesOnly → $_lastCandidates');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] refreshCandidatesOnly error: $e');
    }
  }

  /// initialize 缓存命中时的"背景填池"逻辑，效果等价于 refreshCandidatesOnly，
  /// 但即使失败也悄悄吞掉；单独一个方法方便日志区分调用来源。
  Future<void> _refreshCandidatesInBackground() async {
    try {
      final nodes = await _fetchNodeList();
      if (nodes.isEmpty) return;
      _lastCandidates = List<String>.from(nodes);
      if (kDebugMode) {
        debugPrint(
            '[Discovery] Background candidate refresh → $_lastCandidates');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] BG candidate refresh error: $e');
    }
  }

  // ── 发现主流程 ──────────────────────────────────────────

  Future<String> _discover() async {
    // api.txt 拉取已禁用，直接使用硬编码 fallback
    return '';
    final t0 = DateTime.now();
    if (kDebugMode) debugPrint('[Discovery] ═══ Starting discovery at $t0 ═══');
    final nodes = await _fetchNodeList();

    if (nodes.isEmpty) {
      throw Exception('No reachable server node. Please check your network.');
    }

    if (kDebugMode) debugPrint('[Discovery] Initial Fetch From TXT: $nodes');

    // 1. 等待所有节点测速完成，拿到真正活着的节点列表
    final validNodes = await _probeValidNodes(nodes);

    if (validNodes.isNotEmpty) {
      // 💡 只有有效的、能 Ping 通的线路，才同步给前端候选池
      _lastCandidates = List<String>.from(validNodes);
    } else {
      // ⚠️ 探测全部失败时不要只保留 1 条。以前 `_lastCandidates = [nodes.first]`
      // 会让 `allKnownNodes` 收窄成 1 条，导致「网络线路」页 `_init` 触发
      // 自动 rediscover 死循环、以及离开页面仍在后台 ping 的问题。
      // 现在把 api.txt 里的全部候选都保留下来，让用户在测速页看到全部线路
      // （即便标红为"不可用"也不会触发循环重发现）。
      _lastCandidates = List<String>.from(nodes);
    }

    // ⭐ Bug fix：不再无脑挑 _lastCandidates.first。
    //   如果用户之前手动切到了 IP（_currentNode = ip 并且仍在新拉到的列表里），
    //   保留这个选择，不要因为"域名 ping 得更快"就把它顶回去。
    //   只有当 _currentNode 为空 / 或者用户选的节点已经从 api.txt 里被删除时，
    //   才走默认策略（第一条）。
    final String selected;
    if (_currentNode != null && _lastCandidates.contains(_currentNode)) {
      selected = _currentNode!;
      if (kDebugMode) {
        debugPrint('[Discovery] Preserving user selection: $selected');
      }
    } else {
      selected = _lastCandidates.first;
    }

    if (kDebugMode)
      debugPrint(
          '[Discovery] Selected: $selected, All Valid Nodes For UI: $_lastCandidates');
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
    // Future<void>.delayed(const Duration(seconds: 5), () async {
    //   try {
    //    // await _clearCache();
    //     final node = await _discover();
    //     if (node != _currentNode) {
    //       if (kDebugMode) debugPrint('[Discovery] BG switched to $node');
    //     }
    //   } catch (e) {
    //     if (kDebugMode) debugPrint('[Discovery] BG refresh error: $e');
    //   }
    // });
  }

  // ── 双轨并行获取节点列表 ────────────────────────────────

  Future<List<String>> _fetchNodeList() async {
    final List<String> resultNodes = [];

    // 1. 尝试从 OSS (api.txt) 获取
    try {
      if (kDebugMode) debugPrint('[Discovery] Fetching from OSS...');
      final ossNodes = await _fetchFromOss();
      if (ossNodes != null && ossNodes.isNotEmpty) {
        resultNodes.addAll(ossNodes);
        if (kDebugMode)
          debugPrint('[Discovery] OSS Track success: $resultNodes');
        return resultNodes.toSet().toList(); // 去重返回
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] OSS Track error: $e');
    }

    // 2. 如果 OSS 失败了，尝试从 DNS 获取
    try {
      if (kDebugMode) debugPrint('[Discovery] Fetching from DNS...');
      final dnsNodes = await _fetchFromDns();
      if (dnsNodes != null && dnsNodes.isNotEmpty) {
        resultNodes.addAll(dnsNodes);
        if (kDebugMode)
          debugPrint('[Discovery] DNS Track success: $resultNodes');
        return resultNodes.toSet().toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] DNS Track error: $e');
    }

    // ⚠️ 兜底策略：两条轨道都失败时，只把「当前节点」（如果有）当作候选，
    //   不再硬编码测试服 URL。硬编码 fallback 会掩盖服务发现失败，让线上问题
    //   看起来"网络还好"，实际上 api.txt 已经拉不到了。
    //   完全没有当前节点时（首次冷启动 + 双轨全跪）就返回空，让 _discover 抛
    //   "No reachable server node"，客户端会显性报错。
    if (kDebugMode) {
      debugPrint('[Discovery] Both tracks failed. '
          'Falling back to current node (if any).');
    }
    return _currentNode != null ? [_currentNode!] : <String>[];
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
          if (nodes != null && nodes.isNotEmpty && !completer.isCompleted) {
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
      if (kDebugMode)
        debugPrint('[Discovery] DoH← $dohUrl status=${resp.statusCode}');
      if (resp.statusCode != 200 || resp.data == null) {
        if (kDebugMode) debugPrint('[Discovery] DoH no data: $dohUrl');
        return null;
      }

      final answers = resp.data!['Answer'] as List<dynamic>?;
      if (answers == null || answers.isEmpty) return null;

      if (kDebugMode)
        debugPrint('[Discovery] DoH answers count: ${answers.length}');
      for (final ans in answers) {
        final raw = (ans as Map<String, dynamic>)['data']?.toString() ?? '';
        final cipher = raw.replaceAll('"', '').trim();
        if (cipher.isEmpty) continue;
        final nodes = _decryptNodes(cipher);
        if (nodes != null && nodes.isNotEmpty) return nodes;
      }
    } catch (_) {}
    return null;
  }

  // ── 轨道2: 多OSS全并行 ──────────────────────────────────

  /// 合并"数据库下发的 api.txt 地址（SharedPreferences 缓存）"和"源码硬编码 fallback"，
  /// 数据库地址排在最前面确保优先命中，同时去重。
  Future<List<String>> _effectiveOssUrls() async {
    final result = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_apiTxtUrlPrefsKey)?.trim();
      if (cached != null && cached.isNotEmpty && cached.startsWith('http')) {
        result.add(cached);
        if (kDebugMode)
          debugPrint('[Discovery] OSS use DB-cached url: $cached');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] OSS read prefs error: $e');
    }
    result.addAll(_ossUrls);
    return result.toList();
  }

  Future<List<String>?> _fetchFromOss() async {
    final ossUrls = await _effectiveOssUrls();
    if (ossUrls.isEmpty) return null;

    final completer = Completer<List<String>?>();
    int failed = 0;

    for (final url in ossUrls) {
      _fetchOssUrl(url).then((nodes) {
        if (nodes != null && nodes.isNotEmpty && !completer.isCompleted) {
          if (kDebugMode) debugPrint('[Discovery] OSS hit: $url');
          completer.complete(nodes);
        } else {
          failed++;
          if (failed >= ossUrls.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        failed++;
        if (failed >= ossUrls.length && !completer.isCompleted) {
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
      if (resp.statusCode != 200 || resp.data == null) return null;

      return _parseLineByLineNodes(resp.data!.trim());
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] OSS error: $url → $e');
      return null;
    }
  }

  List<String>? _parseLineByLineNodes(String rawText) {
    try {
      if (kDebugMode) debugPrint('[Discovery] Raw text received: \n$rawText');
      final lines = rawText.split(RegExp(r'[\r\n\s,;]+'));

      // 允许 api.txt 里同时出现三种写法：
      //   1) https://api.example.com
      //   2) http://api.example.com
      //   3) 1.2.3.4  或  1.2.3.4:8081  或  1.2.3.4:8081/path
      // 第三种没有协议前缀，之前的 `startsWith('http')` 会直接丢掉。
      // 现在检测到裸 IPv4（可选端口和路径）就自动补 `http://`。
      // 想走 HTTPS 的裸 IP 仍然要写 `https://1.2.3.4`——因为浏览器/APK
      // 对 IP 的 TLS 证书校验很严，业务代码没法帮它猜。
      final ipPattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d+)?(\/.*)?$');

      final nodes = lines
          .map((e) => e.trim().replaceAll('"', '').replaceAll("'", ''))
          .where((e) => e.isNotEmpty && !e.endsWith('.txt'))
          .map((e) {
            if (!e.startsWith('http') && ipPattern.hasMatch(e)) {
              return 'http://$e';
            }
            return e;
          })
          .where((e) => e.startsWith('http'))
          .toSet()
          .toList();

      if (kDebugMode)
        debugPrint('[Discovery] Successfully parsed nodes: $nodes');
      return nodes.isNotEmpty ? nodes : null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Discovery] Parse text error: $e');
      return null;
    }
  }

  // ── AES-256-CBC 解密 ────────────────────────────────────

  List<String>? _decryptNodes(String base64Cipher) {
    if (base64Cipher.startsWith('http')) {
      return _parseLineByLineNodes(base64Cipher);
    }

    try {
      final key = enc.Key.fromUtf8(_aesKey);
      final iv = enc.IV.fromUtf8(_aesIv);
      final encrypter = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.cbc),
      );
      final plain = encrypter.decrypt64(base64Cipher, iv: iv);
      final json = jsonDecode(plain) as Map<String, dynamic>;
      final nodes = (json['nodes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((e) => e.startsWith('http'))
          .toList();
      return (nodes?.isNotEmpty == true) ? nodes : null;
    } catch (e) {
      return _parseLineByLineNodes(base64Cipher);
    }
  }

  // ── 并发探测最快节点 ────────────────────────────────────

  Future<List<String>> _probeValidNodes(List<String> nodes) async {
    if (nodes.isEmpty) return [];

    final List<String> activeNodes = [];
    final List<Future<void>> futures = [];

    for (final node in nodes) {
      if (kDebugMode) debugPrint('[Discovery] Probing: $node');
      final future = _probeNode(node).then((ok) {
        if (ok) {
          activeNodes.add(node); // 💡 谁通畅谁就进列表，不争抢第一
        }
      });
      futures.add(future);
    }

    // 💡 等待所有人探测完毕（或者整体超时）
    await Future.wait(futures).timeout(
      _probeTimeout + const Duration(seconds: 1),
      onTimeout: () => [],
    );

    return activeNodes;
  }

  Future<bool> _probeNode(String node) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
      ));

      // 🚀 核心修复：如果是 Web 环境，绝对不能强转 IOHttpClientAdapter
      if (kIsWeb) {
        // Web 端由浏览器沙箱直接接管 HTTPS 证书校验，无需也不允许手动忽略证书
        if (kDebugMode)
          debugPrint(
              '[Discovery] Running on Web, skipping IOHttpClientAdapter adjustment.');
      } else {
        // Android / iOS 等原生平台保留原有证书跳过逻辑
        (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
            (client) {
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }

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
      if (kDebugMode)
        debugPrint(
            '[Discovery] Probe $node: ${ok ? "✓" : "✗"} (${resp.statusCode})');
      return ok;
    } catch (e) {
      if (kDebugMode)
        debugPrint('[Discovery] Probe $node FAILED: ${e.runtimeType} → $e');
      return false;
    }
  }

  // ── 缓存管理 ────────────────────────────────────────────

  Future<String?> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final node = p.getString(_cacheNodeKey);
      final ms = p.getInt(_cacheTimeKey);
      if (node == null || ms == null) return null;
      final age =
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
      return age < _cacheValid ? node : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(String node) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheNodeKey, node);
      await p.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
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
