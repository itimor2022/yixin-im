// 文件用途：提供 in app browser 在 Web 平台的实现，服务于跨模块共享能力。
// 核心逻辑：实现 InAppBrowser 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// 关键声明：in app browser web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
class InAppBrowser extends StatelessWidget {
  final String url;
  final String? title;
  final bool hideAddressBar;

  const InAppBrowser({
    super.key,
    required this.url,
    this.title,
    this.hideAddressBar = false,
  });

  static Future<void> open(
    BuildContext context,
    String url, {
    String? title,
    bool hideAddressBar = false,
  }) async {
    // Web 不嵌套 WebView，统一交给浏览器新标签页；页面标题和地址栏选项不生效。
    final uri = Uri.tryParse(_normalizeUrl(url));
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  static String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    // 作为路由组件使用时，首帧后打开新标签并关闭当前占位路由。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      open(context, url, title: title, hideAddressBar: hideAddressBar);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return const SizedBox.shrink();
  }
}
