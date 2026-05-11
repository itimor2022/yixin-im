import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pushTokenChannel: FlutterMethodChannel?
  private var hotUpdateChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("[Push] ========== App launching ==========")
    
    GeneratedPluginRegistrant.register(with: self)
    
    // 设置 Flutter Method Channel
    print("[Push] Setting up Method Channel...")
    print("[Push] window is nil: \(window == nil)")
    print("[Push] rootViewController type: \(String(describing: window?.rootViewController))")
    
    if let controller = window?.rootViewController as? FlutterViewController {
      print("[Push] Got FlutterViewController, creating channel...")
      pushTokenChannel = FlutterMethodChannel(
        name: "com.gaoranim/push",
        binaryMessenger: controller.binaryMessenger
      )
      hotUpdateChannel = FlutterMethodChannel(
        name: "com.gaoranim/hot_update",
        binaryMessenger: controller.binaryMessenger
      )
      
      pushTokenChannel?.setMethodCallHandler { [weak self] call, result in
        print("[Push] Received method call: \(call.method)")
        if call.method == "registerForPush" {
          self?.registerForPushNotifications()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      hotUpdateChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleHotUpdateMethod(call: call, result: result)
      }
      print("[Push] Method Channel setup complete")
    } else {
      print("[Push] ERROR: Could not get FlutterViewController!")
    }
    
    // 设置通知代理
    UNUserNotificationCenter.current().delegate = self
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleHotUpdateMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result([
        "available": true,
        "sdkIntegrated": true,
        "platform": "ios",
        "message": "self_hosted_updater_ready",
      ])
    case "applyPatch":
      applyIOSPatch(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyIOSPatch(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result([
        "success": false,
        "requires_restart": false,
        "message": "patch_params_invalid",
      ])
      return
    }

    let rawPatchURL = (args["patch_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !rawPatchURL.isEmpty else {
      result([
        "success": false,
        "requires_restart": false,
        "message": "patch_url_missing",
      ])
      return
    }

    guard let installURL = buildIOSInstallURL(from: rawPatchURL) else {
      result([
        "success": false,
        "requires_restart": false,
        "message": "ios_install_url_invalid",
      ])
      return
    }

    DispatchQueue.main.async {
      UIApplication.shared.open(installURL, options: [:]) { success in
        result([
          "success": success,
          "requires_restart": success,
          "message": success ? "ios_install_started" : "ios_install_open_failed",
        ])
      }
    }
  }

  private func buildIOSInstallURL(from rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.lowercased().hasPrefix("itms-services://") {
      return URL(string: trimmed)
    }

    guard let sourceURL = URL(string: trimmed) else {
      return nil
    }

    if sourceURL.scheme == "http" || sourceURL.scheme == "https" {
      guard sourceURL.path.lowercased().hasSuffix(".plist") else {
        return nil
      }
      let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
      return URL(string: "itms-services://?action=download-manifest&url=\(encoded)")
    }

    return nil
  }
  
  // 注册推送通知
  private func registerForPushNotifications() {
    print("[Push] ========== Starting push registration ==========")
    print("[Push] pushTokenChannel is nil: \(pushTokenChannel == nil)")
    print("[Push] isRegisteredForRemoteNotifications: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
    
    // 检查当前通知设置
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      print("[Push] Current notification settings:")
      print("[Push]   authorizationStatus: \(settings.authorizationStatus.rawValue)")
      print("[Push]   alertSetting: \(settings.alertSetting.rawValue)")
      print("[Push]   soundSetting: \(settings.soundSetting.rawValue)")
      print("[Push]   badgeSetting: \(settings.badgeSetting.rawValue)")
    }
    
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      print("[Push] Permission result - granted: \(granted), error: \(String(describing: error))")
      
      // 无论是否授权都尝试注册远程通知（可以获取 token 用于静默推送）
      DispatchQueue.main.async {
        print("[Push] Calling registerForRemoteNotifications()...")
        print("[Push] isRegisteredForRemoteNotifications before: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
        UIApplication.shared.registerForRemoteNotifications()
        
        // 延迟检查注册状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          print("[Push] isRegisteredForRemoteNotifications after 2s: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
        }
      }
    }
  }
  
  // 成功获取 APNs token
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("[Push] ========== Got APNs token ==========")
    print("[Push] Token length: \(token.count)")
    print("[Push] Token prefix: \(String(token.prefix(20)))...")
    print("[Push] pushTokenChannel is nil: \(pushTokenChannel == nil)")
    
    // 发送 token 到 Flutter
    if let channel = pushTokenChannel {
      print("[Push] Sending token to Flutter via channel...")
      channel.invokeMethod("onToken", arguments: token) { result in
        if let error = result as? FlutterError {
          print("[Push] Flutter returned error: \(error.code) - \(error.message ?? "no message")")
        } else if FlutterMethodNotImplemented.isEqual(result) {
          print("[Push] Flutter method not implemented!")
        } else {
          print("[Push] Flutter callback success: \(String(describing: result))")
        }
      }
    } else {
      print("[Push] ERROR: pushTokenChannel is nil, cannot send token to Flutter!")
      print("[Push] Will retry setting up channel...")
      // 尝试重新设置 channel
      if let controller = window?.rootViewController as? FlutterViewController {
        print("[Push] Got FlutterViewController, recreating channel...")
        pushTokenChannel = FlutterMethodChannel(
          name: "com.gaoranim/push",
          binaryMessenger: controller.binaryMessenger
        )
        // 重新发送 token
        pushTokenChannel?.invokeMethod("onToken", arguments: token) { result in
          print("[Push] Retry Flutter callback result: \(String(describing: result))")
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
    print("[Push] ========== Registration FAILED ==========")
    print("[Push] Error: \(error.localizedDescription)")
    print("[Push] Full error: \(error)")
    
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
    print("[Push] Received notification: \(userInfo)")
    
    // 发送通知数据到 Flutter
    if let data = try? JSONSerialization.data(withJSONObject: userInfo),
       let jsonString = String(data: data, encoding: .utf8) {
      pushTokenChannel?.invokeMethod("onNotification", arguments: jsonString)
    }
    
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
    print("[Push] Will present notification (foreground): \(userInfo)")
    
    // 前台时不显示通知（用户已在应用内可以看到消息）
    // 只发送数据到 Flutter 处理
    if let data = try? JSONSerialization.data(withJSONObject: userInfo),
       let jsonString = String(data: data, encoding: .utf8) {
      pushTokenChannel?.invokeMethod("onNotification", arguments: jsonString)
    }
    
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
    print("[Push] Did receive response: \(userInfo)")
    
    // 发送点击事件到 Flutter
    if let data = try? JSONSerialization.data(withJSONObject: userInfo),
       let jsonString = String(data: data, encoding: .utf8) {
      pushTokenChannel?.invokeMethod("onNotificationTap", arguments: jsonString)
    }
    
    completionHandler()
  }
}
