import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/theme_provider.dart';

/// 气泡颜色 Provider
final bubbleColorProvider = StateNotifierProvider<BubbleColorNotifier, BubbleColors>((ref) {
  return BubbleColorNotifier();
});

class BubbleColors {
  final Color outgoing;
  final Color incoming;
  
  const BubbleColors({
    this.outgoing = const Color(0xFFDDD6FE),  // 薰衣草
    this.incoming = const Color(0xFFF5F3FF),
  });
  
  BubbleColors copyWith({Color? outgoing, Color? incoming}) {
    return BubbleColors(
      outgoing: outgoing ?? this.outgoing,
      incoming: incoming ?? this.incoming,
    );
  }
}

class BubbleColorNotifier extends StateNotifier<BubbleColors> {
  BubbleColorNotifier() : super(const BubbleColors()) {
    _loadColors();
  }
  
  static const String _outgoingKey = 'bubble_outgoing_color';
  static const String _incomingKey = 'bubble_incoming_color';
  static const String _presetIndexKey = 'bubble_preset_index';
  
  int _presetIndex = 10;  // 默认薰衣草，索引10
  int get presetIndex => _presetIndex;
  
  Future<void> _loadColors() async {
    final prefs = await SharedPreferences.getInstance();
    final outgoingValue = prefs.getInt(_outgoingKey);
    final incomingValue = prefs.getInt(_incomingKey);
    _presetIndex = prefs.getInt(_presetIndexKey) ?? 0;
    
    if (outgoingValue != null || incomingValue != null) {
      state = BubbleColors(
        outgoing: outgoingValue != null ? Color(outgoingValue) : const Color(0xFFDDD6FE),
        incoming: incomingValue != null ? Color(incomingValue) : const Color(0xFFF5F3FF),
      );
    }
  }
  
  Future<void> setOutgoingColor(Color color) async {
    state = state.copyWith(outgoing: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_outgoingKey, color.value);
  }
  
  Future<void> setIncomingColor(Color color) async {
    state = state.copyWith(incoming: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_incomingKey, color.value);
  }
  
  Future<void> setPresetIndex(int index) async {
    _presetIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_presetIndexKey, index);
  }
}

/// 消息设置 Provider
final messageSettingsProvider = StateNotifierProvider<MessageSettingsNotifier, MessageSettings>((ref) {
  return MessageSettingsNotifier();
});

class MessageSettings {
  final bool showPreview;
  final bool showLinkPreview;
  final bool autoDownloadImages;
  final bool autoDownloadVideos;
  final bool autoPlayGif;
  final double fontSize;
  
  const MessageSettings({
    this.showPreview = true,
    this.showLinkPreview = true,
    this.autoDownloadImages = true,
    this.autoDownloadVideos = false,
    this.autoPlayGif = true,
    this.fontSize = 16,
  });
  
  MessageSettings copyWith({
    bool? showPreview,
    bool? showLinkPreview,
    bool? autoDownloadImages,
    bool? autoDownloadVideos,
    bool? autoPlayGif,
    double? fontSize,
  }) {
    return MessageSettings(
      showPreview: showPreview ?? this.showPreview,
      showLinkPreview: showLinkPreview ?? this.showLinkPreview,
      autoDownloadImages: autoDownloadImages ?? this.autoDownloadImages,
      autoDownloadVideos: autoDownloadVideos ?? this.autoDownloadVideos,
      autoPlayGif: autoPlayGif ?? this.autoPlayGif,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

class MessageSettingsNotifier extends StateNotifier<MessageSettings> {
  MessageSettingsNotifier() : super(const MessageSettings()) {
    _loadSettings();
  }
  
  static const String _showPreviewKey = 'msg_show_preview';
  static const String _showLinkPreviewKey = 'msg_show_link_preview';
  static const String _autoDownloadImagesKey = 'msg_auto_download_images';
  static const String _autoDownloadVideosKey = 'msg_auto_download_videos';
  static const String _autoPlayGifKey = 'msg_auto_play_gif';
  static const String _fontSizeKey = 'msg_font_size';
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = MessageSettings(
      showPreview: prefs.getBool(_showPreviewKey) ?? true,
      showLinkPreview: prefs.getBool(_showLinkPreviewKey) ?? true,
      autoDownloadImages: prefs.getBool(_autoDownloadImagesKey) ?? true,
      autoDownloadVideos: prefs.getBool(_autoDownloadVideosKey) ?? false,
      autoPlayGif: prefs.getBool(_autoPlayGifKey) ?? true,
      fontSize: prefs.getDouble(_fontSizeKey) ?? 16,
    );
  }
  
  Future<void> setShowPreview(bool value) async {
    state = state.copyWith(showPreview: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showPreviewKey, value);
  }
  
  Future<void> setShowLinkPreview(bool value) async {
    state = state.copyWith(showLinkPreview: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showLinkPreviewKey, value);
  }
  
  Future<void> setAutoDownloadImages(bool value) async {
    state = state.copyWith(autoDownloadImages: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoDownloadImagesKey, value);
  }
  
  Future<void> setAutoDownloadVideos(bool value) async {
    state = state.copyWith(autoDownloadVideos: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoDownloadVideosKey, value);
  }
  
  Future<void> setAutoPlayGif(bool value) async {
    state = state.copyWith(autoPlayGif: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayGifKey, value);
  }
  
  Future<void> setFontSize(double value) async {
    state = state.copyWith(fontSize: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, value);
  }
}

class ChatSettingsPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;
  
  const ChatSettingsPage({
    super.key,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends ConsumerState<ChatSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final chatBackground = ref.watch(chatBackgroundProvider);
    final bubbleColors = ref.watch(bubbleColorProvider);
    final messageSettings = ref.watch(messageSettingsProvider);

    // 桌面端面板模式：只返回内容，不需要 Scaffold 和 AppBar
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, chatBackground, bubbleColors, messageSettings, l10n);
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(l10n.chatSettings),
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        elevation: 0,
      ),
      body: _buildBody(isDark, chatBackground, bubbleColors, messageSettings, l10n),
    );
  }

  Widget _buildBody(bool isDark, ChatBackground chatBackground, BubbleColors bubbleColors, MessageSettings messageSettings, AppLocalizations l10n) {
    return ListView(
        children: [
          // ============ 消息 ============
          _SectionHeader(title: l10n.get('messages') ?? '消息', isDark: isDark),
          _SettingsCard(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: l10n.get('message_preview') ?? '消息预览',
                subtitle: l10n.get('show_message_in_notification') ?? '在通知中显示消息内容',
                value: messageSettings.showPreview,
                onChanged: (v) => ref.read(messageSettingsProvider.notifier).setShowPreview(v),
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
              _SwitchTile(
                title: l10n.get('link_preview') ?? '链接预览',
                subtitle: l10n.get('show_link_preview_in_message') ?? '在消息中显示网页预览',
                value: messageSettings.showLinkPreview,
                onChanged: (v) => ref.read(messageSettingsProvider.notifier).setShowLinkPreview(v),
                isDark: isDark,
              ),
            ],
          ),
          
          // ============ 外观 ============
          _SectionHeader(title: l10n.appearance, isDark: isDark),
          _SettingsCard(
            isDark: isDark,
            children: [
              // 聊天背景
              _buildBackgroundTile(context, isDark, chatBackground, l10n),
              _Divider(isDark: isDark),
              // 气泡颜色
              _buildBubbleColorTile(context, isDark, bubbleColors, l10n),
              _Divider(isDark: isDark),
              // 字体大小
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.get('font_size') ?? '字体大小',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(l10n.get('small') ?? '小', style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        )),
                        Expanded(
                          child: Slider(
                            value: messageSettings.fontSize,
                            min: 12,
                            max: 24,
                            divisions: 6,
                            activeColor: AppColors.primary,
                            onChanged: (v) => ref.read(messageSettingsProvider.notifier).setFontSize(v),
                          ),
                        ),
                        Text(l10n.get('large') ?? '大', style: TextStyle(
                          fontSize: 20,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        )),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // ============ 媒体 ============
          _SectionHeader(title: l10n.get('media') ?? '媒体', isDark: isDark),
          _SettingsCard(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: '自动下载图片',
                value: messageSettings.autoDownloadImages,
                onChanged: (v) => ref.read(messageSettingsProvider.notifier).setAutoDownloadImages(v),
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
              _SwitchTile(
                title: '自动下载视频',
                value: messageSettings.autoDownloadVideos,
                onChanged: (v) => ref.read(messageSettingsProvider.notifier).setAutoDownloadVideos(v),
                isDark: isDark,
              ),
              _Divider(isDark: isDark),
              _SwitchTile(
                title: '自动播放GIF',
                value: messageSettings.autoPlayGif,
                onChanged: (v) => ref.read(messageSettingsProvider.notifier).setAutoPlayGif(v),
                isDark: isDark,
              ),
            ],
          ),
          
          const SizedBox(height: 32),
        ],
      );
  }

  /// 构建聊天背景设置项
  Widget _buildBackgroundTile(BuildContext context, bool isDark, ChatBackground chatBackground, AppLocalizations l10n) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('[ChatSettings] 点击聊天背景');
        _showBackgroundPicker(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.get('chat_background') ?? '聊天背景',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ),
            Text(
              l10n.get('custom_chat_background') ?? '自定义聊天背景',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(width: 8),
            // 背景预览
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: chatBackground.gradient,
                color: chatBackground.solidColor ?? const Color(0xFFE8D5E0),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建气泡颜色设置项
  Widget _buildBubbleColorTile(BuildContext context, bool isDark, BubbleColors bubbleColors, AppLocalizations l10n) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('[ChatSettings] 点击气泡颜色');
        _showBubbleColorPicker(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.get('bubble_color') ?? '气泡颜色',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ),
            Text(
              l10n.get('default') ?? '默认',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(width: 8),
            // 气泡颜色预览
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: bubbleColors.incoming,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: bubbleColors.outgoing,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 显示背景选择器
  void _showBackgroundPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BackgroundPickerSheet(isDark: isDark),
    );
  }

  /// 显示气泡颜色选择器
  void _showBubbleColorPicker(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BubbleColorPickerSheet(isDark: isDark),
    );
  }
}

/// 背景选择器底部弹窗
class _BackgroundPickerSheet extends ConsumerStatefulWidget {
  final bool isDark;
  
  const _BackgroundPickerSheet({required this.isDark});

  @override
  ConsumerState<_BackgroundPickerSheet> createState() => _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState extends ConsumerState<_BackgroundPickerSheet> {
  int _selectedIndex = 10;  // 默认日落橙
  
  @override
  void initState() {
    super.initState();
    // 从 Provider 读取保存的索引
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedIndex = ref.read(chatBackgroundProvider.notifier).gradientIndex;
      if (savedIndex != _selectedIndex && savedIndex < _gradientPresets.length) {
        setState(() => _selectedIndex = savedIndex);
      }
    });
  }
  
  // TG 风格高级渐变背景色
  static const List<List<Color>> _gradientPresets = [
    // === 经典   ===
    // 紫粉渐变（默认）
    [Color(0xFFE8D5E0), Color(0xFFD4C5E0), Color(0xFFC5D0E8)],
    // 蓝绿渐变
    [Color(0xFFB8E6CF), Color(0xFFA8D8EA), Color(0xFFB8D4E3)],
    // 橙粉渐变
    [Color(0xFFFDE2C8), Color(0xFFFAD0C4), Color(0xFFF5C4D4)],
    // 蓝紫渐变
    [Color(0xFFC9D6FF), Color(0xFFD4C5E0), Color(0xFFE2B0FF)],
    
    // === 高级渐变 ===
    // 极光蓝紫
    [Color(0xFF667EEA), Color(0xFF64B5F6), Color(0xFFA5D6A7)],
    // 晚霞粉橙
    [Color(0xFFFF9A9E), Color(0xFFFECFEF), Color(0xFFFECDD3)],
    // 薄荷清新
    [Color(0xFF84FAB0), Color(0xFF8FD3F4), Color(0xFFD4FC79)],
    // 梦幻紫蓝
    [Color(0xFFA18CD1), Color(0xFFFBC2EB), Color(0xFFD4C5E0)],
    
    // === 自然色系 ===
    // 玫瑰金
    [Color(0xFFFCE4EC), Color(0xFFF8BBD9), Color(0xFFF48FB1)],
    // 薄荷绿
    [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF80DEEA)],
    // 日落橙
    [Color(0xFFFFE5B4), Color(0xFFFFCBA4), Color(0xFFFFB088)],
    // 薰衣草
    [Color(0xFFE6E6FA), Color(0xFFD8BFD8), Color(0xFFDDA0DD)],
    
    // === 高级质感 ===
    // 星空蓝
    [Color(0xFF2C3E50), Color(0xFF4CA1AF), Color(0xFF89CFF0)],
    // 深海蓝绿
    [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    // 极光绿
    [Color(0xFF11998E), Color(0xFF38EF7D), Color(0xFF84FAB0)],
    // 晨曦金
    [Color(0xFFF2994A), Color(0xFFF2C94C), Color(0xFFFFF8DC)],
    
    // === 柔和色系 ===
    // 森林绿
    [Color(0xFFE8F5E9), Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
    // 海洋蓝
    [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
    // 暖阳黄
    [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFFFE082)],
    // 珊瑚粉
    [Color(0xFFFFE4E1), Color(0xFFFFB6C1), Color(0xFFFFA07A)],
    
    // === 高级商务 ===
    // 靛蓝渐变
    [Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFC7D2FE)],
    // 翠绿商务
    [Color(0xFF059669), Color(0xFF34D399), Color(0xFFA7F3D0)],
    // 琥珀金
    [Color(0xFFD97706), Color(0xFFFBBF24), Color(0xFFFDE68A)],
    // 玫红商务
    [Color(0xFFDB2777), Color(0xFFF472B6), Color(0xFFFBCFE8)],
  ];

  @override
  Widget build(BuildContext context) {
    final chatBackground = ref.watch(chatBackgroundProvider);
    final bubbleColors = ref.watch(bubbleColorProvider);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖动条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '聊天背景',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '完成',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 预览区域
          Container(
            height: 280,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // 背景
                  _buildPreviewBackground(),
                  // 示例消息
                  Positioned(
                    left: 16,
                    top: 60,
                    child: _PreviewBubble(
                      text: '你好！今天怎么样？',
                      isOutgoing: false,
                      color: bubbleColors.incoming,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 120,
                    child: _PreviewBubble(
                      text: '很好，谢谢！你呢？',
                      isOutgoing: true,
                      color: bubbleColors.outgoing,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 180,
                    child: _PreviewBubble(
                      text: '我也很好 😊',
                      isOutgoing: false,
                      color: bubbleColors.incoming,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 背景选择网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: _gradientPresets.length,
              itemBuilder: (context, index) {
                final colors = _gradientPresets[index];
                final isSelected = _selectedIndex == index;
                
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedIndex = index);
                    
                    final gradient = LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: colors,
                    );
                    ref.read(chatBackgroundProvider.notifier).setGradient(gradient, presetIndex: index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: AppColors.primary, width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isSelected ? 9 : 12),
                      child: Stack(
                        children: [
                          // 渐变背景
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: colors,
                              ),
                            ),
                          ),
                          // SVG 图案
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0.2,
                              child: SvgPicture.asset(
                                'assets/images/backgrounds/bg5.svg',
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          // 选中标记
                          if (isSelected)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // 自定义选项
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _CustomOptionButton(
                    icon: Icons.photo_library_outlined,
                    label: '从相册选择',
                    onTap: () {
                      // TODO: 从相册选择图片
                    },
                    isDark: widget.isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CustomOptionButton(
                    icon: Icons.color_lens_outlined,
                    label: '纯色背景',
                    onTap: () => _showSolidColorPicker(context),
                    isDark: widget.isDark,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
  
  Widget _buildPreviewBackground() {
    final colors = _gradientPresets[_selectedIndex];
    
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.15,
            child: SvgPicture.asset(
              'assets/images/backgrounds/bg5.svg',
              fit: BoxFit.cover,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  void _showSolidColorPicker(BuildContext context) {
    final solidColors = [
      const Color(0xFFDFE7EB),
      const Color(0xFFCCE5D6),
      const Color(0xFFE5DFD0),
      const Color(0xFFD8D0E5),
      const Color(0xFFD0E0E5),
      const Color(0xFFE5D0D8),
      const Color(0xFFF5F5F5),
      const Color(0xFFE8E8E8),
    ];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择纯色背景'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: solidColors.map((color) {
            return GestureDetector(
              onTap: () {
                ref.read(chatBackgroundProvider.notifier).setSolidColor(color);
                Navigator.pop(context);
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 气泡颜色选择器底部弹窗
class _BubbleColorPickerSheet extends ConsumerStatefulWidget {
  final bool isDark;
  
  const _BubbleColorPickerSheet({required this.isDark});

  @override
  ConsumerState<_BubbleColorPickerSheet> createState() => _BubbleColorPickerSheetState();
}

class _BubbleColorPickerSheetState extends ConsumerState<_BubbleColorPickerSheet> {
  int _selectedPresetIndex = 10;  // 默认薰衣草
  
  @override
  void initState() {
    super.initState();
    // 从 Provider 读取保存的索引
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedIndex = ref.read(bubbleColorProvider.notifier).presetIndex;
      if (savedIndex != _selectedPresetIndex && savedIndex < _bubblePresets.length) {
        setState(() => _selectedPresetIndex = savedIndex);
      }
    });
  }
  
  // 气泡颜色预设
  static const List<Map<String, Color>> _bubblePresets = [
    // === 经典风格 ===
    // 默认 (TG 风格)
    {'outgoing': Color(0xFFEFFEDD), 'incoming': Colors.white},
    // 经典蓝
    {'outgoing': Color(0xFFD6EAF8), 'incoming': Color(0xFFF8F9FA)},
    // 经典紫
    {'outgoing': Color(0xFFE8DAEF), 'incoming': Color(0xFFF5EEF8)},
    // 经典绿
    {'outgoing': Color(0xFFD5F5E3), 'incoming': Color(0xFFF0FFF0)},
    
    // === 高级配色 ===
    // 靛蓝商务
    {'outgoing': Color(0xFFC7D2FE), 'incoming': Color(0xFFF1F5F9)},
    // 翠绿清新
    {'outgoing': Color(0xFFA7F3D0), 'incoming': Color(0xFFF0FDF4)},
    // 玫瑰优雅
    {'outgoing': Color(0xFFFBCFE8), 'incoming': Color(0xFFFDF2F8)},
    // 琥珀温暖
    {'outgoing': Color(0xFFFDE68A), 'incoming': Color(0xFFFFFBEB)},
    
    // === 柔和色系 ===
    // 蜜桃粉
    {'outgoing': Color(0xFFFFD5CD), 'incoming': Color(0xFFFFF5F3)},
    // 薄荷青
    {'outgoing': Color(0xFFB2F5EA), 'incoming': Color(0xFFF0FDFA)},
    // 薰衣草
    {'outgoing': Color(0xFFDDD6FE), 'incoming': Color(0xFFF5F3FF)},
    // 奶油黄
    {'outgoing': Color(0xFFFEF3C7), 'incoming': Color(0xFFFFFBEB)},
    
    // === 高级质感 ===
    // 深空蓝
    {'outgoing': Color(0xFF93C5FD), 'incoming': Color(0xFFEFF6FF)},
    // 森林绿
    {'outgoing': Color(0xFF86EFAC), 'incoming': Color(0xFFECFDF5)},
    // 珊瑚橙
    {'outgoing': Color(0xFFFED7AA), 'incoming': Color(0xFFFFF7ED)},
    // 樱花粉
    {'outgoing': Color(0xFFF9A8D4), 'incoming': Color(0xFFFCE7F3)},
    
    // === 极简风格 ===
    // 纯白简约
    {'outgoing': Color(0xFFF1F5F9), 'incoming': Color(0xFFFFFFFF)},
    // 银灰高级
    {'outgoing': Color(0xFFE2E8F0), 'incoming': Color(0xFFF8FAFC)},
    // 暖灰舒适
    {'outgoing': Color(0xFFE7E5E4), 'incoming': Color(0xFFFAFAF9)},
    // 冷灰科技
    {'outgoing': Color(0xFFD4D4D8), 'incoming': Color(0xFFF4F4F5)},
  ];

  @override
  Widget build(BuildContext context) {
    final chatBackground = ref.watch(chatBackgroundProvider);
    final bubbleColors = ref.watch(bubbleColorProvider);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖动条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '气泡颜色',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '完成',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 预览区域
          Container(
            height: 180,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // 背景
                  Container(
                    decoration: BoxDecoration(
                      gradient: chatBackground.gradient ?? const LinearGradient(
                        colors: [Color(0xFFE8D5E0), Color(0xFFD4C5E0), Color(0xFFC5D0E8)],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.15,
                      child: SvgPicture.asset(
                        'assets/images/backgrounds/bg5.svg',
                        fit: BoxFit.cover,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  // 示例消息
                  Positioned(
                    left: 16,
                    top: 40,
                    child: _PreviewBubble(
                      text: '收到的消息',
                      isOutgoing: false,
                      color: bubbleColors.incoming,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 100,
                    child: _PreviewBubble(
                      text: '发送的消息',
                      isOutgoing: true,
                      color: bubbleColors.outgoing,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 预设选项
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '预设配色',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // 气泡颜色网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: _bubblePresets.length,
              itemBuilder: (context, index) {
                final preset = _bubblePresets[index];
                final isSelected = _selectedPresetIndex == index;
                
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedPresetIndex = index);
                    ref.read(bubbleColorProvider.notifier).setOutgoingColor(preset['outgoing']!);
                    ref.read(bubbleColorProvider.notifier).setIncomingColor(preset['incoming']!);
                    ref.read(bubbleColorProvider.notifier).setPresetIndex(index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: AppColors.primary, width: 2)
                          : Border.all(color: Colors.grey.withOpacity(0.15)),
                      color: widget.isDark ? AppColors.darkCard : Colors.white,
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ] : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 收到的气泡颜色
                        Container(
                          width: 36,
                          height: 14,
                          decoration: BoxDecoration(
                            color: preset['incoming'],
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.grey.withOpacity(0.15)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        // 发送的气泡颜色
                        Container(
                          width: 36,
                          height: 14,
                          decoration: BoxDecoration(
                            color: preset['outgoing'],
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.grey.withOpacity(0.15)),
                          ),
                        ),
                        // 选中标记
                        if (isSelected) ...[
                          const SizedBox(height: 4),
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

/// 预览气泡
class _PreviewBubble extends StatelessWidget {
  final String text;
  final bool isOutgoing;
  final Color color;

  const _PreviewBubble({
    required this.text,
    required this.isOutgoing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
          bottomRight: Radius.circular(isOutgoing ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// 自定义选项按钮
class _CustomOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _CustomOptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置卡片
class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsCard({
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

/// 分割线
class _Divider extends StatelessWidget {
  final bool isDark;

  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
    );
  }
}

/// 开关设置项
class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 导航设置项
class _NavigationTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool isDark;

  const _NavigationTile({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}
