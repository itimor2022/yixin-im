import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';

/// 设置支付密码页面
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
          return '验证原密码';
        case 1:
          return '设置新密码';
        default:
          return '确认新密码';
      }
    }
    return _step == 1 ? '设置支付密码' : '确认支付密码';
  }

  String get _subtitle {
    if (widget.isUpdate && _step == 0) {
      return '请输入原支付密码进行验证';
    }
    return _step == 2 ? '请再次输入支付密码' : '请设置6位数字支付密码';
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
              _oldPassword =
                  _oldPassword.substring(0, _oldPassword.length - 1);
            }
            break;
          case 1:
            if (_newPassword.isNotEmpty) {
              _newPassword =
                  _newPassword.substring(0, _newPassword.length - 1);
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
      _showError('密码错误，请重试');
      setState(() => _oldPassword = '');
    }
  }

  Future<void> _confirmAndSubmit() async {
    if (_newPassword != _confirmPassword) {
      _showError('两次输入的密码不一致');
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
          content: Text(widget.isUpdate ? '密码修改成功' : '密码设置成功'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.of(context).pop();
    } else {
      _showError('设置失败，请重试');
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
          widget.isUpdate ? '修改支付密码' : '设置支付密码',
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
        child: Column(
          children: [
            const Spacer(flex: 1),

            // 图标
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _step == 0
                    ? Icons.lock_outline
                    : (_step == 1 ? Icons.lock_open : Icons.check_circle_outline),
                size: 36,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 24),

            // 标题
            Text(
              _title,
              style: TextStyle(
                fontSize: 22,
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
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),

            const SizedBox(height: 40),

            // 密码显示
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final shake = _shakeAnimation.value * 10;
                return Transform.translate(
                  offset: Offset(
                    shake * (1 - _shakeAnimation.value) * 
                        ((_shakeAnimation.value * 10).toInt().isOdd ? 1 : -1),
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
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isFilled
                          ? AppColors.primary.withOpacity(0.1)
                          : Colors.transparent,
                      border: Border.all(
                        color: hasError
                            ? Colors.red
                            : (isFilled
                                ? AppColors.primary
                                : (isDark ? Colors.white24 : Colors.grey[300]!)),
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
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('empty')),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 错误提示或加载指示器
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 48,
              child: Center(
                child: _isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
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

            const Spacer(flex: 2),

            // 步骤指示器
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.isUpdate ? 3 : 2, (index) {
                final adjustedIndex = widget.isUpdate ? index : index + 1;
                final isActive = _step == adjustedIndex;
                final isCompleted = _step > adjustedIndex;
                return Container(
                  width: isActive ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isCompleted || isActive
                        ? AppColors.primary
                        : (isDark ? Colors.white24 : Colors.grey[300]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // 数字键盘
            _buildKeyboard(isDark),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildKeyRow(['1', '2', '3'], isDark),
          const SizedBox(height: 12),
          _buildKeyRow(['4', '5', '6'], isDark),
          const SizedBox(height: 12),
          _buildKeyRow(['7', '8', '9'], isDark),
          const SizedBox(height: 12),
          _buildKeyRow(['', '0', 'delete'], isDark),
        ],
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys, bool isDark) {
    return Row(
      children: keys.map((key) {
        if (key.isEmpty) {
          return const Expanded(child: SizedBox(height: 60));
        }
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _buildKey(key, isDark),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String key, bool isDark) {
    final isDelete = key == 'delete';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeyPressed(key),
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withOpacity(0.1),
        highlightColor: AppColors.primary.withOpacity(0.05),
        child: Container(
          height: 60,
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
                    color: isDark ? Colors.white54 : Colors.grey[500],
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
