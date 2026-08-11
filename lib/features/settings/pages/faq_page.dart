// 文件用途：实现 FAQPage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 FAQPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/link_utils.dart';
import '../../../shared/widgets/themed_app_bar.dart';

String _faqText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：faq page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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

  List<FAQCategory> _buildCategories(String appName) {
    final language = AppLocalizations.of(context).language;
    if (language == AppLanguage.en) {
      return [
        FAQCategory(
          name: 'Account & Login',
          icon: Icons.lock_outline_rounded,
          color: const Color(0xFF007AFF),
          questions: [
            FAQItem(
              question: 'What should I do if I cannot log in?',
              answer:
                  'Check that your network, username, password, and verification code are correct. If the account is restricted or the code cannot be received repeatedly, contact support and provide your registered account or phone number.',
            ),
            FAQItem(
              question: 'What should I do if I cannot receive the SMS code?',
              answer:
                  'Confirm that the phone number is correct, avoid requesting codes too frequently, and check whether SMS messages are blocked by the carrier or phone security app. If it still fails, contact support.',
            ),
            FAQItem(
              question: 'How do I delete my account?',
              answer:
                  'Open Settings, go to Account & Security, and submit an account deletion request. After deletion, account data cannot be recovered. Contact support first if you only need help recovering access.',
            ),
          ],
        ),
        FAQCategory(
          name: 'Messages & Payments',
          icon: Icons.support_agent_rounded,
          color: const Color(0xFFFF9500),
          questions: [
            FAQItem(
              question: 'What should I do if messages fail to send?',
              answer:
                  'Check the network connection and try refreshing the chat list. If only one conversation fails, confirm whether the other party, group, or channel is still available. Contact support if the problem continues.',
            ),
            FAQItem(
              question:
                  'What should I do about payment, wallet, or withdrawal issues?',
              answer:
                  'Do not repeat the same payment or withdrawal many times. Keep the order number, amount, time, and screenshot, then contact support so we can verify the transaction status.',
            ),
          ],
        ),
      ];
    }
    if (language == AppLanguage.zhTW) {
      return [
        FAQCategory(
          name: '帳號與登入',
          icon: Icons.lock_outline_rounded,
          color: const Color(0xFF007AFF),
          questions: [
            FAQItem(
              question: '登入不了怎麼辦？',
              answer:
                  '先確認網路、帳號、密碼和驗證碼是否正確。如果提示帳號受限，或多次收不到驗證碼，請聯絡客服並提供註冊帳號或手機號。',
            ),
            FAQItem(
              question: '收不到簡訊驗證碼怎麼辦？',
              answer: '請確認手機號正確，不要頻繁重複獲取，並檢查電信商或手機安全軟體是否攔截簡訊。仍無法收到時，請聯絡客服處理。',
            ),
            FAQItem(
              question: '如何註銷帳號？',
              answer: '進入「設定」裡的帳號安全相關入口提交註銷申請。註銷後資料不可恢復；如果只是無法登入，建議先聯絡客服協助找回。',
            ),
          ],
        ),
        FAQCategory(
          name: '消息與支付',
          icon: Icons.support_agent_rounded,
          color: const Color(0xFFFF9500),
          questions: [
            FAQItem(
              question: '消息發不出去怎麼辦？',
              answer: '先檢查網路並刷新聊天列表。如果只有某個會話異常，請確認對方、群組或頻道狀態是否正常；問題持續時請聯絡客服。',
            ),
            FAQItem(
              question: '支付、錢包或提現異常怎麼辦？',
              answer: '請不要連續重複提交同一筆支付或提現。保留訂單號、金額、時間和截圖後聯絡客服，我們會核對交易狀態。',
            ),
          ],
        ),
      ];
    }
    if (language == AppLanguage.zhCN) {
      return [
        FAQCategory(
          name: '账号与登录',
          icon: Icons.lock_outline_rounded,
          color: const Color(0xFF007AFF),
          questions: [
            FAQItem(
              question: '登录不了怎么办？',
              answer:
                  '先确认网络、账号、密码和验证码是否正确。如果提示账号受限，或多次收不到验证码，请联系客服并提供注册账号或手机号。',
            ),
            FAQItem(
              question: '收不到短信验证码怎么办？',
              answer: '请确认手机号正确，不要频繁重复获取，并检查运营商或手机安全软件是否拦截短信。仍无法收到时，请联系客服处理。',
            ),
            FAQItem(
              question: '如何注销账号？',
              answer: '进入“设置”里的账号安全相关入口提交注销申请。注销后资料不可恢复；如果只是无法登录，建议先联系客服协助找回。',
            ),
          ],
        ),
        FAQCategory(
          name: '消息与支付',
          icon: Icons.support_agent_rounded,
          color: const Color(0xFFFF9500),
          questions: [
            FAQItem(
              question: '消息发不出去怎么办？',
              answer: '先检查网络并刷新聊天列表。如果只有某个会话异常，请确认对方、群组或频道状态是否正常；问题持续时请联系客服。',
            ),
            FAQItem(
              question: '支付、钱包或提现异常怎么办？',
              answer: '请不要连续重复提交同一笔支付或提现。保留订单号、金额、时间和截图后联系客服，我们会核对交易状态。',
            ),
          ],
        ),
      ];
    }

    final isEnglish = language == AppLanguage.en;

    if (isEnglish) {
      return [
        FAQCategory(
          name: 'Getting Started',
          icon: Icons.rocket_launch_rounded,
          color: const Color(0xFF007AFF),
          questions: [
            FAQItem(
              question: 'How do I register an account?',
              answer:
                  'Open $appName, tap "Register", then enter a username and password to complete registration. The username cannot be changed after registration, so choose it carefully.',
            ),
            FAQItem(
              question: 'How do I add contacts?',
              answer:
                  'On the Contacts page, tap the "+" button in the top-right corner. Go to Search, enter a username or keyword, then tap "Add" after finding the user. You can also search for public groups or channels and join them.',
            ),
            FAQItem(
              question: 'How do I create a group?',
              answer:
                  'On the Contacts page, tap "New Group", choose the contacts you want to invite, and set a group name. After the group is created, you can manage members, assign roles, and mute members inside the group.',
            ),
            FAQItem(
              question: 'How do I create a channel?',
              answer:
                  'On the Contacts page, tap "New Channel", then set the channel name and description. Channels support public subscriptions and members can view messages posted in the channel.',
            ),
          ],
        ),
        FAQCategory(
          name: 'Contacts',
          icon: Icons.people_rounded,
          color: const Color(0xFF5856D6),
          questions: [
            FAQItem(
              question: 'Why is my contact list empty?',
              answer:
                  'If default official contacts have been configured, they are synced automatically after you enter the app. You can also tap "+" on the Contacts page to search for users and add them. If the app says "Already in contacts", go back and refresh the Contacts page.',
            ),
            FAQItem(
              question: 'Does online status update in real time?',
              answer:
                  'Yes. Contact status such as "Online" and "Last seen xx ago" updates automatically when the other user goes online or offline.',
            ),
            FAQItem(
              question: 'How do I edit a contact remark?',
              answer:
                  'Open the chat or profile page for that contact, then edit the remark in the settings or profile area. The remark is visible only to you.',
            ),
          ],
        ),
        FAQCategory(
          name: 'Chats & Messages',
          icon: Icons.chat_bubble_rounded,
          color: const Color(0xFFFF9500),
          questions: [
            FAQItem(
              question: 'What should I do if a message fails to send?',
              answer:
                  'Check whether your network connection is working. If the network is normal but the message still fails, try:\n\n1. Pull down to refresh the chat list\n2. Restart the app\n3. Check whether the other user has blocked you',
            ),
            FAQItem(
              question: 'How do I recall a message?',
              answer:
                  'Long press the message you want to recall and choose "Recall" from the popup menu. Only messages sent by you can be recalled, and only within the allowed time window.',
            ),
            FAQItem(
              question: 'How do I send photos, voice messages, or files?',
              answer:
                  'Tap the "+" button next to the chat input box, then choose photos, camera, videos, voice messages, files, and more. Photos and files can be sent after selecting them from your device.',
            ),
            FAQItem(
              question: 'How do I edit or delete a sent message?',
              answer:
                  'Long press a message and choose "Edit" or "Delete". Edits keep a record. Deleting only hides the message from your side, and the other user may still be able to see it.',
            ),
            FAQItem(
              question: 'Can chat history be cleared?',
              answer:
                  'You can find "Clear Chat History" in chat details or in group and channel settings. After clearing, messages for that conversation are removed from both local storage and the server, and cannot be recovered.',
            ),
          ],
        ),
        FAQCategory(
          name: 'Moments',
          icon: Icons.explore_rounded,
          color: const Color(0xFFFF2D55),
          questions: [
            FAQItem(
              question: 'How do I post a moment?',
              answer:
                  'On the Moments page, tap the "+" button in the top-right corner to publish text, photos, or videos. You can choose the visibility scope: public, contacts only, partially visible, or private.',
            ),
            FAQItem(
              question: 'How do likes and comments work?',
              answer:
                  'You can like a moment directly on the card. Tap the comment icon to view comments and post your own. Notifications are sent for both likes and comments.',
            ),
            FAQItem(
              question: 'How do I block a moment or a user?',
              answer:
                  'Long press a moment card and choose "Block this moment" or "Block this user" from the menu. Blocked content will no longer appear in your feed.',
            ),
            FAQItem(
              question: 'How do I report inappropriate content?',
              answer:
                  'Long press a moment or message, choose "Report", fill in the reason, then submit it. We will review it as soon as possible.',
            ),
          ],
        ),
        FAQCategory(
          name: 'Privacy & Security',
          icon: Icons.shield_rounded,
          color: const Color(0xFF34C759),
          questions: [
            FAQItem(
              question: 'Is chat history secure?',
              answer:
                  'Messages are encrypted during transmission and storage on the server, and only members of the conversation can view them. Do not share your account password, and change it regularly.',
            ),
            FAQItem(
              question: 'How do I block someone?',
              answer:
                  'Open the chat with that user, tap the top-right corner to enter the profile or settings page, and choose "Block User". You can also manage blocked users in "Settings > Blocked Users".',
            ),
            FAQItem(
              question: 'How do I manage devices and sessions?',
              answer:
                  'In Settings, open "Device Management" or "Session Management" to review logged-in devices and sessions, then sign them out if needed to keep your account secure.',
            ),
            FAQItem(
              question: 'How do I delete my account?',
              answer:
                  'Go to "Settings" and find the entry for "Account & Security" or "Delete Account". Deleting the account permanently removes the account and related data.',
            ),
          ],
        ),
        FAQCategory(
          name: 'Account & Settings',
          icon: Icons.settings_rounded,
          color: const Color(0xFFAF52DE),
          questions: [
            FAQItem(
              question: 'How do I change my nickname and avatar?',
              answer:
                  'Go to "Settings > Profile" to edit your nickname, avatar, bio, and more. The avatar can be taken with the camera or chosen from the gallery.',
            ),
            FAQItem(
              question: 'How do I change my password?',
              answer:
                  'After logging in, go to "Settings", open "Account & Security" or "Change Password", then enter the current password and the new password.',
            ),
            FAQItem(
              question: 'How do I change the chat background and font?',
              answer:
                  'In "Settings > Chat Settings", you can change the chat background using solid colors, gradients, or a custom image, and adjust the font size.',
            ),
            FAQItem(
              question: 'How do I enable or disable notifications?',
              answer:
                  'In "Settings > Notification Settings", you can manage message notifications, sounds, and vibration. Also make sure system settings allow notifications from $appName.',
            ),
          ],
        ),
      ];
    }

    return [
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
  }

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

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    // 桌面端面板模式：只返回内容，不需要 Scaffold 和 AppBar
    if (widget.isDesktopPanel) {
      return _buildBodyContent(isDark, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _faqText(
            context,
            zhCN: '帮助与客服',
            zhTW: '幫助與客服',
            en: 'Help & Support',
          ),
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
          child: Icon(
            Icons.headset_mic_rounded,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildBodyContent(bool isDark, AppLocalizations l10n) {
    final appName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
            defaultAppDisplayName();
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
                  color: AppColors.inputHintFor(context),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.inputIconFor(context),
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSupportEntry(isDark, l10n),
                    const SizedBox(height: 16),
                    ...filteredCategories.map(
                      (category) => _CategoryCard(
                        category: category,
                        isDark: isDark,
                        onQuestionTap: (question) => _showAnswer(question),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSupportEntry(bool isDark, AppLocalizations l10n) {
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final onlineSupportUrl = settings?.onlineSupportUrl ?? '';
    final qqSupportNumber = settings?.qqSupportNumber ?? '';
    final hasSupport =
        onlineSupportUrl.isNotEmpty || qqSupportNumber.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.emphasisSoftFor(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.support_agent_rounded,
              color: AppColors.linkFor(context),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _faqText(
                    context,
                    zhCN: '需要人工帮助？',
                    zhTW: '需要人工協助？',
                    en: 'Need help from support?',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasSupport
                      ? l10n.supportDescription
                      : _faqText(
                          context,
                          zhCN: '客服信息暂未配置',
                          zhTW: '客服資訊暫未配置',
                          en: 'Support information is not configured yet.',
                        ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => _contactSupport(l10n),
            child: Text(l10n.contactSupport),
          ),
        ],
      ),
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
            color: AppColors.textTertiaryFor(context).withOpacity(0.72),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noQuestionsFound,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondaryFor(context),
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
                        color: AppColors.textSecondaryFor(context),
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

  Future<void> _openOnlineService(String url) async {
    final supportUrl = url.trim();
    if (supportUrl.isEmpty) {
      _showSupportNotConfigured();
      return;
    }
    await LinkUtils.openLink(context, supportUrl);
  }

  void _showSupportNotConfigured() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _faqText(
              context,
              zhCN: '客服信息暂未配置',
              zhTW: '客服資訊暫未配置',
              en: 'Support information is not configured yet.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _copyQQAndHint(String qqNumber) {
    final qq = qqNumber.trim();
    if (qq.isEmpty) {
      _showSupportNotConfigured();
      return;
    }
    Clipboard.setData(ClipboardData(text: qq));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _faqText(
            context,
            zhCN: 'QQ $qq 已复制到剪贴板',
            zhTW: 'QQ $qq 已複製到剪貼簿',
            en: 'QQ $qq copied to clipboard',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _contactSupport(AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.read(systemSettingsProvider).valueOrNull;
    final onlineSupportUrl = settings?.onlineSupportUrl ?? '';
    final qqSupportNumber = settings?.qqSupportNumber ?? '';
    final hasOnlineSupport = onlineSupportUrl.isNotEmpty;
    final hasQQSupport = qqSupportNumber.isNotEmpty;

    showModalBottomSheet(
      context: context,
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
                    color: AppColors.emphasisSoftFor(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.headset_mic_rounded,
                    color: AppColors.linkFor(context),
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
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(height: 24),
                if (hasOnlineSupport)
                  _ContactOption(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: l10n.onlineSupport,
                    subtitle: l10n.onlineSupportHint,
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      _openOnlineService(onlineSupportUrl);
                    },
                  ),
                if (hasOnlineSupport && hasQQSupport)
                  const SizedBox(height: 12),
                if (hasQQSupport)
                  _ContactOption(
                    icon: Icons.tag_rounded,
                    title: l10n.qqSupport,
                    subtitle: 'QQ：$qqSupportNumber',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      _copyQQAndHint(qqSupportNumber);
                    },
                  ),
                if (!hasOnlineSupport && !hasQQSupport)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _faqText(
                        context,
                        zhCN: '客服信息暂未配置',
                        zhTW: '客服資訊暫未配置',
                        en: 'Support information is not configured yet.',
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
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
                  _faqText(
                    context,
                    zhCN: '${category.questions.length} 个问题',
                    zhTW: '${category.questions.length} 個問題',
                    en: '${category.questions.length} questions',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiaryFor(context),
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
                  color:
                      isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
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
            Icon(icon, color: AppColors.linkFor(context), size: 24),
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
                      color: AppColors.textTertiaryFor(context),
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
