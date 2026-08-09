# P2 历史消息与 E2EE 跨设备恢复实施及真机测试报告

> 完成日期：2026-07-15
> 范围：历史消息查询边界、长期客户端消息幂等、可信旧设备 E2EE 身份迁移
> 结论：P2 前后端开发、后端接口验证、Android Release 构建及两台 Android 真机恢复链路均已通过。正式上线前仍需部署同版本后端，并完成其他平台回归与安全评审。

## 1. 本阶段交付结果

P2 将“完整恢复聊天”拆成三个可验证的服务端能力：

| 能力 | 本次结果 | 对外边界 |
| --- | --- | --- |
| 历史消息查询 | 所有消息操作统一使用分表定位器，默认覆盖最近 120 个月，可配置 | 只能恢复服务端仍保留的数据，不承诺已删除、已过期或丢失的媒体 |
| 离线重发去重 | 增加跨月长期幂等账本，客户端同一 `chat_id + sender_id + msg_id` 重试返回原消息 ACK | 长期账本从部署后写入；部署前旧消息继续依赖兼容查询 |
| E2EE 跨设备恢复 | 新设备申请、可信旧设备批准、端到端加密迁移旧设备解密身份、新设备一次性消费 | 必须仍有可用旧设备；服务器不保存明文私钥 |

客户端通过 `GET /api/v1/message/recovery-capabilities` 读取真实能力并展示查询期限，不再使用“所有历史一定可恢复”的绝对表述。

## 2. 历史消息与保留策略

### 2.1 统一分表定位

- 新增统一消息存储策略，集中生成保留期内的 `messages_YYYYMM` 集合。
- 兼容旧 `messages` 集合。
- 消息列表、范围同步、搜索、撤回、编辑、删除、已读、送达、转发、媒体、文件、表情回应和统计等路径均复用同一定位逻辑。
- 修复撤回查询缺少 `chat_id` 约束的问题。

### 2.2 配置

新增配置：

```yaml
message_storage:
  retention_months: 120
  idempotency_months: 120
```

可由以下环境变量覆盖：

- `GENERIC_IM_MESSAGE_RETENTION_MONTHS`
- `GENERIC_IM_MESSAGE_IDEMPOTENCY_MONTHS`

程序会保证幂等期限不短于消息查询期限。当前默认值 120 个月是产品查询边界，不代表数据库可以无限保留数据；生产环境仍需同步制定备份、归档、媒体生命周期和合规删除策略。

## 3. 长期客户端消息幂等

新增 MongoDB 集合 `message_idempotency`：

- 唯一键：`chat_id + sender_id + msg_id`；
- TTL 字段：`expires_at`；
- 状态：`pending`、`completed`；
- 支持发送中断后的租约接管和结果恢复；
- 重复发送返回原服务端序号并标记 `duplicate=true`；
- 删除会话全部消息时同步删除对应幂等记录。

真机所用本地后端已确认存在以下索引：

- `uniq_chat_sender_client_msg`
- `ttl_message_idempotency`

接口验证中，同一 `msg_id` 连续发送两次得到相同 `server_seq=1776`，第二次返回重复 ACK。

## 4. E2EE 可信设备恢复

### 4.1 安全模型

恢复过程如下：

1. 新设备生成一次性 RSA-OAEP 迁移密钥并创建恢复请求；
2. 旧设备核对新设备后批准；
3. 旧设备将自己的设备 ID、公钥 JWK 和私钥 JWK 封装，并使用新设备的一次性公钥加密；
4. 服务端只保存和转发不透明密文包；
5. 新设备解密、校验账号、密钥对及指纹后写入安全存储；
6. 本地持久化成功后才消费服务端请求；
7. 服务端将请求标为 `consumed` 并清空加密包；
8. 解密历史消息时，若当前设备信封不匹配，则按消息信封中的旧设备 ID 查找已恢复身份。

设备密钥增加指纹和版本号；相同公钥重复注册不会无意义增加版本。另增加当前设备密钥撤销接口。

### 4.2 接口

- `POST /api/v1/user/e2ee/recovery/requests`
- `GET /api/v1/user/e2ee/recovery/requests`
- `POST /api/v1/user/e2ee/recovery/requests/:id/approve`
- `POST /api/v1/user/e2ee/recovery/requests/:id/consume`
- `DELETE /api/v1/user/e2ee/recovery/requests/:id`
- `DELETE /api/v1/user/e2ee/device-key`

### 4.3 明确不可恢复场景

以下情况仍不能恢复旧密文：

- 没有任何仍持有旧私钥的设备；
- 没有预先建立的密钥备份；
- 旧密钥已重置或已丢失；
- 对应密文、消息密钥信封或服务端消息已被删除；
- 阅后即焚、合规删除等业务规则已使内容不可用。

本方案不把明文私钥上传服务端，也没有实现“忘记密码后由服务器找回私钥”的云备份模型。

## 5. 自动化验证

执行并通过：

```powershell
cd backend
go test ./...

cd ..
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat test
git diff --check
```

结果：

- Go 全量测试：通过；
- `flutter analyze`：通过，0 个问题；
- Flutter 全量测试：84/84 通过；
- `git diff --check`：通过，仅有工作区既有换行符提示；
- 本地后端能力接口、重复消息 ACK、恢复请求创建/批准/消费/撤销：通过。

后端验证证据：`artifacts/p2-local-backend/api-validation.json`。

## 6. Android 双真机恢复验证

设备：

| 角色 | 设备 ID | 型号 | 系统 |
| --- | --- | --- | --- |
| 可信旧设备 | `8MY0220C17006781` | HUAWEI ELS-AN00 | Android 12 / API 31 |
| 新设备 | `UQG5T20915006269` | HUAWEI ELS-AN00 | Android 12 / API 31 |

两台设备使用 `adb install -r` 覆盖安装，保留登录态和 Android 安全存储，并通过 `adb reverse` 连接本地 P2 后端。

验证链路：

1. 新设备从 UI 发出恢复请求；
2. 旧设备从 UI 核对并批准；
3. 新设备解密恢复包并导入旧设备身份；
4. 自动化强制结束应用进程并重新启动；
5. 重启后已批准请求不再出现；
6. MySQL 请求状态为 `consumed`，`encrypted_payload` 长度为 0；
7. 两台设备日志未发现 `FATAL EXCEPTION`、ANR、`IsarError`、`Unhandled Exception`。

最终请求 ID：`b00ffe14-9c59-44df-b21a-8a40f462da9b`。

证据目录：

- `artifacts/p2-device-smoke-20260714/e2ee-recovery-final/UQG5T20915006269-Request`
- `artifacts/p2-device-smoke-20260714/e2ee-recovery-final/8MY0220C17006781-Approve`
- `artifacts/p2-device-smoke-20260714/e2ee-recovery-final/UQG5T20915006269-Import`

期间发现并修复了空恢复索引为不可变列表、首次导入调用 `removeWhere` 失败的问题；修复后重新构建 APK，并完整重跑三步链路通过。测试脚本同时改为使用“杀进程重启后请求消失”的稳定状态，不再依赖短暂 Snackbar。

本轮真机已验证恢复包的端到端加密、解包、安全存储写入、进程重启和一次性消费。由于测试账号没有预置专用的旧 E2EE 密文样本，本轮没有单独形成“恢复前不可读、恢复后可读”的历史消息截图对照；上线验收仍应补这一条业务级样本。

## 7. 构建产物

### 7.1 本地 P2 后端

- 文件：`artifacts/p2-local-backend/server-p2-20260714-224901`
- 大小：40,962,844 字节
- SHA256：`B33A546BD1BA215AC84A43A103FE3E2221E6B0FB642389D0E38DF10F46BE9BDA`
- 本地容器：`genericim-api`，健康检查通过，宿主端口 `18080`

### 7.2 线上 Android Release APK

- 文件：`artifacts/online-android-apk-20260715-105924/genericim-online-release.apk`
- 大小：138,023,690 字节
- SHA256：`FA6E0CF45B643698DE5ED107683B449E8E1C9D26B1A61E17DA5082D188343823`
- API：`https://api.example.com`
- WebSocket：`wss://api.example.com/api/v1/ws`

APK 构建通过。AGP 8.9.1、Kotlin 2.1.0 和 Built-in Kotlin 提示属于未来 Flutter 兼容性预警，不影响本次构建。

## 8. 上线条件与剩余验证

本次只把 P2 后端部署到本地 Docker 测试环境，**尚未部署到线上 `api.example.com`**。因此线上 APK 虽已包含 P2 客户端代码，但必须先部署同版本后端和数据库变更，才能开放恢复功能。

2026-07-15 复测确认，线上能力接口和恢复请求接口均返回 HTTP 404。客户端已增加显式能力门控：只有服务端返回 `e2ee_recovery_mode=trusted_device_rewrap` 时才允许创建恢复请求；旧服务端会显示“加密消息恢复暂不可用 / 当前服务器版本不支持，请先升级服务端”，点击不会再请求不存在的接口。两台 Android 真机连接线上后端复测均未出现原“请求的资源不存在”提示，证据位于 `artifacts/p2-device-smoke-20260715`。

正式发布前还需：

1. 备份生产 MySQL、MongoDB，并验证新增表、字段及索引；
2. 灰度部署后端，检查历史分表查询延迟和 MongoDB 索引构建影响；
3. 用专门旧密文样本完成“恢复前不可读、恢复后可读”验收；
4. 完成 iOS、macOS、Windows 和 Web 的功能及安全存储回归；
5. 对恢复请求冒用、设备丢失、重放、过期、并发批准和日志脱敏做安全评审；
6. 再发布本次线上 APK。

在这些条件完成前，产品文案应表述为“可恢复服务端保留期内的普通消息；E2EE 历史需可信旧设备批准”，不能表述为“任何情况下完整恢复所有聊天”。
