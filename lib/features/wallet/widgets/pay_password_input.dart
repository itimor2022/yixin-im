// 文件用途：提供 PayPasswordInput 可复用界面组件，服务于钱包与支付。
// 核心逻辑：根据输入模型和状态渲染 PayPasswordInput，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

String _payDialogText(
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

// 关键声明：pay password input 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 支付密码输入组件（6位数字）
class PayPasswordInput extends StatefulWidget {
  final String? title;
  final String? subtitle;
  final String? amount;
  final ValueChanged<String> onCompleted;
  final VoidCallback? onCancel;
  final bool showCancel;
  final bool isLoading;
  final String? errorMessage;

  const PayPasswordInput({
    super.key,
    this.title,
    this.subtitle,
    this.amount,
    required this.onCompleted,
    this.onCancel,
    this.showCancel = true,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  State<PayPasswordInput> createState() => _PayPasswordInputState();
}

class _PayPasswordInputState extends State<PayPasswordInput>
    with SingleTickerProviderStateMixin {
  String _password = '';
  bool _hasError = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onKeyPressed(String key) {
    if (widget.isLoading) return;

    HapticFeedback.lightImpact();

    setState(() {
      _hasError = false;
      if (key == 'delete') {
        if (_password.isNotEmpty) {
          _password = _password.substring(0, _password.length - 1);
        }
      } else if (_password.length < 6) {
        _password += key;
        if (_password.length == 6) {
          widget.onCompleted(_password);
        }
      }
    });
  }

  void _clear() {
    setState(() {
      _password = '';
      _hasError = false;
    });
  }

  void showError() {
    setState(() {
      _hasError = true;
      _password = '';
    });
    _shakeController.forward().then((_) => _shakeController.reset());
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorMsg = widget.errorMessage;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部拖动条
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiaryFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (widget.showCancel)
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.close,
                          size: 24,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                  const Spacer(),
                  Text(
                    widget.title ??
                        _payDialogText(
                          context,
                          zhCN: '请输入支付密码',
                          zhTW: '請輸入支付密碼',
                          en: 'Enter Payment Password',
                        ),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // 金额显示
            if (widget.amount != null) ...[
              const SizedBox(height: 24),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    AppColors.primaryFor(context),
                    AppColors.linkEmphasisFor(context),
                  ],
                ).createShader(bounds),
                child: Text(
                  widget.amount!,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],

            // 副标题
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.subtitle!,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryFor(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 32),

            // 密码显示
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final shake = _hasError
                    ? 10 *
                        (1 - _shakeAnimation.value) *
                        ((_shakeAnimation.value * 4).floor() % 2 == 0 ? 1 : -1)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(shake, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _password.length;
                  final isError = _hasError || errorMsg != null;
                  final isActive = index == _password.length;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isFilled
                          ? (isError
                              ? Colors.red.withOpacity(0.1)
                              : AppColors.emphasisSoftFor(context))
                          : AppColors.inputBackgroundFor(context),
                      border: Border.all(
                        color: isError
                            ? Colors.red
                            : (isFilled
                                ? AppColors.controlActiveFor(context)
                                : (isActive
                                    ? AppColors.controlActiveFor(context)
                                        .withOpacity(0.5)
                                    : AppColors.dividerFor(context))),
                        width: isFilled || isActive ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isFilled
                          ? [
                              BoxShadow(
                                color: AppColors.controlActiveFor(context)
                                    .withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: isFilled
                            ? Container(
                                key: ValueKey('dot_$index'),
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isError
                                        ? [Colors.red, Colors.redAccent]
                                        : [
                                            AppColors.primaryFor(context),
                                            AppColors.linkEmphasisFor(context),
                                          ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 错误提示
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: errorMsg != null ? 40 : 16,
              child: errorMsg != null
                  ? Center(
                      child: Text(
                        errorMsg,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                    )
                  : null,
            ),

            // 加载指示器
            if (widget.isLoading) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    AppColors.controlActiveFor(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 数字键盘
            _buildKeyboard(isDark),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboard(bool isDark) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: keys.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 56);
              }
              return _buildKey(key, isDark);
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKey(String key, bool isDark) {
    final isDelete = key == 'delete';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeyPressed(key),
        borderRadius: BorderRadius.circular(36),
        splashColor: AppColors.controlActiveFor(context).withOpacity(0.1),
        highlightColor: AppColors.controlActiveFor(context).withOpacity(0.05),
        child: Container(
          width: 72,
          height: 56,
          margin: const EdgeInsets.all(4),
          child: Center(
            child: isDelete
                ? Icon(
                    Icons.backspace_outlined,
                    size: 24,
                    color: AppColors.textSecondaryFor(context),
                  )
                : Text(
                    key,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 显示支付密码输入弹窗
Future<String?> showPayPasswordDialog({
  required BuildContext context,
  String? title,
  String? subtitle,
  String? amount,
}) async {
  String? result;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) {
      return PayPasswordInput(
        title: title,
        subtitle: subtitle,
        amount: amount,
        onCompleted: (password) {
          result = password;
          Navigator.of(context).pop();
        },
        onCancel: () => Navigator.of(context).pop(),
      );
    },
  );

  return result;
}
