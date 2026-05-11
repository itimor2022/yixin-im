import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../widgets/pay_password_input.dart';

/// 转账页面
class TransferPage extends ConsumerStatefulWidget {
  final String receiverId;  // 接收者 UUID
  final String receiverName;
  final String? receiverAvatar;

  const TransferPage({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
  });

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 页面加载时刷新钱包余额
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadWallet();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  double get _amount {
    return double.tryParse(_amountController.text) ?? 0;
  }

  void _showAmountInput(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String inputAmount = _amountController.text;

        return StatefulBuilder(
          builder: (context, setModalState) {
            void onKeyPressed(String key) {
              HapticFeedback.lightImpact();
              setModalState(() {
                if (key == 'delete') {
                  if (inputAmount.isNotEmpty) {
                    inputAmount =
                        inputAmount.substring(0, inputAmount.length - 1);
                  }
                } else if (key == '.') {
                  if (!inputAmount.contains('.') && inputAmount.isNotEmpty) {
                    inputAmount += '.';
                  } else if (inputAmount.isEmpty) {
                    inputAmount = '0.';
                  }
                } else {
                  if (inputAmount.contains('.')) {
                    final parts = inputAmount.split('.');
                    if (parts.length > 1 && parts[1].length >= 2) {
                      return;
                    }
                  }
                  if (!inputAmount.contains('.') && inputAmount.length >= 8) {
                    return;
                  }
                  inputAmount += key;
                }
              });
            }

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
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
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 标题栏 - 取消/标题/确定
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Row(
                        children: [
                          // 取消按钮
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Colors.white60 : Colors.grey[600],
                              ),
                            ),
                          ),
                          // 标题
                          Expanded(
                            child: Center(
                              child: Text(
                                '转账金额',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                          // 确定按钮
                          TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _amountController.text = inputAmount;
                              setState(() {});
                              Navigator.pop(context);
                            },
                            child: Text(
                              '确定',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 金额显示
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '¥',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            inputAmount.isEmpty ? '0.00' : inputAmount,
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w600,
                              color: inputAmount.isEmpty
                                  ? (isDark
                                      ? Colors.white24
                                      : Colors.grey[300])
                                  : (isDark ? Colors.white : Colors.black87),
                              letterSpacing: -1,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 40,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 键盘
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C1E)
                            : const Color(0xFFD1D5DB),
                      ),
                      child: Column(
                        children: [
                          // 数字键盘
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              children: [
                                _buildKeyboardRow(
                                    ['1', '2', '3'], isDark, onKeyPressed),
                                _buildKeyboardRow(
                                    ['4', '5', '6'], isDark, onKeyPressed),
                                _buildKeyboardRow(
                                    ['7', '8', '9'], isDark, onKeyPressed),
                                _buildKeyboardRow(
                                    ['.', '0', 'delete'], isDark, onKeyPressed),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildKeyboardRow(
      List<String> keys, bool isDark, void Function(String) onKeyPressed) {
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Material(
              color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => onKeyPressed(key),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  child: key == 'delete'
                      ? Icon(
                          Icons.backspace_outlined,
                          size: 22,
                          color: isDark ? Colors.white70 : Colors.black87,
                        )
                      : Text(
                          key,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _transfer() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入有效金额'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // 余额预检（仅作 UX 提示，最终以服务端校验为准）
    final walletState = ref.read(walletProvider);
    final balance = walletState.wallet?.balance ?? 0;
    if (balance < _amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('余额不足'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // 显示密码输入
    final password = await showPayPasswordDialog(
      context: context,
      title: '确认转账',
      amount: '¥${_amount.toStringAsFixed(2)}',
      subtitle: '转账给 ${widget.receiverName}',
    );

    if (password == null) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      // 调用真实 API 发起转账
      final response = await ref.read(walletProvider.notifier).transfer(
        receiverId: widget.receiverId,
        amount: _amount,
        remark: _remarkController.text.isEmpty ? null : _remarkController.text,
        payPassword: password,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response != null) {
        Navigator.of(context).pop(response);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(walletProvider).error ?? '转账失败'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('转账失败: $e'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          '转账',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 顶部紫色区域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Row(
                children: [
                  // 头像
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white24,
                      backgroundImage: widget.receiverAvatar?.isNotEmpty == true
                          ? NetworkImage(widget.receiverAvatar!)
                          : null,
                      child: widget.receiverAvatar?.isNotEmpty != true
                          ? Text(
                              widget.receiverName.isNotEmpty
                                  ? widget.receiverName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '转账给',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.receiverName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '余额 ¥${(walletState.wallet?.balance ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 主要内容卡片
            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 金额输入
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Text(
                            '转账金额',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showAmountInput(isDark),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '¥',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _amountController.text.isEmpty
                                      ? '0.00'
                                      : _amountController.text,
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.w600,
                                    color: _amountController.text.isEmpty
                                        ? (isDark
                                            ? Colors.white24
                                            : Colors.grey[300])
                                        : (isDark
                                            ? Colors.white
                                            : Colors.black87),
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.grey[100]),

                    // 转账说明
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_note,
                            size: 20,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _remarkController,
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: '添加转账说明',
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey[400],
                                ),
                              ),
                              maxLength: 50,
                              buildCounter: (_, {required currentLength, required isFocused, required maxLength}) =>
                                  null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 转账按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading || _amount <= 0 ? null : _transfer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        isDark ? Colors.white12 : Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _amount > 0
                                  ? '转账 ¥${_amount.toStringAsFixed(2)}'
                                  : '转账',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
