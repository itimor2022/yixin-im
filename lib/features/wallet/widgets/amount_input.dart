// 文件用途：提供 AmountInput 可复用界面组件，服务于钱包与支付。
// 核心逻辑：根据输入模型和状态渲染 AmountInput，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

// 关键声明：amount input 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 金额输入组件 - 微信风格
class AmountInput extends StatefulWidget {
  final String? initialAmount;
  final ValueChanged<double> onChanged;
  final Color? accentColor;
  final double? maxAmount;
  final String? hintText;
  final bool autoFocus;
  final String currency;

  const AmountInput({
    super.key,
    this.initialAmount,
    required this.onChanged,
    this.accentColor,
    this.maxAmount,
    this.hintText,
    this.autoFocus = false,
    this.currency = '¥',
  });

  @override
  State<AmountInput> createState() => _AmountInputState();
}

class _AmountInputState extends State<AmountInput> {
  String _amount = '';
  bool _showKeyboard = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    if (widget.initialAmount != null && widget.initialAmount!.isNotEmpty) {
      _amount = widget.initialAmount!;
    }
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _showKeyboard = true);
      });
    }
  }

  double get _amountValue {
    if (_amount.isEmpty) return 0;
    return double.tryParse(_amount) ?? 0;
  }

  void _onKeyPressed(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      if (key == 'delete') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
      } else if (key == '.') {
        if (!_amount.contains('.') && _amount.isNotEmpty) {
          _amount += '.';
        } else if (_amount.isEmpty) {
          _amount = '0.';
        }
      } else {
        // 数字
        if (_amount.contains('.')) {
          // 小数点后最多2位
          final parts = _amount.split('.');
          if (parts.length > 1 && parts[1].length >= 2) {
            return;
          }
        }
        // 限制整数部分不超过8位
        if (!_amount.contains('.') && _amount.length >= 8) {
          return;
        }
        // 检查最大金额
        final newAmount = _amount + key;
        final value = double.tryParse(newAmount) ?? 0;
        if (widget.maxAmount != null && value > widget.maxAmount!) {
          return;
        }
        _amount = newAmount;
      }
      widget.onChanged(_amountValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor =
        widget.accentColor ?? AppColors.controlActiveFor(context);
    final onAccentColor = widget.accentColor == null
        ? AppColors.onControlActiveFor(context)
        : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 金额显示区域
        GestureDetector(
          onTap: () {
            setState(() => _showKeyboard = true);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  widget.currency,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _amount.isEmpty ? (widget.hintText ?? '0.00') : _amount,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    color: _amount.isEmpty
                        ? AppColors.textTertiaryFor(context)
                        : AppColors.textPrimaryFor(context),
                    letterSpacing: -1,
                  ),
                ),
                // 光标
                if (_showKeyboard)
                  Container(
                    width: 2,
                    height: 40,
                    margin: const EdgeInsets.only(left: 2),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 自定义键盘
        if (_showKeyboard) _buildKeyboard(isDark),
      ],
    );
  }

  Widget _buildKeyboard(bool isDark) {
    final l10n = AppLocalizations.of(context);
    final accentColor =
        widget.accentColor ?? AppColors.controlActiveFor(context);
    final onAccentColor = widget.accentColor == null
        ? AppColors.onControlActiveFor(context)
        : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.keyboardBackgroundFor(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 键盘顶部工具栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardFor(context),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.dividerFor(context),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _showKeyboard = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.done,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: onAccentColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 数字键盘
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildKey('1', isDark),
                      _buildKey('2', isDark),
                      _buildKey('3', isDark),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey('4', isDark),
                      _buildKey('5', isDark),
                      _buildKey('6', isDark),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey('7', isDark),
                      _buildKey('8', isDark),
                      _buildKey('9', isDark),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKey('.', isDark),
                      _buildKey('0', isDark),
                      _buildKey('delete', isDark, isDelete: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(String key, bool isDark, {bool isDelete = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: AppColors.keyboardKeyFor(context),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _onKeyPressed(key),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              child: isDelete
                  ? Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color: AppColors.textSecondaryFor(context),
                    )
                  : Text(
                      key,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 显示金额输入的底部弹窗
Future<double?> showAmountInputSheet({
  required BuildContext context,
  required String title,
  String? subtitle,
  double? initialAmount,
  double? maxAmount,
  Color? accentColor,
  String currency = '¥',
}) async {
  double amount = initialAmount ?? 0;

  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final l10n = AppLocalizations.of(context);

      return Container(
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiaryFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 金额输入
              AmountInput(
                initialAmount: initialAmount?.toString(),
                onChanged: (value) => amount = value,
                accentColor: accentColor,
                maxAmount: maxAmount,
                autoFocus: true,
                currency: currency,
              ),
              // 确认按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, amount),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          accentColor ?? AppColors.controlActiveFor(context),
                      foregroundColor: accentColor == null
                          ? AppColors.onControlActiveFor(context)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.confirm,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
