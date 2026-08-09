// 文件用途：实现 SetPayPasswordPage 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 SetPayPasswordPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';

/// 设置支付密码页面
String _payPasswordText(
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

// 关键声明：set pay password page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class SetPayPasswordPage extends ConsumerStatefulWidget {
  final bool isUpdate;

  const SetPayPasswordPage({
    super.key,
    this.isUpdate = false,
  });

  @override
  ConsumerState<SetPayPasswordPage> createState() => _SetPayPasswordPageState();
}

class _SetPayPasswordPageState extends ConsumerState<SetPayPasswordPage>
    with SingleTickerProviderStateMixin {
  int _step = 0; // 0: 输入旧密码(仅修改), 1: 输入新密码, 2: 确认新密码
  String _oldPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';
  String? _errorMessage;
  bool _isLoading = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _step = widget.isUpdate ? 0 : 1;

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

  String get _currentPassword {
    switch (_step) {
      case 0:
        return _oldPassword;
      case 1:
        return _newPassword;
      case 2:
        return _confirmPassword;
      default:
        return '';
    }
  }

  String get _title {
    if (widget.isUpdate) {
      switch (_step) {
        case 0:
          return _payPasswordText(
            context,
            zhCN: '验证原密码',
            zhTW: '驗證原密碼',
            en: 'Verify Current Password',
          );
        case 1:
          return _payPasswordText(
            context,
            zhCN: '设置新密码',
            zhTW: '設定新密碼',
            en: 'Set New Password',
          );
        default:
          return _payPasswordText(
            context,
            zhCN: '确认新密码',
            zhTW: '確認新密碼',
            en: 'Confirm New Password',
          );
      }
    }
    return _step == 1
        ? _payPasswordText(
            context,
            zhCN: '设置支付密码',
            zhTW: '設定支付密碼',
            en: 'Set Payment Password',
          )
        : _payPasswordText(
            context,
            zhCN: '确认支付密码',
            zhTW: '確認支付密碼',
            en: 'Confirm Payment Password',
          );
  }

  String get _subtitle {
    if (widget.isUpdate && _step == 0) {
      return _payPasswordText(
        context,
        zhCN: '请输入原支付密码进行验证',
        zhTW: '請輸入原支付密碼進行驗證',
        en: 'Enter your current payment password for verification',
      );
    }
    return _step == 2
        ? _payPasswordText(
            context,
            zhCN: '请再次输入支付密码',
            zhTW: '請再次輸入支付密碼',
            en: 'Enter the payment password again',
          )
        : _payPasswordText(
            context,
            zhCN: '请设置6位数字支付密码',
            zhTW: '請設定 6 位數字支付密碼',
            en: 'Set a 6-digit numeric payment password',
          );
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    HapticFeedback.heavyImpact();
    _shakeController.forward().then((_) => _shakeController.reset());
  }

  void _onKeyPressed(String key) {
    if (_isLoading) return;

    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = null;

      if (key == 'delete') {
        switch (_step) {
          case 0:
            if (_oldPassword.isNotEmpty) {
              _oldPassword = _oldPassword.substring(0, _oldPassword.length - 1);
            }
            break;
          case 1:
            if (_newPassword.isNotEmpty) {
              _newPassword = _newPassword.substring(0, _newPassword.length - 1);
            }
            break;
          case 2:
            if (_confirmPassword.isNotEmpty) {
              _confirmPassword =
                  _confirmPassword.substring(0, _confirmPassword.length - 1);
            }
            break;
        }
      } else {
        switch (_step) {
          case 0:
            if (_oldPassword.length < 6) {
              _oldPassword += key;
              if (_oldPassword.length == 6) {
                _verifyOldPassword();
              }
            }
            break;
          case 1:
            if (_newPassword.length < 6) {
              _newPassword += key;
              if (_newPassword.length == 6) {
                _step = 2;
              }
            }
            break;
          case 2:
            if (_confirmPassword.length < 6) {
              _confirmPassword += key;
              if (_confirmPassword.length == 6) {
                _confirmAndSubmit();
              }
            }
            break;
        }
      }
    });
  }

  Future<void> _verifyOldPassword() async {
    setState(() => _isLoading = true);

    final isValid =
        await ref.read(walletProvider.notifier).verifyPayPassword(_oldPassword);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (isValid) {
      setState(() {
        _step = 1;
      });
    } else {
      _showError(
        _payPasswordText(
          context,
          zhCN: '密码错误，请重试',
          zhTW: '密碼錯誤，請重試',
          en: 'Incorrect password, please try again',
        ),
      );
      setState(() => _oldPassword = '');
    }
  }

  Future<void> _confirmAndSubmit() async {
    if (_newPassword != _confirmPassword) {
      _showError(
        _payPasswordText(
          context,
          zhCN: '两次输入的密码不一致',
          zhTW: '兩次輸入的密碼不一致',
          en: 'The two passwords do not match',
        ),
      );
      setState(() => _confirmPassword = '');
      return;
    }

    setState(() => _isLoading = true);

    final success = await ref.read(walletProvider.notifier).setPayPassword(
          _newPassword,
          oldPassword: widget.isUpdate ? _oldPassword : null,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isUpdate
                ? _payPasswordText(
                    context,
                    zhCN: '密码修改成功',
                    zhTW: '密碼修改成功',
                    en: 'Password updated successfully',
                  )
                : _payPasswordText(
                    context,
                    zhCN: '密码设置成功',
                    zhTW: '密碼設定成功',
                    en: 'Password set successfully',
                  ),
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.of(context).pop();
    } else {
      _showError(
        _payPasswordText(
          context,
          zhCN: '设置失败，请重试',
          zhTW: '設定失敗，請重試',
          en: 'Failed to set password, please try again',
        ),
      );
      setState(() => _confirmPassword = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        title: Text(
          widget.isUpdate
              ? _payPasswordText(
                  context,
                  zhCN: '修改支付密码',
                  zhTW: '修改支付密碼',
                  en: 'Change Payment Password',
                )
              : _payPasswordText(
                  context,
                  zhCN: '设置支付密码',
                  zhTW: '設定支付密碼',
                  en: 'Set Payment Password',
                ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 760;
            final iconSize = compact ? 56.0 : 72.0;
            final iconRadius = compact ? 16.0 : 20.0;
            final passwordBoxSize = compact ? 44.0 : 48.0;
            final passwordBoxMargin = compact ? 4.0 : 6.0;

            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: compact ? 12 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    SizedBox(height: compact ? 16 : 32),

                    // 图标
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: AppColors.emphasisSoftFor(context),
                        borderRadius: BorderRadius.circular(iconRadius),
                      ),
                      child: Icon(
                        _step == 0
                            ? Icons.lock_outline
                            : (_step == 1
                                ? Icons.lock_open
                                : Icons.check_circle_outline),
                        size: compact ? 30 : 36,
                        color: AppColors.linkFor(context),
                      ),
                    ),

                    SizedBox(height: compact ? 16 : 24),

                    // 标题
                    Text(
                      _title,
                      style: TextStyle(
                        fontSize: compact ? 20 : 22,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 副标题
                    Text(
                      _subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),

                    SizedBox(height: compact ? 24 : 40),

                    // 密码显示
                    AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) {
                        final shake = _shakeAnimation.value * 10;
                        return Transform.translate(
                          offset: Offset(
                            shake *
                                (1 - _shakeAnimation.value) *
                                ((_shakeAnimation.value * 10).toInt().isOdd
                                    ? 1
                                    : -1),
                            0,
                          ),
                          child: child,
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          final isFilled = index < _currentPassword.length;
                          final hasError = _errorMessage != null;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: passwordBoxSize,
                            height: passwordBoxSize,
                            margin: EdgeInsets.symmetric(
                                horizontal: passwordBoxMargin),
                            decoration: BoxDecoration(
                              color: isFilled
                                  ? AppColors.emphasisSoftFor(context)
                                  : Colors.transparent,
                              border: Border.all(
                                color: hasError
                                    ? Colors.red
                                    : (isFilled
                                        ? AppColors.controlActiveFor(context)
                                        : (isDark
                                            ? Colors.white24
                                            : Colors.grey[300]!)),
                                width: isFilled ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                child: isFilled
                                    ? Container(
                                        key: ValueKey('filled_$index'),
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: AppColors.controlActiveFor(
                                              context),
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('empty')),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    // 错误提示或加载指示器
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: compact ? 36 : 48,
                      child: Center(
                        child: _isLoading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.controlActiveFor(context),
                                ),
                              )
                            : _errorMessage != null
                                ? Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.red,
                                    ),
                                  )
                                : null,
                      ),
                    ),

                    SizedBox(height: compact ? 12 : 28),

                    // 步骤指示器
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(widget.isUpdate ? 3 : 2, (index) {
                        final adjustedIndex =
                            widget.isUpdate ? index : index + 1;
                        final isActive = _step == adjustedIndex;
                        final isCompleted = _step > adjustedIndex;
                        return Container(
                          width: isActive ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: isCompleted || isActive
                                ? AppColors.controlActiveFor(context)
                                : (isDark ? Colors.white24 : Colors.grey[300]),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: compact ? 18 : 32),

                    // 数字键盘
                    _buildKeyboard(isDark, compact: compact),

                    SizedBox(height: compact ? 12 : 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeyboard(bool isDark, {required bool compact}) {
    final rowGap = compact ? 8.0 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      child: Column(
        children: [
          _buildKeyRow(['1', '2', '3'], isDark, compact: compact),
          SizedBox(height: rowGap),
          _buildKeyRow(['4', '5', '6'], isDark, compact: compact),
          SizedBox(height: rowGap),
          _buildKeyRow(['7', '8', '9'], isDark, compact: compact),
          SizedBox(height: rowGap),
          _buildKeyRow(['', '0', 'delete'], isDark, compact: compact),
        ],
      ),
    );
  }

  Widget _buildKeyRow(
    List<String> keys,
    bool isDark, {
    required bool compact,
  }) {
    final keyHeight = compact ? 52.0 : 60.0;
    return Row(
      children: keys.map((key) {
        if (key.isEmpty) {
          return Expanded(child: SizedBox(height: keyHeight));
        }
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
            child: _buildKey(key, isDark, height: keyHeight),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String key, bool isDark, {required double height}) {
    final isDelete = key == 'delete';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeyPressed(key),
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.controlActiveFor(context).withOpacity(0.1),
        highlightColor: AppColors.controlActiveFor(context).withOpacity(0.05),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: isDelete
                ? Colors.transparent
                : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey[50]),
            borderRadius: BorderRadius.circular(16),
            border: isDelete
                ? null
                : Border.all(
                    color: isDark ? Colors.white12 : Colors.grey[200]!,
                    width: 1,
                  ),
          ),
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
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
