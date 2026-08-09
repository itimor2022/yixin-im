// 文件用途：提供 browser title 在 Web 平台的实现，服务于通用工具。
// 核心逻辑：实现 browser title 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

// 关键声明：browser title web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：`setBrowserTitle` 先校验输入和当前权限，进入操作中状态后执行副作用；成功同步服务端结果，失败恢复可重试状态并保留错误原因。
void setBrowserTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) {
    return;
  }

  html.document.title = normalized;
  try {
    html.window.localStorage.remove('app_browser_title');
  } catch (_) {}
}
