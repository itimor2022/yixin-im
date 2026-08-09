// 文件用途：实现 _ChatDetailMediaImageActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：处理相册/相机图片选择、压缩、预览和批量发送，保持临时文件清理与消息发送状态一致。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media image actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaImageActions on _ChatDetailPageState {
  // 流程逻辑：`_pickFromGallery` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _pickFromGallery() async {
    if (!_ensureCanSendMedia()) return;
    if (PlatformUtils.isPhysicalDesktop) {
      await _pickDesktopMediaFiles();
      return;
    }

    const maxSelectedMedia = 9;
    List<_ChatPickedMedia> pickedMedia;
    var originalRequested = false;
    if (Platform.isAndroid || Platform.isIOS) {
      final selection = await _openChatMediaPicker();
      if (selection == null) return;
      pickedMedia = selection.items;
      originalRequested = selection.sendOriginal;
    } else {
      final picker = ImagePicker();
      try {
        final files = await picker.pickMultipleMedia(
          // Always request the source asset. Static images are compressed later
          // by MessageProvider. Asking the platform picker to compress here
          // flattens animated GIFs to frame 1.
          limit: maxSelectedMedia,
        );
        pickedMedia = files.map((file) {
          final ext = _mediaExtension(file);
          return _ChatPickedMedia(
            file: file,
            type: _isVideoExt(ext)
                ? _ChatPickedMediaType.video
                : _ChatPickedMediaType.image,
            assetId: file.path,
          );
        }).toList(growable: false);
      } catch (e, st) {
        debugPrint('[Gallery] pickMultipleMedia failed: $e');
        debugPrintStack(stackTrace: st, maxFrames: 8);
        await ImagePickerDiagnosticsService.instance.logPickerResult(
          source: 'chat_pick_multiple_media',
          count: 0,
          error: e,
          stackTrace: st,
        );
        if (mounted) {
          AppSnackBar.error(
            context,
            _localizedText(
              zhCN: '打开相册失败，请重试',
              zhTW: '開啟相簿失敗，請重試',
              en: 'Failed to open gallery. Please try again.',
            ),
          );
        }
        return;
      }
    }

    final mediaList =
        pickedMedia.take(maxSelectedMedia).toList(growable: false);
    if (pickedMedia.length > maxSelectedMedia && mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '一次最多选择 $maxSelectedMedia 个图片或视频',
          zhTW: '一次最多選擇 $maxSelectedMedia 個圖片或影片',
          en: 'Select up to $maxSelectedMedia photos or videos at a time',
        ),
      );
    }

    await ImagePickerDiagnosticsService.instance.logPickerResult(
      source: 'chat_pick_multiple_media',
      count: mediaList.length,
    );

    if (mediaList.isEmpty) {
      if (mounted) {
        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '未获取到图片或视频，请重试',
            zhTW: '未取得圖片或影片，請重試',
            en: 'No photo or video was returned. Please try again.',
          ),
        );
      }
      return;
    }
    final selectedImageCount = mediaList
        .where((item) => item.type == _ChatPickedMediaType.image)
        .length;
    final selectedVideoCount = mediaList.length - selectedImageCount;
    final isMixedSelection = selectedImageCount > 0 && selectedVideoCount > 0;
    debugPrint(
      '[Gallery] selected ${mediaList.length} media items '
      'images=$selectedImageCount videos=$selectedVideoCount '
      'original=$originalRequested',
    );

    final settings =
        await ref.read(systemSettingsServiceProvider).getSettings();
    final maxImageSize = settings.maxImageSize * 1024 * 1024;
    final maxVideoSize = settings.maxVideoSize * 1024 * 1024;

    if (PlatformUtils.isWeb) {
      final pendingToAdd = <_PendingImage>[];
      var failedCount = 0;
      var sentVideoCount = 0;

      for (final picked in mediaList) {
        final media = picked.file;
        try {
          final bytes = await media.readAsBytes();
          final ext = _mediaExtension(media);
          if (picked.type == _ChatPickedMediaType.video) {
            if (bytes.isEmpty) {
              failedCount++;
              continue;
            }
            if (bytes.length > maxVideoSize) {
              if (mounted) {
                this._showFileSizeExceededDialog(
                  bytes.length,
                  maxVideoSize,
                  _localizedText(zhCN: '视频', zhTW: '影片', en: 'Video'),
                );
              }
              continue;
            }
            await ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendVideoFromBytes(
                  bytes,
                  media.name.isNotEmpty ? media.name : 'video.$ext',
                  duration: picked.durationMilliseconds,
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
            sentVideoCount++;
            continue;
          }
          if (bytes.isEmpty) {
            failedCount++;
            continue;
          }
          if (bytes.length > maxImageSize) {
            if (mounted) {
              this._showFileSizeExceededDialog(
                bytes.length,
                maxImageSize,
                _localizedText(zhCN: '图片', zhTW: '圖片', en: 'Image'),
              );
            }
            continue;
          }
          final pending = _PendingImage(
            bytes: bytes,
            ext: ext,
            name: media.name,
            originalRequested: originalRequested,
          );
          if (isMixedSelection) {
            await _queueAndSendPickedImages([pending]);
          } else {
            pendingToAdd.add(pending);
          }
        } catch (e, st) {
          failedCount++;
          debugPrint('[Gallery] Failed to read web media ${media.name}: $e');
          debugPrintStack(stackTrace: st, maxFrames: 8);
        }
      }

      if (!isMixedSelection) {
        await _queueAndSendPickedImages(pendingToAdd);
      }
      if (sentVideoCount > 0 && selectedImageCount == 0) {
        this._updateChatListPreview(
          sentVideoCount > 1
              ? _localizedText(
                  zhCN: '[$sentVideoCount 个视频]',
                  zhTW: '[$sentVideoCount 個影片]',
                  en: '[$sentVideoCount videos]',
                )
              : _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
          type: MessageContentType.video,
        );
        this._scrollToBottom();
      }
      _warnSkippedMedia(failedCount);
      return;
    }
    final pendingToAdd = <_PendingImage>[];
    var failedCount = 0;

    for (final picked in mediaList) {
      final media = picked.file;
      try {
        final ext = _mediaExtension(media);
        if (picked.type == _ChatPickedMediaType.video) {
          final path = media.path;
          int size = 0;
          Uint8List? bytes;
          var canUsePath = false;
          if (path.isNotEmpty) {
            final file = File(path);
            canUsePath = await file.exists();
            if (canUsePath) {
              size = await file.length();
            }
          }
          if (!canUsePath) {
            bytes = await media.readAsBytes();
            size = bytes.length;
          }
          if (size <= 0) {
            failedCount++;
            debugPrint(
                '[Gallery] Empty video skipped: ${media.name} path=$path');
            continue;
          }
          if (size > maxVideoSize) {
            if (mounted) {
              this._showFileSizeExceededDialog(
                size,
                maxVideoSize,
                _localizedText(zhCN: '视频', zhTW: '影片', en: 'Video'),
              );
            }
            continue;
          }

          if (canUsePath) {
            await ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendVideoMessage(
                  path,
                  duration: picked.durationMilliseconds,
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
          } else if (bytes != null && bytes.isNotEmpty) {
            await ref
                .read(messageListProvider(widget.chatId).notifier)
                .sendVideoFromBytes(
                  bytes,
                  media.name.isNotEmpty ? media.name : 'video.$ext',
                  duration: picked.durationMilliseconds,
                  burnAfterRead: _activeBurnAfterRead,
                  anonymous: _activeAnonymousSend,
                );
          } else {
            failedCount++;
            continue;
          }
          this._updateChatListPreview(
            _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
            type: MessageContentType.video,
          );
          continue;
        }

        final pending = await _buildPendingImage(
          media,
          maxImageSize,
          originalRequested: originalRequested,
        );
        if (pending == null) {
          failedCount++;
          continue;
        }
        if (isMixedSelection) {
          await _queueAndSendPickedImages([pending]);
        } else {
          pendingToAdd.add(pending);
        }
      } catch (e, st) {
        failedCount++;
        debugPrint('[Gallery] Failed to add selected media ${media.name}: $e');
        debugPrintStack(stackTrace: st, maxFrames: 8);
      }
    }

    if (!isMixedSelection) {
      await _queueAndSendPickedImages(pendingToAdd);
    }
    _warnSkippedMedia(failedCount);
  }

  Future<void> _queueAndSendPickedImages(List<_PendingImage> images) async {
    if (images.isEmpty || !mounted) return;
    final caption = _inputController.text.trim();
    _updateState(() => _pendingImages.addAll(images));
    await _sendPendingImages(caption: caption.isNotEmpty ? caption : null);
  }

  Future<_PendingImage?> _buildPendingImage(
    XFile media,
    int maxImageSize, {
    required bool originalRequested,
  }) async {
    final path = media.path;
    final ext = _mediaExtension(media);
    final file = File(path);
    final canUsePath = path.isNotEmpty && await file.exists();
    final bytes =
        canUsePath ? await file.readAsBytes() : await media.readAsBytes();

    if (bytes.isEmpty) {
      debugPrint('[Gallery] Empty image skipped: ${media.name} path=$path');
      return null;
    }

    if (bytes.length > maxImageSize) {
      if (mounted) {
        this._showFileSizeExceededDialog(
          bytes.length,
          maxImageSize,
          _localizedText(zhCN: '图片', zhTW: '圖片', en: 'Image'),
        );
      }
      return null;
    }

    int? width;
    int? height;
    try {
      final decodedImage = await decodeImageFromList(bytes);
      width = decodedImage.width;
      height = decodedImage.height;
    } catch (e) {
      debugPrint('[Gallery] Decode image dimensions failed: $e');
    }

    return _PendingImage(
      bytes: canUsePath ? null : bytes,
      path: canUsePath ? path : null,
      width: width,
      height: height,
      ext: ext,
      name: media.name,
      originalRequested: originalRequested,
    );
  }

  String _mediaExtension(XFile media) {
    // Web image pickers expose a blob: URL as `path`; it has no reliable file
    // extension. Prefer the original file name so PNG/WebP/HEIC uploads keep
    // the correct multipart filename and content type.
    for (final source in [media.name, media.path]) {
      final cleanSource = source.split('?').first.split('#').first;
      final name = cleanSource.split('/').last.split(r'\').last;
      final dot = name.lastIndexOf('.');
      if (dot < 0 || dot == name.length - 1) continue;
      final ext = name.substring(dot + 1).toLowerCase().trim();
      if (const {
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'avif',
        'mp4',
        'mov',
        'm4v',
        'avi',
        'webm',
      }.contains(ext)) {
        return ext;
      }
    }

    switch (media.mimeType?.toLowerCase().trim()) {
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
      case 'image/avif':
        return 'avif';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'video/quicktime':
        return 'mov';
      case 'video/x-m4v':
        return 'm4v';
      case 'video/x-msvideo':
      case 'video/avi':
        return 'avi';
      case 'video/webm':
        return 'webm';
      case 'video/mp4':
      case 'video/mpeg':
        return 'mp4';
      default:
        return 'jpg';
    }
  }

  bool _isVideoExt(String ext) {
    return ['mp4', 'mov', 'avi', 'm4v', 'webm'].contains(ext);
  }

  void _warnSkippedMedia(int failedCount) {
    if (failedCount <= 0 || !mounted) return;
    AppSnackBar.warning(
      context,
      _localizedText(
        zhCN: '有 $failedCount 个文件无法读取，已跳过',
        zhTW: '有 $failedCount 個檔案無法讀取，已略過',
        en: '$failedCount files could not be read and were skipped.',
      ),
    );
  }

  Future<void> _sendPendingImages({String? caption}) async {
    if (_pendingImages.isEmpty) return;
    if (!_ensureCanSendMedia()) return;
    final images = List<_PendingImage>.from(_pendingImages);
    if (!mounted) return;
    _updateState(() => _pendingImages.clear());
    _inputController.clear();
    _stopTyping();

    final notifier = ref.read(messageListProvider(widget.chatId).notifier);
    var failedCount = 0;
    var successCount = 0;
    final mediaGroupId =
        images.length > 1 ? _createMediaGroupId(images.length) : null;
    final captionMentions = caption != null && caption.isNotEmpty
        ? (_pendingMentionIds.isNotEmpty
            ? List<String>.from(_pendingMentionIds)
            : null)
        : null;
    if (captionMentions != null) {
      _pendingMentionIds.clear();
      _updateState(() {
        _mentionQuery = null;
        _atSignIndex = -1;
      });
    }

    for (int i = 0; i < images.length; i++) {
      final img = images[i];
      final cap = i == 0 ? caption : null;
      final mentions = i == 0 ? captionMentions : null;
      try {
        if (img.bytes != null) {
          final sent = await notifier.sendImageFromBytes(
            img.bytes!,
            ext: img.ext.isNotEmpty ? img.ext : 'png',
            caption: cap,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
            mentions: mentions,
            mediaGroupId: mediaGroupId,
          );
          if (sent) {
            successCount++;
          } else {
            failedCount++;
          }
        } else if (img.path != null) {
          final sent = await notifier.sendImageMessage(
            img.path!,
            width: img.width,
            height: img.height,
            skipCompress: shouldSkipChatImageCompression(
              originalRequested: img.originalRequested,
              extension: img.ext,
            ),
            caption: cap,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
            mentions: mentions,
            mediaGroupId: mediaGroupId,
          );
          if (sent) {
            successCount++;
          } else {
            failedCount++;
          }
        } else {
          failedCount++;
        }
      } catch (e, st) {
        debugPrint('[Gallery] Send pending image failed: $e');
        debugPrintStack(stackTrace: st, maxFrames: 8);
        failedCount++;
      }
    }

    if (!mounted) return;
    if (failedCount > 0) {
      AppSnackBar.error(
        context,
        _localizedText(
          zhCN: '有 $failedCount 张图片发送失败，请重试',
          zhTW: '有 $failedCount 張圖片傳送失敗，請重試',
          en: '$failedCount images failed to send. Please try again.',
        ),
      );
    }
    if (successCount > 0) {
      this._updateChatListPreview(
        successCount > 1
            ? _localizedText(
                zhCN: '[${successCount}张图片]',
                zhTW: '[${successCount}張圖片]',
                en: '[${successCount} photos]',
              )
            : _localizedText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]'),
        type: MessageContentType.photo,
        mediaUrl: images.first.path,
      );
    }
    this._scrollToBottom();
    GlobalHaptics.light();
  }

  String _createMediaGroupId(int count) {
    final userId = ref.read(authServiceProvider).user?.uuid ?? 'user';
    return 'album_${widget.chatId}_${userId}_${DateTime.now().microsecondsSinceEpoch}_$count';
  }

  Future<void> _pickDesktopMediaFiles() async {
    if (!_ensureCanSendMedia()) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'mp4',
        'm4v',
        'mov',
        'avi',
        'webm',
      ],
    );

    if (result == null || result.files.isEmpty) return;

    const maxSelectedMedia = 9;
    final pickedFiles =
        result.files.take(maxSelectedMedia).toList(growable: false);
    if (result.files.length > maxSelectedMedia && mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '一次最多选择 $maxSelectedMedia 个图片或视频',
          zhTW: '一次最多選擇 $maxSelectedMedia 個圖片或影片',
          en: 'Select up to $maxSelectedMedia photos or videos at a time',
        ),
      );
    }

    final settings =
        await ref.read(systemSettingsServiceProvider).getSettings();
    final maxImageSize = settings.maxImageSize * 1024 * 1024;
    final maxVideoSize = settings.maxVideoSize * 1024 * 1024;
    final pendingToAdd = <_PendingImage>[];
    var failedCount = 0;
    var sentVideoCount = 0;

    for (final picked in pickedFiles) {
      final path = picked.path;
      final ext = _extensionFromName(picked.name);
      if (path == null || path.isEmpty) {
        failedCount++;
        debugPrint('[DesktopMedia] Empty file path skipped: ${picked.name}');
        continue;
      }

      try {
        final file = File(path);
        if (!await file.exists()) {
          failedCount++;
          debugPrint('[DesktopMedia] Missing file skipped: $path');
          continue;
        }

        final size = await file.length();
        if (_isVideoExt(ext)) {
          if (size > maxVideoSize) {
            if (mounted) {
              this._showFileSizeExceededDialog(
                size,
                maxVideoSize,
                _localizedText(zhCN: '视频', zhTW: '影片', en: 'Video'),
              );
            }
            continue;
          }

          await ref
              .read(messageListProvider(widget.chatId).notifier)
              .sendVideoMessage(
                path,
                burnAfterRead: _activeBurnAfterRead,
                anonymous: _activeAnonymousSend,
              );
          sentVideoCount++;
          continue;
        }

        final pending = await _buildPendingImageFromPath(
          path: path,
          name: picked.name,
          ext: ext,
          size: size,
          maxImageSize: maxImageSize,
        );
        if (pending == null) {
          failedCount++;
          continue;
        }
        pendingToAdd.add(pending);
      } catch (e, st) {
        failedCount++;
        debugPrint('[DesktopMedia] Failed to add ${picked.name}: $e');
        debugPrintStack(stackTrace: st, maxFrames: 8);
      }
    }

    if (pendingToAdd.isNotEmpty && mounted) {
      _updateState(() => _pendingImages.addAll(pendingToAdd));
    }
    if (sentVideoCount > 0) {
      this._updateChatListPreview(
        sentVideoCount > 1
            ? _localizedText(
                zhCN: '[$sentVideoCount 个视频]',
                zhTW: '[$sentVideoCount 個影片]',
                en: '[$sentVideoCount videos]',
              )
            : _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
        type: MessageContentType.video,
      );
      this._scrollToBottom();
    }
    _warnSkippedMedia(failedCount);
  }

  Future<_PendingImage?> _buildPendingImageFromPath({
    required String path,
    required String name,
    required String ext,
    required int size,
    required int maxImageSize,
  }) async {
    if (size > maxImageSize) {
      if (mounted) {
        this._showFileSizeExceededDialog(
          size,
          maxImageSize,
          _localizedText(zhCN: '图片', zhTW: '圖片', en: 'Image'),
        );
      }
      return null;
    }

    int? width;
    int? height;
    try {
      final bytes = await File(path).readAsBytes();
      final decodedImage = await decodeImageFromList(bytes);
      width = decodedImage.width;
      height = decodedImage.height;
    } catch (e) {
      debugPrint('[DesktopMedia] Decode image dimensions failed: $e');
    }

    return _PendingImage(
      path: path,
      width: width,
      height: height,
      ext: ext,
      name: name,
    );
  }

  String _extensionFromName(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase().trim();
  }
}
