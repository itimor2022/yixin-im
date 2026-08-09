import Flutter
import UIKit
import UserNotifications
import CryptoKit
import PushKit
import CallKit
import os
import flutter_callkit_incoming

private final class PushCompletionOnce {
  private let lock = NSLock()
  private var didFinish = false
  private let completion: () -> Void

  init(_ completion: @escaping () -> Void) {
    self.completion = completion
  }

  func finish() {
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    didFinish = true
    lock.unlock()
    completion()
  }
}

private final class NativeCallKitManager: NSObject, CXProviderDelegate {
  typealias EventHandler = (_ event: String, _ data: [String: Any]) -> Void

  private let provider: CXProvider
  private var calls: [UUID: flutter_callkit_incoming.Data] = [:]
  private var timeoutTasks: [UUID: DispatchWorkItem] = [:]
  var onEvent: EventHandler?

  init(appName: String) {
    let configuration = CXProviderConfiguration(localizedName: appName)
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 2
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = true
    if let icon = UIImage(named: "CallKitLogo")?.pngData() {
      configuration.iconTemplateImageData = icon
    }
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: .main)
  }

  func reportIncomingCall(
    _ data: flutter_callkit_incoming.Data,
    completion: @escaping (Error?) -> Void
  ) {
    guard let uuid = UUID(uuidString: data.uuid) else {
      completion(NSError(
        domain: "com.genericim.callkit",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid CallKit UUID"]
      ))
      return
    }

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: data.handle)
    update.localizedCallerName = data.nameCaller
    update.hasVideo = data.type > 0
    update.supportsDTMF = data.supportsDTMF
    update.supportsHolding = data.supportsHolding
    update.supportsGrouping = data.supportsGrouping
    update.supportsUngrouping = data.supportsUngrouping

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      guard let self = self else {
        completion(error)
        return
      }
      if error == nil {
        self.calls[uuid] = data
        self.emit("incoming", data: data)
        self.scheduleTimeout(for: uuid)
      }
      completion(error)
    }
  }

  func endCall(uuidString: String, reason: CXCallEndedReason = .remoteEnded) {
    guard let uuid = UUID(uuidString: uuidString), calls[uuid] != nil else {
      return
    }
    provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    removeCall(uuid)
  }

  func providerDidReset(_ provider: CXProvider) {
    for task in timeoutTasks.values {
      task.cancel()
    }
    timeoutTasks.removeAll()
    calls.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let data = calls[action.callUUID] else {
      action.fail()
      return
    }
    data.isAccepted = true
    timeoutTasks.removeValue(forKey: action.callUUID)?.cancel()
    emit("accept", data: data)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let data = calls[action.callUUID] else {
      action.fail()
      return
    }
    emit(data.isAccepted ? "ended" : "decline", data: data)
    removeCall(action.callUUID)
    action.fulfill()
  }

  private func scheduleTimeout(for uuid: UUID) {
    timeoutTasks.removeValue(forKey: uuid)?.cancel()
    let task = DispatchWorkItem { [weak self] in
      guard let self = self, let data = self.calls[uuid] else { return }
      self.provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      self.emit("timeout", data: data)
      self.removeCall(uuid)
    }
    timeoutTasks[uuid] = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: task)
  }

  private func removeCall(_ uuid: UUID) {
    timeoutTasks.removeValue(forKey: uuid)?.cancel()
    calls.removeValue(forKey: uuid)
  }

  private func emit(_ event: String, data: flutter_callkit_incoming.Data) {
    var body = data.toJSON()
    var extra = (body["extra"] as? [String: Any]) ?? [:]
    extra["_native_callkit_fallback"] = true
    body["extra"] = extra
    onEvent?(event, body)
  }
}

private final class VoiceProximityStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(proximityChanged),
      name: UIDevice.proximityStateDidChangeNotification,
      object: nil
    )
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    events(UIDevice.current.proximityState)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    setEnabled(false)
    return nil
  }

  func setEnabled(_ enabled: Bool) {
    UIDevice.current.isProximityMonitoringEnabled = enabled
  }

  @objc private func proximityChanged() {
    eventSink?(UIDevice.current.proximityState)
  }

  deinit {
    UIDevice.current.isProximityMonitoringEnabled = false
    NotificationCenter.default.removeObserver(self)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, FlutterImplicitEngineDelegate {
  private var pushTokenChannel: FlutterMethodChannel?
  private var hotUpdateChannel: FlutterMethodChannel?
  private var deepLinkChannel: FlutterMethodChannel?
  private var voiceProximityMethodChannel: FlutterMethodChannel?
  private var voiceProximityEventChannel: FlutterEventChannel?
  private var voiceProximityHandler: VoiceProximityStreamHandler?
  private var pendingDeepLink: String?
  private var voipRegistry: PKPushRegistry?
  private let voIPTokenDefaultsKey = "genericim.latest_voip_push_token.v1"
  private var latestVoIPToken: String?
  private let callKitAppName = "通用IM"
  private lazy var nativeCallKitManager = NativeCallKitManager(appName: callKitAppName)
  private var nativeCallKitEventsReady = false
  private var pendingNativeCallKitEvents: [[String: Any]] = []
  private lazy var pushLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.genericim.app",
    category: "PushKit"
  )

  private func pushDebugLog(_ message: String) {
    pushLogger.log(level: .info, "\(message, privacy: .public)")
  }
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    pushDebugLog("[Push] ========== App launching ==========")
    nativeCallKitManager.onEvent = { [weak self] event, data in
      self?.enqueueNativeCallKitEvent(event, data: data)
    }
    if let launchURL = launchOptions?[.url] as? URL,
       launchURL.scheme?.lowercased() == "genericim" {
      pendingDeepLink = launchURL.absoluteString
    }
    // 设置通知代理
    UNUserNotificationCenter.current().delegate = self
    // PushKit must be recreated on every launch, including a background
    // launch caused by a VoIP push. Do not wait for Dart registration.
    registerForVoIPPush()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureFlutterChannels(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func configureFlutterChannels(binaryMessenger: FlutterBinaryMessenger) {
    pushDebugLog("[Push] Setting up Method Channels with initialized Flutter engine")
    pushTokenChannel = FlutterMethodChannel(
      name: "com.genericim/push",
      binaryMessenger: binaryMessenger
    )
    hotUpdateChannel = FlutterMethodChannel(
      name: "com.genericim/hot_update",
      binaryMessenger: binaryMessenger
    )
    deepLinkChannel = FlutterMethodChannel(
      name: "com.genericim/deep_link",
      binaryMessenger: binaryMessenger
    )

    let proximityHandler = VoiceProximityStreamHandler()
    voiceProximityHandler = proximityHandler
    voiceProximityEventChannel = FlutterEventChannel(
      name: "com.genericim/voice_proximity/events",
      binaryMessenger: binaryMessenger
    )
    voiceProximityEventChannel?.setStreamHandler(proximityHandler)
    voiceProximityMethodChannel = FlutterMethodChannel(
      name: "com.genericim/voice_proximity/methods",
      binaryMessenger: binaryMessenger
    )
    voiceProximityMethodChannel?.setMethodCallHandler { call, result in
      guard call.method == "setScreenOffEnabled" else {
        result(FlutterMethodNotImplemented)
        return
      }
      proximityHandler.setEnabled(call.arguments as? Bool == true)
      result(true)
    }

    pushTokenChannel?.setMethodCallHandler { [weak self] call, result in
      self?.pushDebugLog("[Push] Received method call: \(call.method)")
      switch call.method {
      case "registerForPush":
        self?.registerForPushNotifications()
        self?.replayLatestVoIPToken()
        result(nil)
      case "nativeCallKitEventsReady":
        self?.nativeCallKitEventsReady = true
        self?.flushPendingNativeCallKitEvents()
        result(nil)
      case "endNativeCall":
        let arguments = call.arguments as? [String: Any]
        let uuid = arguments?["uuid"] as? String ?? ""
        self?.nativeCallKitManager.endCall(uuidString: uuid)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    hotUpdateChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleHotUpdateMethod(call: call, result: result)
    }
    deepLinkChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pendingDeepLink)
      self?.pendingDeepLink = nil
    }
    flushPendingNativeCallKitEvents()
    pushDebugLog("[Push] Method Channel setup complete")
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme?.lowercased() == "genericim" {
      pendingDeepLink = url.absoluteString
      deepLinkChannel?.invokeMethod("onLink", arguments: url.absoluteString)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func handleHotUpdateMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result([
        // App Store builds must use Shorebird's signed updater. Self-hosted
        // package installation is intentionally unavailable on iOS.
        "available": false,
        "sdkIntegrated": false,
        "platform": "ios",
        "message": "ios_self_hosted_updater_disabled",
      ])
    case "applyPatch":
      result([
        "success": false,
        "requires_restart": false,
        "message": "ios_self_hosted_updater_disabled",
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func stringifyKeyMap(_ raw: [AnyHashable: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in raw {
      result[String(describing: key)] = value
    }
    return result
  }

  private func mapFromAny(_ value: Any?) -> [String: Any] {
    if let map = value as? [String: Any] {
      return map
    }
    if let map = value as? [AnyHashable: Any] {
      return stringifyKeyMap(map)
    }
    if let string = value as? String,
       let data = string.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) {
      return mapFromAny(json)
    }
    return [:]
  }

  private func normalizedPushPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var payload = stringifyKeyMap(userInfo)
    let nestedData = mapFromAny(payload["data"])
    for (key, value) in nestedData {
      payload[key] = value
    }

    let aps = mapFromAny(payload["aps"])
    let alert = mapFromAny(aps["alert"])
    if payload["title"] == nil, let title = alert["title"] {
      payload["title"] = title
    }
    if payload["body"] == nil, let body = alert["body"] {
      payload["body"] = body
    }
    return payload
  }

  private func firstString(_ payload: [String: Any], _ keys: [String]) -> String {
    for key in keys {
      if let value = payload[key] {
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && text != "<null>" {
          return text
        }
      }
    }
    return ""
  }

  private func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.boolValue
    }
    if let value = value as? String {
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return normalized == "true" || normalized == "1" || normalized == "yes"
    }
    return false
  }

  private func callKitUUID(for callID: String) -> String {
    let normalized = callID.trimmingCharacters(in: .whitespacesAndNewlines)
    if UUID(uuidString: normalized) != nil {
      return normalized
    }

    let digest = SHA256.hash(data: Foundation.Data("genericim-call-\(normalized)".utf8))
    let bytes = Array(digest)
    return String(
      format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
  }

  private func fallbackCallID(for payload: [String: Any]) -> String {
    let encoded: Foundation.Data
    if JSONSerialization.isValidJSONObject(payload),
       let json = try? JSONSerialization.data(
         withJSONObject: payload,
         options: [.sortedKeys]
       ) {
      encoded = json
    } else {
      encoded = Foundation.Data(payload.keys.sorted().joined(separator: "|").utf8)
    }
    let digest = SHA256.hash(data: encoded)
    return "invalid-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  private func incomingCallKitData(
    from userInfo: [AnyHashable: Any],
    forceReport: Bool
  ) -> flutter_callkit_incoming.Data? {
    var payload = normalizedPushPayload(userInfo)
    let originalType = firstString(payload, ["type"])
    guard forceReport || originalType == "incoming_call" else {
      return nil
    }

    let suppliedCallID = firstString(payload, ["call_id", "callId"])
    let callID = suppliedCallID.isEmpty ? fallbackCallID(for: payload) : suppliedCallID
    let callerID = firstString(payload, ["caller_id"])
    let suppliedCallerName = firstString(payload, ["caller_name", "title", "nameCaller"])
    let callerName = suppliedCallerName.isEmpty ? "未知来电" : suppliedCallerName
    let channelName = firstString(payload, ["channel_name", "room_name"])
    var missingFields: [String] = []
    if originalType != "incoming_call" { missingFields.append("type") }
    if suppliedCallID.isEmpty { missingFields.append("call_id") }
    if callerID.isEmpty { missingFields.append("caller_id") }
    if suppliedCallerName.isEmpty { missingFields.append("caller_name") }
    if channelName.isEmpty { missingFields.append("channel_name") }
    if !missingFields.isEmpty {
      pushDebugLog(
        "[PushKit] Incoming call payload incomplete missing=\(missingFields.sorted()) keys=\(payload.keys.sorted())"
      )
    }

    let roomName = firstString(payload, ["room_name", "channel_name"])
    let provider = firstString(payload, ["rtc_provider", "provider"])
    let serverURL = firstString(payload, ["server_url", "livekit_server_url"])
    let callType = firstString(payload, ["call_type"])
    let isVideo = callType == "video" || boolValue(payload["is_video"])
    let avatar = firstString(payload, ["caller_avatar", "avatar"])
    let uuid = callKitUUID(for: callID)

    payload["type"] = "incoming_call"
    if !originalType.isEmpty && originalType != "incoming_call" {
      payload["_voip_original_type"] = originalType
    }
    payload["call_id"] = callID
    payload["callId"] = callID
    payload["caller_id"] = callerID
    payload["caller_name"] = callerName
    payload["caller_avatar"] = avatar
    payload["call_type"] = isVideo ? "video" : "voice"
    payload["is_video"] = isVideo
    payload["channel_name"] = channelName
    payload["room_name"] = roomName.isEmpty ? channelName : roomName
    payload["provider"] = provider
    payload["rtc_provider"] = provider
    payload["server_url"] = serverURL
    payload["livekit_server_url"] = serverURL
    payload["_business_data_incomplete"] = !missingFields.isEmpty
    payload["_missing_fields"] = missingFields.sorted()
    payload["_callkit_uuid"] = uuid
    payload.removeValue(forKey: "aps")
    payload.removeValue(forKey: "data")

    let data = flutter_callkit_incoming.Data(
      id: uuid,
      nameCaller: callerName,
      handle: callerName,
      type: isVideo ? 1 : 0
    )
    data.appName = callKitAppName
    data.avatar = avatar
    data.duration = 30000
    data.extra = payload as NSDictionary
    data.iconName = "CallKitLogo"
    data.handleType = "generic"
    data.supportsVideo = true
    data.maximumCallGroups = 2
    data.maximumCallsPerCallGroup = 1
    data.configureAudioSession = false
    data.audioSessionMode = "default"
    data.audioSessionActive = false
    data.supportsDTMF = true
    data.supportsHolding = true
    data.supportsGrouping = false
    data.supportsUngrouping = false
    data.ringtonePath = ""
    return data
  }

  private func enqueueNativeCallKitEvent(_ event: String, data: [String: Any]) {
    let item: [String: Any] = ["event": event, "body": data]
    pendingNativeCallKitEvents.append(item)
    flushPendingNativeCallKitEvents()
  }

  private func flushPendingNativeCallKitEvents() {
    guard nativeCallKitEventsReady,
          let channel = pushTokenChannel,
          !pendingNativeCallKitEvents.isEmpty else {
      return
    }
    let events = pendingNativeCallKitEvents
    pendingNativeCallKitEvents.removeAll()
    for event in events {
      channel.invokeMethod("onNativeCallKitEvent", arguments: event)
    }
  }

  private func forwardNotificationToFlutter(_ userInfo: [AnyHashable: Any], method: String) {
    if let data = try? JSONSerialization.data(withJSONObject: userInfo),
       let jsonString = String(data: data, encoding: .utf8) {
      pushTokenChannel?.invokeMethod(method, arguments: jsonString)
    }
  }
  
  // 注册推送通知
  private func registerForPushNotifications() {
    pushDebugLog("[Push] ========== Starting push registration ==========")
    pushDebugLog("[Push] pushTokenChannel is nil: \(pushTokenChannel == nil)")
    pushDebugLog("[Push] isRegisteredForRemoteNotifications: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
    
    // 检查当前通知设置
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      self.pushDebugLog("[Push] Current notification settings:")
      self.pushDebugLog("[Push]   authorizationStatus: \(settings.authorizationStatus.rawValue)")
      self.pushDebugLog("[Push]   alertSetting: \(settings.alertSetting.rawValue)")
      self.pushDebugLog("[Push]   soundSetting: \(settings.soundSetting.rawValue)")
      self.pushDebugLog("[Push]   badgeSetting: \(settings.badgeSetting.rawValue)")
    }
    
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      self.pushDebugLog("[Push] Permission result - granted: \(granted), error: \(String(describing: error))")
      
      // 无论是否授权都尝试注册远程通知（可以获取 token 用于静默推送）
      DispatchQueue.main.async {
        self.pushDebugLog("[Push] Calling registerForRemoteNotifications()...")
        self.pushDebugLog("[Push] isRegisteredForRemoteNotifications before: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
        UIApplication.shared.registerForRemoteNotifications()
        
        // 延迟检查注册状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          self.pushDebugLog("[Push] isRegisteredForRemoteNotifications after 2s: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
        }
      }
    }

    registerForVoIPPush()
  }

  private func registerForVoIPPush() {
    DispatchQueue.main.async {
      if self.voipRegistry == nil {
        let registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry
      } else {
        self.voipRegistry?.desiredPushTypes = [.voIP]
      }
      self.pushDebugLog("[PushKit] VoIP push registration requested")
    }
  }

  private func replayLatestVoIPToken() {
    let token = latestVoIPToken ??
      UserDefaults.standard.string(forKey: voIPTokenDefaultsKey)
    guard let token, !token.isEmpty else {
      pushDebugLog("[PushKit] No cached VoIP token to replay")
      return
    }
    latestVoIPToken = token
    pushDebugLog("[PushKit] Replaying cached VoIP token, length: \(token.count)")
    pushTokenChannel?.invokeMethod("onVoipToken", arguments: token)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
    pushDebugLog("[PushKit] Got VoIP token, length: \(token.count)")
    latestVoIPToken = token
    UserDefaults.standard.set(token, forKey: voIPTokenDefaultsKey)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
    pushTokenChannel?.invokeMethod("onVoipToken", arguments: token)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    pushDebugLog("[PushKit] VoIP token invalidated")
    latestVoIPToken = nil
    UserDefaults.standard.removeObject(forKey: voIPTokenDefaultsKey)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    pushTokenChannel?.invokeMethod("onVoipTokenInvalidated", arguments: nil)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    handleIncomingVoIPPush(
      payload,
      mustReport: true,
      completion: completion
    )
  }

  @available(iOS 26.4, *)
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingVoIPPushWith payload: PKPushPayload,
    metadata: PKVoIPPushMetadata,
    withCompletionHandler completion: @escaping @Sendable () -> Void
  ) {
    handleIncomingVoIPPush(
      payload,
      mustReport: metadata.mustReport,
      completion: completion
    )
  }

  private func handleIncomingVoIPPush(
    _ payload: PKPushPayload,
    mustReport: Bool,
    completion: @escaping () -> Void
  ) {
    let finishOnce = PushCompletionOnce(completion)
    let userInfo = payload.dictionaryPayload
    let normalized = normalizedPushPayload(userInfo)
    pushDebugLog(
      "[PushKit] Received VoIP push keys=\(normalized.keys.sorted()) mustReport=\(mustReport)"
    )

    if !mustReport {
      pushDebugLog("[PushKit] CallKit report not required by metadata")
      forwardNotificationToFlutter(userInfo, method: "onNotification")
      finishOnce.finish()
      return
    }

    guard let callData = incomingCallKitData(from: userInfo, forceReport: true) else {
      pushDebugLog("[PushKit] Unable to construct fallback CallKit data")
      finishOnce.finish()
      return
    }

    pushDebugLog(
      "[PushKit] Reporting CallKit uuid=\(callData.uuid) pluginReady=\(SwiftFlutterCallkitIncomingPlugin.sharedInstance != nil)"
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      self?.pushDebugLog("[PushKit] Completion timeout guard fired uuid=\(callData.uuid)")
      finishOnce.finish()
    }

    if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      plugin.showCallkitIncoming(callData, fromPushKit: true) { [weak self] in
        self?.pushDebugLog("[PushKit] CallKit plugin callback uuid=\(callData.uuid)")
        self?.forwardNotificationToFlutter(userInfo, method: "onNotification")
        finishOnce.finish()
      }
      return
    }

    pushDebugLog("[PushKit] Plugin unavailable; using native CXProvider fallback")
    nativeCallKitManager.reportIncomingCall(callData) { [weak self] error in
      if let error = error as NSError? {
        self?.pushDebugLog(
          "[PushKit] Native CallKit report failed uuid=\(callData.uuid) domain=\(error.domain) code=\(error.code)"
        )
      } else {
        self?.pushDebugLog("[PushKit] Native CallKit report succeeded uuid=\(callData.uuid)")
      }
      finishOnce.finish()
    }
  }
  
  // 成功获取 APNs token
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    pushDebugLog("[Push] ========== Got APNs token ==========")
    pushDebugLog("[Push] Token length: \(token.count)")
    pushDebugLog("[Push] Token captured for Flutter sync")
    pushDebugLog("[Push] pushTokenChannel is nil: \(pushTokenChannel == nil)")
    
    // 发送 token 到 Flutter
    if let channel = pushTokenChannel {
      pushDebugLog("[Push] Sending token to Flutter via channel...")
      channel.invokeMethod("onToken", arguments: token) { result in
        if let error = result as? FlutterError {
          self.pushDebugLog("[Push] Flutter returned error: \(error.code) - \(error.message ?? "no message")")
        } else if FlutterMethodNotImplemented.isEqual(result) {
          self.pushDebugLog("[Push] Flutter method not implemented!")
        } else {
          self.pushDebugLog("[Push] Flutter callback success: \(String(describing: result))")
        }
      }
    } else {
      pushDebugLog("[Push] ERROR: pushTokenChannel is nil, cannot send token to Flutter!")
      pushDebugLog("[Push] Will retry setting up channel...")
      // 尝试重新设置 channel
      if let controller = window?.rootViewController as? FlutterViewController {
        pushDebugLog("[Push] Got FlutterViewController, recreating channel...")
        pushTokenChannel = FlutterMethodChannel(
          name: "com.genericim/push",
          binaryMessenger: controller.binaryMessenger
        )
        // 重新发送 token
        pushTokenChannel?.invokeMethod("onToken", arguments: token) { result in
          self.pushDebugLog("[Push] Retry Flutter callback result: \(String(describing: result))")
        }
      }
    }
    
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
  
  // 注册失败
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pushDebugLog("[Push] ========== Registration FAILED ==========")
    pushDebugLog("[Push] Error: \(error.localizedDescription)")
    pushDebugLog("[Push] Full error: \(error)")
    
    // 通知 Flutter 注册失败
    pushTokenChannel?.invokeMethod("onRegistrationFailed", arguments: error.localizedDescription)
    
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
  
  // 收到远程通知（后台/前台）
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    pushDebugLog("[Push] Received notification keys: \(stringifyKeyMap(userInfo).keys.sorted())")

    if application.applicationState != .active,
       let callData = incomingCallKitData(from: userInfo, forceReport: false),
       let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      pushDebugLog("[Push] Showing native CallKit incoming call from APNs")
      plugin.showCallkitIncoming(callData, fromPushKit: true) { [weak self] in
        self?.forwardNotificationToFlutter(userInfo, method: "onNotification")
        completionHandler(.newData)
      }
      return
    }

    forwardNotificationToFlutter(userInfo, method: "onNotification")
    completionHandler(.newData)
  }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate {
  // 前台收到通知
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    pushDebugLog("[Push] Will present notification keys: \(stringifyKeyMap(userInfo).keys.sorted())")
    
    // 前台时不显示通知（用户已在应用内可以看到消息）
    // 只发送数据到 Flutter 处理
    forwardNotificationToFlutter(userInfo, method: "onNotification")
    
    // 不显示横幅、声音、角标
    completionHandler([])
  }
  
  // 点击通知
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    pushDebugLog("[Push] Did receive response keys: \(stringifyKeyMap(userInfo).keys.sorted())")
    
    // 发送点击事件到 Flutter
    forwardNotificationToFlutter(userInfo, method: "onNotificationTap")
    
    completionHandler()
  }
}
