# Android 原厂推送接入说明（华为 / 小米 / OPPO）

## 当前实现状态
- 客户端已接入 `MethodChannel`：`com.gaoranim/push_vendor`
- 品牌识别 + 通道路由：
  - 华为/荣耀 -> `hms`
  - 小米/红米 -> `xiaomi`
  - OPPO/OnePlus/realme -> `oppo`
  - 其他 -> `fcm`
- token 拉取能力：
  - HMS：已支持（反射调用，SDK 存在时生效）
  - 小米：已支持（反射调用，SDK 存在时生效）
  - OPPO：已支持（反射调用 + 回调代理 + 轮询兜底）

## 后端推送状态
- 已支持按 `push_channel` 路由发送：`apns / fcm / hms / xiaomi / oppo`
- OPPO 后端已补齐：鉴权、单推、auth token 缓存与失效重试

## FCM 基线配置（Android）
- 已接入 Google Services 插件：
  - [settings.gradle.kts](/e:/yi-xin-ai2k/android/settings.gradle.kts)
  - [build.gradle.kts](/e:/yi-xin-ai2k/android/app/build.gradle.kts)
- 已声明 FCM 默认通知渠道：
  - `gaoranim_messages`（高优先级，支持角标和震动）
- `google-services.json` 放置位置：
  - `android/app/google-services.json`
- 当前 Android 包名：
  - `com.yixinim.app`
- 后端/管理端已增加 FCM 配置校验：
  - `fcm_project_id` 不能为空
  - 禁止将 `mobilesdk_app_id`（形如 `1:xxx:android:xxx`）误填到 `fcm_project_id`
  - `fcm_project_id` 必须与 Service Account JSON 内的 `project_id` 一致

## Android 配置（gradle.properties）
编辑 [android/gradle.properties](/e:/yi-xin-ai2k/android/gradle.properties)：

```properties
# 主开关：false 时不引入原厂 SDK 依赖，保持当前稳定编译
ENABLE_VENDOR_PUSH_SDK=false

# 业务参数（Manifest 占位）
PUSH_HMS_APP_ID=你的华为AppID
PUSH_XIAOMI_APP_ID=你的小米AppID
PUSH_XIAOMI_APP_KEY=你的小米AppKey
PUSH_OPPO_APP_KEY=你的OPPO AppKey
PUSH_OPPO_APP_SECRET=你的OPPO AppSecret

# SDK 坐标（仅在 ENABLE_VENDOR_PUSH_SDK=true 时生效）
HMS_PUSH_SDK=com.huawei.hms:push:<version>
XIAOMI_PUSH_SDK=com.xiaomi.mipush:mipush-sdk:<version>
OPPO_PUSH_SDK=com.heytap.msp:push:<version>

# 可选：小米 SDK 如需私有/定制仓库，可配置
XIAOMI_PUSH_MAVEN_REPO=https://your-maven-host/repository/maven-public/

# 可选：OPPO SDK 如默认 heytap 仓库不可达，可配置
OPPO_PUSH_MAVEN_REPO=https://your-maven-host/repository/maven-public/
```

也可直接参考模板：
- [gradle.vendor.sample.properties](/e:/yi-xin-ai2k/android/gradle.vendor.sample.properties)

如果不希望把密钥写进 `gradle.properties`，可在本地新建：
- `android/gradle.vendor.local.properties`（已加入 `.gitignore`）
- 内容可直接从 `gradle.vendor.sample.properties` 复制后填写

## 构建校验（已启用）
- 当 `ENABLE_VENDOR_PUSH_SDK=true` 时，构建会对以下项做**强校验**，任一为空将直接失败：
  - `HMS_PUSH_SDK`
  - `XIAOMI_PUSH_SDK`
  - `OPPO_PUSH_SDK`
  - `PUSH_HMS_APP_ID`
  - `PUSH_XIAOMI_APP_ID`
  - `PUSH_XIAOMI_APP_KEY`
  - `PUSH_OPPO_APP_KEY`
  - `PUSH_OPPO_APP_SECRET`
- 目的：避免“开了正式 SDK 模式但参数缺失，应用运行后才暴露问题”。
- 上述参数支持三种来源（优先级从高到低）：
  - `-P` / `gradle.properties` 中的同名属性
  - 同名环境变量（如 `HMS_PUSH_SDK`、`PUSH_HMS_APP_ID`）
  - `android/gradle.vendor.local.properties` 中的同名属性
- `ENABLE_VENDOR_PUSH_SDK` 也支持通过 `-P`、环境变量、`gradle.vendor.local.properties` 控制；若都未设置，默认视为 `false`。
- `XIAOMI_PUSH_MAVEN_REPO`、`OPPO_PUSH_MAVEN_REPO` 也支持同样的三种来源与优先级。

PowerShell 示例（使用环境变量，不改仓库文件）：

```powershell
$env:ENABLE_VENDOR_PUSH_SDK="true"
$env:HMS_PUSH_SDK="com.huawei.hms:push:6.12.0.300"
$env:XIAOMI_PUSH_SDK="com.xiaomi.mipush:mipush-sdk:5.0.8"
$env:OPPO_PUSH_SDK="com.heytap.msp:push:3.4.0"
$env:PUSH_HMS_APP_ID="your_hms_app_id"
$env:PUSH_XIAOMI_APP_ID="your_xiaomi_app_id"
$env:PUSH_XIAOMI_APP_KEY="your_xiaomi_app_key"
$env:PUSH_OPPO_APP_KEY="your_oppo_app_key"
$env:PUSH_OPPO_APP_SECRET="your_oppo_app_secret"
cd android
.\gradlew.bat app:compileDebugKotlin
```

## 一键预检（推荐）
可直接运行预检脚本，查看参数是否齐全、参数来自哪里，并可选附带编译探测：

```powershell
cd e:\yi-xin-ai2k
.\scripts\android_vendor_push_preflight.ps1
.\scripts\android_vendor_push_preflight.ps1 -Compile
```

预检脚本会额外输出 FCM 基线信息（`applicationId`、`google-services.json` 是否存在、`project_id`、`mobilesdk_app_id`、`package_name`），用于快速排查包名不匹配与 Firebase 配置错误。

若你想在 `ENABLE_VENDOR_PUSH_SDK=false` 的情况下，提前按“生产开启状态”检查一次，可用：

```powershell
.\scripts\android_vendor_push_preflight.ps1 -ForceVendorEnabled
```

## 仓库配置
项目已预置：
- Huawei: `https://developer.huawei.com/repo/`
- OPPO/Heytap: 默认 `https://maven.heytapmcs.com/repository/maven-public/`，可用 `OPPO_PUSH_MAVEN_REPO` 覆盖
- Xiaomi: 默认走 `google()/mavenCentral()`，特殊场景可配 `XIAOMI_PUSH_MAVEN_REPO`
- `XIAOMI_PUSH_MAVEN_REPO` 读取优先级：`-P/gradle.properties` > 同名环境变量 > `android/gradle.vendor.local.properties`
- `OPPO_PUSH_MAVEN_REPO` 读取优先级：`-P/gradle.properties` > 同名环境变量 > `android/gradle.vendor.local.properties`
- 各厂商仓库已按 group 做精确匹配，避免依赖解析时误请求到不相关仓库。

对应文件：
- [build.gradle.kts](/e:/yi-xin-ai2k/android/build.gradle.kts)

## 混淆配置
已补充 HMS / 小米 / OPPO keep 规则，见：
- [proguard-rules.pro](/e:/yi-xin-ai2k/android/app/proguard-rules.pro)

## 关键说明
- 当前代码采用“反射 + 可开关依赖”模式：
  - 不开启 SDK 依赖时，APK 可正常编译并自动降级 FCM
  - 开启后可切到正式 SDK 运行链路
- Android 设备的桌面角标已接入，但是否显示数字取决于系统与启动器（Launcher）能力：
  - 支持角标的系统/桌面会显示
  - 不支持角标的设备会自动忽略（代码已做兼容，不影响消息通知本身）
- 如果你要上生产，建议开启 `ENABLE_VENDOR_PUSH_SDK=true`，并填好三家 SDK 坐标与密钥参数。
- 后端系统设置保存时已增加推送参数校验：
  - 启用某通道但缺少必填字段会直接返回错误，不会写入无效配置。
