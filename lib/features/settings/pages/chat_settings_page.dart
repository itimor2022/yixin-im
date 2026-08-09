// 文件用途：实现 BubbleColors 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 BubbleColors 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/theme_provider.dart';

String _chatSettingsText(
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

/// 气泡颜色 Provider
final bubbleColorProvider =
    StateNotifierProvider<BubbleColorNotifier, BubbleColors>((ref) {
  return BubbleColorNotifier();
});

// 关键声明：chat settings page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class BubbleColors {
  final Color outgoing;
  final Color incoming;

  const BubbleColors({
    this.outgoing = const Color(0xFFD4D4D8),
    this.incoming = const Color(0xFFF4F4F5),
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

  static const int _defaultPresetIndex = 19;
  static const Color _defaultOutgoing = Color(0xFFD4D4D8);
  static const Color _defaultIncoming = Color(0xFFF4F4F5);
  static const Color _legacyDefaultOutgoing = Color(0xFFDDD6FE);
  static const Color _legacyDefaultIncoming = Color(0xFFF5F3FF);
  static const String _outgoingKey = 'bubble_outgoing_color';
  static const String _incomingKey = 'bubble_incoming_color';
  static const String _presetIndexKey = 'bubble_preset_index';

  int _presetIndex = _defaultPresetIndex; // 默认冷灰科技，索引19
  int get presetIndex => _presetIndex;

  Future<void> _loadColors() async {
    final prefs = await SharedPreferences.getInstance();
    final outgoingValue = prefs.getInt(_outgoingKey);
    final incomingValue = prefs.getInt(_incomingKey);
    _presetIndex = prefs.getInt(_presetIndexKey) ?? _defaultPresetIndex;

    final isLegacyDefault = (outgoingValue == null &&
            incomingValue == null &&
            _presetIndex == 10) ||
        (outgoingValue == _legacyDefaultOutgoing.value &&
            incomingValue == _legacyDefaultIncoming.value);

    if (isLegacyDefault) {
      _presetIndex = _defaultPresetIndex;
      state = const BubbleColors();
      await prefs.setInt(_presetIndexKey, _defaultPresetIndex);
      await prefs.setInt(_outgoingKey, _defaultOutgoing.value);
      await prefs.setInt(_incomingKey, _defaultIncoming.value);
      return;
    }

    if (outgoingValue != null || incomingValue != null) {
      state = BubbleColors(
        outgoing:
            outgoingValue != null ? Color(outgoingValue) : _defaultOutgoing,
        incoming:
            incomingValue != null ? Color(incomingValue) : _defaultIncoming,
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
final messageSettingsProvider =
    StateNotifierProvider<MessageSettingsNotifier, MessageSettings>((ref) {
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
      return _buildBody(
          isDark, chatBackground, bubbleColors, messageSettings, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(l10n.chatSettings),
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        elevation: 0,
      ),
      body: _buildBody(
          isDark, chatBackground, bubbleColors, messageSettings, l10n),
    );
  }

  Widget _buildBody(
      bool isDark,
      ChatBackground chatBackground,
      BubbleColors bubbleColors,
      MessageSettings messageSettings,
      AppLocalizations l10n) {
    return ListView(
      children: [
        // ============ 消息 ============
        _SectionHeader(
          title: l10n.get('messages') ??
              _chatSettingsText(
                context,
                zhCN: '消息',
                zhTW: '訊息',
                en: 'Messages',
              ),
          isDark: isDark,
        ),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.get('message_preview') ??
                  _chatSettingsText(
                    context,
                    zhCN: '消息预览',
                    zhTW: '訊息預覽',
                    en: 'Message Preview',
                  ),
              subtitle: l10n.get('show_message_in_notification') ??
                  _chatSettingsText(
                    context,
                    zhCN: '在通知中显示消息内容',
                    zhTW: '在通知中顯示訊息內容',
                    en: 'Show message content in notifications',
                  ),
              value: messageSettings.showPreview,
              onChanged: (v) =>
                  ref.read(messageSettingsProvider.notifier).setShowPreview(v),
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              title: l10n.get('link_preview') ??
                  _chatSettingsText(
                    context,
                    zhCN: '链接预览',
                    zhTW: '連結預覽',
                    en: 'Link Preview',
                  ),
              subtitle: l10n.get('show_link_preview_in_message') ??
                  _chatSettingsText(
                    context,
                    zhCN: '在消息中显示网页预览',
                    zhTW: '在訊息中顯示網頁預覽',
                    en: 'Show web previews in messages',
                  ),
              value: messageSettings.showLinkPreview,
              onChanged: (v) => ref
                  .read(messageSettingsProvider.notifier)
                  .setShowLinkPreview(v),
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
                    l10n.get('font_size') ??
                        _chatSettingsText(
                          context,
                          zhCN: '字体大小',
                          zhTW: '字體大小',
                          en: 'Font Size',
                        ),
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                          l10n.get('small') ??
                              _chatSettingsText(
                                context,
                                zhCN: '小',
                                zhTW: '小',
                                en: 'Small',
                              ),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryFor(context),
                          )),
                      Expanded(
                        child: Slider(
                          value: messageSettings.fontSize,
                          min: 12,
                          max: 24,
                          divisions: 6,
                          activeColor: AppColors.controlActiveFor(context),
                          onChanged: (v) => ref
                              .read(messageSettingsProvider.notifier)
                              .setFontSize(v),
                        ),
                      ),
                      Text(
                          l10n.get('large') ??
                              _chatSettingsText(
                                context,
                                zhCN: '大',
                                zhTW: '大',
                                en: 'Large',
                              ),
                          style: TextStyle(
                            fontSize: 20,
                            color: AppColors.textSecondaryFor(context),
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // ============ 媒体 ============
        _SectionHeader(
          title: l10n.get('media') ??
              _chatSettingsText(
                context,
                zhCN: '媒体',
                zhTW: '媒體',
                en: 'Media',
              ),
          isDark: isDark,
        ),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: _chatSettingsText(
                context,
                zhCN: '自动下载图片',
                zhTW: '自動下載圖片',
                en: 'Auto-Download Images',
              ),
              value: messageSettings.autoDownloadImages,
              onChanged: (v) => ref
                  .read(messageSettingsProvider.notifier)
                  .setAutoDownloadImages(v),
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              title: _chatSettingsText(
                context,
                zhCN: '自动下载视频',
                zhTW: '自動下載影片',
                en: 'Auto-Download Videos',
              ),
              value: messageSettings.autoDownloadVideos,
              onChanged: (v) => ref
                  .read(messageSettingsProvider.notifier)
                  .setAutoDownloadVideos(v),
              isDark: isDark,
            ),
            _Divider(isDark: isDark),
            _SwitchTile(
              title: _chatSettingsText(
                context,
                zhCN: '自动播放GIF',
                zhTW: '自動播放 GIF',
                en: 'Auto-Play GIFs',
              ),
              value: messageSettings.autoPlayGif,
              onChanged: (v) =>
                  ref.read(messageSettingsProvider.notifier).setAutoPlayGif(v),
              isDark: isDark,
            ),
          ],
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  /// 构建聊天背景设置项
  Widget _buildBackgroundTile(BuildContext context, bool isDark,
      ChatBackground chatBackground, AppLocalizations l10n) {
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
                l10n.get('chat_background') ??
                    _chatSettingsText(
                      context,
                      zhCN: '聊天背景',
                      zhTW: '聊天背景',
                      en: 'Chat Background',
                    ),
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ),
            Text(
              l10n.get('custom_chat_background') ??
                  _chatSettingsText(
                    context,
                    zhCN: '自定义聊天背景',
                    zhTW: '自訂聊天背景',
                    en: 'Custom Chat Background',
                  ),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryFor(context),
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
              color: AppColors.textSecondaryFor(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建气泡颜色设置项
  Widget _buildBubbleColorTile(BuildContext context, bool isDark,
      BubbleColors bubbleColors, AppLocalizations l10n) {
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
                l10n.get('bubble_color') ??
                    _chatSettingsText(
                      context,
                      zhCN: '气泡颜色',
                      zhTW: '氣泡顏色',
                      en: 'Bubble Color',
                    ),
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ),
            Text(
              l10n.get('default') ??
                  _chatSettingsText(
                    context,
                    zhCN: '默认',
                    zhTW: '預設',
                    en: 'Default',
                  ),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryFor(context),
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
              color: AppColors.textSecondaryFor(context),
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
  ConsumerState<_BackgroundPickerSheet> createState() =>
      _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState
    extends ConsumerState<_BackgroundPickerSheet> {
  int _selectedIndex = 2; // 默认银灰

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    // 从 Provider 读取保存的索引
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedIndex =
          ref.read(chatBackgroundProvider.notifier).gradientIndex;
      if (savedIndex != _selectedIndex &&
          savedIndex < _gradientPresets.length) {
        setState(() => _selectedIndex = savedIndex);
      }
    });
  }

  // TG 风格黑灰商务渐变背景色
  static const List<List<Color>> _gradientPresets = [
    // === 黑灰商务 ===
    // 浅灰默认
    [Color(0xFFF8FAFC), Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
    // 雾面灰
    [Color(0xFFF6F7F9), Color(0xFFEDEFF3), Color(0xFFDADDE3)],
    // 银灰
    [Color(0xFFE5E7EB), Color(0xFFD1D5DB), Color(0xFF9CA3AF)],
    // 石墨黑
    [Color(0xFF111827), Color(0xFF27272A), Color(0xFF3F3F46)],

    // === 低饱和蓝灰 ===
    // 冷白蓝灰
    [Color(0xFFEFF6FF), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
    // 浅天蓝灰
    [Color(0xFFE0F2FE), Color(0xFFBAE6FD), Color(0xFF94A3B8)],
    // 深蓝灰
    [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
    // 夜色黑灰
    [Color(0xFF020617), Color(0xFF111827), Color(0xFF374151)],

    // === 柔和自然 ===
    // 森林绿
    [Color(0xFFE8F5E9), Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
    // 薄荷灰
    [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF9CA3AF)],
    // 暖米灰
    [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFE5E7EB)],
    // 柔粉灰
    [Color(0xFFFFF1F2), Color(0xFFFFE4E6), Color(0xFFD1D5DB)],

    // === 高级质感 ===
    // 星空灰蓝
    [Color(0xFF2C3E50), Color(0xFF4B5563), Color(0xFF9CA3AF)],
    // 深海蓝绿
    [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    // 极光绿
    [Color(0xFF064E3B), Color(0xFF0F766E), Color(0xFF99F6E4)],
    // 晨曦金
    [Color(0xFF78350F), Color(0xFFD97706), Color(0xFFFDE68A)],

    // === 柔和色系 ===
    // 云灰
    [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
    // 海洋蓝
    [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
    // 暖阳黄
    [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFCD34D)],
    // 珊瑚粉
    [Color(0xFFFFEDD5), Color(0xFFFED7AA), Color(0xFFFB923C)],

    // === 高级商务 ===
    // 石墨商务
    [Color(0xFF111827), Color(0xFF374151), Color(0xFF6B7280)],
    // 翠绿商务
    [Color(0xFF059669), Color(0xFF34D399), Color(0xFFA7F3D0)],
    // 琥珀金
    [Color(0xFFD97706), Color(0xFFFBBF24), Color(0xFFFDE68A)],
    // 蓝灰商务
    [Color(0xFF334155), Color(0xFF64748B), Color(0xFFCBD5E1)],
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
                  _chatSettingsText(
                    context,
                    zhCN: '聊天背景',
                    zhTW: '聊天背景',
                    en: 'Chat Background',
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _chatSettingsText(
                      context,
                      zhCN: '完成',
                      zhTW: '完成',
                      en: 'Done',
                    ),
                    style: TextStyle(
                      color: AppColors.linkFor(context),
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
                      text: _chatSettingsText(
                        context,
                        zhCN: '你好！今天怎么样？',
                        zhTW: '你好！今天怎麼樣？',
                        en: 'Hi! How is your day going?',
                      ),
                      isOutgoing: false,
                      color: bubbleColors.incoming,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 120,
                    child: _PreviewBubble(
                      text: _chatSettingsText(
                        context,
                        zhCN: '很好，谢谢！你呢？',
                        zhTW: '很好，謝謝！你呢？',
                        en: 'Pretty good, thanks. How about you?',
                      ),
                      isOutgoing: true,
                      color: bubbleColors.outgoing,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 180,
                    child: _PreviewBubble(
                      text: _chatSettingsText(
                        context,
                        zhCN: '我也很好 😊',
                        zhTW: '我也很好 😊',
                        en: 'I am doing great too 😊',
                      ),
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
                    ref
                        .read(chatBackgroundProvider.notifier)
                        .setGradient(gradient, presetIndex: index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: AppColors.controlActiveFor(context),
                              width: 3,
                            )
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.controlActiveFor(context)
                                    .withOpacity(0.3),
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
                                  color: AppColors.controlActiveFor(context),
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
                    label: _chatSettingsText(
                      context,
                      zhCN: '从相册选择',
                      zhTW: '從相簿選擇',
                      en: 'Choose from Album',
                    ),
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
                    label: _chatSettingsText(
                      context,
                      zhCN: '纯色背景',
                      zhTW: '純色背景',
                      en: 'Solid Background',
                    ),
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
        title: Text(
          _chatSettingsText(
            context,
            zhCN: '选择纯色背景',
            zhTW: '選擇純色背景',
            en: 'Choose a Solid Background',
          ),
        ),
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
  ConsumerState<_BubbleColorPickerSheet> createState() =>
      _BubbleColorPickerSheetState();
}

class _BubbleColorPickerSheetState
    extends ConsumerState<_BubbleColorPickerSheet> {
  int _selectedPresetIndex = 19; // 默认冷灰科技

  @override
  void initState() {
    super.initState();
    // 从 Provider 读取保存的索引
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedIndex = ref.read(bubbleColorProvider.notifier).presetIndex;
      if (savedIndex != _selectedPresetIndex &&
          savedIndex < _bubblePresets.length) {
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
                  _chatSettingsText(
                    context,
                    zhCN: '气泡颜色',
                    zhTW: '氣泡顏色',
                    en: 'Bubble Colors',
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _chatSettingsText(
                      context,
                      zhCN: '完成',
                      zhTW: '完成',
                      en: 'Done',
                    ),
                    style: TextStyle(
                      color: AppColors.primaryFor(context),
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
                      gradient: chatBackground.gradient ??
                          const LinearGradient(
                            colors: [
                              Color(0xFFE8D5E0),
                              Color(0xFFD4C5E0),
                              Color(0xFFC5D0E8)
                            ],
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
                      text: _chatSettingsText(
                        context,
                        zhCN: '收到的消息',
                        zhTW: '收到的消息',
                        en: 'Received message',
                      ),
                      isOutgoing: false,
                      color: bubbleColors.incoming,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 100,
                    child: _PreviewBubble(
                      text: _chatSettingsText(
                        context,
                        zhCN: '发送的消息',
                        zhTW: '傳送的消息',
                        en: 'Sent message',
                      ),
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
                _chatSettingsText(
                  context,
                  zhCN: '预设配色',
                  zhTW: '預設配色',
                  en: 'Preset Colors',
                ),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryFor(context),
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
                    ref
                        .read(bubbleColorProvider.notifier)
                        .setOutgoingColor(preset['outgoing']!);
                    ref
                        .read(bubbleColorProvider.notifier)
                        .setIncomingColor(preset['incoming']!);
                    ref
                        .read(bubbleColorProvider.notifier)
                        .setPresetIndex(index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(
                              color: AppColors.primaryFor(context),
                              width: 2,
                            )
                          : Border.all(color: Colors.grey.withOpacity(0.15)),
                      color: AppColors.cardFor(context),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.primaryFor(context)
                                    .withOpacity(0.2),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
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
                            border: Border.all(
                                color: Colors.grey.withOpacity(0.15)),
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
                            border: Border.all(
                                color: Colors.grey.withOpacity(0.15)),
                          ),
                        ),
                        // 选中标记
                        if (isSelected) ...[
                          const SizedBox(height: 4),
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: AppColors.primaryFor(context),
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
            Icon(icon, size: 20, color: AppColors.primaryFor(context)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryFor(context),
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
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primaryFor(context),
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
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondaryFor(context),
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
              color: AppColors.textSecondaryFor(context),
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
          color: AppColors.textSecondaryFor(context),
        ),
      ),
    );
  }
}
