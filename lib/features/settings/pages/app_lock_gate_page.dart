// 文件用途：实现 AppLockGatePage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 AppLockGatePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/app_lock_service.dart';
import '../../../core/theme/app_colors.dart';

// 关键声明：app lock gate page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class AppLockGatePage extends ConsumerStatefulWidget {
  const AppLockGatePage({super.key});

  @override
  ConsumerState<AppLockGatePage> createState() => _AppLockGatePageState();
}

class _AppLockGatePageState extends ConsumerState<AppLockGatePage> {
  final TextEditingController _passcodeController = TextEditingController();

  Future<void> _submitPasscode(String passcode) async {
    if (!isValidAppLockPasscode(passcode)) return;
    // 页面只收集输入；密码校验和解锁状态统一由 AppLockService 管理。
    final ok = await ref
        .read(appLockServiceProvider.notifier)
        .unlockWithPasscode(passcode);
    if (!ok && mounted) {
      _passcodeController.clear();
    }
  }

  @override
  void dispose() {
    _passcodeController.dispose();
    super.dispose();
  }

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockServiceProvider);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 锁定页是安全门禁，不能通过系统返回键退回到受保护内容。
    return PopScope(
      canPop: false,
      child: Material(
        color: AppColors.backgroundFor(context),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.emphasisSoftFor(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 34,
                        color: AppColors.primaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      _lockText(
                        l10n,
                        zhCN: '通用IM已锁定',
                        zhTW: '通用IM已鎖定',
                        en: 'GenericIM is locked',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimaryFor(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lockText(
                        l10n,
                        zhCN: '验证身份后继续使用',
                        zhTW: '驗證身分後繼續使用',
                        en: 'Verify your identity to continue',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondaryFor(context),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (state.canUseBiometric) ...[
                      // canUseBiometric 同时包含本地开关和系统硬件/录入能力。
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: state.isUnlocking
                              ? null
                              : () => ref
                                  .read(appLockServiceProvider.notifier)
                                  .unlockWithBiometric(
                                    reason: _lockText(
                                      l10n,
                                      zhCN: '验证身份以解锁应用',
                                      zhTW: '驗證身分以解鎖應用程式',
                                      en: 'Verify your identity to unlock',
                                    ),
                                  ),
                          icon: state.isUnlocking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.fingerprint_rounded),
                          label: Text(
                            _lockText(
                              l10n,
                              zhCN: '面容/指纹解锁',
                              zhTW: 'Face ID/指紋解鎖',
                              en: 'Unlock with Biometrics',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (state.hasPasscode) ...[
                      TextField(
                        controller: _passcodeController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        obscureText: true,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: TextStyle(
                          color: AppColors.textPrimaryFor(context),
                          fontSize: 22,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.inputBackgroundFor(context),
                          hintText: _lockText(
                            l10n,
                            zhCN: '输入6位锁定密码',
                            zhTW: '輸入 6 位鎖定密碼',
                            en: 'Enter 6-digit passcode',
                          ),
                          hintStyle: TextStyle(
                            color: AppColors.inputHintFor(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.dividerFor(context),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.dividerFor(context),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.primaryFor(context),
                              width: 1.2,
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          ref
                              .read(appLockServiceProvider.notifier)
                              .clearError();
                          if (value.length == 6) {
                            _submitPasscode(value);
                          }
                        },
                        onSubmitted: _submitPasscode,
                      ),
                    ],
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _localizedError(l10n, state.errorMessage!),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFFF8A8A)
                              : AppColors.error,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _localizedError(AppLocalizations l10n, String message) {
    if (l10n.language == AppLanguage.zhCN) return message;
    if (message == '锁定密码不正确') {
      return _lockText(
        l10n,
        zhCN: message,
        zhTW: '鎖定密碼不正確',
        en: 'Incorrect app lock passcode',
      );
    }
    if (message == '请先在系统设置中录入面容或指纹') {
      return _lockText(
        l10n,
        zhCN: message,
        zhTW: '請先在系統設定中錄入 Face ID 或指紋',
        en: 'Set up Face ID or fingerprint in system settings first',
      );
    }
    return message;
  }

  String _lockText(
    AppLocalizations l10n, {
    required String zhCN,
    required String zhTW,
    required String en,
  }) {
    switch (l10n.language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }
}
