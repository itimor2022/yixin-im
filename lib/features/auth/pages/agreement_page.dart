import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/api/api_client.dart';

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
          _error = response.message ?? '加载失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '网络错误，请稍后重试';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _title.isNotEmpty ? _title : (widget.type == AgreementType.userAgreement ? '用户协议' : '隐私政策'),
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
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('重试'),
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
          color: isDark ? Colors.white70 : Colors.black87,
        ),
        listBullet: TextStyle(
          fontSize: 15,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
        blockquote: TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white24 : Colors.black12,
            ),
          ),
        ),
      ),
    );
  }
}
