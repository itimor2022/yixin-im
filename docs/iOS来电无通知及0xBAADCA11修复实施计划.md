# iOS 来电无通知及 0xBAADCA11 修复实施计划

## 背景与已确认根因

- 影响平台：iOS 真机
- 影响版本：`5.0.0 (31)` TestFlight
- 崩溃特征：`FRONTBOARD / 0xBAADCA11`
- 对应证据：
  - `artifacts/ios/crashlogs/Runner-2026-07-23-122943.ips`
  - `artifacts/ios/crashlogs/Runner-2026-07-23-123001.ips`

当前 `ios/Runner/AppDelegate.swift` 在 VoIP payload 缺少
`call_id`、`caller_id`、`caller_name` 或 `channel_name` 时直接返回；
`flutter_callkit_incoming` 插件实例尚未就绪时也直接返回。这两条路径只调用
PushKit completion，没有向 CallKit 报告来电，符合系统强制结束 App 的条件。

## 修复范围

### P0 iOS 原生链路

1. 对必须报告的 VoIP push，业务字段不完整时仍生成可展示的 CallKit 数据。
2. `call_id` 缺失时生成稳定的兜底 UUID，昵称缺失时显示“未知来电”。
3. 统一使用一次性 completion，避免成功、错误和超时分支重复完成。
4. 优先使用 `flutter_callkit_incoming`；插件未就绪时使用原生
   `CXProvider` 兜底。
5. 支持带 `PKVoIPPushMetadata` 的新回调；`mustReport == false` 时允许忽略
   非来电事件，旧回调默认必须报告。
6. Release/TestFlight 使用 `Logger` 记录字段名、缺失字段、CallKit UUID、
   插件状态和 CallKit 错误，不记录 token、JWT、RTC token 或完整用户隐私数据。
7. 原生兜底产生的接听、拒绝、结束和超时事件通过现有 Flutter MethodChannel
   缓存并转交给 `CallService`。

### P0 服务端契约

1. `PushIncomingCall` 在进入通用推送分发前规范化并校验：
   - `type == incoming_call`
   - `call_id`
   - `caller_id`
   - `caller_name`（允许安全兜底）
   - `channel_name` / `room_name`
   - `call_type` 为 `voice` 或 `video`
   - `expires_at` 存在且未过期
2. `apns_voip` 发送前再次执行防御性校验，非法 payload 不发送。
3. 保留 `apns-push-type: voip`、`.voip` topic、优先级 `10` 和
   `apns-expiration: 0`。
4. 日志只记录缺失字段、call ID、逻辑设备 ID 和脱敏 token。

## 验证计划

### 自动化与静态验证

- Go：新增 payload 规范化、缺字段、错误类型和过期来电测试。
- Flutter：验证原生 CallKit 事件缓存和分发；对涉及文件运行定向 analyze/test。
- iOS：检查 Swift 接口和工程引用；在可用的 macOS/Xcode 环境执行 Release
  archive。

### 真机验收

模拟器和静态检查不作为最终验收。使用 build 32、两台真机覆盖：

- 前台、后台、锁屏、进程结束、冷启动；
- 语音和视频来电；
- 缺昵称、缺非展示业务字段、完全异常 payload；
- 重复 call ID、立即取消、拒接、30 秒超时；
- 连续 20 次拨打；
- 导出崩溃报告，确认不再出现 `0xBAADCA11`。

## 发布与回滚

1. 先发布服务端契约校验和投递观测。
2. 客户端内部 TestFlight 使用 `5.0.0 (32)`。
3. 真机矩阵通过后再扩大 TestFlight 范围。
4. 保留按客户端 build 停止 VoIP 投递的服务端开关；异常时仅保留在线
   WebSocket 来电，不删除设备 token、用户数据或通话记录。

## 完成标准

- 必须报告的 VoIP push 所有分支都调用 CallKit。
- PushKit completion 每次只执行一次。
- 插件未就绪时仍显示系统来电并能转交操作事件。
- 服务端不向 `apns_voip` 发送不符合契约或已过期的来电。
- Release 日志可定位字段缺失和 CallKit 错误且不泄露敏感信息。
- 两台真机连续 20 次拨打无静默来电、无残留、无 `0xBAADCA11`。
