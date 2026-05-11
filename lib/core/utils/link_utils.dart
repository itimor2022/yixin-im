import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/in_app_browser.dart';

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
