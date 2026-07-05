import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';

/// 您的颜色设置页面
class PersonalizationPage extends ConsumerStatefulWidget {
  const PersonalizationPage({super.key});

  @override
  ConsumerState<PersonalizationPage> createState() => _PersonalizationPageState();
}

class _PersonalizationPageState extends ConsumerState<PersonalizationPage> {
  int _selectedProfileBgIndex = 0;
  int _selectedNameColorIndex = 0;
  bool _isSaving = false;

  // 个人资料页背景渐变色
  final List<List<Color>> _profileBgGradients = [
    [const Color(0xFF5B9EE1), const Color(0xFF2575BC)], // 蓝色
    [const Color(0xFF43C6AC), const Color(0xFF1D976C)], // 绿色
    [const Color(0xFFFFB347), const Color(0xFFFF8008)], // 橙色
    [const Color(0xFFFF6B6B), const Color(0xFFEE0979)], // 红色
    [const Color(0xFFA18CD1), const Color(0xFF6A3093)], // 紫色
    [const Color(0xFF4ECDC4), const Color(0xFF009688)], // 青色
    [const Color(0xFFFF9A9E), const Color(0xFFFECFEF)], // 粉色
    [const Color(0xFF8E9AAF), const Color(0xFF5C6B7A)], // 灰色
  ];

  // 昵称颜色
  final List<dynamic> _nameColors = [
    const Color(0xFF3390EC), // 蓝色
    const Color(0xFF4FAE4E), // 绿色
    const Color(0xFFF5A623), // 橙色
    const Color(0xFFE05656), // 红色
    const Color(0xFF9B7CE0), // 紫色
    const Color(0xFF50B6C5), // 青色
    const Color(0xFFFF7EB3), // 粉色
    const Color(0xFF7D8B99), // 灰色
    // 双色渐变
    [const Color(0xFF5B9EE1), const Color(0xFF54C7A6)],
    [const Color(0xFF54C7A6), const Color(0xFFB8E986)],
    [const Color(0xFFF5A623), const Color(0xFFE05656)],
    [const Color(0xFF9B7CE0), const Color(0xFF50B6C5)],
    [const Color(0xFF50B6C5), const Color(0xFF5B9EE1)],
    [const Color(0xFFFF7EB3), const Color(0xFFF5A623)],
    [const Color(0xFF5B9EE1), const Color(0xFF9B7CE0)],
    [const Color(0xFFE05656), const Color(0xFF9B7CE0)],
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    final user = ref.read(authServiceProvider).user;
    if (user != null && user.nicknameColor != null && user.nicknameColor!.isNotEmpty) {
      final parts = user.nicknameColor!.split(',');
      for (final part in parts) {
        if (part.startsWith('bg:')) {
          _selectedProfileBgIndex = int.tryParse(part.substring(3)) ?? 0;
        } else if (part.startsWith('name:')) {
          _selectedNameColorIndex = int.tryParse(part.substring(5)) ?? 0;
        }
      }
      _selectedProfileBgIndex = _selectedProfileBgIndex.clamp(0, _profileBgGradients.length - 1);
      _selectedNameColorIndex = _selectedNameColorIndex.clamp(0, _nameColors.length - 1);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiClientProvider);
      final colorValue = 'bg:$_selectedProfileBgIndex,name:$_selectedNameColorIndex';
      final response = await api.put('/user/me', data: {'nickname_color': colorValue});
      if (response.isSuccess) {
        await ref.read(authServiceProvider.notifier).getCurrentUser();
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
      } else {
        throw AppCleanException(response.message);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<Color> get _currentBgGradient => _profileBgGradients[_selectedProfileBgIndex];
  Color get _currentBgColor => _currentBgGradient[0];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authServiceProvider).user;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final displayName = user?.nickname ?? user?.username ?? l10n.get('user') ?? '用户';
    final avatar = user?.avatar;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.get('personalization_settings') ?? '个性化设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 资料页预览
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _currentBgGradient,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // SVG 背景图案
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.2,
                          child: SvgPicture.asset(
                            'assets/images/backgrounds/bg5.svg',
                            fit: BoxFit.cover,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ),
                      ),
                      // 内容
                      Positioned.fill(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 头像
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: ClipOval(child: _buildAvatar(displayName, avatar, 74)),
                              ),
                              const SizedBox(height: 12),
                              // 昵称（带颜色）
                              _buildColoredName(displayName, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 资料背景颜色
                _buildSectionTitle(l10n.get('profile_background') ?? '资料背景', isDark),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(_profileBgGradients.length, (index) {
                      final isSelected = _selectedProfileBgIndex == index;
                      final colors = _profileBgGradients[index];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedProfileBgIndex = index);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: colors,
                            ),
                            border: isSelected
                                ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 2.5)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                              : null,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    l10n.get('profile_background_hint') ?? '其他人查看您的资料时会看到此背景',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                const SizedBox(height: 24),

                // 昵称颜色
                _buildSectionTitle(l10n.get('nickname_color') ?? '昵称颜色', isDark),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(_nameColors.length, (index) {
                      final colorItem = _nameColors[index];
                      final isSelected = _selectedNameColorIndex == index;
                      final isGradient = colorItem is List<Color>;

                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedNameColorIndex = index);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isGradient ? null : colorItem as Color,
                            gradient: isGradient
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: colorItem as List<Color>,
                                  )
                                : null,
                            border: isSelected
                                ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 2.5)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                              : null,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    l10n.get('nickname_color_hint') ?? '在群聊和频道中显示的昵称颜色',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // 底部按钮
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewPadding.bottom + 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                ),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l10n.save, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
    );
  }

  /// 构建头像（避免闪烁）
  Widget _buildAvatar(String name, String? avatarUrl, double size) {
    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => _buildDefaultAvatar(firstLetter, size),
        errorWidget: (_, __, ___) => _buildDefaultAvatar(firstLetter, size),
      );
    }
    return _buildDefaultAvatar(firstLetter, size);
  }

  /// 默认头像
  Widget _buildDefaultAvatar(String letter, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _currentBgColor,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 带颜色的昵称
  Widget _buildColoredName(String name, {double size = 15}) {
    final colorItem = _nameColors[_selectedNameColorIndex];
    final isGradient = colorItem is List<Color>;

    if (isGradient) {
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(colors: colorItem as List<Color>).createShader(bounds),
        child: Text(
          name,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
      );
    }
    return Text(
      name,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: colorItem as Color,
        shadows: const [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
    );
  }
}
