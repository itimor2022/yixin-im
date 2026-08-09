// 文件用途：实现 AgreementType 页面及其交互流程，属于用户认证。
// 核心逻辑：维护 AgreementType 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/api/api_client.dart';

String _agreementText(
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

// 关键声明：agreement page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 协议类型
enum AgreementType { userAgreement, privacyPolicy }

/// 协议页面
class AgreementPage extends ConsumerStatefulWidget {
  final AgreementType type;

  const AgreementPage({
    super.key,
    required this.type,
  });

  @override
  ConsumerState<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends ConsumerState<AgreementPage> {
  bool _isLoading = true;
  String _title = '';
  String _content = '';
  String? _error;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadAgreement();
  }

  Future<void> _loadAgreement() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final endpoint = widget.type == AgreementType.userAgreement
          ? '/app/user-agreement'
          : '/app/privacy-policy';

      final response = await api.get(endpoint);

      if (response.isSuccess && response.data != null) {
        setState(() {
          _title = response.data['title'] ?? '';
          _content = response.data['content'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = localizeServerMessage(
            response.message,
            fallbackZhCN: '加载失败',
            fallbackZhTW: '載入失敗',
            fallbackEn: 'Load failed',
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = _agreementText(
          context,
          zhCN: '网络错误，请稍后重试',
          zhTW: '網路錯誤，請稍後重試',
          en: 'Network error. Please try again later.',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _title.isNotEmpty
              ? _title
              : (widget.type == AgreementType.userAgreement
                  ? _agreementText(
                      context,
                      zhCN: '用户协议',
                      zhTW: '使用者協議',
                      en: 'User Agreement',
                    )
                  : _agreementText(
                      context,
                      zhCN: '隐私政策',
                      zhTW: '隱私政策',
                      en: 'Privacy Policy',
                    )),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadAgreement,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryFor(context),
                foregroundColor: AppColors.onPrimaryFor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _agreementText(
                  context,
                  zhCN: '重试',
                  zhTW: '重試',
                  en: 'Retry',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Markdown(
      data: _content,
      selectable: false, // 禁用选择避免 flutter_markdown bug
      padding: const EdgeInsets.all(16),
      styleSheet: MarkdownStyleSheet(
        h1: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
        h2: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
        h3: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
        p: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: AppColors.textSecondaryFor(context),
        ),
        listBullet: TextStyle(
          fontSize: 15,
          color: AppColors.textSecondaryFor(context),
        ),
        blockquote: TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: AppColors.textSecondaryFor(context),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.dividerFor(context),
            ),
          ),
        ),
      ),
    );
  }
}
