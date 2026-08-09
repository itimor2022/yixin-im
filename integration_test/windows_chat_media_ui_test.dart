import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:generic_im/core/router/app_router.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/core/services/api/auth_service.dart';
import 'package:generic_im/features/chat/providers/message_provider.dart';
import 'package:generic_im/main.dart' as app;

const _username = String.fromEnvironment(
  'GENERIC_IM_SMOKE_USERNAME',
  defaultValue: 'smoke_alice',
);
const _password = String.fromEnvironment(
  'GENERIC_IM_SMOKE_PASSWORD',
  defaultValue: 'Smoke123',
);
const _chatId = String.fromEnvironment('GENERIC_IM_SMOKE_CHAT_ID');
const _chatName = String.fromEnvironment(
  'GENERIC_IM_SMOKE_CHAT_NAME',
  defaultValue: 'smoke_bob',
);
const _chatType = String.fromEnvironment(
  'GENERIC_IM_SMOKE_CHAT_TYPE',
  defaultValue: 'private',
);
const _incomingImageMessageId =
    String.fromEnvironment('GENERIC_IM_QA_INCOMING_IMAGE_MSG_ID');
const _incomingVideoMessageId =
    String.fromEnvironment('GENERIC_IM_QA_INCOMING_VIDEO_MSG_ID');
const _imageFixture = String.fromEnvironment('GENERIC_IM_QA_IMAGE_FIXTURE');
const _videoFixture = String.fromEnvironment('GENERIC_IM_QA_VIDEO_FIXTURE');
const _imageFixtureBase64 =
    String.fromEnvironment('GENERIC_IM_QA_IMAGE_FIXTURE_BASE64');
const _videoFixtureBase64 =
    String.fromEnvironment('GENERIC_IM_QA_VIDEO_FIXTURE_BASE64');
const _artifactDir = String.fromEnvironment('GENERIC_IM_QA_ARTIFACT_DIR');
const _skipUploads = bool.fromEnvironment('GENERIC_IM_QA_SKIP_UPLOAD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows receives, plays, and sends chat media', (
    tester,
  ) async {
    _requireDefine('GENERIC_IM_SMOKE_CHAT_ID', _chatId);
    _requireDefine('GENERIC_IM_QA_INCOMING_IMAGE_MSG_ID', _incomingImageMessageId);
    _requireDefine('GENERIC_IM_QA_INCOMING_VIDEO_MSG_ID', _incomingVideoMessageId);
    var resolvedImageFixture = _imageFixture;
    var resolvedVideoFixture = _videoFixture;
    if (!_skipUploads) {
      resolvedImageFixture = await _resolveFixture(
        name: 'image',
        configuredPath: _imageFixture,
        base64Payload: _imageFixtureBase64,
        extension: 'png',
      );
      resolvedVideoFixture = await _resolveFixture(
        name: 'video',
        configuredPath: _videoFixture,
        base64Payload: _videoFixtureBase64,
        extension: 'mp4',
      );
    }
    _requireDefine('GENERIC_IM_QA_ARTIFACT_DIR', _artifactDir);
    _stage('requirements-validated');

    await TokenStorage.clear();
    _stage('token-cleared');
    Object? unexpectedAsyncError;
    StackTrace? unexpectedAsyncStack;
    await runZonedGuarded(
      () => app.main(const <String>[]),
      (error, stack) {
        if (_isExpectedStartupError(error)) {
          debugPrint('MEDIA_QA_IGNORED_ASYNC_STARTUP_ERROR $error');
          return;
        }
        unexpectedAsyncError ??= error;
        unexpectedAsyncStack ??= stack;
        debugPrint('MEDIA_QA_UNEXPECTED_ASYNC_ERROR $error\n$stack');
      },
    );
    final appFlutterErrorHandler = FlutterError.onError;
    FlutterErrorDetails? unexpectedFlutterError;
    addTearDown(() {
      FlutterError.onError = appFlutterErrorHandler;
    });
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (_isExpectedStartupError(details.exception)) {
        debugPrint('MEDIA_QA_IGNORED_STARTUP_ERROR $message');
        return;
      }
      unexpectedFlutterError ??= details;
      FlutterError.presentError(details);
    };
    _stage('app-started');

    await _pumpUntil(
      tester,
      () {
        if (find
            .byKey(const Key('login_username_field'))
            .hitTestable()
            .evaluate()
            .isNotEmpty) {
          return true;
        }
        final context = rootNavigatorKey.currentContext;
        if (context == null) return false;
        final state = ProviderScope.containerOf(context, listen: false)
            .read(authServiceProvider);
        return state.status == AuthStatus.authenticated &&
            state.user?.username == _username;
      },
      timeout: const Duration(seconds: 40),
      failure: 'Expected login page or an authenticated session.',
    );
    final loginField =
        find.byKey(const Key('login_username_field')).hitTestable();
    if (loginField.evaluate().isNotEmpty) {
      _stage('login-visible');
      await tester.enterText(loginField, _username);
      await tester.enterText(
        find.byKey(const Key('login_password_field')).hitTestable(),
        _password,
      );
      await tester.tap(
        find.byKey(const Key('login_terms_checkbox')).hitTestable(),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(
        find.byKey(const Key('login_submit_button')).hitTestable(),
      );
      await _pumpUntilGone(
        tester,
        find.byKey(const Key('login_submit_button')),
        timeout: const Duration(seconds: 40),
      );
      _stage('login-complete');
    } else {
      final context = rootNavigatorKey.currentContext!;
      final state = ProviderScope.containerOf(context, listen: false)
          .read(authServiceProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.user?.username, _username);
      _stage('authenticated-session-reused');
    }
    await _dismissMultiDeviceNotice(tester);

    final rootContext =
        await _rootContext(timeout: const Duration(seconds: 10));
    _stage('root-context-ready');
    rootContext.go(
      '/chat/$_chatId?name=${Uri.encodeComponent(_chatName)}&type=$_chatType',
    );
    _stage('chat-route-requested');
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat_message_input')),
      timeout: const Duration(seconds: 40),
    );
    _stage('chat-visible');

    final container = ProviderScope.containerOf(rootContext, listen: false);
    final provider = messageListProvider(_chatId);
    await tester.runAsync(() => container.read(provider.notifier).initialize());
    _stage('messages-initialized');

    final incomingImage = await _waitForMessage(
      container,
      provider,
      _incomingImageMessageId,
      timeout: const Duration(seconds: 40),
    );
    final incomingVideo = await _waitForMessage(
      container,
      provider,
      _incomingVideoMessageId,
      timeout: const Duration(seconds: 40),
    );
    _stage('incoming-messages-found');
    expect(incomingImage.mediaId, isNotEmpty);
    expect(incomingVideo.mediaId, isNotEmpty);
    expect(incomingVideo.thumbnailMediaId, isNotEmpty);

    final resolvedIncoming = await _waitForResolvedMedia(
      container,
      provider,
      imageMessageId: _incomingImageMessageId,
      videoMessageId: _incomingVideoMessageId,
      timeout: const Duration(seconds: 45),
    );
    await tester.runAsync(
      () => Future.wait([
        _decodeNetworkImage(resolvedIncoming.image.mediaUrl!),
        _decodeNetworkImage(resolvedIncoming.video.thumbnail!),
      ]),
    );
    _stage('incoming-images-decoded');
    await tester.pump(const Duration(seconds: 1));
    await _dismissMultiDeviceNotice(tester);
    await _saveScreenshot('windows-received-media');
    _stage('incoming-screenshot-finished');

    final videoBubble =
        find.byKey(const ValueKey('message_video_bubble')).hitTestable();
    await _pumpUntilVisible(
      tester,
      videoBubble,
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(videoBubble.first);
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('message_video_player_page')),
      timeout: const Duration(seconds: 35),
    );
    await _pumpUntil(
      tester,
      () {
        final players = find.byType(VideoPlayer).evaluate();
        if (players.isEmpty) return false;
        final player = players.first.widget as VideoPlayer;
        return player.controller.value.isInitialized &&
            player.controller.value.position > Duration.zero &&
            !player.controller.value.hasError;
      },
      timeout: const Duration(seconds: 45),
      failure: 'Expected the Windows video player to make playback progress.',
    );
    _stage('incoming-video-playing');
    await _saveScreenshot('windows-video-playing');
    _stage('video-screenshot-finished');
    final playerContext = tester.element(
      find.byKey(const ValueKey('message_video_player_page')),
    );
    Navigator.of(playerContext).pop();
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat_message_input')),
      timeout: const Duration(seconds: 15),
    );
    _stage('video-player-closed');
    _debugVideoBubbleLayout(tester);
    if (_skipUploads) {
      _stage('complete');
      // Dispose the app tree before the integration binding tears down. The
      // desktop app has delayed animations/listeners that otherwise report
      // post-dispose errors after the test has already completed.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        unexpectedFlutterError,
        isNull,
        reason: unexpectedFlutterError?.exceptionAsString(),
      );
      expect(
        unexpectedAsyncError,
        isNull,
        reason: '$unexpectedAsyncError\n$unexpectedAsyncStack',
      );
      return;
    }

    final beforeIds =
        container.read(provider).map((message) => message.id).toSet();
    final imageSent = await tester.runAsync(
      () => container.read(provider.notifier).sendImageMessage(
            resolvedImageFixture,
            width: 192,
            height: 192,
            skipCompress: true,
            caption: 'windows-media-qa-image',
          ),
    );
    expect(imageSent, isTrue);
    _stage('image-upload-returned');
    final sentImage = await _waitForNewSentMedia(
      container,
      provider,
      beforeIds,
      MessageItemType.image,
      timeout: const Duration(seconds: 90),
    );
    expect(sentImage.mediaId, isNotEmpty);
    _stage('image-message-sent');

    final imageIds =
        container.read(provider).map((message) => message.id).toSet();
    await tester.runAsync(
      () => container.read(provider.notifier).sendVideoMessage(
            resolvedVideoFixture,
            duration: 800,
          ),
    );
    _stage('video-upload-returned');
    final sentVideo = await _waitForNewSentMedia(
      container,
      provider,
      imageIds,
      MessageItemType.video,
      timeout: const Duration(minutes: 5),
    );
    expect(sentVideo.mediaId, isNotEmpty);
    expect(sentVideo.thumbnailMediaId, isNotEmpty);
    _stage('video-message-sent');

    final resolvedSent = await _waitForResolvedMedia(
      container,
      provider,
      imageMessageId: sentImage.id,
      videoMessageId: sentVideo.id,
      timeout: const Duration(seconds: 45),
    );
    await tester.runAsync(
      () => Future.wait([
        _decodeNetworkImage(resolvedSent.image.mediaUrl!),
        _decodeNetworkImage(resolvedSent.video.thumbnail!),
      ]),
    );
    _stage('sent-images-decoded');
    await tester.pump(const Duration(seconds: 1));
    await _saveScreenshot('windows-sent-media');
    _stage('complete');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      unexpectedFlutterError,
      isNull,
      reason: unexpectedFlutterError?.exceptionAsString(),
    );
    expect(
      unexpectedAsyncError,
      isNull,
      reason: '$unexpectedAsyncError\n$unexpectedAsyncStack',
    );

    debugPrint(
      'WINDOWS_MEDIA_QA '
      'image_msg_id=${sentImage.id} image_media_id=${sentImage.mediaId} '
      'video_msg_id=${sentVideo.id} video_media_id=${sentVideo.mediaId} '
      'thumbnail_media_id=${sentVideo.thumbnailMediaId}',
    );
  });
}

bool _isExpectedStartupError(Object error) {
  final message = error.toString();
  return message.contains('Request throttled') ||
      message.contains("No Firebase App '[DEFAULT]' has been created");
}

Future<String> _resolveFixture({
  required String name,
  required String configuredPath,
  required String base64Payload,
  required String extension,
}) async {
  final configured = configuredPath.trim();
  if (configured.isNotEmpty && File(configured).existsSync()) {
    return configured;
  }
  _requireDefine(
      'GENERIC_IM_QA_${name.toUpperCase()}_FIXTURE_BASE64', base64Payload);
  final bytes = base64Decode(base64Payload);
  if (bytes.isEmpty) {
    fail('Decoded $name fixture is empty.');
  }
  final output = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'genericim-s3-real-device-$name.$extension',
  );
  await output.writeAsBytes(bytes, flush: true);
  return output.path;
}

Future<_ResolvedMediaPair> _waitForResolvedMedia(
  ProviderContainer container,
  AutoDisposeStateNotifierProvider<MessageListNotifier, List<MessageItem>>
      provider, {
  required String imageMessageId,
  required String videoMessageId,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final messages = container.read(provider);
    final image = _findMessage(messages, imageMessageId);
    final video = _findMessage(messages, videoMessageId);
    if (image != null &&
        video != null &&
        _isSignedAccessUrl(image.mediaUrl) &&
        _isSignedAccessUrl(video.mediaUrl) &&
        _isSignedAccessUrl(video.thumbnail)) {
      return _ResolvedMediaPair(image, video);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Private media URLs did not resolve.', timeout);
}

Future<MessageItem> _waitForMessage(
  ProviderContainer container,
  AutoDisposeStateNotifierProvider<MessageListNotifier, List<MessageItem>>
      provider,
  String messageId, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final message = _findMessage(container.read(provider), messageId);
    if (message != null) return message;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Message $messageId did not load.', timeout);
}

Future<MessageItem> _waitForNewSentMedia(
  ProviderContainer container,
  AutoDisposeStateNotifierProvider<MessageListNotifier, List<MessageItem>>
      provider,
  Set<String> previousIds,
  MessageItemType type, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final message in container.read(provider)) {
      if (!previousIds.contains(message.id) &&
          message.type == type &&
          message.status == MessageStatus.sent &&
          (message.mediaId?.isNotEmpty ?? false)) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('New $type message was not sent.', timeout);
}

MessageItem? _findMessage(List<MessageItem> messages, String messageId) {
  for (final message in messages) {
    if (message.id == messageId) return message;
  }
  return null;
}

bool _isSignedAccessUrl(String? rawUrl) {
  final uri = Uri.tryParse(rawUrl ?? '');
  return uri != null &&
      uri.isScheme('https') &&
      uri.queryParameters.containsKey('X-Amz-Signature');
}

Future<void> _decodeNetworkImage(String url) {
  final completer = Completer<void>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, synchronousCall) {
      if (info.image.width <= 0 || info.image.height <= 0) {
        completer.completeError(StateError('Decoded image has no dimensions.'));
      } else {
        completer.complete();
      }
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stackTrace) {
      completer.completeError(error, stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 30));
}

Future<void> _saveScreenshot(String name) async {
  if (Platform.isIOS || Platform.isAndroid) {
    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    await binding.convertFlutterSurfaceToImage();
    await binding.takeScreenshot(name);
    debugPrint(
      'MEDIA_QA_SCREENSHOT name=$name path=integration-artifacts:$name',
    );
    return;
  }
  final directory = Directory(_artifactDir);
  await directory.create(recursive: true);
  final outputPath = '${directory.path}${Platform.pathSeparator}$name.png';
  if (Platform.isMacOS) {
    final result = await Process.run(
      '/usr/sbin/screencapture',
      ['-x', outputPath],
    ).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0 || !File(outputPath).existsSync()) {
      throw ProcessException(
        '/usr/sbin/screencapture',
        ['-x', outputPath],
        '${result.stderr}\n${result.stdout}',
        result.exitCode,
      );
    }
    debugPrint('MEDIA_QA_SCREENSHOT name=$name path=$outputPath');
    return;
  }
  final scriptPath = '${Directory.current.path}${Platform.pathSeparator}scripts'
      '${Platform.pathSeparator}capture-windows-app.ps1';
  final result = await Process.run(
    r'pwsh',
    [
      '-NoProfile',
      '-File',
      scriptPath,
      '-OutputPath',
      outputPath,
    ],
    runInShell: true,
  ).timeout(const Duration(seconds: 20));
  if (result.exitCode != 0 || !File(outputPath).existsSync()) {
    throw ProcessException(
      r'pwsh',
      ['-NoProfile', '-File', scriptPath, '-OutputPath', outputPath],
      '${result.stderr}\n${result.stdout}',
      result.exitCode,
    );
  }
  debugPrint('WINDOWS_MEDIA_QA_SCREENSHOT name=$name path=$outputPath');
}

Future<BuildContext> _rootContext({required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final context = rootNavigatorKey.currentContext;
    if (context != null) return context;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Root navigator context was not ready.', timeout);
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) {
  return _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
    failure: 'Expected ${finder.description} to be visible.',
  );
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) {
  return _pumpUntil(
    tester,
    () => finder.evaluate().isEmpty,
    timeout: timeout,
    failure: 'Expected ${finder.description} to disappear.',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail(failure);
}

void _requireDefine(String name, String value) {
  if (value.trim().isEmpty) fail('$name is required.');
}

Future<void> _dismissMultiDeviceNotice(WidgetTester tester) async {
  final action = find.text('我知道了').hitTestable();
  if (action.evaluate().isEmpty) return;
  await tester.tap(action.last);
  await tester.pump(const Duration(milliseconds: 500));
  _stage('multi-device-notice-dismissed');
}

void _requireFile(String name, String path) {
  _requireDefine(name, path);
  if (!File(path).existsSync()) fail('$name does not exist: $path');
}

class _ResolvedMediaPair {
  const _ResolvedMediaPair(this.image, this.video);

  final MessageItem image;
  final MessageItem video;
}

void _stage(String name) {
  if (Platform.isIOS || Platform.isAndroid) {
    debugPrint('MEDIA_QA_STAGE name=$name');
    return;
  }
  final directory = Directory(_artifactDir);
  directory.createSync(recursive: true);
  final timestamp = DateTime.now().toIso8601String();
  File('${directory.path}${Platform.pathSeparator}windows-media-qa.stage')
      .writeAsStringSync('$timestamp $name\n',
          mode: FileMode.append, flush: true);
  debugPrint('WINDOWS_MEDIA_QA_STAGE name=$name timestamp=$timestamp');
}

void _debugVideoBubbleLayout(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('message_video_bubble'));
  var index = 0;
  for (final element in finder.evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) continue;
    final offset = renderObject.localToGlobal(Offset.zero);
    debugPrint(
      'WINDOWS_MEDIA_QA_LAYOUT index=$index '
      'x=${offset.dx.toStringAsFixed(1)} y=${offset.dy.toStringAsFixed(1)} '
      'width=${renderObject.size.width.toStringAsFixed(1)} '
      'height=${renderObject.size.height.toStringAsFixed(1)}',
    );
    index++;
  }
  final renderView = tester.binding.renderViews.first;
  debugPrint(
    'WINDOWS_MEDIA_QA_RENDER_VIEW '
    'width=${renderView.size.width.toStringAsFixed(1)} '
    'height=${renderView.size.height.toStringAsFixed(1)}',
  );
}
