# iOS 平台层

> IM 客户端在 iOS 端的原生宿主工程，承载 Flutter 引擎与「通用IM」应用在 iPhone / iPad 上的运行，负责推送、权限、后台模式、CallKit/Intent 等平台能力。

---

## 1. 模块简介 (Overview)

`ios` 在整个 IM 系统中的定位是 **iOS 平台宿主**，与项目根目录下的 Flutter 代码（`lib/`、`pubspec.yaml`）共同构成完整的 iOS 客户端。主要作用包括：

- **Flutter 引擎承载**：通过 Xcode 工程与 CocoaPods 将 Flutter 应用打包为 iOS/iPadOS 应用，提供 Flutter 运行环境。
- **应用入口与配置**：`AppDelegate`、`Runner/Info.plist`、Bundle ID（`com.genericim.app`）、应用名「通用IM」、版本与权限文案等。
- **推送与通知**：APNs 注册、Device Token 通过 Method Channel（`com.genericim/push`）回传 Flutter；前台/后台远程通知、点击通知回调 Flutter。
- **权限与能力**：相册/相机/麦克风/蓝牙、后台模式（audio、voip、fetch、remote-notification）、Intent（发消息、音视频通话）等，为 IM 聊天与音视频通话提供支撑。
- **依赖管理**：CocoaPods 集成 Flutter 插件及原生库（如 Agora、权限等）。

业务与 UI 逻辑在 Flutter 侧（项目根目录）；本目录负责原生层配置与推送/通知桥接，日常开发以 Flutter 为主，按需修改原生配置或扩展 Method Channel。

---

## 2. 技术栈 (Tech Stack)

| 类别           | 技术 |
|----------------|------|
| 开发语言       | Swift、Objective-C（Flutter 插件生成） |
| 构建/工程      | Xcode、CocoaPods |
| 最低部署版本   | iOS 15.0（Podfile 与 IPHONEOS_DEPLOYMENT_TARGET） |
| Flutter 集成   | Flutter 插件通过 `flutter_install_all_ios_pods` 安装 |

与 IM 相关的原生侧要点：

- **推送**：`Runner/AppDelegate.swift` 中注册 Method Channel `com.genericim/push`，处理 `registerForPush`、回传 `onToken`/`onNotification`/`onNotificationTap`/`onRegistrationFailed`；APNs 注册与 UNUserNotificationCenter 代理。
- **权限**：Podfile `post_install` 中为 permission_handler 启用 PERMISSION_MICROPHONE、PERMISSION_CAMERA、PERMISSION_PHOTOS、PERMISSION_NOTIFICATIONS；Info.plist 中相册/相机/麦克风/蓝牙/本地网络等使用说明。
- **后台与 Intent**：Info.plist 中 UIBackgroundModes（audio、voip、fetch、remote-notification）、NSUserActivityTypes（INSendMessageIntent、INStartCallIntent 等），配合 CallKit/来电与消息意图。
- **网络与安全**：NSAppTransportSecurity 允许 HTTP/本地网络，便于开发与内网部署。

Flutter 侧 IM 能力（WebSocket、Dio、Isar、音视频等）由根目录 `pubspec.yaml` 管理；CocoaPods 负责对应 iOS 原生依赖。

---

## 3. 环境准备 (Prerequisites)

- **Flutter SDK**：满足项目根目录 `pubspec.yaml` 要求（如 `sdk: '>=3.2.0 <4.0.0'`），且已配置 `flutter doctor` 通过。
- **macOS**：iOS 开发需在 Mac 上完成。
- **Xcode**：最新稳定版，并安装 iOS 模拟器或连接真机；Command Line Tools 已选好对应 Xcode。
- **CocoaPods**：`gem install cocoapods` 或通过 Homebrew 安装，用于 `pod install`。
- **Apple 开发者账号**：真机运行与推送需配置 Signing & Capabilities（如 Push Notifications）；上架需付费开发者账号。

无需单独数据库或后端服务；iOS 端仅作为客户端运行。

---

## 4. 快速上手 (Getting Started)

### 4.1 建议在项目根目录操作

iOS 工程依赖 Flutter 源码与 Generated.xcconfig，因此**推荐在项目根目录**执行 Flutter 命令：

```bash
# 在项目根目录
flutter pub get
flutter run
```

或指定设备：

```bash
flutter devices
flutter run -d <device_id>
```

首次或依赖变更后需在 `ios` 目录安装 Pods：

```bash
cd ios
pod install
cd ..
flutter run
```

### 4.2 使用 Xcode 打开（可选）

在项目根目录执行 `flutter pub get` 后，用 Xcode 打开 `ios/Runner.xcworkspace`（不要打开 `.xcodeproj`，否则 Pods 未加载）：

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中选择目标设备、配置 Signing、运行或归档。

### 4.3 环境变量与配置文件

| 文件/配置           | 说明 |
|---------------------|------|
| **ios/Flutter/Generated.xcconfig** | 由 Flutter 生成，包含 FLUTTER_ROOT、FLUTTER_BUILD_NAME/NUMBER 等；勿手改，执行 `flutter pub get` 或 `flutter run` 会更新。 |
| **ios/Podfile**     | platform :ios, '15.0'；post_install 中统一 IPHONEOS_DEPLOYMENT_TARGET 与 permission_handler 宏。 |
| **ios/Runner/Info.plist** | 应用名、权限说明、UIBackgroundModes、NSUserActivityTypes、NSAppTransportSecurity 等。 |
| **Signing**         | 在 Xcode 中为 Runner target 配置 Team、Bundle Identifier（如 com.genericim.app）、Provisioning Profile；推送需勾选 Push Notifications capability。 |

无 `.env` 类环境变量；与后端或功能开关相关的配置在 Flutter 侧。

---

## 5. 核心目录结构 (Directory Structure)

```
ios/
├── Runner/
│   ├── AppDelegate.swift      # 入口、Method Channel、APNs 注册与通知回调
│   ├── Info.plist             # 应用名、权限文案、后台模式、Intent、ATS
│   ├── Runner-Bridging-Header.h
│   ├── Assets.xcassets/
│   ├── Base.lproj/             # LaunchScreen、Main.storyboard
│   └── ...
├── Runner.xcodeproj/
├── Runner.xcworkspace/         # 使用 Xcode 时打开此 workspace
├── Flutter/
│   ├── Generated.xcconfig     # Flutter 生成，勿手改
│   └── AppFrameworkInfo.plist
├── Podfile                     # CocoaPods 配置、iOS 15、权限宏
├── Podfile.lock
├── Pods/                       # 依赖（pod install 后生成）
└── README.md
```

---

## 6. IM 核心业务引导 (Key Concepts)

| 关注点             | 位置说明 |
|--------------------|----------|
| **应用入口与推送** | `Runner/AppDelegate.swift`：Flutter 注册、Method Channel `com.genericim/push`、APNs 注册、token/通知/点击回传 Flutter。 |
| **权限与后台**     | `Runner/Info.plist`：相册/相机/麦克风/蓝牙/本地网络等 NS*UsageDescription；UIBackgroundModes（audio、voip、fetch、remote-notification）；NSUserActivityTypes（消息与通话 Intent）。 |
| **CocoaPods**      | `Podfile`：iOS 15、post_install 中权限宏与部署目标；`pod install` 后 Pods 集成 Flutter 插件与 Agora 等。 |
| **Flutter 集成**   | `Flutter/Generated.xcconfig` 由 Flutter 写入；Xcode 使用 Runner.xcworkspace 加载 Runner + Pods。 |
| **Bundle ID / 应用名** | Xcode 中 PRODUCT_BUNDLE_IDENTIFIER（如 com.genericim.app）；Info.plist 中 CFBundleName/CFBundleDisplayName「通用IM」。 |
| **实际 IM 逻辑**   | 消息、连接、存储、UI 等均在项目根目录的 Flutter 代码（`lib/`）及 `pubspec.yaml` 依赖中；本目录仅提供 iOS 运行环境与推送/权限等平台能力。 |

---

## 7. 打包与发布 (Build & Deploy)

### 7.1 推荐方式（项目根目录）

```bash
# Debug（模拟器/真机）
flutter run

# Release 构建（真机）
flutter build ios

# 归档与上架需在 Xcode 中：Product → Archive，再 Distribute App。
```

构建完成后用 Xcode 打开 `ios/Runner.xcworkspace`，选择 Any iOS Device (arm64)，Product → Archive，按向导上传或导出。

### 7.2 注意事项

- **推送**：确保在 Apple 开发者后台配置 App ID 的 Push Notifications，并上传证书或使用 Key；Xcode 中为 Runner 启用 Push Notifications capability。
- **最低版本**：当前 iOS 15.0；若需支持更低版本，需改 Podfile 的 `platform :ios` 与 post_install 中的 `IPHONEOS_DEPLOYMENT_TARGET`，并验证各插件兼容性。
- **签名**：真机与上架前在 Xcode 中配置好 Team、Provisioning Profile 与 Capabilities。

---

## 附录：常用命令速查

| 场景           | 建议执行 |
|----------------|----------|
| 安装 Flutter 依赖 | 项目根目录：`flutter pub get` |
| 安装 Pods      | `cd ios && pod install` |
| 运行           | 项目根目录：`flutter run` |
| 构建 Release   | `flutter build ios` |
| 清理           | `flutter clean`；必要时 `cd ios && pod deintegrate && pod install` |

---

如有问题，可优先查阅本 README、项目根目录的 Flutter 文档与 `pubspec.yaml`，以及 `Runner/AppDelegate.swift`、`Runner/Info.plist`、`Podfile` 中的注释。
