// 文件用途：实现 ForwardBundlePreviewPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 ForwardBundlePreviewPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/time_zone_refresh_service.dart';
import '../models/forward_bundle_snapshot.dart';

// 关键声明：forward bundle preview page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class ForwardBundlePreviewPage extends StatelessWidget {
  final ForwardBundleSnapshot bundle;

  const ForwardBundlePreviewPage({super.key, required this.bundle});

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final english = AppLocalizations.of(context).language == AppLanguage.en;
    return Scaffold(
      appBar: AppBar(title: Text(bundle.title)),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: bundle.items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final item = bundle.items[index];
          return ListTile(
            leading: CircleAvatar(
              child: Text(
                item.senderName.isEmpty
                    ? '?'
                    : item.senderName.characters.first,
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(item.senderName)),
                Text(
                  DateFormat('MM-dd HH:mm')
                      .format(toCurrentLocalTime(item.createdAt)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.preview(english: english),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: item.nestedBundle == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
            onTap: item.nestedBundle == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ForwardBundlePreviewPage(
                          bundle: item.nestedBundle!,
                        ),
                      ),
                    ),
          );
        },
      ),
    );
  }
}
