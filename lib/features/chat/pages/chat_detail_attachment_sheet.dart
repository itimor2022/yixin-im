// 文件用途：实现 _AttachmentSheet 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _AttachmentSheet 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail attachment sheet 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _AttachmentSheet extends StatefulWidget {
  final VoidCallback onPickFromGallery;
  final VoidCallback? onPasteImage;
  final VoidCallback onTakePhoto;
  final VoidCallback? onStartCall;
  final VoidCallback? onStartMeeting;
  final VoidCallback? onSendLocation;
  final VoidCallback? onOpenFavorites;
  final VoidCallback onPickFile;
  final VoidCallback? onSendRedPacket;
  final VoidCallback? onTransfer;
  final VoidCallback? onBurnAfterReadToggle;
  final VoidCallback? onDismiss;
  final ChatAttachmentMenuSettings menuSettings;
  final bool burnAfterReadEnabled;
  final bool allowBurnAfterRead;

  const _AttachmentSheet({
    required this.onPickFromGallery,
    this.onPasteImage,
    required this.onTakePhoto,
    this.onStartCall,
    this.onStartMeeting,
    this.onSendLocation,
    this.onOpenFavorites,
    required this.onPickFile,
    this.onSendRedPacket,
    this.onTransfer,
    this.onBurnAfterReadToggle,
    this.onDismiss,
    required this.menuSettings,
    this.burnAfterReadEnabled = false,
    this.allowBurnAfterRead = true,
  });

  @override
  State<_AttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<_AttachmentSheet> {
  late final PageController _pageController;
  int _pageIndex = 0;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AttachmentSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availabilityChanged =
        !identical(oldWidget.menuSettings, widget.menuSettings) ||
            oldWidget.allowBurnAfterRead != widget.allowBurnAfterRead ||
            (oldWidget.onBurnAfterReadToggle == null) !=
                (widget.onBurnAfterReadToggle == null);
    if (!availabilityChanged) return;

    _pageIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pages = _buildPages(context);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7F7),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            top: 6,
            bottom: MediaQuery.of(context).padding.bottom + 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: PlatformUtils.isPhysicalDesktop ? 196 : 178,
                child: PageView.builder(
                  controller: _pageController,
                  physics: pages.length > 1
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() => _pageIndex = index);
                  },
                  itemCount: pages.length,
                  itemBuilder: (context, index) {
                    return _AttachmentActionPage(actions: pages[index]);
                  },
                ),
              ),
              if (pages.length > 1) ...[
                const SizedBox(height: 2),
                _AttachmentPageDots(
                  count: pages.length,
                  activeIndex: _pageIndex,
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<List<_AttachmentActionData>> _buildPages(BuildContext context) {
    if (!widget.menuSettings.enabled) return const [];

    final actions = <_AttachmentActionData>[
      if (widget.menuSettings.album)
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/album.png',
          label: AppLocalizations.of(context).get('album'),
          onTap: () => _closeThen(widget.onPickFromGallery),
        ),
      if (widget.menuSettings.album && widget.onPasteImage != null)
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/album.png',
          label: _localizedPasteImageLabel(context),
          onTap: () => _closeThen(widget.onPasteImage!),
        ),
      if (widget.menuSettings.camera)
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/camera.png',
          label: AppLocalizations.of(context).camera,
          onTap: () => _closeThen(widget.onTakePhoto),
        ),
    ];

    if (widget.menuSettings.call && widget.onStartCall != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/call.png',
          label: AppLocalizations.of(context).videoCall,
          onTap: () => _closeThen(widget.onStartCall!),
        ),
      );
    } else if (widget.menuSettings.call && widget.onStartMeeting != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/call.png',
          label: AppLocalizations.of(context).get('meeting'),
          onTap: () => _closeThen(widget.onStartMeeting!),
        ),
      );
    }

    if (widget.menuSettings.location && widget.onSendLocation != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/location.png',
          label: AppLocalizations.of(context).get('location'),
          onTap: () => _closeThen(widget.onSendLocation!),
        ),
      );
    }

    if (widget.menuSettings.redPacket && widget.onSendRedPacket != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/red_packet.png',
          label: AppLocalizations.of(context).get('red_packet'),
          onTap: () => _closeThen(widget.onSendRedPacket!),
        ),
      );
    }

    if (widget.menuSettings.transfer && widget.onTransfer != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/transfer.png',
          label: AppLocalizations.of(context).get('transfer'),
          onTap: () => _closeThen(widget.onTransfer!),
        ),
      );
    }

    if (widget.menuSettings.favorite && widget.onOpenFavorites != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/favorite.png',
          label: AppLocalizations.of(context).get('favorite'),
          onTap: () => _closeThen(widget.onOpenFavorites!),
        ),
      );
    }

    if (widget.menuSettings.file) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/file.png',
          label: AppLocalizations.of(context).file,
          onTap: () => _closeThen(widget.onPickFile),
        ),
      );
    }

    if (widget.allowBurnAfterRead && widget.onBurnAfterReadToggle != null) {
      actions.add(
        _AttachmentActionData(
          imagePath: 'assets/images/attachment_actions/burn_after_read.png',
          label: _localizedBurnAfterReadLabel(context),
          selected: widget.burnAfterReadEnabled,
          onTap: () => _closeThen(widget.onBurnAfterReadToggle!),
        ),
      );
    }

    return paginateChatAttachmentActions(actions);
  }

  void _closeThen(VoidCallback callback) {
    widget.onDismiss?.call();
    callback();
  }

  String _localizedBurnAfterReadLabel(BuildContext context) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return 'Burn';
      case AppLanguage.zhTW:
        return '閱後即焚';
      case AppLanguage.zhCN:
        return '阅后即焚';
    }
  }

  String _localizedPasteImageLabel(BuildContext context) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return 'Paste';
      case AppLanguage.zhTW:
        return '閱後即焚';
      case AppLanguage.zhCN:
        return '阅后即焚';
    }
  }
}

class _AttachmentActionData {
  final String imagePath;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _AttachmentActionData({
    required this.imagePath,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
}

class _AttachmentActionPage extends StatelessWidget {
  final List<_AttachmentActionData> actions;

  const _AttachmentActionPage({required this.actions});

  @override
  Widget build(BuildContext context) {
    final cells = <_AttachmentActionData?>[
      ...actions,
      for (var i = actions.length; i < 8; i++) null,
    ];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlatformUtils.isPhysicalDesktop ? 34 : 24,
      ),
      child: Column(
        children: [
          Expanded(child: _AttachmentActionRow(actions: cells.sublist(0, 4))),
          SizedBox(height: PlatformUtils.isPhysicalDesktop ? 12 : 8),
          Expanded(child: _AttachmentActionRow(actions: cells.sublist(4, 8))),
        ],
      ),
    );
  }
}

class _AttachmentActionRow extends StatelessWidget {
  final List<_AttachmentActionData?> actions;

  const _AttachmentActionRow({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          Expanded(
            child: actions[i] == null
                ? const SizedBox.shrink()
                : _AttachmentOption(action: actions[i]!),
          ),
          if (i != actions.length - 1)
            SizedBox(width: PlatformUtils.isPhysicalDesktop ? 18 : 12),
        ],
      ],
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final _AttachmentActionData action;

  const _AttachmentOption({required this.action});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileSize = PlatformUtils.isPhysicalDesktop ? 66.0 : 60.0;
    final iconSize = PlatformUtils.isPhysicalDesktop ? 38.0 : 36.0;
    final iconColor = action.selected
        ? const Color(0xFFE65100)
        : (isDark ? const Color(0xFFE2E2E2) : const Color(0xFF4F4F4F));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        GlobalHaptics.selection();
        action.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: action.selected
                  ? (isDark ? const Color(0xFF3A2418) : const Color(0xFFFFF1E8))
                  : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: action.selected
                    ? const Color(0xFFFFB083)
                    : (isDark ? Colors.white10 : const Color(0xFFEDEDED)),
              ),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              action.imagePath,
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              color: iconColor,
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (_, __, ___) => Icon(
                Icons.add_rounded,
                color: iconColor,
                size: iconSize,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.15,
              color: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF777777),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPageDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  final bool isDark;

  const _AttachmentPageDots({
    required this.count,
    required this.activeIndex,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == activeIndex
                  ? (isDark ? const Color(0xFF8E8E93) : const Color(0xFF7D7D7D))
                  : (isDark
                      ? const Color(0xFF4A4A4C)
                      : const Color(0xFFD8D8D8)),
            ),
          ),
      ],
    );
  }
}
