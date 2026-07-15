import 'dart:io';

import 'package:flutter/foundation.dart';

/// 只匹配点分十进制 IPv4；纯 IPv6 场景走域名路径不进这里。
final RegExp _ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

bool isIpv4Host(String host) => _ipv4Pattern.hasMatch(host);

/// ─────────────────────────────────────────────────────────────
/// 场景 & 目的
/// -------------------------------------------------------------
/// api.txt 里同时下发：
///   - `https://api.example.com`      ← 主线路（域名）
///   - `https://1.2.3.4:8123`         ← 容灾线路（ZeroSSL 签的 IP 证书）
///
/// 浏览器 (Web) 能正常访问 IP 那条，因为浏览器：
///   1. 内置 Sectigo/USERTrust 全套根
///   2. 会做 AIA fetching 自动补中间证书
///   3. 对 IP SAN 的编码兼容性好
///
/// 但 APK / iOS 走 dart:io 的 HttpClient (Dio 和 WebSocket 底层都是它)
/// 时经常挂：
///   - 服务器只挂了叶子证书没挂 fullchain，OS 找不到 Sectigo 中间证书
///   - Android 系统 CA 里没有 ZeroSSL 用的具体那张 root
///   - IP SAN 的 X.509 编码 OS TLS 栈解析姿势和浏览器不同
///
/// 用户可见现象：测速页 IP 那条显示"可用"（ping 代码有 badCertificate bypass），
/// 但选中它之后登录 / 拉验证码全部失败 —— 就是本 Overrides 要解的问题。
/// ─────────────────────────────────────────────────────────────
/// 安全边界
/// -------------------------------------------------------------
/// 不做全局 `badCertificateCallback = true`。那是之前安全审计里被点名的漏洞。
/// 这里只对**裸 IPv4** host 放行证书校验：
///   - `api.legg.click`   → 系统 CA 严格校验（不放行）
///   - `1.2.3.4`          → 允许证书校验失败继续（放行）
///
/// 理由：
///   - 域名指向的一般是生产环境，必须严格；
///   - IP 一般是运营人员手填的容灾/内网线路，用户是在测速页里主动选它的，
///     可以接受略弱一点的传输层校验，否则这条线路根本用不了。
/// ─────────────────────────────────────────────────────────────
/// 使用
/// -------------------------------------------------------------
/// 在 native 的 bootstrap 里、**任何网络代码执行前**放：
///
///   ```dart
///   HttpOverrides.global = IpTolerantHttpOverrides();
///   ```
///
/// Web bootstrap 不需要（dart:io 在 web 是 stub，`HttpOverrides` 也不会
/// 影响浏览器的 XHR/WebSocket/Fetch）。
class IpTolerantHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      final relaxed = isIpv4Host(host);
      if (kDebugMode) {
        debugPrint(
          '[TLS] cert-fail $host:$port '
          'subject=${cert.subject} issuer=${cert.issuer} '
          '→ ${relaxed ? "BYPASS (ip)" : "REJECT (domain)"}',
        );
      }
      return relaxed;
    };
    return client;
  }
}
