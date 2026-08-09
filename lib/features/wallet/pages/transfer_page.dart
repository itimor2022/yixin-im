// 文件用途：实现 TransferPage 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 TransferPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../providers/wallet_provider.dart';
import '../widgets/pay_password_input.dart';

/// 转账页面
String _transferText(
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

// 关键声明：transfer page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class TransferPage extends ConsumerStatefulWidget {
  final String receiverId; // 接收者 UUID
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
  String get _currency => ref.read(walletCurrencyProvider);

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
                          color: AppColors.dividerFor(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 标题栏 - 取消/标题/确定
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Row(
                        children: [
                          // 取消按钮
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              _transferText(
                                context,
                                zhCN: '取消',
                                zhTW: '取消',
                                en: 'Cancel',
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondaryFor(context),
                              ),
                            ),
                          ),
                          // 标题
                          Expanded(
                            child: Center(
                              child: Text(
                                _transferText(
                                  context,
                                  zhCN: '转账金额',
                                  zhTW: '轉帳金額',
                                  en: 'Transfer Amount',
                                ),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimaryFor(context),
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
                              _transferText(
                                context,
                                zhCN: '确定',
                                zhTW: '確定',
                                en: 'Confirm',
                              ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.linkFor(context),
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
                            _currency,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: AppColors.linkFor(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            inputAmount.isEmpty ? '0.00' : inputAmount,
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w600,
                              color: inputAmount.isEmpty
                                  ? AppColors.textTertiaryFor(context)
                                  : AppColors.textPrimaryFor(context),
                              letterSpacing: -1,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 40,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: AppColors.linkFor(context),
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
      }).toList(),
    );
  }

  Future<void> _transfer() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _transferText(
              context,
              zhCN: '请输入有效金额',
              zhTW: '請輸入有效金額',
              en: 'Enter a valid amount',
            ),
          ),
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
          content: Text(
            _transferText(
              context,
              zhCN: '余额不足',
              zhTW: '餘額不足',
              en: 'Insufficient balance',
            ),
          ),
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
      title: _transferText(
        context,
        zhCN: '确认转账',
        zhTW: '確認轉帳',
        en: 'Confirm Transfer',
      ),
      amount: '$_currency${_amount.toStringAsFixed(2)}',
      subtitle: _transferText(
        context,
        zhCN: '转账给 ${widget.receiverName}',
        zhTW: '轉帳給 ${widget.receiverName}',
        en: 'Transfer to ${widget.receiverName}',
      ),
    );

    if (password == null) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      // 调用真实 API 发起转账
      final response = await ref.read(walletProvider.notifier).transfer(
            receiverId: widget.receiverId,
            amount: _amount,
            remark:
                _remarkController.text.isEmpty ? null : _remarkController.text,
            payPassword: password,
          );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response != null) {
        Navigator.of(context).pop(response);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.read(walletProvider).error ??
                  _transferText(
                    context,
                    zhCN: '转账失败',
                    zhTW: '轉帳失敗',
                    en: 'Transfer failed',
                  ),
            ),
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
            content: Text(
              _transferText(
                context,
                zhCN: '转账失败: $e',
                zhTW: '轉帳失敗: $e',
                en: 'Transfer failed: $e',
              ),
            ),
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
    ref.watch(walletCurrencyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: AppColors.primaryFor(context),
        systemOverlayStyle: AppSystemUiStyles.onDarkBackground,
        elevation: 0,
        title: Text(
          _transferText(
            context,
            zhCN: '转账',
            zhTW: '轉帳',
            en: 'Transfer',
          ),
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
                color: AppColors.primaryFor(context),
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
                          _transferText(
                            context,
                            zhCN: '转账给',
                            zhTW: '轉帳給',
                            en: 'Transfer to',
                          ),
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
                      _transferText(
                        context,
                        zhCN:
                            '余额 $_currency${(walletState.wallet?.balance ?? 0).toStringAsFixed(2)}',
                        zhTW:
                            '餘額 $_currency${(walletState.wallet?.balance ?? 0).toStringAsFixed(2)}',
                        en: 'Balance $_currency${(walletState.wallet?.balance ?? 0).toStringAsFixed(2)}',
                      ),
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
                            _transferText(
                              context,
                              zhCN: '转账金额',
                              zhTW: '轉帳金額',
                              en: 'Transfer Amount',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryFor(context),
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
                                  _currency,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.linkFor(context),
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
                                        ? AppColors.textTertiaryFor(context)
                                        : AppColors.textPrimaryFor(context),
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
                            color: AppColors.textSecondaryFor(context),
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
                                hintText: _transferText(
                                  context,
                                  zhCN: '添加转账说明',
                                  zhTW: '新增轉帳說明',
                                  en: 'Add transfer note',
                                ),
                                hintStyle: TextStyle(
                                  color: AppColors.inputHintFor(context),
                                ),
                              ),
                              maxLength: 50,
                              buildCounter: (_,
                                      {required currentLength,
                                      required isFocused,
                                      required maxLength}) =>
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
                    backgroundColor: AppColors.primaryFor(context),
                    foregroundColor: AppColors.onPrimaryFor(context),
                    disabledBackgroundColor:
                        isDark ? Colors.white12 : Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimaryFor(context),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _amount > 0
                                  ? _transferText(
                                      context,
                                      zhCN:
                                          '转账 $_currency${_amount.toStringAsFixed(2)}',
                                      zhTW:
                                          '轉帳 $_currency${_amount.toStringAsFixed(2)}',
                                      en: 'Transfer $_currency${_amount.toStringAsFixed(2)}',
                                    )
                                  : _transferText(
                                      context,
                                      zhCN: '转账',
                                      zhTW: '轉帳',
                                      en: 'Transfer',
                                    ),
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
