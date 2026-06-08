import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import 'package:url_launcher/url_launcher.dart';


/// 常见问题页面
class FAQPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const FAQPage({super.key, this.isDesktopPanel = false});

  @override
  ConsumerState<FAQPage> createState() => _FAQPageState();
}

class _FAQPageState extends ConsumerState<FAQPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<FAQCategory> _buildCategories(String appName) => [
    FAQCategory(
      name: '入门指南',
      icon: Icons.rocket_launch_rounded,
      color: const Color(0xFF007AFF),
      questions: [
        FAQItem(
          question: '如何注册账号？',
          answer: '打开$appName，点击「注册」，输入用户名、密码即可完成注册。用户名注册后不可修改，请谨慎填写。',
        ),
        FAQItem(
          question: '如何添加联系人？',
          answer:
              '在「联系人」页点击右上角「+」，进入「搜索」后输入用户名或关键词，找到用户后点击「添加」即可。也可通过搜索公开群组、频道加入。',
        ),
        FAQItem(
          question: '如何创建群组？',
          answer: '在「联系人」页点击「新建群组」，选择要邀请的联系人并设置群名称即可创建。创建后可在群内管理成员、设置角色与禁言。',
        ),
        FAQItem(
          question: '如何创建频道？',
          answer: '在「联系人」页点击「新建频道」，设置频道名称与说明即可创建。频道支持公开订阅，成员可查看频道内消息。',
        ),
      ],
    ),
    FAQCategory(
      name: '联系人',
      icon: Icons.people_rounded,
      color: const Color(0xFF5856D6),
      questions: [
        FAQItem(
          question: '联系人列表为什么是空的？',
          answer:
              '若已设置官方默认联系人，进入 App 后会自动同步到列表。也可在「联系人」页点击「+」搜索用户添加。添加时若提示「已是联系人」，返回联系人页刷新即可看到。',
        ),
        FAQItem(
          question: '在线状态会实时更新吗？',
          answer: '会。联系人的「在线」与「最近在线 xx 前」会随对方上线/下线实时更新，无需手动刷新。',
        ),
        FAQItem(
          question: '如何修改联系人备注？',
          answer: '进入该联系人的聊天或资料页，在设置/资料中可修改备注，备注仅自己可见。',
        ),
      ],
    ),
    FAQCategory(
      name: '聊天与消息',
      icon: Icons.chat_bubble_rounded,
      color: const Color(0xFFFF9500),
      questions: [
        FAQItem(
          question: '消息发送失败怎么办？',
          answer:
              '请检查网络是否正常。若网络正常仍无法发送，可尝试：\n\n1. 下拉聊天列表刷新\n2. 重启应用\n3. 检查是否被对方屏蔽',
        ),
        FAQItem(
          question: '如何撤回消息？',
          answer: '长按要撤回的消息，在弹出菜单中选择「撤回」。仅自己发送的消息可撤回，且需在限定时间内操作。',
        ),
        FAQItem(
          question: '如何发送图片、语音、文件？',
          answer: '在聊天输入框旁点击「+」，可选择图片、拍照、视频、语音、文件等。图片与文件从本机选择后即可发送。',
        ),
        FAQItem(
          question: '如何编辑或删除已发消息？',
          answer: '长按消息可选择「编辑」或「删除」。编辑会保留记录，删除仅对自己隐藏，对方仍可能看到。',
        ),
        FAQItem(
          question: '聊天记录可以清空吗？',
          answer: '在聊天详情或群/频道设置中可找到「清空聊天记录」。清空后本地与服务器该会话的消息会被删除，且不可恢复。',
        ),
      ],
    ),
    FAQCategory(
      name: '动态广场',
      icon: Icons.explore_rounded,
      color: const Color(0xFFFF2D55),
      questions: [
        FAQItem(
          question: '如何发布动态？',
          answer: '在「动态」页点击右上角「+」，可发布文字、图片或视频。可设置可见范围：公开、仅联系人、部分可见或私密。',
        ),
        FAQItem(
          question: '如何点赞和评论？',
          answer: '在动态卡片上可点赞；点击评论图标可查看评论并发表评论。点赞与评论会收到通知。',
        ),
        FAQItem(
          question: '如何屏蔽某条动态或用户？',
          answer: '长按动态卡片，在菜单中选择「屏蔽该动态」或「屏蔽该用户」。屏蔽后其动态将不再出现在你的列表中。',
        ),
        FAQItem(
          question: '如何举报不当内容？',
          answer: '长按动态或消息，选择「举报」，填写原因后提交。我们会尽快处理举报内容。',
        ),
      ],
    ),
    FAQCategory(
      name: '隐私与安全',
      icon: Icons.shield_rounded,
      color: const Color(0xFF34C759),
      questions: [
        FAQItem(
          question: '聊天记录安全吗？',
          answer: '消息经服务器加密传输与存储，仅会话成员可查看。请勿向他人透露账号密码，并建议定期修改密码。',
        ),
        FAQItem(
          question: '如何屏蔽某人？',
          answer: '打开与该用户的聊天，点击右上角进入资料/设置，选择「屏蔽用户」。也可在「设置 > 屏蔽名单」中管理已屏蔽用户。',
        ),
        FAQItem(
          question: '如何管理设备和会话？',
          answer: '在「设置」中可查看「设备管理」与「会话管理」，对已登录设备或会话进行下线、终止，保障账号安全。',
        ),
        FAQItem(
          question: '如何删除我的账号？',
          answer: '在「设置」中找到「账号与安全」或「删除账号」入口。删除后账号及关联数据将不可恢复，请谨慎操作。',
        ),
      ],
    ),
    FAQCategory(
      name: '账号与设置',
      icon: Icons.settings_rounded,
      color: const Color(0xFFAF52DE),
      questions: [
        FAQItem(
          question: '如何修改昵称和头像？',
          answer: '进入「设置 > 个人资料」可修改昵称、头像、简介等。头像支持拍照或从相册选择。',
        ),
        FAQItem(
          question: '如何修改密码？',
          answer: '登录后进入「设置」，在「账号与安全」或「修改密码」中，输入原密码与新密码即可修改。',
        ),
        FAQItem(
          question: '如何设置聊天背景和字体？',
          answer: '在「设置 > 聊天设置」中可更换聊天背景（纯色、渐变或自定义图片），以及调整字体大小等。',
        ),
        FAQItem(
          question: '如何开启/关闭通知？',
          answer: '在「设置 > 通知设置」中可管理消息通知、声音与震动。同时请在系统设置中允许$appName发送通知。',
        ),
      ],
    ),
  ];

  List<FAQCategory> _filteredCategories(String appName) {
    final categories = _buildCategories(appName);
    if (_searchQuery.isEmpty) return categories;

    return categories
        .map((category) {
          final filteredQuestions = category.questions
              .where(
                (q) =>
                    q.question.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ||
                    q.answer.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();

          if (filteredQuestions.isEmpty) return null;

          return FAQCategory(
            name: category.name,
            icon: category.icon,
            color: category.color,
            questions: filteredQuestions,
          );
        })
        .whereType<FAQCategory>()
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final appName = ref.watch(systemSettingsProvider).valueOrNull?.displayName ?? kDefaultAppDisplayName;
    final filteredCategories = _filteredCategories(appName);

    // 桌面端面板模式：只返回内容，不需要 Scaffold 和 AppBar
    if (widget.isDesktopPanel) {
      return _buildBodyContent(isDark, l10n);
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0D1117)
          : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.faqTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBodyContent(isDark, l10n),
      floatingActionButton: Tooltip(
        message: l10n.contactSupport,
        child: FloatingActionButton(
          onPressed: () => _contactSupport(l10n),
          backgroundColor: AppColors.primary,
          child: const Icon(
            Icons.headset_mic_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildBodyContent(bool isDark, AppLocalizations l10n) {
    final appName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
        kDefaultAppDisplayName;
    final filteredCategories = _filteredCategories(appName);

    return Column(
      children: [
        // 搜索框
        Container(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: l10n.searchQuestion,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),

        // 问题列表
        Expanded(
          child: filteredCategories.isEmpty
              ? _buildEmptyState(isDark, l10n)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredCategories.length,
                  itemBuilder: (context, index) {
                    final category = filteredCategories[index];
                    return _CategoryCard(
                      category: category,
                      isDark: isDark,
                      onQuestionTap: (question) => _showAnswer(question),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noQuestionsFound,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _contactSupport(l10n),
            child: Text(l10n.contactSupportForHelp),
          ),
        ],
      ),
    );
  }

  void _showAnswer(FAQItem question) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      question.question,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      question.answer,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 反馈
                    Text(
                      l10n.wasThisHelpful,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _FeedbackButton(
                          icon: Icons.thumb_up_outlined,
                          label: l10n.helpful,
                          onTap: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.thankYouFeedback),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        _FeedbackButton(
                          icon: Icons.thumb_down_outlined,
                          label: l10n.notHelpful,
                          onTap: () {
                            Navigator.pop(context);
                            _contactSupport(l10n);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOnlineService() async {
    String url = '';
    try {
      final s = await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true)
          .timeout(const Duration(seconds: 3));
      url = s.customerServiceUrl.trim();
    } catch (_) {
      // 强刷超时/失败:回退本地缓存
      final cached = await loadCachedSystemSettings();
      url = cached?.customerServiceUrl.trim() ?? '';
    }
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('客服暂未配置，请稍后再试')),
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('客服地址无效')),
        );
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开客服链接')),
        );
      }
    }
  }

  void _contactSupport(AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.headset_mic_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.contactSupport,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.supportDescription,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                _ContactOption(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: l10n.onlineSupport,
                  subtitle: l10n.onlineSupportHint,
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(context);
                    _openOnlineService();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FAQCategory {
  final String name;
  final IconData icon;
  final Color color;
  final List<FAQItem> questions;

  FAQCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.questions,
  });
}

class FAQItem {
  final String question;
  final String answer;

  FAQItem({required this.question, required this.answer});
}

class _CategoryCard extends StatelessWidget {
  final FAQCategory category;
  final bool isDark;
  final Function(FAQItem) onQuestionTap;

  const _CategoryCard({
    required this.category,
    required this.isDark,
    required this.onQuestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: category.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(category.icon, color: category.color, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  category.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                Text(
                  '${category.questions.length} 个问题',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          ...category.questions.asMap().entries.map((entry) {
            final index = entry.key;
            final question = entry.value;
            final isLast = index == category.questions.length - 1;

            return Column(
              children: [
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withOpacity(0.06),
                ),
                InkWell(
                  onTap: () => onQuestionTap(question),
                  borderRadius: isLast
                      ? const BorderRadius.vertical(bottom: Radius.circular(16))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            question.question,
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? Colors.white24 : Colors.black26,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white70 : Colors.black54,
          side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _ContactOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _ContactOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}
