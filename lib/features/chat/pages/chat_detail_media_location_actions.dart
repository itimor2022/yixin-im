// 文件用途：实现 _ChatDetailMediaLocationActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMediaLocationActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media location actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaLocationActions on _ChatDetailPageState {
  // 流程逻辑：`_sendCurrentLocation` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _sendCurrentLocation() async {
    try {
      if (PlatformUtils.isWeb) {
        await _sendBrowserCurrentLocation();
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        if (!mounted) return;
        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '请先开启定位服务',
            zhTW: '請先開啟定位服務',
            en: 'Please enable location services first',
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (permission == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        }
        if (!mounted) return;
        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '未获得定位权限，无法发送位置',
            zhTW: '未取得定位權限，無法發送位置',
            en: 'Location permission not granted. Unable to send location.',
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await _sendLocationPosition(position);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(
        context,
        _localizedText(
          zhCN: '发送位置失败',
          zhTW: '發送位置失敗',
          en: 'Failed to send location',
        ),
      );
    }
  }

  Future<void> _sendBrowserCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '浏览器未允许定位权限，无法发送位置',
          zhTW: '瀏覽器未允許定位權限，無法發送位置',
          en: 'Browser location permission is not allowed.',
        ),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    await _sendLocationPosition(position);
  }

  Future<void> _sendLocationPosition(Position position) async {
    final address =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

    final error = await ref
        .read(messageListProvider(widget.chatId).notifier)
        .sendLocationMessage(
          latitude: position.latitude,
          longitude: position.longitude,
          title: _localizedText(
            zhCN: '我的位置',
            zhTW: '我的位置',
            en: 'My Location',
          ),
          address: address,
          burnAfterRead: _activeBurnAfterRead,
        );
    if (!mounted) return;
    if (error != null) {
      this._showMessageSendError(error);
      return;
    }

    this._updateChatListPreview(
      _localizedText(zhCN: '[位置]', zhTW: '[位置]', en: '[Location]'),
      type: MessageContentType.location,
    );
    this._scrollToBottom();
    GlobalHaptics.light();
  }
}
