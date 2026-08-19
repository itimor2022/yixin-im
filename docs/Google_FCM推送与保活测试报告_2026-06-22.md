# Google FCM 推送与 Android 保活测试报告

测试时间：2026-06-22  
测试应用：通用IM Android 正式包，包名 `com.genericim.ma100`  
测试设备：Android Studio 模拟器 `emulator-5554`，机型 `sdk_gphone64_x86_64`  
Google Play services：`25.26.35 (260800-783060121)`  
后端环境：本地 Docker `genericim-api`、`genericim-mysql`、`genericim-redis`、`genericim-mongodb`

## 结论

本轮测试通过。当前 FCM 配置、客户端 token 注册、后端配置、后端发送、Android 通知展示、后台来电展示、锁屏/Doze 高优先级消息到达、前台服务保活都已验证。

需要明确的系统边界：用户或系统执行 `force-stop` 后，Android 会把应用置为 stopped state，FCM 广播会被系统取消，应用不会被推送唤醒。这是 Android 系统限制，不是当前代码缺陷。用户重新手动打开应用后恢复。

本轮模拟器锁屏短时保活观察结果：锁屏 3 分钟核心采样内，进程号保持 `9502`，后台服务保持 `isForeground=true`，后台保活通知保持存在。另一次 5 分钟锁屏观察中，后台通知与服务也持续存在。模拟器不能代表华为/小米/OPPO/vivo 等厂商系统的长期后台策略；“最多锁屏多久”必须用真机做 2 小时、8 小时、24 小时分层长测。

## 配置核对

| 项目 | 结果 |
| --- | --- |
| Android 包名 | `com.genericim.ma100` |
| Firebase 客户端配置 | `android/app/google-services.json` 已用于打包 |
| Firebase Project ID | `genericim-c7ffc` |
| 后端 FCM 开关 | `fcm_enabled=true` |
| 后端服务账号配置 | 已写入系统配置，不在报告中展示密钥 |
| 当前有效设备 token | 用户 `1` 最新 Android 设备 `id=139`，`push_channel=fcm`，token 长度 `142` |
| 后端单元测试 | `go test ./internal/services -run 'FCM|Push' -count=1` 通过 |

## 测试结果

| 用例 | 操作 | 结果 |
| --- | --- | --- |
| 客户端 token 注册 | 登录后查询 `user_devices` | 通过，设备 `026f5746-d2d5-4762-a0aa-3d4b8d7b361b` 注册 FCM token |
| 后台消息推送 | 应用退到后台，发送 FCM notification 消息 | 通过，通知栏出现 `FCM测试消息`，渠道 `genericim_messages`，重要性 `4` |
| 普通杀进程对照 | 后台执行 `am kill com.genericim.ma100` 后发送消息 | 通过；前台保活服务存在时进程未被杀掉，消息继续到达 |
| 系统强停对照 | 执行 `am force-stop com.genericim.ma100` 后发送消息 | 符合预期；Firebase 接口返回成功，但系统取消广播，应用无进程、无新通知 |
| 后台来电推送 | 发送 `type=incoming_call` 的 FCM data-only 高优先级消息 | 通过，显示 CallKit 来电通知，渠道 `callkit_incoming_channel_id`，有全屏 intent、接听/拒绝动作 |
| 来电超时 | 未接听，等待超时 | 通过，产生未接来电通知，渠道 `callkit_missed_channel_id` |
| 锁屏 + deep idle | 屏幕关闭并 `dumpsys deviceidle force-idle` 后发送高优先级消息 | 通过，系统状态 `mState=IDLE`，通知 `doze-lock` 到达，进程保持存在 |
| 后端实际发送 | 管理端接口 `/api/v1/admin/users/1/test-push` 触发后端 PushService | 通过，后端 FCM 发送当前设备成功，通知栏出现 `推送诊断` |
| 失效 token 清理 | 后端测试推送同时命中旧设备 token | 通过，旧 FCM token 返回 `UNREGISTERED` 后被后端清空 |
| 锁屏保活短测 | 锁屏后每 30 秒采样 3 分钟 | 通过，进程号稳定，后台服务和后台通知持续存在 |

## 关键证据

### FCM 发送成功

消息推送返回：

```text
projects/genericim-c7ffc/messages/0:1782102408526278%c0920637c0920637
```

普通杀进程后消息推送返回：

```text
projects/genericim-c7ffc/messages/0:1782102431006208%c0920637c0920637
```

锁屏 deep idle 后消息推送返回：

```text
projects/genericim-c7ffc/messages/0:1782102557059692%c0920637c0920637
```

来电推送返回：

```text
projects/genericim-c7ffc/messages/0:1782102493126415%c0920637f9fd7ecd
```

### Android 通知状态

后台消息通知：

```text
pkg=com.genericim.ma100
tag=FCM-Notification:6651675
channel=genericim_messages
android.title=FCM测试消息
android.text=通用IM Google 推送测试 am-kill
```

后台来电通知：

```text
pkg=com.genericim.ma100
channel=callkit_incoming_channel_id
category=call
android.title=FCM测试来电
fullscreenIntent=PendingIntent
actions=Decline / Answer
```

锁屏 deep idle 消息通知：

```text
mForceIdle=true
mScreenOn=false
mState=IDLE
android.title=FCM测试消息
android.text=通用IM Google 推送测试 doze-lock
```

### 后端发送状态

管理端测试推送返回：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "push_device_count": 3,
    "user_id": 1,
    "uuid": "10000000-0000-0000-0000-000000000001"
  }
}
```

后端日志：

```text
[Push][FCM] Sent push to device=026f5746-d2d5-4762-a0aa-3d4b8d7b361b
[Push] Removing invalid push token for device f1bde5f2-625d-425b-b114-a646a60e50f0 (channel=fcm)
```

当前设备表：

```text
id=139
user_id=1
device_id=026f5746-d2d5-4762-a0aa-3d4b8d7b361b
device_type=android
push_channel=fcm
push_token_len=142
```

### 强停边界

`force-stop` 后日志：

```text
Force stopping com.genericim.ma100
Killing com.genericim.ma100
isStopped true
broadcast intent callback: result=CANCELLED
```

结论：强停后 Firebase 服务端仍可接受发送请求，但 Android 不把消息投递给应用，直到用户手动打开应用。

### 保活采样

锁屏 3 分钟核心采样：

```text
2026-06-22 12:35:05 app_pid=9502 service=true notification=true state=INACTIVE
2026-06-22 12:35:36 app_pid=9502 service=true notification=true state=INACTIVE
2026-06-22 12:36:06 app_pid=9502 service=true notification=true state=INACTIVE
2026-06-22 12:36:36 app_pid=9502 service=true notification=true state=INACTIVE
2026-06-22 12:37:06 app_pid=9502 service=true notification=true state=INACTIVE
2026-06-22 12:37:37 app_pid=9502 service=true notification=true state=INACTIVE
2026-06-22 12:38:07 app_pid=9502 service=true notification=true state=INACTIVE
```

后台服务状态：

```text
id.flutter.flutter_background_service.BackgroundService
isForeground=true
foregroundId=888
foregroundNoti=Notification(channel=genericim_background)
```

## 发现的问题与处理

发现一个历史模拟器设备 token 已失效，FCM 返回 `UNREGISTERED`。后端已按预期自动清空该旧 token，不影响当前设备推送。

模拟器日志中出现：

```text
FirebaseMessaging: Unable to log event: analytics library is missing
```

这是 Firebase Analytics 未集成导致的埋点日志提示，不影响 FCM 收发。

## 保活时长判断

当前实现属于“前台服务 + FCM 高优先级 + 厂商通道补充”的稳态方案。模拟器上锁屏短测稳定，强制 Doze 下高优先级消息可达。

但不能承诺“无限保活”或“锁屏一定多少小时都在线”。影响因素包括：

- Android 原生强停机制；
- 厂商后台限制和省电策略；
- 用户是否关闭通知权限、后台运行权限、自启动权限；
- 电量、网络、Doze 配额、高优先级 FCM 额度；
- 是否被系统判定为异常耗电应用。

交付口径建议：

- 未强停、通知权限开启、网络正常：消息推送可稳定到达；
- 锁屏/Doze：高优先级消息可达，本轮模拟器验证通过；
- 强停应用：系统限制，必须用户重新打开后恢复；
- 真机长期保活：需要按品牌做 2 小时、8 小时、24 小时锁屏长测。

## 后续真机长测建议

建议至少覆盖以下机型：

| 品牌 | 测试重点 |
| --- | --- |
| 华为/Honor | HMS 离线推送、自启动、后台运行、电池优化 |
| 小米/Redmi | FCM/小米通道、神隐模式、省电策略 |
| OPPO/realme/OnePlus | 后台冻结、通知展示、来电全屏 |
| vivo/iQOO | 高耗电限制、后台弹窗、锁屏通知 |
| Google Pixel | 原生 Android/FCM 基准 |

建议测试窗口：

```text
T+5分钟：消息、来电、后台服务状态
T+30分钟：消息、来电、后台服务状态
T+2小时：消息、来电、后台服务状态
T+8小时：消息、来电、后台服务状态
T+24小时：消息、来电、后台服务状态
```

每轮记录：应用是否强停、屏幕是否锁定、通知权限、电池优化状态、进程是否存在、后台通知是否存在、消息推送是否到达、来电是否全屏/横幅展示。
