// 文件用途：提供 _VoiceBubbleWidget 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据语音消息的远程地址和播放队列控制播放、暂停与连续播放，展示时长、播放状态及转写结果。
part of 'message_bubble.dart';

// 关键声明：message bubble voice 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 语音气泡组件 - 支持播放
class _VoiceBubbleWidget extends ConsumerStatefulWidget {
  final MessageItem message;
  final List<MessageItem> voicePlaylist;
  final Color bubbleColor;
  final Color textColor;
  final Color timeColor;
  final bool isOutgoing;
  final BorderRadius bubbleRadius;
  final Widget Function() buildStatusIcon;

  const _VoiceBubbleWidget({
    required this.message,
    required this.voicePlaylist,
    required this.bubbleColor,
    required this.textColor,
    required this.timeColor,
    required this.isOutgoing,
    required this.bubbleRadius,
    required this.buildStatusIcon,
  });

  @override
  ConsumerState<_VoiceBubbleWidget> createState() => _VoiceBubbleWidgetState();
}

class _VoiceBubbleWidgetState extends ConsumerState<_VoiceBubbleWidget>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static AudioPlayer? _currentPlayer;
  static String? _currentPlayingId;
  static final Map<String, _VoiceBubbleWidgetState> _mountedVoices = {};
  static VoicePlaybackRoute _preferredRoute = VoicePlaybackRoute.speaker;
  static bool _autoAdvanceEnabled = false;

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _completionHandled = false;
  bool _proximityNear = false;
  VoicePlaybackRoute _activeRoute = VoicePlaybackRoute.speaker;
  bool _showTranscript = false;
  bool _isTranscribing = false;
  String? _transcriptText;
  String? _transcriptError;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  late AnimationController _waveController;
  // 存储订阅以避免泄漏
  final List<dynamic> _playerSubscriptions = [];
  StreamSubscription<bool>? _proximitySubscription;
  Timer? _completionFallbackTimer;

  @override
  bool get wantKeepAlive => _currentPlayingId == widget.message.id;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _mountedVoices[widget.message.id] = this;
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 初始化时长
    _duration = Duration(milliseconds: widget.message.mediaDuration ?? 0);
  }

  @override
  void didUpdateWidget(covariant _VoiceBubbleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _mountedVoices.remove(oldWidget.message.id);
      _mountedVoices[widget.message.id] = this;
    }
    if (oldWidget.message.mediaDuration != widget.message.mediaDuration) {
      _duration = Duration(milliseconds: widget.message.mediaDuration ?? 0);
    }
  }

  @override
  void dispose() {
    _mountedVoices.remove(widget.message.id);
    for (final sub in _playerSubscriptions) {
      sub.cancel();
    }
    _playerSubscriptions.clear();
    _positionNotifier.dispose();
    _waveController.dispose();
    _completionFallbackTimer?.cancel();
    if (_currentPlayingId == widget.message.id) {
      _autoAdvanceEnabled = false;
      unawaited(_disableProximity());
      unawaited(_player?.stop() ?? Future<void>.value());
      unawaited(_player?.dispose() ?? Future<void>.value());
      _currentPlayer = null;
      _currentPlayingId = null;
    }
    super.dispose();
  }

  VoicePlaybackRoute get _displayedRoute =>
      _currentPlayingId == widget.message.id ? _activeRoute : _preferredRoute;

  List<VoicePlaybackQueueItem> get _queueItems => widget.voicePlaylist
      .map(
        (message) => VoicePlaybackQueueItem(
          id: message.id,
          chatId: message.chatId,
          seq: message.seq,
          createdAt: message.createdAt,
        ),
      )
      .toList(growable: false);

  Future<void> _enableProximity() async {
    await _proximitySubscription?.cancel();
    // Register the sensor first. Acquiring a proximity wake lock while the
    // device is still far can make some Huawei devices blank/re-layout the
    // window before the sensor reports its initial value.
    await VoicePlaybackProximityBridge.setScreenOffEnabled(false);
    _proximitySubscription = VoicePlaybackProximityBridge.changes.listen(
      (near) {
        if (!mounted || !_isPlaying || _currentPlayingId != widget.message.id) {
          return;
        }
        _proximityNear = near;
        unawaited(
          VoicePlaybackProximityBridge.setScreenOffEnabled(near),
        );
        final route = resolveVoicePlaybackRoute(
          preferredRoute: _preferredRoute,
          proximityNear: near,
        );
        if (route == _activeRoute) return;
        setState(() => _activeRoute = route);
        final player = _player;
        if (player != null) {
          unawaited(configureVoicePlaybackAudio(player, route: route));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[VoiceBubble] Proximity listener error: $error');
      },
    );
  }

  Future<void> _disableProximity() async {
    await _proximitySubscription?.cancel();
    _proximitySubscription = null;
    _proximityNear = false;
    await VoicePlaybackProximityBridge.setScreenOffEnabled(false);
  }

  Future<void> _toggleRoute() async {
    GlobalHaptics.selection();
    _preferredRoute = _preferredRoute == VoicePlaybackRoute.speaker
        ? VoicePlaybackRoute.earpiece
        : VoicePlaybackRoute.speaker;
    debugPrint(
      '[VoiceBubble] route-toggle preferred=$_preferredRoute '
      'current=$_currentPlayingId near=$_proximityNear',
    );
    final route = resolveVoicePlaybackRoute(
      preferredRoute: _preferredRoute,
      proximityNear: _proximityNear,
    );
    for (final state in _mountedVoices.values.toList(growable: false)) {
      if (state.mounted) state.setState(() {});
    }
    if (_currentPlayingId == widget.message.id && _player != null) {
      setState(() => _activeRoute = route);
      await configureVoicePlaybackAudio(_player!, route: route);
    }
  }

  Future<void> _stopPlayback({required bool manual}) async {
    if (manual) _autoAdvanceEnabled = false;
    _completionFallbackTimer?.cancel();
    await _disableProximity();
    await _player?.stop();
    if (_currentPlayingId == widget.message.id) {
      _currentPlayingId = null;
      _currentPlayer = null;
      updateKeepAlive();
    }
    if (!mounted) return;
    _positionNotifier.value = Duration.zero;
    _waveController
      ..stop()
      ..reset();
    setState(() {
      _isPlaying = false;
      _activeRoute = _preferredRoute;
    });
  }

  String? _existingLocalVoicePath(String? raw) {
    if (PlatformUtils.isWeb) return null;
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower == 'null' ||
        lower == 'undefined' ||
        lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//')) {
      return null;
    }

    final candidates = <String>[value];
    if (lower.startsWith('file://')) {
      final uri = Uri.tryParse(value);
      if (uri != null) {
        try {
          candidates.add(uri.toFilePath());
        } catch (_) {}
      }
    }

    for (final candidate in candidates) {
      try {
        if (File(candidate).existsSync()) return candidate;
      } catch (_) {}
    }
    return null;
  }

  Source? _buildVoiceSource() {
    final localPath = _existingLocalVoicePath(widget.message.localPath) ??
        _existingLocalVoicePath(widget.message.mediaUrl);
    if (localPath != null) {
      return DeviceFileSource(localPath);
    }

    final remoteUrl = ApiConfig.getMediaUrl(widget.message.mediaUrl);
    if (remoteUrl.isEmpty) return null;
    return UrlSource(remoteUrl);
  }

  Future<void> _togglePlay() async {
    // A voice tap must not leave a focused composer waiting to show the IME.
    // The resulting viewport resize can otherwise recycle the active bubble.
    FocusManager.instance.primaryFocus?.unfocus();
    GlobalHaptics.selection();

    if (_currentPlayingId == widget.message.id && _isPlaying) {
      _autoAdvanceEnabled = false;
      await _player?.pause();
      await _disableProximity();
      _waveController.stop();
      setState(() => _isPlaying = false);
      return;
    }
    await _startPlayback(autoAdvance: true);
  }

  Future<void> _startPlayback({required bool autoAdvance}) async {
    final previousId = _currentPlayingId;
    if (previousId != null && previousId != widget.message.id) {
      final previousState = _mountedVoices[previousId];
      if (previousState != null) {
        await previousState._stopPlayback(manual: false);
      } else {
        await _currentPlayer?.stop();
        await _currentPlayer?.dispose();
        _currentPlayer = null;
        _currentPlayingId = null;
      }
    }

    final source = _buildVoiceSource();
    if (source == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizedUiText(
                context,
                zhCN: '语音文件不存在，请稍后重试',
                zhTW: '語音檔案不存在，請稍後重試',
                en: 'Voice file is unavailable. Please try again later.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _player ??= AudioPlayer();
    _currentPlayer = _player;
    _currentPlayingId = widget.message.id;
    updateKeepAlive();
    _autoAdvanceEnabled = autoAdvance;
    _completionHandled = false;
    debugPrint(
      '[VoiceBubble] play-start id=${widget.message.id} '
      'auto=$autoAdvance queue=${_queueItems.map((item) => '${item.id}:${item.seq}').join(',')}',
    );

    for (final sub in _playerSubscriptions) {
      await sub.cancel();
    }
    _playerSubscriptions.clear();
    _playerSubscriptions.add(
      _player!.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        if (state == PlayerState.completed) {
          unawaited(_handlePlaybackComplete());
        }
        final playing = state == PlayerState.playing;
        setState(() => _isPlaying = playing);
        if (playing) {
          _waveController.repeat();
        } else {
          _waveController.stop();
        }
      }),
    );
    _playerSubscriptions.add(
      _player!.onPositionChanged.listen((pos) {
        if (mounted) _positionNotifier.value = pos;
      }),
    );
    _playerSubscriptions.add(
      _player!.onPlayerComplete.listen((_) {
        unawaited(_handlePlaybackComplete());
      }),
    );

    try {
      _activeRoute = resolveVoicePlaybackRoute(
        preferredRoute: _preferredRoute,
        proximityNear: false,
      );
      await _player!.setReleaseMode(ReleaseMode.stop);
      await _player!.stop();
      await configureVoicePlaybackAudio(_player!, route: _activeRoute);
      await _player!.play(source);
      await _enableProximity();
      _completionFallbackTimer?.cancel();
      _completionFallbackTimer = Timer(
        _duration + const Duration(seconds: 2),
        () => unawaited(_handlePlaybackComplete()),
      );
      if (!mounted) return;
      _waveController.repeat();
      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('[VoiceBubble] Play error: $e');
      _autoAdvanceEnabled = false;
      await _disableProximity();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizedUiText(
                context,
                zhCN: '播放失败，请重试',
                zhTW: '播放失敗，請稍後重試',
                en: 'Playback failed. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handlePlaybackComplete() async {
    if (_completionHandled || _currentPlayingId != widget.message.id) return;
    _completionHandled = true;
    _completionFallbackTimer?.cancel();
    final shouldAdvance = _autoAdvanceEnabled;
    final nextId = shouldAdvance
        ? nextVoicePlaybackId(
            items: _queueItems,
            currentId: widget.message.id,
          )
        : null;

    await _disableProximity();
    _currentPlayer = null;
    _currentPlayingId = null;
    updateKeepAlive();
    if (mounted) {
      _positionNotifier.value = Duration.zero;
      _waveController
        ..stop()
        ..reset();
      setState(() {
        _isPlaying = false;
        _activeRoute = _preferredRoute;
      });
    }

    final nextState = nextId == null ? null : _mountedVoices[nextId];
    debugPrint(
      '[VoiceBubble] play-complete id=${widget.message.id} next=$nextId '
      'mounted=${nextState != null} auto=$shouldAdvance',
    );
    if (nextState == null || !nextState.mounted) {
      _autoAdvanceEnabled = false;
      return;
    }
    await nextState._startPlayback(autoAdvance: true);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get _voiceTranscript =>
      (_transcriptText ?? widget.message.content).trim();

  Future<void> _toggleTranscript() async {
    GlobalHaptics.selection();
    if (_showTranscript) {
      setState(() => _showTranscript = false);
      return;
    }
    setState(() {
      _showTranscript = true;
      _transcriptError = null;
    });
    if (_voiceTranscript.isEmpty) {
      await _requestTranscript();
    }
  }

  Future<ApiClient> _createApiClient() async {
    final apiClient = ApiClient();
    final token = await TokenStorage.getToken();
    if (token != null) apiClient.setToken(token);
    return apiClient;
  }

  Future<void> _requestTranscript() async {
    if (_isTranscribing) return;
    setState(() {
      _isTranscribing = true;
      _transcriptError = null;
    });
    try {
      final apiClient = await _createApiClient();
      final response = await apiClient.post<Map<String, dynamic>>(
        '/message/voice/transcribe',
        data: {
          'chat_id': widget.message.chatId,
          'msg_id': widget.message.id,
        },
        fromJson: (json) => Map<String, dynamic>.from(json as Map),
      );
      if (!mounted) return;
      if (response.isSuccess) {
        final text = response.data?['transcript']?.toString().trim() ?? '';
        setState(() {
          _transcriptText = text;
          _transcriptError = text.isEmpty
              ? _localizedUiText(
                  context,
                  zhCN: '未识别到文字',
                  zhTW: '未識別到文字',
                  en: 'No text recognized',
                )
              : null;
        });
      } else {
        setState(() => _transcriptError = response.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _transcriptError = _localizedUiText(
          context,
          zhCN: '转文字失败，请稍后重试',
          zhTW: '轉文字失敗，請稍後重試',
          en: 'Transcription failed. Please try again.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final transcriptionEnabled = ref
            .watch(systemSettingsProvider)
            .valueOrNull
            ?.voiceTranscriptionEnabled ??
        false;
    final showTranscriptAction =
        transcriptionEnabled || _voiceTranscript.isNotEmpty;
    final waveColor = widget.isOutgoing
        ? const Color(0xFF5D9B5D)
        : AppColors.primaryFor(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
      decoration: BoxDecoration(
        color: widget.bubbleColor,
        borderRadius: widget.bubbleRadius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 播放/暂停按钮
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlay,
                child: Semantics(
                  button: true,
                  liveRegion: true,
                  label: _localizedUiText(
                    context,
                    zhCN: _isPlaying ? '正在播放语音' : '播放语音',
                    zhTW: _isPlaying ? '正在播放語音' : '播放語音',
                    en: _isPlaying ? 'Voice playing' : 'Play voice',
                  ),
                  child: ExcludeSemantics(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isPlaying
                            ? waveColor
                            : AppColors.primaryFor(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 波形图 + 时长（使用 ValueListenableBuilder 精准更新）
              ValueListenableBuilder<Duration>(
                valueListenable: _positionNotifier,
                builder: (context, position, child) {
                  final progress = _duration.inMilliseconds > 0
                      ? position.inMilliseconds / _duration.inMilliseconds
                      : 0.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 动态波形图
                      SizedBox(
                        width: 100,
                        height: 24,
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _VoiceWavePainter(
                                progress: progress,
                                isPlaying: _isPlaying,
                                animValue: _waveController.value,
                                activeColor: waveColor,
                                inactiveColor: waveColor.withValues(alpha: 0.3),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 显示当前进度或总时长
                          Text(
                            _isPlaying
                                ? _formatDuration(position)
                                : _formatDuration(_duration),
                            style: AppTextStyles.caption.copyWith(
                              color: widget.textColor.withValues(alpha: 0.7),
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('HH:mm').format(
                              toCurrentLocalTime(widget.message.createdAt),
                            ),
                            style: AppTextStyles.timestamp.copyWith(
                              color: widget.timeColor,
                            ),
                          ),
                          if (widget.isOutgoing) ...[
                            const SizedBox(width: 3),
                            widget.buildStatusIcon(),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 4),
              Semantics(
                key: ValueKey('voice_route_${widget.message.id}'),
                button: true,
                onTap: _toggleRoute,
                excludeSemantics: true,
                label: _displayedRoute == VoicePlaybackRoute.speaker
                    ? _localizedUiText(
                        context,
                        zhCN: '当前为扬声器，点击切换听筒',
                        zhTW: '目前為揚聲器，點擊切換聽筒',
                        en: 'Speaker on. Switch to earpiece',
                      )
                    : _localizedUiText(
                        context,
                        zhCN: _proximityNear ? '靠近耳朵，已自动切换听筒' : '当前为听筒，点击切换扬声器',
                        zhTW: _proximityNear ? '靠近耳朵，已自動切換聽筒' : '目前為聽筒，點擊切換揚聲器',
                        en: _proximityNear
                            ? 'Near ear. Earpiece selected automatically'
                            : 'Earpiece on. Switch to speaker',
                      ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerUp: (_) => unawaited(_toggleRoute()),
                    child: Icon(
                      _displayedRoute == VoicePlaybackRoute.speaker
                          ? Icons.volume_up_rounded
                          : Icons.phone_in_talk_rounded,
                      size: 19,
                      color: waveColor,
                    ),
                  ),
                ),
              ),
              if (showTranscriptAction) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _isTranscribing ? null : () => _toggleTranscript(),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    foregroundColor: waveColor,
                  ),
                  child: Text(
                    _localizedUiText(
                      context,
                      zhCN: _isTranscribing
                          ? '识别中'
                          : (_showTranscript ? '收起' : '转文字'),
                      zhTW: _isTranscribing
                          ? '識別中'
                          : (_showTranscript ? '收起' : '轉文字'),
                      en: _isTranscribing
                          ? 'Text...'
                          : (_showTranscript ? 'Hide' : 'Text'),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_showTranscript) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.textColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isTranscribing
                    ? _localizedUiText(
                        context,
                        zhCN: '正在识别语音...',
                        zhTW: '正在識別語音...',
                        en: 'Transcribing voice...',
                      )
                    : (_transcriptError?.isNotEmpty == true
                        ? _transcriptError!
                        : (_voiceTranscript.isNotEmpty
                            ? _voiceTranscript
                            : _localizedUiText(
                                context,
                                zhCN: '暂未生成文字',
                                zhTW: '暫未生成文字',
                                en: 'No transcript yet',
                              ))),
                style: AppTextStyles.bodySmall.copyWith(
                  color: widget.textColor.withValues(alpha: 0.78),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 语音波形绘制器
class _VoiceWavePainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final double animValue;
  final Color activeColor;
  final Color inactiveColor;

  _VoiceWavePainter({
    required this.progress,
    required this.isPlaying,
    required this.animValue,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // 固定种子保证波形一致
    const barCount = 20;
    const barWidth = 3.0;
    final spacing = (size.width - barCount * barWidth) / (barCount - 1);

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final normalizedProgress = progress * barCount;
      final isActive = i < normalizedProgress;

      // 基础高度
      double baseHeight = size.height * (0.3 + random.nextDouble() * 0.7);

      // 播放时添加动画效果
      if (isPlaying && isActive) {
        final wave = math.sin((animValue * 2 * math.pi) + (i * 0.3));
        baseHeight = baseHeight * (0.7 + 0.3 * wave);
      }

      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      final y1 = (size.height - baseHeight) / 2;
      final y2 = y1 + baseHeight;

      canvas.drawLine(
        Offset(x + barWidth / 2, y1),
        Offset(x + barWidth / 2, y2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.animValue != animValue;
  }
}
