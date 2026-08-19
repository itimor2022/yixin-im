# Shorebird iOS 发布与补丁 SOP

## 适用范围

App Store 正式包必须由 `shorebird release ios` 生成。只有安装过该基线版本的用户，才能接收此版本对应的 Dart 补丁。Swift、Pod、权限、签名、Flutter SDK、原生插件或打包资源变化必须发布新的 App Store 基线。

## 发布前准备

1. 在 App Store Connect 查询目标版本已使用的最高 Build Number，新构建号必须更大。
2. 确认 Bundle ID 为 `com.genericim.ma100`，Team ID 为 `U4TWR5VCQ3`。
3. 在后台填写 `app_update_url_ios`，仅接受 Apple 官方 App Store HTTPS 链接。
4. 确认 `latest_version_ios`（当前字段 `app_version_ios`）和 `min_supported_version_ios` 的运营含义不同：前者触发可关闭提示，后者才触发强制更新。
5. 本机执行 `shorebird login`、`shorebird doctor`，并确认 Xcode、CocoaPods、证书和 Provisioning Profile 有效。
6. 将 `pubspec.yaml` 版本改成本次完整版本，例如 `5.0.0+41`，并提交 `ios/`、`lib/`、`assets/`、`pubspec 和 `shorebird.yaml` 的所有变更。脚本默认拒绝从未提交的应用源码发布。

## 创建 App Store 基线

先打印命令并核对所有线上入口：

```bash
scripts/shorebird-release-ios.sh \
  --server-url https://api.example.com \
  --bootstrap-url https://api.example.com/api/v1/client/bootstrap \
  --build-name 5.0.0 \
  --build-number 41 \
  --print-only
```

确认后去掉 `--print-only`。脚本会执行环境检查、`shorebird doctor`、Release 构建，并校验 IPA/Archive 的版本、构建号、签名和 SHA256。校验成功后脚本自动在当前提交创建带注释的 `shorebird-ios-5.0.0+41` 基线标签。上传到 TestFlight/App Store Connect 的必须是这次 Shorebird Release 产生的同一份产物。

不要让 Xcode 或 App Store 上传工具改写版本号；`ios/ExportOptions.plist` 已关闭自动管理 Version/Build Number。

## 创建补丁

补丁脚本默认发布到 `staging`，并会对比基线标签。检测到 `ios/`、assets、依赖锁文件、Flutter 工具链或 Shorebird 配置变化时会中止。

```bash
scripts/shorebird-patch-ios.sh \
  --release-version '5.0.0+41' \
  --server-url https://api.example.com \
  --bootstrap-url https://api.example.com/api/v1/client/bootstrap \
  --dry-run

scripts/shorebird-patch-ios.sh \
  --release-version '5.0.0+41' \
  --server-url https://api.example.com \
  --bootstrap-url https://api.example.com/api/v1/client/bootstrap
```

补丁修改也必须先提交。补丁脚本会确认基线标签是当前 `HEAD` 的祖先、`pubspec.yaml` 版本与目标 Release 一致，并拦截原生、assets、依赖、Flutter 工具链或 Shorebird 配置变更。基线和补丁必须使用完全一致的 Dart Defines 和 Flutter 版本。正式流程中不要使用 `--allow-native-diffs` 或 `--allow-asset-diffs`。

## staging 真机验收

1. 使用真实 iPhone；iOS 模拟器不能验证 Shorebird 补丁。
2. 仅执行一次 `shorebird preview --release-version 5.0.0+41 --track staging`。`preview` 会安装 Shorebird 的可侧载基线并清空 App 数据，不要先安装 TestFlight，也不要用再次执行 `preview` 代替冷启动。
3. 首次启动后保持 App 在前台，等待 Shorebird 引擎自动完成 staging 检查和下载。`shorebird.yaml` 必须保持 `auto_update: true`，不要在 Dart 启动流程中另外指定 track。
4. 从多任务界面完全杀掉 App，再直接点击桌面图标启动，确认补丁生效。
5. 回归登录、消息、图片/文件、APNs、VoIP/CallKit、相机相册权限及本次修复功能。
6. 记录 Release Version、Patch Number、Git Commit、Shorebird/Flutter 版本、设备和测试结果。
7. 执行 `shorebird patches promote --release-version 5.0.0+41 --patch-number N`，把已验证的同一个 Patch Number 从 `staging` 提升到 `stable`。不要重新构建另一份补丁冒充已验证产物。

TestFlight/App Store 安装包只会读取 `stable` channel。所以 staging 验收使用 `preview`；提升后再用 TestFlight 基线做一次 stable 冒烟验收。

## 线上止损

发现问题时先关闭相关后台入口、停止 App Store 分阶段发布和补丁推广。Dart 问题优先停用问题补丁或发布已验证的纠正补丁；原生问题必须提交新 App Store 版本。保留问题版本、Patch Number、Git Commit、影响范围、日志和回滚结果。

## 验收记录

| 字段 | 内容 |
|---|---|
| Release Version | |
| Patch Number / Track | |
| Git Commit | |
| Flutter / Shorebird Version | |
| IPA SHA256 | |
| TestFlight Build | |
| 测试设备 / iOS | |
| 测试人 / 时间 | |
| 核心回归结果 | |
| App Store 链接验证 | |
| 回滚/开关演练 | |
