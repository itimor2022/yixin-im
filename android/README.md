# Android 平台层

> IM 客户端在 Android 端的原生宿主工程，承载 Flutter 引擎与「壹信」应用在 Android 11+ 设备上的运行，负责权限、通知、后台保活、高刷新率等平台能力。

---

## 1. 模块简介 (Overview)

`android` 在整个 IM 系统中的定位是 **Android 平台宿主**，与项目根目录下的 Flutter 代码（`lib/`、`pubspec.yaml`）共同构成完整的 Android 客户端。主要作用包括：

- **Flutter 引擎承载**：通过 Flutter Gradle 插件将 Flutter 应用打包为 Android APK，提供 Flutter 运行环境。
- **应用入口与配置**：`MainActivity`、`AndroidManifest`、应用 ID（`com.yixinim.app`）、应用名「壹信」、版本与 ABI 配置等。
- **平台能力**：通知渠道（含后台服务通知）、高刷新率与刘海屏适配、前台服务与开机自启（消息保活）、网络与媒体权限等，为 IM 的聊天、音视频通话、推送与后台连接提供支撑。
- **构建与优化**：仅保留 arm64-v8a 与中英文资源以控制包体、Release 混淆与压缩、Java 17 / Kotlin 等工具链配置。

业务与 UI 逻辑在 Flutter 侧（项目根目录）；本目录仅做原生层配置与少量 Kotlin/Java 代码，一般无需在此编写业务代码。

---

## 2. 技术栈 (Tech Stack)

| 类别           | 技术 |
|----------------|------|
| 开发语言       | Kotlin、Java（Flutter 插件生成） |
| 构建系统       | Gradle 8.14（Kotlin DSL） |
| Android 插件   | Android Gradle Plugin 8.9.1 |
| Kotlin         | 2.1.0 |
| 最低/目标 SDK  | minSdk 30（Android 11+）/ targetSdk 36 / compileSdk 36 |
| Java           | 17（sourceCompatibility / targetCompatibility / jvmTarget） |
| Flutter 集成   | Flutter Gradle Plugin，Flutter 源码路径 `../..` |

与 IM 相关的原生侧要点：

- **通知与后台**：`MainActivity` 中创建通知渠道 `gaoranim_background`，供后台保活使用；Manifest 中声明前台服务、开机自启 Receiver（`flutter_background_service`）。
- **权限**：网络、存储/媒体、相机、麦克风、蓝牙、唤醒锁、前台服务、通知等，在 `AndroidManifest.xml` 中声明。
- **混淆**：`proguard-rules.pro` 中保留 Flutter、Agora、Gson、后台服务、通知等与 IM 相关的类。

Flutter 侧 IM 能力（WebSocket、Dio、Isar、音视频等）由根目录 `pubspec.yaml` 管理，本目录不直接依赖这些库的源码。

---

## 3. 环境准备 (Prerequisites)

- **Flutter SDK**：满足项目根目录 `pubspec.yaml` 要求（如 `sdk: '>=3.2.0 <4.0.0'`），且已配置 `flutter doctor` 通过。
- **Android 开发环境**：Android Studio 或命令行工具；**Android SDK** 需包含 compileSdk 36 及 NDK（版本由 Flutter 指定，在 `app/build.gradle.kts` 中通过 `flutter.ndkVersion` 使用）。
- **JDK**：17（与 `build.gradle.kts` 中 `JavaVersion.VERSION_17` 一致）。若使用 `gradle.properties` 指定 `org.gradle.java.home`，请指向 JDK 17。
- **Gradle**：由 wrapper 管理（8.14），无需单独安装。
- **local.properties**：需包含 `flutter.sdk`，通常由 `flutter pub get` 或 IDE 在项目根目录执行 Flutter 命令时自动生成；若 `android` 单独打开，需保证该文件存在且路径正确。

无需单独安装数据库或后端服务；Android 端仅作为客户端运行。

---

## 4. 快速上手 (Getting Started)

### 4.1 建议在项目根目录操作

Android 工程依赖 Flutter 源码（`source = "../.."`），因此**推荐在项目根目录**（即包含 `pubspec.yaml` 和 `android/` 的目录）执行 Flutter 命令：

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

构建 APK 同样建议在根目录：

```bash
flutter build apk
# 或 debug
flutter run
```

### 4.2 仅在 android 目录构建（可选）

若已配置好 `local.properties`（含 `flutter.sdk`），可在 `android` 目录执行：

```bash
cd android
./gradlew assembleDebug
# 或
./gradlew assembleRelease
```

产出在项目根目录下的 `build/app/outputs/`（因 `build.gradle.kts` 中已将 `buildDirectory` 指向 `../../build`）。

### 4.3 环境变量与配置文件

| 文件/配置           | 说明 |
|---------------------|------|
| **local.properties** | 需包含 `flutter.sdk=<Flutter SDK 路径>`，用于 `settings.gradle.kts` 中引入 Flutter Gradle 插件。一般由 Flutter 工具或 IDE 自动生成。 |
| **gradle.properties** | JVM 参数、AndroidX 等；其中 `org.gradle.java.home` 为可选，指向 JDK 17 可避免与系统默认 JDK 冲突。 |
| **app/build.gradle.kts** | `applicationId`、`versionCode`/`versionName`（来自 `flutter` 扩展）、`minSdk`/`targetSdk`、ABI 与资源过滤、签名与混淆等，按需修改。 |

无 `.env` 类环境变量；与后端或功能开关相关的配置在 Flutter 侧（如 `lib/` 下的配置或环境变量方案）。

---

## 5. 核心目录结构 (Directory Structure)

```
android/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── kotlin/com/ranxin/jstx/www/
│   │   │   │   └── MainActivity.kt    # 启动页：通知渠道、高刷、刘海屏
│   │   │   ├── res/                   # 图标、启动图、样式、xml 配置
│   │   │   │   ├── drawable/
│   │   │   │   ├── mipmap-*/
│   │   │   │   ├── values/            # styles.xml
│   │   │   │   ├── values-night/
│   │   │   │   └── xml/               # 网络安全、备份、数据提取规则
│   │   │   └── AndroidManifest.xml   # 权限、Application、Activity、Service、Receiver
│   │   ├── debug/                     # Debug 专用 Manifest（如有）
│   │   └── profile/
│   ├── build.gradle.kts               # 应用级构建与 Flutter 集成
│   └── proguard-rules.pro             # 混淆规则（Flutter、Agora、后台服务等）
├── gradle/
│   └── wrapper/
│       ├── gradle-wrapper.properties  # Gradle 8.14
│       ├── gradlew
│       └── gradlew.bat
├── build.gradle.kts                   # 根项目：仓库、Isar 兼容、统一 build 目录
├── settings.gradle.kts                 # Flutter SDK 路径、插件、include :app
├── gradle.properties
├── local.properties                   # flutter.sdk（通常自动生成）
└── README.md
```

---

## 6. IM 核心业务引导 (Key Concepts)

新同事可从以下位置快速理解 Android 宿主层与 IM 的关联：

| 关注点             | 位置说明 |
|--------------------|----------|
| **应用入口与窗口** | `app/src/main/kotlin/.../MainActivity.kt`：继承 `FlutterActivity`；创建后台服务通知渠道、请求高刷新率与刘海屏布局。 |
| **权限与组件**     | `app/src/main/AndroidManifest.xml`：网络、存储/媒体、相机、麦克风、蓝牙、前台服务、通知、开机自启等权限；`MainActivity`、`BackgroundService`、`BootReceiver` 声明。 |
| **Flutter 集成**   | `app/build.gradle.kts` 中 `id("dev.flutter.flutter-gradle-plugin")` 与 `flutter { source = "../.." }`；版本号由 Flutter 提供。 |
| **后台保活**       | Manifest 中 `flutter_background_service` 的 Service（foregroundServiceType="dataSync"）与 BootReceiver；通知渠道在 `MainActivity.createNotificationChannel()`。 |
| **混淆与加固**     | `app/proguard-rules.pro`：保留 Flutter、Agora、Gson、后台服务、通知等，避免 IM 与音视频相关类被误删。 |
| **包名与资源**     | `applicationId` / `namespace`：`com.yixinim.app`；应用名「壹信」在 Manifest 的 `android:label`。 |
| **实际 IM 逻辑**   | 消息、连接、存储、UI 等均在项目根目录的 Flutter 代码（`lib/`）及 `pubspec.yaml` 依赖中，本目录仅提供 Android 运行环境与平台能力。 |

---

## 7. 打包与发布 (Build & Deploy)

### 7.1 推荐方式（项目根目录）

```bash
# Debug APK（开发与联调）
flutter run
# 或仅构建
flutter build apk --debug

# Release APK（发布）
flutter build apk
# 或 AAB（上架 Google Play）
flutter build appbundle
```

Release 会使用 `app/build.gradle.kts` 中 `release` 的配置：混淆、资源压缩、`proguard-rules.pro`；签名当前与 debug 共用，正式发布需在 `build.gradle.kts` 中配置 `signingConfigs` 并引用。

### 7.2 仅在 android 目录

```bash
cd android
./gradlew assembleRelease
# 或
./gradlew bundleRelease
```

产出路径受根项目 `build.gradle.kts` 影响，一般在项目根下的 `build/` 目录中。

### 7.3 注意事项

- **minSdk 30**：仅支持 Android 11+；若需支持更低版本，需修改 `app/build.gradle.kts` 的 `minSdk` 并验证兼容性。
- **ABI**：当前仅保留 `arm64-v8a`，若需 x86_64（模拟器等），在 `defaultConfig.ndk.abiFilters` 中增加。
- **签名**：Release 建议配置正式 keystore，避免长期使用 `signingConfigs.getByName("debug")`。

---

## 附录：常用命令速查

| 场景           | 建议在项目根目录执行 |
|----------------|----------------------|
| 安装依赖       | `flutter pub get`    |
| 运行 Debug     | `flutter run`        |
| 构建 Debug APK | `flutter build apk --debug` |
| 构建 Release APK | `flutter build apk` |
| 构建 AAB       | `flutter build appbundle` |
| 清理           | `flutter clean` 或 `cd android && ./gradlew clean` |

---

如有问题，可优先查阅本 README、项目根目录的 Flutter 文档与 `pubspec.yaml`，以及 `app/build.gradle.kts`、`AndroidManifest.xml` 中的注释。
