import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';

class BindPhonePage extends ConsumerStatefulWidget {
  const BindPhonePage({super.key});

  @override
  ConsumerState<BindPhonePage> createState() => _BindPhonePageState();
}

class _BindPhonePageState extends ConsumerState<BindPhonePage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  int _cooldown = 0;
  Timer? _timer;
  bool _busy = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showMessage('请输入手机号');
      return;
    }
    if (_cooldown > 0) return;

    setState(() => _busy = true);
    final res =
        await ref.read(authServiceProvider.notifier).sendPhoneBindCode(phone);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res.isSuccess) {
      _showMessage('验证码已发送');
      setState(() => _cooldown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _cooldown--;
          if (_cooldown <= 0) t.cancel();
        });
      });
    } else {
      _showMessage(res.message);
    }
  }

  Future<void> _bind() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _showMessage('请填写手机号和验证码');
      return;
    }

    setState(() => _busy = true);
    final res =
        await ref.read(authServiceProvider.notifier).bindPhone(phone, code);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res.isSuccess) {
      _showMessage('绑定成功');
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        context.go('/home');
      }
    } else {
      _showMessage(res.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(systemSettingsProvider);
    final ready = asyncSettings.maybeWhen(
        data: (s) => s.smsBindReady, orElse: () => false);

    return Scaffold(
      appBar: AppBar(title: const Text('绑定手机号')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '当前服务器未开启短信服务，无法发送验证码。请在管理后台配置并启用短信网关。',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 14),
              ),
            ),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '手机号',
              hintText: '11 位中国大陆手机号',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 136,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(136, 56),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: (!ready || _busy) ? null : _sendCode,
                  child: Text(
                    _cooldown > 0 ? '${_cooldown}s' : '获取验证码',
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: (!ready || _busy) ? null : _bind,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认绑定'),
          ),
        ],
      ),
    );
  }
}
