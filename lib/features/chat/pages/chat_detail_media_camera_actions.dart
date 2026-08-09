// 文件用途：实现 _ChatDetailMediaCameraActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMediaCameraActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media camera actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaCameraActions on _ChatDetailPageState {
  // 流程逻辑：`_takePhotoOrVideo` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _takePhotoOrVideo() async {
    if (!_ensureCanSendMedia()) return;
    final picker = ImagePicker();

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachmentOption(
                    action: _AttachmentActionData(
                      imagePath: 'assets/images/attachment_actions/camera.png',
                      label: AppLocalizations.of(context).takePhoto,
                      onTap: () => Navigator.pop(context, 'photo'),
                    ),
                  ),
                  if (!PlatformUtils.isWeb)
                    _AttachmentOption(
                      action: _AttachmentActionData(
                        imagePath: 'assets/images/attachment_actions/video.png',
                        label: _translate(
                          context,
                          'record_video',
                          _localizedText(
                            zhCN: '录像',
                            zhTW: '錄影',
                            en: 'Record Video',
                          ),
                        ),
                        onTap: () => Navigator.pop(context, 'video'),
                      ),
                    ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    _isUsingCamera = true;

    try {
      if (result == 'photo') {
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        if (photo != null && mounted) {
          if (PlatformUtils.isWeb) {
            final bytes = await photo.readAsBytes();
            if (bytes.isEmpty) return;
            int? imgWidth;
            int? imgHeight;
            try {
              final decodedImage = await decodeImageFromList(bytes);
              imgWidth = decodedImage.width;
              imgHeight = decodedImage.height;
            } catch (e) {
              debugPrint('[Chat] Failed to decode web camera image: $e');
            }
            _updateState(
              () => _pendingImages.add(
                _PendingImage(
                  bytes: bytes,
                  width: imgWidth,
                  height: imgHeight,
                  ext: _mediaExtension(photo),
                  name: photo.name,
                ),
              ),
            );
            _inputFocusNode.requestFocus();
            return;
          }

          final canUsePhotoPath =
              photo.path.isNotEmpty && await File(photo.path).exists();
          final photoBytes = canUsePhotoPath
              ? await File(photo.path).readAsBytes()
              : await photo.readAsBytes();
          if (photoBytes.isEmpty) {
            AppSnackBar.error(
              context,
              _localizedText(
                zhCN: '图片读取失败，请重试',
                zhTW: '圖片讀取失敗，請重試',
                en: 'Failed to read image. Please try again.',
              ),
            );
            return;
          }
          int? imgWidth;
          int? imgHeight;
          try {
            final decodedImage = await decodeImageFromList(photoBytes);
            imgWidth = decodedImage.width;
            imgHeight = decodedImage.height;
          } catch (e) {
            debugPrint('[Chat] Failed to decode image dimensions: $e');
          }

          if (!mounted) return;

          if (canUsePhotoPath) {
            ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendImageMessage(
                  photo.path,
                  width: imgWidth,
                  height: imgHeight,
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
          } else {
            await ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendImageFromBytes(
                  photoBytes,
                  ext: _mediaExtension(photo),
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
          }
          this._updateChatListPreview(
            _localizedText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]'),
            type: MessageContentType.photo,
            mediaUrl: photo.path,
          );
          this._scrollToBottom();
        }
      } else if (result == 'video') {
        final video =
            await Navigator.of(context, rootNavigator: true).push<XFile>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const ChatVideoRecorderPage(
              maxDuration: Duration(minutes: 5),
            ),
          ),
        );

        if (video != null && mounted) {
          final canUseVideoPath =
              video.path.isNotEmpty && await File(video.path).exists();
          final videoBytes = canUseVideoPath ? null : await video.readAsBytes();
          final size = canUseVideoPath
              ? await File(video.path).length()
              : (videoBytes?.length ?? 0);
          if (size <= 0) {
            AppSnackBar.error(
              context,
              _localizedText(
                zhCN: '视频读取失败，请重试',
                zhTW: '影片讀取失敗，請重試',
                en: 'Failed to read video. Please try again.',
              ),
            );
            return;
          }

          final settings =
              await ref.read(systemSettingsServiceProvider).getSettings();
          final maxSize = settings.maxVideoSize * 1024 * 1024;
          if (size > maxSize) {
            if (mounted) {
              this._showFileSizeExceededDialog(
                size,
                maxSize,
                _localizedText(zhCN: '视频', zhTW: '影片', en: 'Video'),
              );
            }
            return;
          }

          if (!mounted) return;

          if (canUseVideoPath) {
            ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendVideoMessage(
                  video.path,
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
          } else if (videoBytes != null && videoBytes.isNotEmpty) {
            await ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendVideoFromBytes(
                  videoBytes,
                  video.name.isNotEmpty ? video.name : 'camera_video.mp4',
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
          }
          this._updateChatListPreview(
            _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
            type: MessageContentType.video,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            this._scrollToBottom();
          });
        }
      }
    } catch (e, st) {
      debugPrint('[Camera] capture failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 8);
      if (mounted) {
        AppSnackBar.error(
          context,
          _localizedText(
            zhCN: '拍摄失败，请重试',
            zhTW: '拍攝失敗，請重試',
            en: 'Capture failed. Please try again.',
          ),
        );
      }
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        _isUsingCamera = false;
      });
    }
  }
}
