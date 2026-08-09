// 文件用途：实现 ReportPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 ReportPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/theme/app_colors.dart';

// 关键声明：report page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class ReportPage extends ConsumerStatefulWidget {
  final String targetId;
  final String targetType;
  final String targetName;
  final String? chatId;

  const ReportPage({
    super.key,
    required this.targetId,
    required this.targetType,
    required this.targetName,
    this.chatId,
  });

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  final _descriptionController = TextEditingController();
  String? _reason;
  bool _submitting = false;

  static const _reasons = <(String, IconData)>[
    ('spam', Icons.mail_outline),
    ('fake', Icons.warning_amber_outlined),
    ('violence', Icons.dangerous_outlined),
    ('porn', Icons.block),
    ('harassment', Icons.person_off_outlined),
    ('copyright', Icons.copyright),
    ('other', Icons.more_horiz),
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  String _text({required String zhCN, String? zhTW, required String en}) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'spam':
        return _text(zhCN: '垃圾信息', zhTW: '垃圾訊息', en: 'Spam');
      case 'fake':
        return _text(
            zhCN: '虚假信息或诈骗', zhTW: '虛假資訊或詐騙', en: 'Fraud or false information');
      case 'violence':
        return _text(
            zhCN: '暴力或危险内容',
            zhTW: '暴力或危險內容',
            en: 'Violence or dangerous content');
      case 'porn':
        return _text(zhCN: '色情内容', zhTW: '色情內容', en: 'Adult content');
      case 'harassment':
        return _text(
            zhCN: '骚扰或欺凌', zhTW: '騷擾或欺凌', en: 'Harassment or bullying');
      case 'copyright':
        return _text(zhCN: '侵犯版权', zhTW: '侵犯版權', en: 'Copyright infringement');
      default:
        return _text(zhCN: '其他', en: 'Other');
    }
  }

  IconData get _targetIcon {
    switch (widget.targetType) {
      case 'user':
        return Icons.person_outline;
      case 'group':
        return Icons.group_outlined;
      case 'channel':
        return Icons.campaign_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  Future<void> _submit() async {
    if (_reason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            zhCN: '请选择举报原因',
            zhTW: '請選擇檢舉原因',
            en: 'Please select a reason',
          )),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final response = await ref.read(apiClientProvider).post(
        '/report',
        data: {
          'target_id': widget.targetId,
          'target_type': widget.targetType,
          if (widget.chatId?.isNotEmpty == true) 'chat_id': widget.chatId,
          'reason': _reason,
          'description': _descriptionController.text.trim(),
        },
      );
      if (!mounted) return;
      if (!response.isSuccess) {
        final message = localizeServerMessage(
          response.message,
          fallbackZhCN: '举报提交失败，请重试',
          fallbackZhTW: '檢舉提交失敗，請重試',
          fallbackEn: 'Report submission failed',
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            zhCN: '举报已提交，我们会尽快处理',
            zhTW: '檢舉已提交，我們會盡快處理',
            en: 'Report submitted for review',
          )),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            zhCN: '举报提交失败，请重试',
            zhTW: '檢舉提交失敗，請重試',
            en: 'Report submission failed',
          )),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final surface = AppColors.surfaceFor(context);
    final divider = AppColors.dividerFor(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon:
              Icon(Icons.arrow_back_ios, color: AppColors.primaryFor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _text(zhCN: '举报', zhTW: '檢舉', en: 'Report'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_text(zhCN: '提交', en: 'Submit')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(_targetIcon, color: AppColors.textSecondaryFor(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.targetName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16, color: AppColors.textPrimaryFor(context)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
            child: Text(
              _text(zhCN: '选择举报原因', zhTW: '選擇檢舉原因', en: 'Select a reason'),
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondaryFor(context)),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                for (var index = 0; index < _reasons.length; index++) ...[
                  RadioListTile<String>(
                    value: _reasons[index].$1,
                    groupValue: _reason,
                    onChanged: (value) => setState(() => _reason = value),
                    secondary: Icon(_reasons[index].$2),
                    title: Text(_reasonLabel(_reasons[index].$1)),
                  ),
                  if (index != _reasons.length - 1)
                    Divider(height: 1, indent: 56, color: divider),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
            child: Text(
              _text(
                  zhCN: '补充说明（可选）',
                  zhTW: '補充說明（可選）',
                  en: 'Additional details (optional)'),
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondaryFor(context)),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(8)),
            child: TextField(
              controller: _descriptionController,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _text(
                  zhCN: '请描述具体问题',
                  zhTW: '請描述具體問題',
                  en: 'Describe the issue',
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
