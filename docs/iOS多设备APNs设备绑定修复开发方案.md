# iOS 多设备 APNs 设备绑定修复开发方案

> 状态：已按当前代码复核并优化，可作为开发实施基线。
>
> 核心原则：不依赖 APNs token 长度判断有效性；设备身份、登录会话、推送绑定必须分别建模；任何解绑都不能扩大到其他设备或其他通道。

## 1. 目标与最终技术决策

当前故障不是“APNs token 为 64 个十六进制字符”，而是 iOS 设备身份可能随备份迁移，造成不同物理设备共享 `device_id`，进而发生 token 覆盖和登出误删。

本期采用以下固定决策，开发过程中不得混用另一套数据模型：

| 项目 | 本期决策 |
| --- | --- |
| iOS 物理设备 ID | 首选 IDFV；失败时使用 `ThisDeviceOnly` Keychain installation ID |
| JWT 中的设备 ID | 使用不带推送通道后缀的逻辑设备 ID |
| `user_devices.device_id` | 继续保存 `PushStorageDeviceID` 生成的存储设备 ID |
| APNs 普通通道 | 使用逻辑设备 ID 本身 |
| APNs VoIP | 使用 `<逻辑设备ID>:voip` |
| Android 厂商通道 | 继续使用 `<逻辑设备ID>:push:<channel>` |
| 设备行唯一键 | `(user_id, device_id)`，其中 `device_id` 是存储设备 ID |
| token 全局归属 | `(push_channel, push_token_hash)` 唯一 |
| 新会话迁移 | 为当前物理设备创建新身份，只迁移当前会话，不搬走旧设备记录 |
| 登出 | 将精确绑定随 `/auth/logout` 一次提交，先解绑再撤销当前会话 |
| 旧客户端 | Flutter/H5 上传接口兼容旧请求；危险的无请求体 DELETE 仅短期保留并通过版本治理退出 |

不采用 `(user_id, device_id, push_channel)` 作为 `user_devices` 唯一键。当前代码的登录、设备管理和 E2EE 路径大量按 `user_id + device_id` 查询；在继续保留通道后缀的前提下，三元组索引会允许同一存储设备 ID 出现多行，导致查询歧义和错误合并。

如果以后要彻底移除设备 ID 后缀，应另立 `user_device_push_bindings` 表，本期不同时进行该结构性重构。

## 2. 当前代码边界

| 能力 | 当前实现 | 本期处理 |
| --- | --- | --- |
| iOS 设备 ID | `DeviceService.getDeviceId()` 使用 SharedPreferences UUID | iOS 改为 IDFV/ThisDeviceOnly Keychain |
| 登录会话设备 ID | JWT 和 `user_sessions.device_id` 保存逻辑设备 ID | 增加当前会话身份迁移 |
| token 上传 | 按 `user_id + PushStorageDeviceID(deviceID, channel)` 查询并覆盖 | 增加 hash、事务抢占和请求设备校验 |
| Flutter 登出 | 无请求体 `DELETE /user/push-token`，之后直接清本地登录态 | 改为 `/auth/logout` 携带精确 bindings |
| H5 登出 | 并发执行无请求体 DELETE、WebPush 退订和 `/auth/logout` | 先保存当前 subscription，再由 `/auth/logout` 精确解绑和撤销会话 |
| 服务端登出 | 当前只撤销会话，不处理精确推送绑定 | 同一请求内先精确解绑再撤销当前会话 |
| token 删除 | 按 `PushStorageDeviceIDs(deviceID)` 批量清理 | 新链路只允许用户、存储设备、通道、hash、原 token 全匹配 |
| 永久失效清理 | 按设备行 `id` 清空 token | 增加发送快照条件，避免清掉刚刷新的 token |
| 管理端清理 | 多处仅清 `push_token` | 所有清理入口统一同时清 token、hash 和更新时间 |
| 多设备发送 | 查询用户全部有效 token，按通道/token 去重 | 保留并增加多设备回归测试 |

主要涉及：

- `lib/core/services/device_service.dart`
- `lib/core/services/push_notification_service.dart`
- `lib/core/services/api/auth_service.dart`
- `backend/internal/handlers/auth_handler.go`
- `backend/internal/handlers/user_handler.go`
- `backend/internal/handlers/user_login_session.go`
- `backend/internal/handlers/push_admin_handler.go`
- `backend/internal/services/push_channel.go`
- `backend/internal/services/push_service.go`
- `backend/internal/models/user.go`
- `backend/baota/init.sql`
- `backend/scripts/init.sql`

## 3. 数据模型与数据库迁移

### 3.1 两种设备 ID 的定义

必须在代码和日志中区分：

```text
logicalDeviceID = ios:idfv:<IDFV>
storageDeviceID = PushStorageDeviceID(logicalDeviceID, pushChannel)
```

映射示例：

| 通道 | `user_devices.device_id` |
| --- | --- |
| APNs | `ios:idfv:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| APNs VoIP | `ios:idfv:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:voip` |
| FCM | `<logicalDeviceID>:push:fcm` |
| HMS | `<logicalDeviceID>:push:hms` |

客户端只能提交逻辑设备 ID。存储设备 ID 必须由服务端通过 `PushStorageDeviceID` 生成，不能信任客户端提交的后缀。

### 3.2 目标字段和索引

`push_token_hash` 使用规范化 token 的 SHA-256 十六进制值。采用 ASCII 定长字段，避免直接索引最长可达 8192 字节的 WebPush 内容。

第一步只加字段并对齐类型，不立即创建唯一索引：

```sql
ALTER TABLE user_devices
  MODIFY COLUMN push_channel VARCHAR(20) NOT NULL DEFAULT '',
  MODIFY COLUMN push_token TEXT NULL,
  ADD COLUMN push_token_hash CHAR(64)
    CHARACTER SET ascii COLLATE ascii_bin NULL
    AFTER push_token;
```

历史数据修复完成后再增加：

```sql
ALTER TABLE user_devices
  ADD UNIQUE KEY uk_user_device (user_id, device_id),
  ADD UNIQUE KEY uk_push_channel_token_hash (push_channel, push_token_hash);
```

MySQL 唯一索引允许多个 `NULL`，未绑定 token 的设备行不会在 token 索引上冲突。`push_channel` 必须为非空字符串，避免三值逻辑导致数据核验失真。

以下位置必须同步，不允许只修改 GORM 模型：

- `backend/internal/models/user.go`
- `backend/baota/init.sql`
- `backend/scripts/init.sql`
- 线上增量迁移脚本
- 服务启动时的补列/补索引逻辑

### 3.3 token 规范化规则

hash 前必须按通道规范化，不能对原始字符串简单 `TrimSpace` 后一概计算：

- APNs/APNs VoIP：移除外围空白和可选尖括号；兼容历史格式时可移除中间分隔空白；转小写并验证为偶数长度十六进制，但不把长度硬编码为 64。
- FCM/HMS/JPush/小米/OPPO：仅移除首尾空白，保持大小写。
- WebPush：解析 `endpoint`、`keys.auth`、`keys.p256dh`，按固定字段顺序重新序列化后计算 hash。
- 空 token：`push_token = ''`、`push_token_hash = NULL`、`push_token_updated_at = NULL`。

服务端应只有一个公共函数负责规范化和计算 hash，上传、删除、迁移、失效清理和管理端工具全部复用。日志禁止输出完整 token 或完整 WebPush subscription。

### 3.4 历史数据迁移顺序

迁移必须由可测试、可重复执行的 Go 迁移程序或管理命令完成，不建议只依赖一段不可恢复的手写 SQL。

1. 备份 `user_devices`，记录总行数、有效 token 数和重复组数量。
2. 增加 hash 字段，将 `push_token` 改为 `TEXT`，将空通道规范化为 `''`。
3. 先通过 `NormalizePushChannel` 处理通道别名；无法识别的值输出审计清单并隔离，不允许猜测通道后继续建索引。
4. 使用幂等迁移函数规范化历史 storage device ID：已带正确 `:voip` 或 `:push:<channel>` 后缀的记录不能再次追加后缀，冲突记录进入异常清单。
5. 按 `(user_id, storage_device_id)` 合并重复设备行。
6. 合并时只选一个主行，保留更新时间最新的设备元数据；E2EE 公钥按自己的更新时间选择，不能被空值覆盖。
7. 对每条非空 token 规范化并分批回填 hash。
8. 对重复 `(push_channel, push_token_hash)`，按 `push_token_updated_at DESC、last_active DESC、id DESC` 确定唯一保留行；其他行清空三个推送字段，但不删除设备行。
9. 再次执行重复查询，结果为 0 后创建两个唯一索引。
10. 创建索引失败必须停止发布，不得临时忽略唯一约束继续运行。

合并历史设备行时不要复制或交换不同物理设备的 E2EE 公钥。无法证明属于同一物理设备的数据应进入人工核验清单并阻塞唯一索引上线，而不是自动拼接。

## 4. iOS 客户端改造

### 4.1 本机设备 ID

iOS 调用顺序：

1. 读取 `device_info_plus` 的 `identifierForVendor`。
2. 成功时生成 `ios:idfv:<lowercase-idfv>`。
3. IDFV 暂不可用时，读取 Keychain 键 `ios_installation_id_v1`。
4. Keychain 不存在时生成 UUID，并以 `KeychainAccessibility.first_unlock_this_device` 保存。
5. Keychain 兜底输出 `ios:install:<uuid>`。

不得继续把 iOS 主设备 ID 写入 SharedPreferences。SharedPreferences 中的旧 `app_device_id` 只作为迁移来源读取，迁移完成后可以删除。

`ThisDeviceOnly` 的目的，是确保 installation ID 不随 iCloud/整机备份迁移到另一台 iPhone。卸载同一 Vendor 的全部 App 后 IDFV 可能变化，此时按新安装处理。

Android、Windows、macOS 和 Web 本期保持原设备 ID 逻辑。所有设备 ID 都必须满足后端 `varchar(100)` 长度限制。

### 4.2 迁移检测

JWT 中仍包含旧 `device_id`。客户端不能只更换 `DeviceService.getDeviceId()` 的返回值后继续使用旧 JWT。

启动后按以下规则处理：

- 未登录：直接使用新 iOS 设备 ID进行后续登录。
- 已登录且 JWT/当前会话设备 ID 等于新 ID：无需迁移。
- 已登录且旧 ID 与新 ID 不同：进入一次性迁移流程。
- 迁移接口不可用或失败：保留旧状态并重试；超过受控次数后清除登录态，要求用新设备 ID重新登录。
- 禁止在旧 JWT 仍生效时静默切换本地设备 ID。

迁移完成标记只能在新 JWT 原子写入成功后保存。即使 SharedPreferences 中的标记随备份迁移，客户端每次仍必须重新读取本机 IDFV，不能只看标记跳过校验。

### 4.3 当前会话身份迁移

新增：

```http
POST /api/v1/user/device-identity/migrate
Authorization: Bearer <old-token>
Content-Type: application/json

{
  "new_device_id": "ios:idfv:...",
  "device_type": "ios",
  "device_name": "iPhone ..."
}
```

服务端从旧 JWT 和当前原始 Bearer token 得到迁移来源，不接受客户端提交 `old_device_id`。

`new_device_id` 必须满足 iOS 允许的前缀、UUID 格式和 `varchar(100)` 长度限制，并拒绝 `:voip`、`:push:*` 等服务端保留后缀。接口按用户和当前 session 限流，记录迁移审计，但日志不得包含 JWT。

同一备份可能使 A、B 两台手机共享旧设备 ID，因此迁移必须遵守：

1. 客户端先暂停自动重连并主动断开 WebSocket，防止迁移过程中继续以旧设备 ID 建立实时连接。
2. 服务端按 `user_id + raw bearer token` 锁定当前 `user_sessions` 行，同时锁定可能已存在的 `user_id + new device ID` 会话。
3. 校验会话中的设备 ID 与 JWT 旧设备 ID 一致。
4. 为新 ID 创建或更新新的 `user_devices` 基础行，只写设备类型、名称、IP、`last_active` 等安全元数据。
5. 不重命名、不删除旧 `user_devices` 行。
6. 不复制旧设备的 push token、token hash、E2EE 公钥或 E2EE 更新时间。
7. 只按 `user_id + raw bearer token + old device ID` 更新当前 `user_sessions` 行，不能批量更新同旧设备 ID 的其他会话。
8. 签发包含新设备 ID 的 JWT，保留原 `session_version`，并在数据库中原子替换当前 session token。
9. 只精确撤销当前旧 JWT；严禁调用设备级失效或全账号 session version 变更逻辑。
10. 返回新 JWT 后，客户端原子替换本地 token，再重连 WebSocket、生成/注册新设备自己的 E2EE 密钥并上传 APNs bindings。

重复调用迁移接口应幂等：新设备基础行已存在时只刷新安全元数据，不得重新触碰旧设备行。

若新设备 ID 已存在另一条不同 raw token 的活动会话，不得静默合并或批量撤销；返回 `device_identity_conflict`，让客户端重新登录并走现有同设备会话收敛逻辑。

迁移事务、session token 替换或旧 JWT 精确撤销任一步失败，都不得返回迁移成功。若现有 JWT 撤销存储无法与数据库共用事务，应增加 pending 状态或事务 outbox 保证可恢复；客户端在受控重试后仍失败时退回重新登录，不能带着半迁移状态继续运行。

### 4.4 token 上传与刷新

新客户端上传：

```json
{
  "device_id": "ios:idfv:...",
  "push_token": "<apns-token>",
  "device_type": "ios",
  "push_channel": "apns",
  "app_version": "5.0.0+25"
}
```

服务端兼容规则：

- 旧客户端未传 `device_id`：使用 JWT 中的逻辑设备 ID。
- 新客户端传了 `device_id`：必须与 JWT 逻辑设备 ID 完全一致。
- 不一致时返回稳定业务码 `device_identity_mismatch`，客户端只能先迁移设备身份或重新登录，不能自动改写请求值重试。
- 只有设备身份迁移接口可以改变 JWT 中的设备 ID。
- 服务端生成 storage device ID，客户端不得提交 `:voip` 或 `:push:*` 后缀。
- 保留当前 `registration_id`、`platform`、`push_provider` 等旧字段别名；无论使用哪个别名，通道规范化、token 规范化与 hash 都只能由服务端执行。

上传成功返回：

```json
{
  "binding_id": 123,
  "device_id": "ios:idfv:...",
  "push_channel": "apns",
  "updated_at": "2026-07-13T12:00:00Z"
}
```

客户端按通道保存最近一次成功 binding 的 ID、规范化前 token 和更新时间。APNs token refresh 回调继续调用同一上传接口，事务会释放当前行的旧 hash 并绑定新 token。

### 4.5 安全登出

当前 Flutter 只调用无请求体 `DELETE /user/push-token`，没有调用服务端 `/auth/logout`；H5 则并发执行无请求体 DELETE、WebPush 退订和 `/auth/logout`。本期必须把登出场景的推送解绑和会话撤销收口到一次认证请求中。

扩展现有接口：

```http
POST /api/v1/auth/logout
Authorization: Bearer <current-token>
Content-Type: application/json

{
  "push_bindings": [
    {
      "binding_id": 123,
      "device_id": "ios:idfv:...",
      "push_channel": "apns",
      "push_token": "<current-apns-token>"
    },
    {
      "binding_id": 124,
      "device_id": "ios:idfv:...",
      "push_channel": "apns_voip",
      "push_token": "<current-voip-token>"
    }
  ]
}
```

服务端在同一业务流程中：

1. 校验请求逻辑设备 ID 等于 JWT 设备 ID。
2. 按通道生成 storage device ID 并计算请求 token hash。
3. 精确清理匹配的 bindings。
4. 提交解绑后，撤销当前 raw JWT 和当前 `user_sessions` 行。
5. 不调用按设备 ID 批量撤销其他会话的逻辑。
6. `binding_id` 可选；存在时增加 ID 条件，不存在时仍以用户、storage device ID、通道、hash 和规范化原 token 五项精确匹配。
7. 单条 binding 未匹配按幂等成功返回，并报告 `cleared: false`。

客户端必须先发服务端 logout，再清理本地 token、APNs 状态和缓存。网络失败时仍可为了本地安全退出，但必须记录诊断事件；不能退回按 device ID 批量删除。

通知设置中“仅关闭当前通道”不走 logout，使用不依赖 DELETE 请求体的接口：

```http
POST /api/v1/user/push-token/unbind
Authorization: Bearer <current-token>
Content-Type: application/json

{
  "binding_id": 123,
  "device_id": "ios:idfv:...",
  "push_channel": "apns",
  "push_token": "<current-apns-token>"
}
```

现有 `POST /api/v1/user/devices/unbind-push` 可在兼容期作为同一处理器的别名。新协议不使用 DELETE 请求体，旧 `DELETE /user/push-token` 只识别为无请求体旧协议，避免客户端或代理丢弃 DELETE body 后意外落入宽泛删除。

H5 必须先读取并保存当前 WebPush subscription 及 binding 信息，再请求精确解绑或带 bindings 的 logout，成功后才调用浏览器 unsubscribe；不能继续三项并发，否则退订后可能拿不到用于精确匹配的 token。

## 5. 服务端绑定与清理实现

### 5.1 上传事务

`UpdatePushToken` 在短事务中执行：

1. 解析 JWT 逻辑设备 ID，并兼容/校验请求设备 ID。
2. 规范化通道和 token，生成 hash 与 storage device ID。
3. `SELECT ... FOR UPDATE` 锁定目标设备行和已存在的 token 归属行。
4. 清空同一 `push_channel + push_token_hash` 在其他用户或其他存储设备上的三个推送字段。
5. 按 `(user_id, storage_device_id)` 更新或创建目标行。
6. 同时写 token、hash、通道、设备元数据、更新时间和 `last_active`。
7. 提交并返回 binding ID。

唯一索引负责两个并发请求抢占同一 token 时的最终互斥。若插入发生唯一键冲突，重新读取归属并在完整事务中最多重试一次，不能在事务外先清后写。

伪代码：

```go
err := db.Transaction(func(tx *gorm.DB) error {
    existing := lockBindingByChannelAndHash(tx, channel, tokenHash)
    clearOtherOwner(tx, existing, user.ID, storageDeviceID)
    return upsertStorageBinding(
        tx,
        user.ID,
        storageDeviceID,
        channel,
        normalizedToken,
        tokenHash,
        metadata,
    )
})
```

### 5.2 精确解绑条件

所有用户侧精确解绑最终必须包含：

```sql
WHERE user_id = ?
  AND device_id = ?
  AND push_channel = ?
  AND push_token_hash = ?
  AND push_token = ?
```

请求带 `binding_id` 时再追加 `AND id = ?`。不能只凭 binding ID、device ID 或 channel 其中任一项删除。

`binding_id` 用于定位，其他字段用于防止绑定在请求途中刷新或转移后被旧请求误删。更新内容统一为：

```text
push_token = ''
push_token_hash = NULL
push_token_updated_at = NULL
```

匹配 0 行仍返回成功，但必须给出逐条结果用于诊断。

### 5.3 永久失效 token 的快照保护

发送前保存 `id + channel + hash + token` 快照。只有 APNs 明确返回 `Unregistered`、`BadDeviceToken`、`DeviceTokenNotForTopic` 等永久错误时，才按完整快照条件清理。

超时、网络错误、证书错误、APNs 5xx 和限流不能清 token。发送期间如果 token 已刷新，旧回包匹配 0 行，不得清除新 token。

### 5.4 统一清理入口

下列入口都必须调用同一个快照清理函数，不能各自只更新 `push_token`：

- 用户精确解绑
- `/auth/logout` bindings 清理
- APNs/FCM/HMS 等永久失效处理
- 管理端单条停用
- 管理端批量清理
- 历史数据迁移

删除整条设备行时不需要额外清 hash，但必须确认该操作的权限和设备范围本身正确。

旧逻辑设备行不能在身份迁移时删除。只有在确认没有任何活动 session 引用、所有通道 token 均为空、超过配置的保留期且不再承载待兼容 E2EE 数据后，后台任务才可将其标记失效或清理；该任务同样不能按旧 device ID 批量影响仍在线设备。

### 5.5 多设备发送

保留按用户查询全部有效 token 的逻辑：

- 去重键为 `push_channel + normalized token`，不能只按 device ID。
- 一条设备发送失败不得中断其他设备。
- 兼容阶段允许发送 `hash IS NULL` 的历史有效 token；回填完成后应监控并逐步要求非空 hash。
- APNs 与 APNs VoIP 必须分别选择 topic 和 push type。

## 6. 接口清单

| 接口 | 调整 | 兼容性 |
| --- | --- | --- |
| `POST /user/device-identity/migrate` | 迁移当前会话到新 iOS 设备 ID 并换发 JWT | 新增 |
| `POST /user/push-token` | 可选接收 device_id；事务抢占并返回 binding ID | 兼容旧请求 |
| `POST /user/push-token/unbind` | 接收单条完整 binding，执行精确幂等解绑 | 新增；`POST /user/devices/unbind-push` 可作兼容别名 |
| `DELETE /user/push-token` | 不再扩展语义，不接收新协议请求体 | 旧无请求体模式进入废弃流程 |
| `POST /auth/logout` | 可选接收 `push_bindings`，先精确解绑再撤销当前会话 | 空请求体继续兼容旧客户端 |
| 管理端设备诊断 | 展示 binding ID、掩码、通道、更新时间和 hash 短前缀 | 禁止返回完整 token |

## 7. 旧客户端兼容与发布顺序

旧客户端的无请求体 DELETE 不包含 token 和通道，不存在既能精确解绑、又能保证不误删共享设备 ID 的安全算法。方案必须承认这一限制，不能伪造“安全兼容分支”。

### 阶段 A：数据库和兼容服务端

1. 增加字段并统一 `push_token TEXT`。
2. 服务端上传接口开始兼容式双写 hash；缺少 device_id 时使用 JWT 值。
3. 增加身份迁移、POST 精确解绑和带 bindings 的 `/auth/logout`。
4. 增加所有自动化测试，但暂不关闭旧 DELETE。
5. 统计旧 DELETE 的客户端类型、app/H5 版本、平台和调用量。

### 阶段 B：数据治理与唯一索引

1. 小批量执行历史规范化、重复设备合并和 token hash 回填。
2. 两类重复查询持续为 0。
3. 在低峰期创建唯一索引并验证写入事务。
4. 打开 token 抢占事务和快照清理。

### 阶段 C：客户端协议升级

1. Flutter iOS 发布 IDFV/ThisDeviceOnly Keychain 设备 ID。
2. Flutter iOS 执行当前会话身份迁移并原子替换 JWT。
3. Flutter 全平台上传 bindings 并保存 binding ID，登出改用携带 bindings 的 `/auth/logout`。
4. H5 保存 WebPush binding，在退订前调用精确 unbind 或带 bindings 的 `/auth/logout`。
5. 验证 APNs/厂商 token refresh、WebPush 退订和切换账号后的重新归属。

### 阶段 D：结束危险兼容

1. 对 Flutter 各平台设置支持新登出协议的最低版本并执行版本治理。
2. 发布新版 H5，处理 CDN/Service Worker 缓存，并确认旧资源版本自然过期或被强制刷新。
3. 确认旧 DELETE 调用量降至可接受阈值。
4. 将旧无请求体 DELETE 改为非破坏性 `upgrade_required`，随后移除危险批量清理代码。
5. 永远不要在回滚时恢复 `PushStorageDeviceIDs(deviceID)` 批量清 token。

阶段 A 到 D 之间，旧 DELETE 的既有误删风险仍然存在，只能通过缩短灰度窗口、监控和强制升级降低，不能宣称已经完全修复。

## 8. 测试矩阵

### 8.1 数据迁移测试

- 相同 `(user_id, storage_device_id)` 多行可确定性合并。
- 不同 E2EE 公钥不会被无条件复制到新物理设备。
- WebPush 8192 字节内容可完整保存并稳定计算 hash。
- 相同 WebPush JSON 不同字段顺序产生同一 hash。
- 重复 channel/hash 只保留更新时间最新的有效绑定。
- 迁移重复执行结果一致。
- 任一步失败可回滚，唯一索引不会在脏数据上强建。

### 8.2 后端绑定测试

- 旧客户端不传 device_id：使用 JWT 设备 ID 并成功绑定。
- 新客户端 device_id 与 JWT 一致：成功。
- 新客户端 device_id 与 JWT 不一致：返回 `device_identity_mismatch`。
- `registration_id` 等旧字段仍能上传，但服务端生成相同规范化 token/hash。
- 同账号两个 iOS 设备和两个 token：保留两条绑定并分别发送。
- 同 token 从账号 A 转绑 B：A 清空，B 成功。
- 同 token 从设备 A 转绑 B：最终只由 B 持有。
- 并发抢占同一 token：最终只有一个有效归属。
- 登录 upsert 与 push upload 并发：不会产生同一存储设备 ID 重复行。

### 8.3 会话迁移测试

- A、B 共享旧 device ID，B 迁移后 A 的设备行、JWT、session 和 push token 均不变。
- B 只更新当前 raw token 对应的 `user_sessions` 行。
- 迁移不会触发旧 device ID 的设备级会话失效标记。
- 迁移不会复制 A 的 E2EE 公钥和 push token。
- 迁移重复调用幂等。
- 新 JWT 写入失败时客户端仍保留可恢复的旧登录态。

### 8.4 登出与失效测试

- A 登出提交完整 binding：只清 A，B 不变。
- A 使用旧 token 登出：匹配 0 行，A 的新 token 不被清。
- `/auth/logout` 只撤销当前 raw JWT，不终止共享旧 device ID 的其他会话。
- APNs 与 VoIP 两条 binding 可分别删除。
- 发送旧 token 期间上传新 token：旧 token 失效回包不能清新 token。
- APNs 永久错误只清当前快照。
- APNs 5xx、超时和限流不清 token。
- 管理端停用和批量清理同时清 token、hash 和更新时间。
- Flutter 与 H5 新版均不再发送无请求体 DELETE。
- H5 在读取 binding 后执行服务端解绑，再执行浏览器 WebPush unsubscribe。
- 旧无请求体 DELETE 切换为 `upgrade_required` 后不会修改任何 binding。

### 8.5 iOS 真机

至少使用两台 iPhone，模拟器不能替代 APNs 验收。

| 场景 | 预期 |
| --- | --- |
| 同账号在 A、B 登录 | logical device ID 不同，两台均可收推送 |
| B 从 A 的整机备份恢复 | B 使用本机 IDFV，不复用 A 的旧 UUID |
| B 执行旧会话迁移 | 只迁移 B 当前 session，A 不掉线 |
| A 登出、B 保持登录 | A 停止接收，B 继续接收 |
| B 切换账号 | token 转绑新账号，旧账号其他设备不受影响 |
| APNs token refresh | 只更新当前设备当前通道 |
| 卸载重装 | 作为新安装绑定，不覆盖其他设备 |
| APNs 与 VoIP 同时启用 | 两通道独立绑定、删除和失效处理 |
| 两台设备 E2EE | 各自生成并保留独立设备公钥 |

### 8.6 数据核验

```sql
SELECT user_id, device_id, COUNT(*) AS cnt
FROM user_devices
GROUP BY user_id, device_id
HAVING COUNT(*) > 1;

SELECT push_channel, push_token_hash, COUNT(*) AS cnt
FROM user_devices
WHERE push_token_hash IS NOT NULL
GROUP BY push_channel, push_token_hash
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS inconsistent_token_hash
FROM user_devices
WHERE (COALESCE(push_token, '') = '' AND push_token_hash IS NOT NULL)
   OR (COALESCE(push_token, '') != '' AND push_token_hash IS NULL);
```

完成治理后，三条查询都应返回 0 个异常结果。

## 9. 监控、安全与回滚

建议增加：

- `push_token_bind_total{channel,result}`
- `push_token_rebind_total{channel,reason}`
- `push_token_delete_total{channel,matched,source}`
- `push_token_invalidated_total{channel,apns_reason}`
- `ios_device_identity_migrate_total{result}`
- `legacy_push_delete_total{platform,app_version}`
- `push_token_without_hash_total{channel}`
- 单用户有效 APNs 设备数分布

日志只能记录用户 ID、逻辑设备 ID、存储设备 ID、通道、binding ID、token 长度和短掩码。禁止记录完整 token、完整 WebPush subscription、JWT 或 E2EE 私钥。

回滚原则：

- 客户端迁移可通过远程开关暂停，并回退到要求重新登录。
- 新字段和 hash 双写可以保留，不需要立即删列。
- 唯一索引若暴露历史脏数据，先停相关写入并修数；不能长期移除 token 全局唯一约束。
- 不能恢复按设备 ID批量清 token。
- 已迁移到新设备 ID的会话不得自动改回旧 ID。

## 10. 完成标准

同时满足以下条件才可关闭问题：

- 两台由同一备份来源恢复的 iPhone 得到不同 logical device ID。
- B 的旧会话迁移不会修改、删除或失效 A 的设备记录和会话。
- 同账号多台 iPhone 各有独立 APNs bindings 并均可收推送。
- 任一设备登出、切换账号、刷新 token 或 token 失效均不影响其他设备。
- `user_devices` 不存在重复 `(user_id, storage_device_id)`。
- 同一通道/token hash 最多只有一个有效归属。
- 所有 token 清理入口同时清 token、hash 和更新时间。
- 旧无请求体 DELETE 已通过最低版本治理退出生产链路。
- Android 多通道、WebPush、APNs VoIP、设备管理、登录续期和 E2EE 均无回归。
- 两台 iPhone 的真实 APNs/VoIP 验收证据已归档。

满足以上条件后，才可认定“同一账号多台苹果设备推送不稳定”已完成修复。
