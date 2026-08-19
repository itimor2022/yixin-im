# iOS Shorebird 自动补丁开发方案

日期：2026-07-23

## 1. 背景

当前 iOS 客户端已经接入 `shorebird_code_push`，仓库根目录也存在 `shorebird.yaml`，但现状还不能作为稳定、低维护成本的 App Store 热更新方案直接使用：

- 当前应用版本为 `5.0.0+30`。
- `shorebird.yaml` 已配置 Shorebird App ID，但 `auto_update: false`。
- Flutter 启动页通过自建 `/app/hot-update/check` 接口控制补丁命中和安装。
- 已登录用户在启动页直接跳过升级检查，可能完全不执行自建补丁流程。
- 仓库只有 Android 的 Shorebird release/patch 脚本，没有 iOS 自动化脚本。
- iOS 原生桥接仍保留 `manifest.plist` / `itms-services` 自托管安装能力，该能力不应作为 App Store 用户的正式更新通道。
- iOS 和 Android 目前共用一个 `app_update_url`，不利于分别配置 App Store 与 Android 下载地址。
- `ios/ExportOptions.plist` 尚未显式关闭 Xcode 自动管理 Version/Build Number。

已经上架但不是通过 `shorebird release ios` 构建的旧版本，不能事后获得 Shorebird 补丁能力。必须先通过 App Store 发布一次 Shorebird 基线版本，用户升级到该版本后，后续纯 Dart 修复才可以通过补丁下发。

## 2. 目标

### 2.1 核心目标

建立一套低操作成本、可验证、可止损的 iOS 更新体系：

1. App Store 正式版本使用 `shorebird release ios` 构建。
2. Shorebird 在 iOS App 启动时自动检查并下载 `stable` 补丁。
3. 纯 Dart 修复可以先发 `staging`，真机验证后再切换到 `stable`。
4. Swift、权限、原生插件、资源文件和重大功能继续走 App Store 新版本。
5. 后台保留 App Store 整包更新提示和紧急功能开关。
6. 已登录和未登录用户都能收到 App Store 版本提示，不再被认证状态绕过。
7. App Store 构建不使用企业签名式 `itms-services` 更新。

### 2.2 用户体验目标

- 普通 Dart 补丁在后台下载，不打断用户当前操作。
- 补丁下载后，用户下一次完全重启 App 时生效。
- 补丁下载失败时继续运行基线版本，不出现启动死循环。
- 需要 App Store 更新时，跳转到本应用的官方 App Store 页面。
- 强制整包更新仅由明确的最低支持版本触发，不把所有更新都设为强制。

## 3. 非目标与边界

本方案不用于：

- 绕过 App Store 审核发布重大新功能。
- 热更新 Swift、Objective-C、C/C++ 或 Flutter Engine。
- 热更新 iOS 权限、Entitlements、签名、Bundle ID、Pod 或原生插件。
- 热更新新增或替换的图片、字体、启动图等打包资源。
- 给未安装 Shorebird 基线包的旧用户直接下发补丁。
- 通过企业签名 IPA 覆盖安装 App Store 版本。

下列变化必须重新提交 App Store：

- `ios/**` 发生有效变更。
- `pubspec.yaml` 依赖变更包含原生实现。
- 新增、删除或替换 assets、字体、图标、启动图。
- Flutter SDK、Xcode、最低 iOS 版本或构建链路变化。
- 推送、CallKit、后台模式、相机、相册、定位等原生能力变化。
- 支付、账号体系或应用核心用途发生重大变化。

## 4. 总体架构

```text
                         ┌─────────────────────────┐
                         │      iOS App 启动        │
                         └────────────┬────────────┘
                                      │
                 ┌────────────────────┴────────────────────┐
                 │                                         │
                 ▼                                         ▼
      Shorebird 自动检查 stable                  自有后端读取运行配置
                 │                                         │
          有 Dart 补丁？                           版本/功能开关判断
          │           │                           │             │
         否          是                     功能正常       紧急关闭/整包升级
          │           │                           │             │
          │       后台下载补丁                    │      跳转 App Store
          │           │                           │
          └──────继续运行当前版本──────────────────┘
                      │
                下次重启应用补丁
```

三条更新路径必须保持独立：

| 更新类型 | 发布通道 | 是否重新审核 | 典型内容 |
|---|---|---:|---|
| Dart 小修复 | Shorebird Patch | 否 | 页面、文案、Dart 业务逻辑、接口调用 |
| 原生/资源/重大功能 | App Store 新版本 | 是 | Swift、权限、插件、assets、签名、核心功能 |
| 紧急止损 | 后台功能开关 | 否 | 关闭故障入口、维护模式、最低支持版本 |

## 5. 关键技术决策

### 5.1 iOS 使用 Shorebird 自动更新

将 `shorebird.yaml` 改为显式启用：

```yaml
app_id: "<YOUR_SHOREBIRD_APP_ID>"
auto_update: true
```

采用自动更新后：

- iOS 不再依赖启动页自建补丁弹窗来触发 Shorebird。
- 不再要求管理员为每个 Shorebird 补丁额外创建 `/admin/hot-update` 记录。
- `stable` / `staging` 和补丁状态由 Shorebird 管理。
- 自有后端继续管理 App Store 整包版本和紧急功能开关。
- Android 是否继续使用现有自建灰度流程另行决定，不在本次 iOS 方案内强制改变。

### 5.2 App Store 与企业分发通道分离

App Store iOS 构建：

- 只允许跳转 App Store 官方链接进行整包更新。
- 不使用 `.plist`、`itms-services` 或企业 IPA 覆盖安装。
- 不在后台为 App Store iOS 发布 `delivery_mode=self_hosted` 补丁。

如果未来确实需要企业内部发行，应使用独立 Flavor、独立 Bundle ID、独立 Shorebird App ID 和独立后台渠道，不能与 App Store 包混用。

### 5.3 保留 App Store 整包升级兜底

后端设置建议从当前共用字段：

```text
app_update_url
app_force_update
```

拆分为至少：

```text
app_update_url_ios
app_update_url_android
min_supported_version_ios
min_supported_version_android
latest_version_ios
latest_version_android
```

兼容策略：

1. 新字段为空时读取旧字段，保证旧后台和旧客户端不立即失效。
2. 新管理后台优先保存平台独立字段。
3. iOS 更新地址只接受 `https://apps.apple.com/...` 或经确认的 Apple 官方跳转地址。
4. 当当前版本低于 `min_supported_version_ios` 时才强制更新。
5. 当前版本低于 `latest_version_ios` 但不低于最低支持版本时，只做可关闭的普通提示。

### 5.4 紧急功能开关使用现有 Go 后台

不额外接入 Firebase Remote Config，优先复用现有系统设置接口，减少新 SDK、原生配置和运营入口。

第一批建议配置：

```text
ios_maintenance_mode
ios_disable_wallet
ios_disable_call
ios_disable_moments
ios_disable_file_upload
ios_min_supported_version
ios_maintenance_message
```

要求：

- App 内置安全默认值。
- 后端不可用时不把所有功能默认关闭。
- 维护模式保留登录退出、隐私政策、联系客服和版本更新入口。
- 高风险功能必须支持后台关闭后立即或下次前台刷新生效。

## 6. 开发阶段

### 阶段 P0：发布信息和环境确认

在修改代码前确认：

- App Store Connect 当前正式版本和 Build Number。
- App Store 应用 Apple ID 和正式下载链接。
- 当前线上包是否由 Shorebird 构建；如果没有明确证据，按“不是 Shorebird 基线”处理。
- Apple Developer Team：`U4TWR5VCQ3` 是否仍有效。
- Bundle ID：`com.genericim.ma100` 是否与 App Store 记录一致。
- Distribution Certificate 和 App Store Provisioning Profile 是否有效。
- Mac 上的 Xcode、CocoaPods、Flutter、Shorebird CLI 是否正常。
- `shorebird login` 和 `shorebird doctor` 是否通过。

版本策略：

- 不直接假定下一版一定是 `5.0.1+31`。
- 先读取 App Store Connect 已使用的最高 Build Number。
- 新 Build Number 必须大于 App Store Connect 中该版本的所有历史构建。
- Shorebird Release、IPA 内版本和 App Store Connect 版本必须完全一致。

### 阶段 P1：客户端更新流程收敛

涉及文件：

- `shorebird.yaml`
- `lib/features/splash/pages/splash_page.dart`
- `lib/core/services/hot_update_sdk_adapter.dart`
- `lib/core/services/api/system_settings_service.dart`
- `ios/Runner/AppDelegate.swift`

工作项：

1. 将 Shorebird 自动更新设为开启。
2. iOS 不再由 `_runHotUpdatePatchFlow()` 主动执行 Shorebird `checkForUpdate/update`。
3. 避免自动更新与自建 Shorebird 更新同时运行，防止重复下载、重复提示和重复上报。
4. 将 App Store 整包版本检查移到认证跳转之前，确保已登录和未登录用户都能检查。
5. 为整包版本检查增加单次执行锁和超时，失败时不阻塞普通启动。
6. App Store 更新按钮只打开 Apple 官方应用页面。
7. App Store Flavor 禁用 iOS `self_hosted` 安装入口。
8. 保留 Android 现有 APK 自托管更新能力，不在本阶段顺带删除。
9. 补丁不可用、离线或 Shorebird 服务异常时继续运行基线版本。
10. 记录基础诊断日志，但不得输出用户 Token、证书或后台密钥。

### 阶段 P2：后端和管理后台配置拆分

涉及文件：

- `backend/internal/models/system_setting.go`
- `backend/internal/handlers/setting_handler.go`
- `admin/src/api/admin.ts`
- `admin/src/views/system/settings/index.vue`
- `lib/core/services/api/system_settings_service.dart`

工作项：

1. 新增 iOS/Android 独立更新地址。
2. 新增 iOS/Android 最低支持版本。
3. 保留历史字段兼容读取。
4. 管理后台将“最新版本”和“最低支持版本”分开填写。
5. iOS 更新地址增加 Apple 官方域名格式校验。
6. 强制更新改为由最低支持版本自动判断，减少人工误开启风险。
7. 增加第一批 iOS 紧急功能开关。
8. 客户端设置模型增加新字段和旧字段回退逻辑。
9. 后端单元测试覆盖版本比较、旧字段兼容和空配置。

### 阶段 P3：iOS Shorebird 脚本

建议新增：

- `scripts/shorebird-release-ios.sh`
- `scripts/shorebird-patch-ios.sh`
- `scripts/verify-shorebird-ios-release.sh`
- `docs/Shorebird-iOS发布与补丁SOP.md`

`shorebird-release-ios.sh` 参数建议：

```text
--build-name
--build-number
--server-url
--ws-url
--bootstrap-url
--export-options-plist
--flutter-version
--dry-run
```

脚本职责：

1. 校验运行环境必须是 macOS。
2. 校验 `shorebird`、`xcodebuild`、`pod` 和签名环境。
3. 校验工作区存在未提交修改时给出明确提示，但不自动清理。
4. 读取并显示目标版本、Bundle ID、Team ID 和线上接口地址。
5. 运行 `shorebird doctor`。
6. 调用 `shorebird release ios`。
7. 透传与正式包一致的 Dart Defines。
8. 输出 IPA、Archive、版本、构建号和 SHA256。
9. 不保存 App Store Connect 私钥、证书密码或 Token 到仓库。

`shorebird-patch-ios.sh` 参数建议：

```text
--release-version
--track
--server-url
--ws-url
--bootstrap-url
--export-options-plist
--dry-run
```

脚本职责：

1. 默认 `track=staging`，不得默认直接发布 `stable`。
2. 检查相对目标 Release 是否存在原生或 assets 变化。
3. 检测到 `ios/**`、Flutter SDK 或打包资源差异时默认中止。
4. 不自动使用 `--allow-native-diffs` 或 `--allow-asset-diffs`。
5. 使用与基线 Release 完全一致的线上地址和 Flutter 版本。
6. 输出 Release Version、Patch Number、Track 和执行时间。
7. 提供明确的 `staging` 真机验证和转 `stable` 后续命令。

### 阶段 P4：ExportOptions 和签名稳定化

修改 `ios/ExportOptions.plist`：

```xml
<key>manageAppVersionAndBuildNumber</key>
<false/>
```

验证：

- Shorebird 检测的 Release Version 与 `pubspec.yaml` 一致。
- Archive 内 `CFBundleShortVersionString` 与目标版本一致。
- Archive 内 `CFBundleVersion` 与目标 Build Number 一致。
- Xcode/Transporter 上传后 App Store Connect 显示的版本不发生变化。
- IPA 使用 App Store Distribution 正式证书签名。
- Entitlements 与当前上架版本所需能力一致。

### 阶段 P5：基线版本发布

建议顺序：

1. 完成 P1～P4。
2. 在 Mac 上生成 Shorebird iOS Release。
3. 使用 `shorebird preview` 在真实 iPhone 验证基线。
4. 上传同一份 IPA 到 TestFlight。
5. TestFlight 真机完成完整核心功能回归。
6. 确认 Shorebird Console 存在对应 Release Version。
7. 提交 App Store 审核。
8. 审核通过后先使用 App Store 分阶段发布。
9. 观察崩溃、登录、消息、推送、通话和更新指标。
10. 基线稳定后再发布第一个正式 Shorebird Patch。

必须强调：

- 普通 `flutter build ipa` 生成的包不能替代这次 Shorebird Release。
- 上传到 App Store 的必须是 Shorebird Release 对应的同一份 IPA/Archive。
- 不得在上传时让 Xcode自动改变 Build Number。

### 阶段 P6：补丁发布流程

每个补丁按以下流程执行：

1. 确认改动仅包含允许补丁的 Dart 代码。
2. 记录目标 App Store Release Version。
3. 运行补丁 dry-run。
4. 发布到 `staging`。
5. 使用真实 iPhone 执行 `shorebird preview --track=staging`。
6. 第一次启动等待补丁下载。
7. 完全杀掉 App。
8. 第二次启动确认补丁生效。
9. 回归登录、消息、上传、推送、通话和本次修改功能。
10. 保存 Patch Number、Git Commit、测试设备和结果。
11. 将同一个已验证补丁切换到 `stable`。
12. 观察线上指标，不直接连续发布多个未观察补丁。

建议发布记录字段：

```text
release_version
patch_number
track
git_commit
flutter_version
shorebird_version
server_url
ws_url
created_at
tester
physical_device
test_result
```

## 7. 测试与验证

### 7.1 自动化检查

- `flutter analyze --no-pub`
- 热更新相关 Flutter 单元测试
- 系统设置服务单元测试
- 后端系统设置和版本比较测试
- 管理后台类型检查和构建
- 脚本 shellcheck 或等价静态检查
- `shorebird release ios --dry-run`
- `shorebird patch ios --dry-run`

### 7.2 基线真机验证

至少使用一台真实 iPhone，覆盖：

- App Store/TestFlight 安装。
- 首次启动。
- 已登录冷启动。
- 未登录冷启动。
- 后台恢复。
- 离线启动。
- 弱网启动。
- 登录、注册和退出。
- 私聊、群聊、图片、语音、视频和文件消息。
- APNs 普通推送。
- VoIP/CallKit 通话。
- 相机、相册、麦克风和定位权限。
- App Store 更新链接。
- 后台功能开关。

### 7.3 补丁真机验证

必须证明：

1. 基线包第一次启动不包含补丁修改。
2. `staging` 补丁能够被真实 iPhone 下载。
3. 第一次启动下载补丁时 App 仍可正常使用。
4. 完全退出并第二次启动后补丁生效。
5. `readCurrentPatch()` 或 Shorebird 日志能确认 Patch Number。
6. 断网时继续运行已安装的基线/补丁。
7. 下载中断不会破坏 App。
8. 已登录用户可以自动获得补丁。
9. 未登录用户可以自动获得补丁。
10. 补丁不改变原生权限和签名行为。

模拟器结果不能替代 Shorebird iOS 真机验收。

### 7.4 App Store 整包更新验证

- 当前版本低于 `latest_version_ios`：显示可跳过更新提示。
- 当前版本低于 `min_supported_version_ios`：阻止进入核心业务并显示强制更新。
- 点击更新打开正确 App Store 应用页面。
- App Store 地址为空时不进入无法退出的强更页面。
- 已登录和未登录状态行为一致。
- Android 不读取 iOS 的更新地址。

## 8. 灰度、监控与止损

### 8.1 App Store 基线灰度

使用 App Store 分阶段发布，先观察小比例用户：

```text
1% → 2% → 5% → 10% → 20% → 50% → 100%
```

重点观察：

- 崩溃率和卡死率。
- 冷启动成功率。
- 登录成功率。
- WebSocket 连接成功率。
- 消息发送成功率。
- APNs 和 VoIP Push。
- CallKit 接听和结束。
- Shorebird Release/Patch 识别情况。

### 8.2 Shorebird 补丁灰度

最简模式采用：

```text
staging 真机验证 → stable 正式发布
```

如果未来需要百分比灰度，再评估 Shorebird Rollout 或独立 Flavor；第一阶段不同时维护自有灰度和 Shorebird 灰度，避免双重筛选导致排障困难。

### 8.3 紧急止损

发现严重问题时按优先级执行：

1. 后台关闭故障功能。
2. 停止扩大 App Store 分阶段发布。
3. 停止继续推广问题补丁。
4. 根据 Shorebird 当时版本支持的管理能力停用问题补丁，或发布已验证的纠正补丁。
5. 如果涉及原生层，立即准备 App Store 修复版本。
6. 关键线上故障申请 Apple 加急审核。

执行回滚前必须保存：

- 问题版本和 Patch Number。
- 影响用户范围。
- 崩溃和服务端错误日志。
- 最小复现步骤。
- 回滚或纠正补丁结果。

## 9. 安全与审核要求

- Shorebird Patch 只用于不改变应用主要用途的 Dart 修复。
- 不通过补丁新增审核敏感支付、权限或隐藏功能。
- 不在仓库提交 App Store Connect API 私钥、证书或 Token。
- 不在日志输出用户 Token、手机号、会话内容或签名密码。
- App Store 版本不暴露企业 IPA 安装入口。
- 后台配置不能下发可执行脚本或任意动态代码。
- 功能开关只能控制客户端已包含并已审核的功能。

## 10. 交付物

### 代码与配置

- 更新后的 `shorebird.yaml`
- 更新后的 `ios/ExportOptions.plist`
- 收敛后的 iOS 启动/整包升级流程
- iOS/Android 独立版本和更新地址设置
- iOS 最低支持版本逻辑
- 第一批 iOS 紧急功能开关
- App Store Flavor 对 `self_hosted` iOS 安装的隔离

### 脚本

- `scripts/shorebird-release-ios.sh`
- `scripts/shorebird-patch-ios.sh`
- `scripts/verify-shorebird-ios-release.sh`

### 文档与证据

- `docs/Shorebird-iOS发布与补丁SOP.md`
- TestFlight 基线安装证据
- 真实 iPhone staging 补丁证据
- Patch Number 和 Git Commit 对照记录
- App Store 更新链接验证记录
- 回滚与紧急开关演练记录

## 11. 验收标准

全部满足后才可认为 iOS 自动补丁方案完成：

- [ ] App Store/TestFlight 基线包由 `shorebird release ios` 生成。
- [ ] Shorebird Console 中存在与 IPA 完全一致的 Release Version。
- [ ] App Store Connect 没有自动修改 Version/Build Number。
- [ ] 真实 iPhone 能安装并正常运行基线版本。
- [ ] `staging` 补丁能在真实 iPhone 下载。
- [ ] 完全退出并第二次启动后补丁生效。
- [ ] 已登录用户能够自动获得补丁。
- [ ] 未登录用户能够自动获得补丁。
- [ ] 弱网、断网和补丁下载失败不阻塞 App 启动。
- [ ] App Store 整包更新链接正确。
- [ ] iOS/Android 更新地址互不串用。
- [ ] App Store 构建不使用 `itms-services` 自托管安装。
- [ ] 原生或 assets 变化会被补丁脚本阻止。
- [ ] 后台紧急功能开关能够真实止损。
- [ ] 登录、消息、推送、CallKit 和本次修改功能完成真机回归。
- [ ] 发布、验证、转 stable 和止损流程都有可追溯记录。

## 12. 推荐实施顺序

```text
P0 账号/版本/签名确认
→ P1 客户端自动更新和启动流程收敛
→ P2 后端版本字段与紧急开关
→ P3 iOS Release/Patch 脚本
→ P4 ExportOptions 和签名校验
→ P5 TestFlight/App Store 基线发布
→ P6 staging 补丁真机验证
→ stable 正式启用
```

不建议在基线包尚未通过 TestFlight 真机验证前，提前对正式用户承诺热更新已经可用。

## 13. 官方参考

- Shorebird Release：<https://docs.shorebird.dev/code-push/release/>
- Shorebird Patch：<https://docs.shorebird.dev/code-push/patch/>
- Shorebird Preview：<https://docs.shorebird.dev/code-push/preview/>
- Shorebird App Store 发布：<https://docs.shorebird.dev/code-push/guides/stores/app-store/>
- Shorebird Staging Patch：<https://docs.shorebird.dev/code-push/guides/staging-patches/>
- Apple App Review Guidelines：<https://developer.apple.com/app-store/review/guidelines/>
- Apple 创建新版本：<https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/>
- Apple 分阶段发布：<https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/>
