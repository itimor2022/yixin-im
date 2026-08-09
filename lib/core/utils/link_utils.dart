// 文件用途：提供 LinkUtils 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 LinkUtils 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'package:flutter/foundation.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/in_app_browser.dart';

// 关键声明：link utils 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
/// 链接工具类
class LinkUtils {
  /// URL 正则表达式
  static final RegExp urlRegex = RegExp(
    r'https?://[^\s<>]+|www\.[^\s<>]+',
    caseSensitive: false,
  );

  /// 检查文本是否包含链接
  static bool containsLink(String text) {
    return urlRegex.hasMatch(text);
  }

  /// 提取文本中的所有链接
  static List<String> extractLinks(String text) {
    return urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  /// 打开链接
  static Future<void> openLink(BuildContext context, String url) async {
    // 确保 URL 有协议前缀
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    final uri = Uri.parse(finalUrl);
    
    // 特殊协议使用系统处理
    if (uri.scheme == 'tel' || uri.scheme == 'mailto' || uri.scheme == 'sms') {
      await launchUrl(uri);
      return;
    }

    // Web 端不支持 WebView，直接在新标签页打开
    if (kIsWeb) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    // 原生平台使用内置浏览器
    if (context.mounted) {
      await InAppBrowser.open(context, finalUrl);
    }
  }

  /// 构建带链接高亮的 TextSpan
  static TextSpan buildLinkText({
    required String text,
    required TextStyle defaultStyle,
    required TextStyle linkStyle,
    required BuildContext context,
  }) {
    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final match in urlRegex.allMatches(text)) {
      // 添加链接前的普通文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      // 添加链接
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => openLink(context, url),
      ));

      lastEnd = match.end;
    }

    // 添加剩余文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: defaultStyle,
      ));
    }

    return TextSpan(children: spans);
  }

  /// 构建带链接的 RichText Widget
  static Widget buildLinkTextWidget({
    required String text,
    required TextStyle defaultStyle,
    Color? linkColor,
    required BuildContext context,
  }) {
    final linkStyle = defaultStyle.copyWith(
      color: linkColor ?? Colors.blue,
      decoration: TextDecoration.underline,
      decorationColor: linkColor ?? Colors.blue,
    );

    if (!containsLink(text)) {
      return Text(text, style: defaultStyle);
    }

    return RichText(
      text: buildLinkText(
        text: text,
        defaultStyle: defaultStyle,
        linkStyle: linkStyle,
        context: context,
      ),
    );
  }
}
