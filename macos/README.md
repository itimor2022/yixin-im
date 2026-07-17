# macOS 平台层

> IM 客户端在 macOS 端的原生宿主工程，承载 Flutter 引擎与「锦绣汇」应用在 Apple 电脑上的运行，提供窗口、沙盒与系统能力（网络、相机、麦克风、钥匙串等）。

---

## 1. 模块简介 (Overview)

`macOS` 在整个 IM 系统中的定位是 **macOS 平台宿主**，与项目根目录下的 Flutter 代码（`lib/`、`pubspec.yaml`）共同构成完整的 macOS 桌面客户端。主要作用包括：

- **Flutter 引擎承载**：通过 Xcode 工程将 Flutter 应用构建为 macOS App（.app bundle），提供 Flutter 运行环境。
- **应用入口与配置**：`AppDelegate.swift`、`MainFlutterWindow.swift`、`Info.plist`、Bundle ID（`com.yixinim.app`）、应用名「锦绣汇」、最低系统版本（macOS 11.0）等。
- **沙盒与权限**：entitlements 中配置 App Sandbox、网络客户端/服务端、相机与麦克风、JIT、钥匙串访问组（如 com.gaoran.gaoRanIm），满足上架与 IM 联网、音视频需求。
- **窗口**：MainFlutterWindow 将 FlutterViewController 设为 contentViewController，并注册插件。

业务与 UI 逻辑在 Flutter 侧（项目根目录）；本目录负责原生层配置与窗口/沙盒，日常开发以 Flutter 为主，按需修改 entitlements 或 Info.plist。

---

## 2. 技术栈 (Tech Stack)

| 类别           | 技术 |
|----------------|------|
| 开发语言       | Swift |
| 构建/工程      | Xcode |
| 最低系统版本   | macOS 11.0（MACOSX_DEPLOYMENT_TARGET） |
| Flutter 集成   | FlutterMacOS 框架、RegisterGeneratedPlugins |

与 IM 相关的原生侧要点：

- **沙盒与能力**：`Runner/DebugProfile.entitlements`、`Runner/Release.entitlements` 中开启 App Sandbox、网络客户端/服务端、相机、麦克风、JIT（Debug 需要）；keychain-access-groups 用于安全存储（如 Flutter 侧 flutter_secure_storage）。
- **窗口**：`Runner/MainFlutterWindow.swift` 使用 FlutterViewController 并注册插件；`AppDelegate` 配置关闭最后窗口时退出、支持可恢复状态。
- **应用标识**：`Runner/Configs/AppInfo.xcconfig` 中 PRODUCT_BUNDLE_IDENTIFIER = com.yixinim.app；Info.plist 中 CFBundleName/CFBundleDisplayName「锦绣汇」。

Flutter 侧 IM 能力（WebSocket、Dio、Isar、窗口/托盘等）由根目录 `pubspec.yaml` 管理；本目录不直接依赖这些库的源码。

---

## 3. 环境准备 (Prerequisites)

- **Flutter SDK**：满足项目根目录 `pubspec.yaml` 要求（如 `sdk: '>=3.2.0 <4.0.0'`），且已配置 `flutter doctor` 通过；macOS 桌面支持已启用。
- **macOS**：开发与运行均在 Mac 上进行。
- **Xcode**：最新稳定版，并安装 macOS SDK；Command Line Tools 已选好对应 Xcode。
- **Apple 开发者账号**：本地开发可用个人 Team；上架 Mac App Store 需付费开发者账号并配置签名与公证。

无需单独数据库或后端服务；macOS 端仅作为客户端运行。

---

## 4. 快速上手 (Getting Started)

### 4.1 建议在项目根目录操作

macOS 工程依赖 Flutter 源码与生成文件，因此**推荐在项目根目录**执行 Flutter 命令：

```bash
# 在项目根目录
flutter pub get
flutter run -d macos
```

或指定设备：

```bash
flutter devices
flutter run -d macos
```

### 4.2 使用 Xcode 打开（可选）

在项目根目录执行 `flutter pub get` 后，用 Xcode 打开 macOS 工程：

```bash
open macos/Runner.xcworkspace
# 或
open macos/Runner.xcodeproj
```

在 Xcode 中选择 My Mac 目标，配置 Signing，运行或归档。

### 4.3 环境变量与配置文件

| 文件/配置           | 说明 |
|---------------------|------|
| **Runner/Info.plist** | 应用名「锦绣汇」、版本（FLUTTER_BUILD_NAME/NUMBER）、LSMinimumSystemVersion（MACOSX_DEPLOYMENT_TARGET）。 |
| **Runner/Configs/AppInfo.xcconfig** | PRODUCT_BUNDLE_IDENTIFIER = com.yixinim.app。 |
| **Runner/DebugProfile.entitlements** | 开发/Profile：沙盒、网络、相机、麦克风、JIT、钥匙串。 |
| **Runner/Release.entitlements** | 发布：沙盒、网络、相机、麦克风、钥匙串（无 JIT）。 |
| **Signing**         | 在 Xcode 中为 Runner target 配置 Team 与 Signing Certificate。 |

无 `.env` 类环境变量；与后端或功能开关相关的配置在 Flutter 侧。

---

## 5. 核心目录结构 (Directory Structure)

```
macos/
├── Runner/
│   ├── AppDelegate.swift       # 入口：最后一窗口关闭时退出、可恢复状态
│   ├── MainFlutterWindow.swift # Flutter 窗口、FlutterViewController、插件注册
│   ├── Info.plist              # 应用名、版本、最低系统版本
│   ├── Configs/
│   │   └── AppInfo.xcconfig    # PRODUCT_BUNDLE_IDENTIFIER
│   ├── DebugProfile.entitlements
│   ├── Release.entitlements
│   ├── MainMenu.xib
│   └── Assets.xcassets/
├── RunnerTests/
│   └── RunnerTests.swift
├── Flutter/
│   └── GeneratedPluginRegistrant.swift   # Flutter 生成，勿手改
├── Runner.xcodeproj/
└── README.md
```

---

## 6. IM 核心业务引导 (Key Concepts)

| 关注点             | 位置说明 |
|--------------------|----------|
| **应用入口与窗口** | `Runner/AppDelegate.swift`：应用生命周期；`Runner/MainFlutterWindow.swift`：FlutterViewController、RegisterGeneratedPlugins。 |
| **沙盒与权限**     | `Runner/DebugProfile.entitlements`、`Runner/Release.entitlements`：网络、相机、麦克风、钥匙串；Debug 含 JIT。 |
| **Bundle ID / 应用名** | `Runner/Configs/AppInfo.xcconfig` 中 PRODUCT_BUNDLE_IDENTIFIER；Info.plist 中 CFBundleName/CFBundleDisplayName「锦绣汇」。 |
| **Flutter 集成**   | `Flutter/GeneratedPluginRegistrant.swift` 由 Flutter 生成；MainFlutterWindow 中调用 RegisterGeneratedPlugins。 |
| **实际 IM 逻辑**   | 消息、连接、存储、UI、窗口管理/托盘等均在项目根目录的 Flutter 代码（`lib/`）及 `pubspec.yaml` 依赖中；本目录仅提供 macOS 运行环境与沙盒能力。 |

---

## 7. 打包与发布 (Build & Deploy)

### 7.1 推荐方式（项目根目录）

```bash
# Debug
flutter run -d macos

# Release 构建
flutter build macos
```

构建完成后可在 `build/macos/Build/Products/Release/` 下找到「锦绣汇.app」，可直接运行或拖入「应用程序」。上架 Mac App Store 或对外分发需在 Xcode 中 Product → Archive，再 Distribute App，并完成公证（Notarization）与签名。

### 7.2 注意事项

- **最低版本**：当前 macOS 11.0；若需支持更老系统，需修改 Runner.xcodeproj 中 MACOSX_DEPLOYMENT_TARGET，并验证各插件兼容性。
- **公证**：非 App Store 分发时，Apple 要求对 app 进行公证，否则在较新 macOS 上可能被拦截；需使用 Apple Developer 账号与 notarytool/altool。
- **签名**：在 Xcode 中为 Runner 配置好 Team 与 Signing；发布前确认 Release.entitlements 与 App Store 或对外分发策略一致。

---

## 附录：常用命令速查

| 场景           | 建议执行 |
|----------------|----------|
| 安装 Flutter 依赖 | 项目根目录：`flutter pub get` |
| 运行           | 项目根目录：`flutter run -d macos` |
| 构建 Release   | `flutter build macos` |
| 清理           | `flutter clean` |

---

如有问题，可优先查阅本 README、项目根目录的 Flutter 文档与 `pubspec.yaml`，以及 `Runner/AppDelegate.swift`、`Runner/MainFlutterWindow.swift`、entitlements 与 Info.plist。
