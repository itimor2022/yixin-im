// 文件用途：提供 in app browser 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 in app browser，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
// 关键声明：in app browser 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
// Web 端退化为系统新窗口，支持 dart:io 的平台使用内嵌 WebView。
export 'in_app_browser_web.dart'
    if (dart.library.io) 'in_app_browser_native.dart';
