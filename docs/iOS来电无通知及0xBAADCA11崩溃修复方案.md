# iOS 来电无通知及 0xBAADCA11 崩溃修复方案

## 1. 文档信息

- 问题平台：iOS 真机
- 问题版本：`5.0.0 (31)` TestFlight
- 测试系统：iOS `26.5 (23F77)`
- Bundle ID：`com.genericim.ma100`
- 问题类型：PushKit VoIP 推送未成功上报 CallKit，导致系统强制结束 App
- 修复优先级：P0
- 文档日期：2026-07-23

## 2. 问题现象

真机测试来电时出现以下现象：

1. 被叫设备没有显示普通通知；
2. 没有出现 iOS 系统 CallKit 来电界面；
3. App 被系统直接结束，用户感知为报错或闪退；
4. 连续拨打可以稳定复现。

本次真机提取到两份对应时间的崩溃报告：

- `artifacts/ios/crashlogs/Runner-2026-07-23-122943.ips`
- `artifacts/ios/crashlogs/Runner-2026-07-23-123001.ips`

两次报告均具有以下特征：

- `exception.type = EXC_CRASH`
- `exception.signal = SIGKILL`
- `termination.namespace = FRONTBOARD`
- `termination.code = 0xBAADCA11`
- App 被 VoIP 推送唤醒后约 7.49 秒被系统结束

Apple 对 `0xBAADCA11` 的定义是：App 收到 PushKit VoIP 通知后，没有按要求向 CallKit 报告来电，因此被操作系统终止。

## 3. 根因分析

### 3.1 当前 iOS 处理流程

当前 PushKit 入口位于：

```text
ios/Runner/AppDelegate.swift
```

主要处理流程为：

```text
收到 PushKit VoIP 推送
  → 解析 payload
  → 校验业务字段
  → 生成 CallKit Data
  → 调用 flutter_callkit_incoming
  → reportNewIncomingCall
  → 完成 PushKit completion
```

`incomingCallKitData` 当前强制要求以下字段全部存在：

- `type == incoming_call`
- `call_id` 或 `callId`
- `caller_id`
- `caller_name`、`title` 或 `nameCaller`
- `channel_name` 或 `room_name`

任意字段缺失时，方法直接返回 `nil`。

PushKit 回调随后进入以下逻辑：

```text
callData 为空或插件实例为空
  → 调用 completion()
  → return
```

这条路径没有执行 `reportNewIncomingCall`。对于必须报告的 VoIP 推送，iOS 会将其认定为违规处理并以 `0xBAADCA11` 结束进程。

### 3.2 为什么同时没有通知

服务端发送 `apns_voip` 推送时会主动移除普通 APNs 通知内容：

- 清空 `aps.alert`
- 清空 `aps.sound`
- 关闭 `mutable-content`
- 保留 `content-available`
- 使用 `apns-push-type: voip`

因此，VoIP 推送本身不会显示普通横幅，用户可见提醒完全依赖 CallKit。

当客户端没有成功调用 CallKit 时：

```text
普通 APNs 横幅不存在
+ CallKit 来电没有上报
= 用户看不到任何来电提醒
```

随后 App 又会被 iOS 强制结束。

### 3.3 当前证据能够确定的范围

已经确定：

1. 不是普通 Dart 异常；
2. 不是内存不足；
3. 不是 Flutter 页面渲染崩溃；
4. 是收到 VoIP 推送后没有成功报告 CallKit；
5. 当前客户端存在一条明确的“完成 PushKit 回调但不报告 CallKit”路径；
6. 真机安装包与本地 build 31 归档 UUID 一致，源码与崩溃二进制能够对应。

当前 TestFlight Release 包的 PushKit 日志被 `#if DEBUG` 屏蔽，因此仅凭崩溃报告暂时无法确认实际缺失的是哪个字段。

可能性排序如下：

1. 线上实际 VoIP payload 缺少字段或嵌套格式不符合客户端解析预期；
2. 冷启动时 `SwiftFlutterCallkitIncomingPlugin.sharedInstance` 尚未就绪；
3. 服务端线上版本与当前源码的 payload 契约存在差异；
4. 历史设备 token 或多设备绑定产生了异常来电推送。

## 4. 修复目标

修复后必须满足：

1. 任何必须向 CallKit 报告的 VoIP 推送都不会直接退出；
2. 业务字段不完整时，App 不崩溃；
3. 前台、后台、锁屏和进程结束状态均能正确处理来电；
4. 同一个 `call_id` 不会重复显示；
5. PushKit completion 每次只调用一次；
6. Release/TestFlight 环境能够诊断 payload 和 CallKit 上报结果；
7. 服务端不会向 APNs 发送不符合契约的 VoIP payload；
8. 真机不再产生 `0xBAADCA11`。

## 5. 总体修复设计

采用以下三层修复：

```text
服务端 payload 契约与发送前校验
             ↓
iOS 原生 PushKit/CallKit 强制上报与容错
             ↓
Release 诊断日志、真机回归和线上监控
```

## 6. P0：iOS 客户端止崩修复

### 6.1 拆分系统展示字段与业务接听字段

CallKit 展示所需字段：

- 合法的 CallKit UUID
- 来电人显示名称
- 语音或视频类型

接听后进入 RTC 所需字段：

- `call_id`
- `caller_id`
- `channel_name` 或 `room_name`
- `rtc_provider`
- `server_url`
- RTC token 等服务端返回信息

业务字段不完整时，不应阻止系统来电上报。可以先显示 CallKit，再根据 `call_id` 查询完整通话详情。

### 6.2 增加 CallKit 展示兜底值

建议的容错规则：

| 字段 | 正常来源 | 缺失时处理 |
| --- | --- | --- |
| `call_id` | VoIP payload | 生成临时 UUID，并标记业务数据不完整 |
| CallKit UUID | `call_id` 的稳定映射 | 使用新的合法 UUID |
| `caller_name` | payload | 显示“未知来电” |
| `call_type` | `voice` 或 `video` | 默认按语音处理 |
| `caller_id` | payload | 不阻止 CallKit，接听后补拉 |
| `channel_name` | payload | 不阻止 CallKit，接听后补拉 |
| `rtc_provider` | payload | 不阻止 CallKit，接听后补拉 |

如果 `type` 不是 `incoming_call`，需要结合 iOS 26.4 以上的 `metadata.mustReport` 决定是否必须报告。服务端不得通过 VoIP 通道发送非通话业务事件。

### 6.3 保证必须上报时先调用 CallKit

目标流程：

```text
收到 VoIP 推送
  → 判断 mustReport
  → 规范化 payload
  → 生成完整或兜底 CallKit 数据
  → reportNewIncomingCall
  → 记录成功或错误
  → 调用 PushKit completion
  → 异步转发业务数据到 Flutter
```

禁止以下流程再次出现：

```text
收到必须报告的 VoIP 推送
  → payload 校验失败
  → 仅调用 completion
  → 退出
```

### 6.4 completion 一次性保护

PushKit completion 需要统一管理：

1. 建立 `finishOnce` 或同类一次性完成保护；
2. CallKit completion 返回后调用；
3. 异常分支也通过同一个完成入口；
4. 避免 CallKit 回调、超时保护和业务回调重复完成；
5. 不等待 Flutter 网络请求、RTC 初始化或页面初始化后再完成。

### 6.5 适配 iOS 26.4 以上 PushKit metadata

iOS 26.4 以上优先实现带 metadata 的 VoIP 回调：

```text
pushRegistry(
  didReceiveIncomingVoIPPushWith payload,
  metadata,
  withCompletionHandler
)
```

处理规则：

- `metadata.mustReport == true`：必须报告 CallKit；
- `metadata.mustReport == false`：允许根据业务状态忽略并完成回调；
- 旧版 iOS：收到 `.voIP` 推送时默认按必须报告处理。

### 6.6 降低冷启动对 Flutter 插件的依赖

当前 PushKit 回调依赖：

```text
SwiftFlutterCallkitIncomingPlugin.sharedInstance
```

建议增加原生 `NativeCallKitManager`：

1. App 原生启动阶段创建唯一 `CXProvider`；
2. PushKit 回调直接使用原生 `CXProvider` 报告来电；
3. Flutter Engine 就绪后再转发来电数据；
4. 接听、拒接和超时事件缓存后转发给 Dart；
5. Flutter 插件实例未初始化时，系统来电仍能显示。

可以分两阶段实施：

- 快速止血：继续使用现有插件，并增加原生 `CXProvider` 兜底；
- 稳定改造：PushKit 到 CallKit 的系统链路完全由原生层负责，Flutter 只处理业务状态和 RTC。

### 6.7 接听后的业务补偿

当 CallKit 已显示但业务字段不完整时：

1. 用户点击接听；
2. 使用 `call_id` 请求通话详情或 `/call/active`；
3. 获取频道、RTC 服务商、服务器地址和 token；
4. 信息完整则进入 RTC；
5. 信息不存在、已过期或无权限时：
   - 将 CallKit 通话标记为 `failed`；
   - 关闭系统通话；
   - 显示“来电已结束”或“通话信息无效”；
   - 不进入崩溃或无限加载状态。

如果连 `call_id` 都不存在，只能显示短暂的系统来电并立即按失败结束，同时记录服务端契约错误。

## 7. P0：服务端 payload 契约修复

### 7.1 发送前强制校验

涉及文件：

```text
backend/internal/handlers/call_handler.go
backend/internal/services/push_service.go
```

发送 `apns_voip` 前验证：

- `type == incoming_call`
- `call_id` 非空且对应有效通话
- `caller_id` 非空
- `caller_name` 非空
- `channel_name` 或 `room_name` 非空
- `call_type` 为 `voice` 或 `video`
- `expires_at` 未过期
- 被叫用户和设备 token 有效

推荐服务端 payload：

```json
{
  "aps": {
    "content-available": 1
  },
  "data": {
    "type": "incoming_call",
    "call_id": "123",
    "caller_id": "caller-uuid",
    "caller_name": "来电用户",
    "caller_avatar": "",
    "call_type": "voice",
    "is_video": false,
    "channel_name": "call-channel",
    "room_name": "call-channel",
    "provider": "livekit",
    "rtc_provider": "livekit",
    "expires_at": "2026-07-23T12:30:00+08:00"
  }
}
```

### 7.2 发送失败处理

校验失败时：

1. 不发送无效 VoIP 推送；
2. 记录缺失字段、`call_id`、用户 ID、设备逻辑 ID和应用版本；
3. 不记录完整 push token、JWT、密码或 RTC token；
4. 将通话创建结果标记为推送失败或可降级状态；
5. 如果被叫 WebSocket 在线，仍可保留站内来电事件；
6. 服务端监控中增加 payload 契约失败指标。

### 7.3 保留正确的 APNs 请求头

VoIP 推送应继续使用：

```text
apns-push-type: voip
apns-topic: com.genericim.ma100.voip
apns-priority: 10
apns-expiration: 0
```

`apns-expiration: 0` 可以避免过期来电在稍后被补发。

### 7.4 多设备和重复推送治理

1. 普通 APNs token 与 VoIP token 分开存储；
2. 同一物理设备存在有效 VoIP token 时，来电不再额外发送普通 APNs 来电；
3. 同一个 `call_id + 设备` 只发送一次有效 VoIP 推送；
4. 服务端记录 APNs request ID 和返回状态；
5. 无效 token 按逻辑设备精确清理，避免误删另一通道 token；
6. 主叫取消后通过现有连接通知被叫结束 CallKit，不使用新的 VoIP 推送发送取消事件。

## 8. P1：Release 可观测性

### 8.1 当前问题

`pushDebugLog` 只在 DEBUG 编译条件下输出。TestFlight 属于 Release，导致发生问题时无法确认具体缺失字段。

### 8.2 建议记录内容

使用 `Logger`、`os_log` 或持久化诊断事件记录：

- 收到 VoIP 推送的时间；
- App 当时处于前台、后台、锁屏唤醒或冷启动；
- payload 顶层和 `data` 中包含的字段名；
- 缺失字段列表；
- `metadata.mustReport`；
- 生成的 CallKit UUID；
- 是否调用 `reportNewIncomingCall`；
- CallKit completion 是否返回错误；
- 错误域和错误码；
- PushKit completion 是否执行；
- 是否检测到重复 `call_id`；
- Flutter Engine 和插件是否就绪。

### 8.3 隐私要求

日志不得记录：

- 完整 APNs token；
- JWT、密码和登录凭证；
- RTC token；
- 完整手机号；
- 完整私聊内容；
- 私钥或证书内容。

用户 ID、设备 ID和 token 只允许记录不可逆哈希或脱敏片段。

## 9. 测试方案

### 9.1 单元测试

为 payload 解析和 CallKit 决策增加测试：

1. 完整语音来电；
2. 完整视频来电；
3. `data` 为字典；
4. `data` 为 JSON 字符串；
5. `call_id` 为数字；
6. `call_id` 为字符串；
7. 缺少 `caller_name`；
8. 缺少 `caller_id`；
9. 缺少 `channel_name`；
10. 缺少 `call_type`；
11. 完全非法 payload；
12. 重复 `call_id`；
13. 已过期来电；
14. `mustReport == true`；
15. `mustReport == false`；
16. Flutter 插件未初始化；
17. CallKit 返回错误；
18. completion 重复触发保护。

关键断言：

- 必须报告的推送一定调用 CallKit；
- payload 不完整不会直接退出；
- PushKit completion 只调用一次；
- 同一个业务来电生成稳定 UUID；
- 非必须报告的推送不会制造虚假来电。

### 9.2 服务端测试

1. `PushIncomingCall` 生成完整字段；
2. APNs VoIP payload 为对象而不是错误编码的字符串；
3. 请求头使用 `.voip` topic；
4. 缺失字段时拒绝发送；
5. 空昵称使用安全兜底；
6. 过期来电不发送；
7. 同设备普通 APNs 与 VoIP 不重复；
8. 多设备 token 正确分发；
9. APNs 返回无效 token 时只清理对应 token；
10. payload 和请求体大小符合 APNs 限制。

### 9.3 真机测试矩阵

至少准备两台真实设备，模拟器不能作为 PushKit 最终验收依据。

| 编号 | 被叫状态 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| IOS-CALL-01 | App 前台 | 语音来电 | 显示应用内或系统来电，不崩溃 |
| IOS-CALL-02 | App 后台 | 语音来电 | 显示 CallKit |
| IOS-CALL-03 | 锁屏 | 语音来电 | 锁屏显示 CallKit |
| IOS-CALL-04 | 进程结束 | 语音来电 | App 被唤醒并显示 CallKit |
| IOS-CALL-05 | 进程结束 | 视频来电 | 显示视频来电标记 |
| IOS-CALL-06 | 冷启动 | Flutter 初始化延迟 | CallKit 仍正常显示 |
| IOS-CALL-07 | 后台 | 缺少非展示字段 | 显示来电，接听后补拉数据 |
| IOS-CALL-08 | 后台 | 缺少 `caller_name` | 显示“未知来电”，不崩溃 |
| IOS-CALL-09 | 后台 | 重复相同 `call_id` | 只显示一个系统来电 |
| IOS-CALL-10 | 后台 | 主叫立即取消 | CallKit 及时结束 |
| IOS-CALL-11 | 后台 | 被叫拒接 | 双端状态正确释放 |
| IOS-CALL-12 | 后台 | 30 秒无人接听 | CallKit 超时，通话释放 |
| IOS-CALL-13 | 勿扰模式 | 来电 | 正确处理 CallKit 返回结果 |
| IOS-CALL-14 | 通知权限关闭 | 来电 | PushKit/CallKit 链路仍按系统规则处理 |
| IOS-CALL-15 | 弱网 | 来电和接听 | 系统来电先显示，业务连接可重试 |
| IOS-CALL-16 | 多设备登录 | 同账号收到来电 | 每个目标设备行为符合策略 |

### 9.4 稳定性测试

1. 连续拨打至少 20 次；
2. 语音、视频各不少于 10 次；
3. 前台、后台、锁屏和进程结束状态轮换；
4. 每次结束后立即重拨；
5. 检查 CallKit 是否残留；
6. 检查服务端 active call 是否释放；
7. 测试后导出真机崩溃报告；
8. 确认没有新的 `0xBAADCA11`。

## 10. 验收标准

满足以下条件才可认为修复完成：

- [ ] 真机不再产生 `0xBAADCA11`
- [ ] App 进程结束状态可以正常收到系统来电
- [ ] 后台和锁屏状态可以正常显示 CallKit
- [ ] payload 缺少非关键业务字段时不会崩溃
- [ ] Flutter 插件未就绪时仍可以报告系统来电
- [ ] PushKit completion 每次只执行一次
- [ ] 同一个 `call_id` 不重复显示
- [ ] 接听后能够补齐业务字段并进入 RTC
- [ ] 无效或过期来电能够安全结束
- [ ] 主叫取消、被叫拒接和超时均能释放服务端通话
- [ ] Release/TestFlight 日志可以定位缺失字段和 CallKit 错误
- [ ] 服务端不会发送不符合契约的 VoIP payload
- [ ] 连续 20 次真机拨打无闪退、无残留、无静默来电

## 11. 发布计划

### 阶段一：服务端观测与契约校验

1. 增加 payload 发送前校验；
2. 增加 APNs VoIP 投递日志；
3. 核对线上实际 payload；
4. 确认生产服务与当前源码版本一致。

### 阶段二：客户端 P0 止崩

1. 调整 payload 容错规则；
2. 保证必须上报时进入 CallKit；
3. 增加 completion 一次性保护；
4. 增加插件未就绪时的原生兜底；
5. 增加 Release 脱敏诊断。

### 阶段三：内部 TestFlight

建议使用：

```text
5.0.0 (32)
```

完成两台真机全矩阵测试，重点验证：

- 进程结束来电；
- 锁屏来电；
- payload 缺字段；
- Flutter 冷启动；
- 连续拨打；
- 崩溃报告。

### 阶段四：扩大测试

1. 先分配给内部测试组；
2. 观察 PushKit 接收、CallKit 上报成功率和崩溃数据；
3. 确认无 `0xBAADCA11` 后扩大 TestFlight 范围；
4. 最终再提交正式版本审核。

## 12. 回滚方案

客户端版本发布后无法直接回滚已安装二进制，因此应准备服务端开关：

- 暂停向异常客户端版本发送 VoIP；
- 按 App build 控制 VoIP payload 结构；
- 异常时只保留 WebSocket 在线来电；
- 关闭新 payload 扩展字段；
- 保留 build 31 与 build 32 的投递统计对比。

服务端回滚时不得删除设备 token、用户数据或通话记录。

## 13. 涉及文件

预计主要涉及：

```text
ios/Runner/AppDelegate.swift
lib/core/services/call_service.dart
lib/core/services/push_notification_service.dart
backend/internal/handlers/call_handler.go
backend/internal/services/push_service.go
backend/internal/services/push_service_test.go
```

如果增加独立原生管理器，建议新增：

```text
ios/Runner/NativeCallKitManager.swift
ios/Runner/VoIPPushPayload.swift
```

## 14. 最终结论

本问题的核心不是通知权限，也不是 Flutter 页面异常，而是 PushKit 的强制系统契约没有在所有分支得到满足。

修复必须保证：

```text
收到必须报告的 VoIP 推送
  → 无论业务字段是否完整
  → 都先安全地向 CallKit 报告或按 mustReport 规则处理
  → 再完成 PushKit 回调
```

服务端同时需要保证只通过 VoIP 通道发送真实、完整、未过期的来电事件。客户端系统链路容错与服务端 payload 契约同时完成后，才能从根本上解决“无通知 + 0xBAADCA11 强制退出”问题。
