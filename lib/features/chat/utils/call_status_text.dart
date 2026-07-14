/// 通话消息文案规范化
///
/// 历史遗留：早期后端把通话结束状态直接以英文小写落库
/// （如 `视频通话 cancelled` / `语音通话 rejected`），
/// 前端会在气泡和会话列表预览里露出这些原始英文字样，非常突兀。
///
/// 本工具在渲染前把末尾的英文状态词翻译成对应的中文短语，
/// 之后气泡组件 [_parseCallContent] / 会话列表预览
/// 就能命中它们已有的中文关键字判断分支，样式表现一致。
///
/// 已经是中文状态或数字时长（`视频通话 00:26`）格式的消息不会被改动。
library;

/// 把"通话 + 英文状态"格式的字符串规范化成中文
///
/// 覆盖：`cancelled / canceled / declined / rejected / no_answer /
/// no answer / noanswer / busy / missed / timeout / unanswered / failed`
///
/// 只匹配「视频通话 / 语音通话 + 空白 + 英文小写状态词 + 末尾」这种严格
/// 的形状，避免把消息正文里的英文单词误伤。
String normalizeCallStatusText(String content) {
  if (content.isEmpty) return content;

  const stateMap = <String, String>{
    'cancelled': '已取消',
    'canceled': '已取消',
    'declined': '已拒绝',
    'rejected': '已拒绝',
    'no_answer': '未接听',
    'no answer': '未接听',
    'noanswer': '未接听',
    'busy': '对方忙',
    'missed': '未接',
    'timeout': '未接通',
    'unanswered': '未接听',
    'failed': '未接通',
  };

  for (final entry in stateMap.entries) {
    final re = RegExp(
      r'(视频通话|语音通话)\s+' + entry.key + r'\s*$',
      caseSensitive: false,
    );
    if (re.hasMatch(content)) {
      // replaceFirst 不支持捕获组回填，改用 replaceFirstMapped
      return content.replaceFirstMapped(
        re,
        (m) => '${m.group(1)} ${entry.value}',
      );
    }
  }
  return content;
}
