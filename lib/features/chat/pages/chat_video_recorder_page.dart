// 文件用途：实现 ChatVideoRecorderPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 ChatVideoRecorderPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/system_ui_styles.dart';

// 关键声明：chat video recorder page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class ChatVideoRecorderPage extends StatefulWidget {
  final Duration maxDuration;

  const ChatVideoRecorderPage({
    super.key,
    this.maxDuration = const Duration(minutes: 5),
  });

  @override
  State<ChatVideoRecorderPage> createState() => _ChatVideoRecorderPageState();
}

class _ChatVideoRecorderPageState extends State<ChatVideoRecorderPage>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isFinishing = false;
  bool _torchEnabled = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _error;
  XFile? _recordedFile;
  VideoPlayerController? _previewController;
  bool _isPreviewInitializing = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _previewController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_recordedFile != null) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        unawaited(_previewController?.pause());
      }
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isRecording) {
        _finishRecording();
      } else {
        controller.dispose();
      }
    } else if (state == AppLifecycleState.resumed && !_isRecording) {
      _initializeCamera(_cameras[_cameraIndex]);
    }
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _error = 'No camera available';
        });
        return;
      }

      final backIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameras = cameras;
      _cameraIndex = backIndex >= 0 ? backIndex : 0;
      await _initializeCamera(_cameras[_cameraIndex]);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = e.description ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    if (!mounted) return;

    setState(() {
      _isInitializing = true;
      _error = null;
      _torchEnabled = false;
    });

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );
    _controller = controller;

    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted || _controller != controller) return;
      setState(() => _isInitializing = false);
    } on CameraException catch (e) {
      if (!mounted || _controller != controller) return;
      setState(() {
        _isInitializing = false;
        _error = e.description ?? e.code;
      });
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _isFinishing) {
      return;
    }

    try {
      HapticFeedback.mediumImpact();
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _elapsed = Duration.zero;
        _isRecording = true;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _elapsed + const Duration(seconds: 1);
        if (next >= widget.maxDuration) {
          _finishRecording();
          return;
        }
        setState(() => _elapsed = next);
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.description ?? e.code);
    }
  }

  Future<void> _finishRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isRecordingVideo ||
        _isFinishing) {
      return;
    }

    setState(() => _isFinishing = true);
    _timer?.cancel();

    try {
      HapticFeedback.mediumImpact();
      final file = await controller.stopVideoRecording();
      if (!mounted) return;
      await _preparePreview(file);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _isFinishing = false;
        _isRecording = false;
        _error = e.description ?? e.code;
      });
    }
  }

  Future<void> _preparePreview(XFile file) async {
    final cameraController = _controller;
    _controller = null;
    await cameraController?.dispose();

    final previousPreview = _previewController;
    _previewController = null;
    await previousPreview?.dispose();

    if (!mounted) return;
    setState(() {
      _recordedFile = file;
      _isRecording = false;
      _isFinishing = false;
      _isPreviewInitializing = true;
      _error = null;
    });

    try {
      final preview = VideoPlayerController.file(File(file.path));
      _previewController = preview;
      await preview.initialize();
      await preview.setLooping(true);
      await preview.play();
      if (!mounted || _previewController != preview) return;
      setState(() => _isPreviewInitializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPreviewInitializing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _retake() async {
    if (_isFinishing) return;
    HapticFeedback.selectionClick();
    final file = _recordedFile;
    final preview = _previewController;
    _recordedFile = null;
    _previewController = null;
    await preview?.dispose();
    if (file != null) {
      try {
        final localFile = File(file.path);
        if (await localFile.exists()) await localFile.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isPreviewInitializing = false;
      _elapsed = Duration.zero;
      _error = null;
    });
    await _initializeCamera(_cameras[_cameraIndex]);
  }

  void _confirmRecording() {
    final file = _recordedFile;
    if (file == null || _isFinishing) return;
    HapticFeedback.mediumImpact();
    setState(() => _isFinishing = true);
    Navigator.of(context).pop(file);
  }

  Future<void> _cancel() async {
    if (_isFinishing) return;
    final controller = _controller;
    if (controller != null && controller.value.isRecordingVideo) {
      setState(() => _isFinishing = true);
      _timer?.cancel();
      try {
        await controller.stopVideoRecording();
      } catch (_) {}
    }
    final preview = _previewController;
    _previewController = null;
    await preview?.dispose();
    final recordedFile = _recordedFile;
    _recordedFile = null;
    if (recordedFile != null) {
      try {
        final file = File(recordedFile.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording || _isFinishing) return;
    HapticFeedback.selectionClick();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_cameraIndex]);
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isFinishing) {
      return;
    }
    try {
      HapticFeedback.selectionClick();
      final next = !_torchEnabled;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchEnabled = next);
    } catch (_) {}
  }

  String _formatElapsed() {
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DarkSystemUiScope(
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _cancel();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: _buildPreview(l10n)),
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 18,
                right: 18,
                child: _buildTopBar(l10n),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 34,
                child: Center(child: _buildRecordControls(l10n)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(AppLocalizations l10n) {
    final preview = _previewController;
    if (_recordedFile != null) {
      if (_isPreviewInitializing ||
          preview == null ||
          !preview.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: preview.value.aspectRatio,
          child: VideoPlayer(preview),
        ),
      );
    }

    final controller = _controller;
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? l10n.cameraPermission,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }

    return Center(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1080,
            height: controller.value.previewSize?.width ?? 1920,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    return Row(
      children: [
        _IconGlassButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: _cancel,
          semanticLabel: l10n.cancel,
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: _isRecording ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.30),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stop_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 5),
                Text(
                  _formatElapsed(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        _IconGlassButton(
          icon: _recordedFile != null
              ? Icons.close_rounded
              : (_torchEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded),
          onTap: _recordedFile != null ? _cancel : _toggleTorch,
          semanticLabel:
              _recordedFile != null ? l10n.cancel : l10n.switchCamera,
        ),
      ],
    );
  }

  Widget _buildRecordControls(AppLocalizations l10n) {
    if (_recordedFile != null) {
      return Container(
        width: 260,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                key: const ValueKey('chat_video_retake_button'),
                onPressed: _isFinishing ? null : _retake,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('重拍'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('chat_video_send_button'),
                onPressed: _isFinishing ? null : _confirmRecording,
                icon: const Icon(Icons.send_rounded),
                label: Text(l10n.send),
              ),
            ),
          ],
        ),
      );
    }

    final showDone = _isRecording || _isFinishing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: showDone ? 238 : 98,
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(40),
      ),
      child: showDone
          ? Row(
              children: [
                SizedBox(
                  width: 104,
                  child: TextButton(
                    onPressed: _isFinishing ? null : _finishRecording,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                      disabledForegroundColor: Colors.black38,
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(l10n.done),
                  ),
                ),
                const Spacer(),
                _RecordButton(
                  isRecording: true,
                  isBusy: _isFinishing,
                  onTap: _finishRecording,
                ),
              ],
            )
          : Center(
              child: _RecordButton(
                isRecording: false,
                isBusy: _isFinishing || _isInitializing,
                onTap: _startRecording,
              ),
            ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final bool isBusy;
  final VoidCallback onTap;

  const _RecordButton({
    required this.isRecording,
    required this.isBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isBusy ? null : onTap,
      child: SizedBox(
        width: 58,
        height: 58,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: isRecording ? 34 : 46,
            height: isRecording ? 34 : 46,
            decoration: BoxDecoration(
              color: isBusy ? Colors.red.withOpacity(0.45) : Colors.redAccent,
              shape: BoxShape.circle,
            ),
            child: isBusy
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  const _IconGlassButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 23),
        ),
      ),
    );
  }
}
