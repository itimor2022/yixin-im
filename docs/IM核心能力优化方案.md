# IM 核心能力优化方案

> 日期：2026-06-21  
> 范围：消息可靠性闭环、通知与多端同步、全局搜索  
> 目标：把现有 IM 从“功能可用”推进到“消息可信、状态一致、可搜索可定位”的成熟产品形态。

## 1. 总目标

当前系统已经具备聊天、WebSocket、消息同步、已读、推送、搜索、置顶、免打扰等基础能力。下一阶段不建议继续堆新功能，而应围绕三条主链路做可靠性闭环：

1. 消息可靠性闭环：每条消息有明确状态、可重试、可去重、可补偿、可追踪。
2. 通知与多端同步：未读数、已读、置顶、免打扰、删除/清空等会话状态在多端最终一致。
3. 全局搜索：联系人、会话、群/频道、聊天记录、文件、图片、链接统一搜索，支持从结果跳转定位。

## 2. 设计原则

- 服务端为准：消息序号、已读游标、未读数、会话状态最终以服务端为准。
- 客户端乐观展示：发送操作先本地显示“发送中”，服务端确认后替换为正式消息。
- 幂等优先：发送、重试、同步、已读、置顶、免打扰等操作都要支持重复提交不产生副作用。
- 增量同步：避免每次重连全量拉会话和消息，优先使用游标和序号增量补偿。
- 可观测：每条消息、每次推送、每次同步失败都要能定位原因。
- 分阶段交付：先补最核心的数据契约和状态，再优化体验和后台诊断。

## 3. 一期优先级

| 优先级 | 模块 | 目标 | 价值 |
| --- | --- | --- | --- |
| P0 | 消息发送状态 | 发送中、已入库、发送失败、可重试 | 用户知道消息是否真的发出 |
| P0 | 消息去重与乱序处理 | 按 client_msg_id/msg_id/seq 去重，按 seq 排序 | 防止重复消息、乱序消息 |
| P0 | 重连补偿同步 | WS 重连、App 唤醒、通知点击后补拉 | 防止漏消息 |
| P0 | 未读/已读多端一致 | last_read_seq 与 unread_count 跨端同步 | 会话列表可信 |
| P1 | 置顶/免打扰多端同步 | 会话状态跨端一致 | 多设备体验一致 |
| P1 | 全局搜索 MVP | 搜联系人、会话、消息、文件 | 消息多了之后仍可用 |
| P1 | 推送诊断 | 最近推送结果、失败原因、设备 token | 交付和运维可定位 |
| P2 | 搜索高亮与跳转定位 | 从搜索结果定位到消息上下文 | 提升专业度 |
| P2 | 后台可靠性看板 | 消息失败率、推送失败率、同步延迟 | 运营可观察 |

## 4. 消息可靠性闭环

### 4.1 当前问题要解决

1. 用户发消息后，只看到“发出去/失败”的粗粒度反馈，不足以区分本地排队、网络发送、服务端入库、对方已读。
2. 弱网、重连、重复点击、离线队列重发时，容易出现重复请求，需要强幂等。
3. WebSocket 实时消息和 HTTP 拉取消息可能同时到达，客户端必须去重。
4. 重连后需要补偿同步，不能只依赖 WS 在线期间的实时推送。
5. 消息列表需要按服务端 seq 排序，不能完全依赖客户端时间。

### 4.2 目标状态模型

客户端消息状态建议统一为：

| 状态 | 含义 | 用户可见 |
| --- | --- | --- |
| local_pending | 本地已生成，等待发送 | 显示发送中 |
| queued | 离线或网络不可用，进入本地队列 | 显示待发送 |
| sending | 正在请求服务端 | 显示发送中 |
| sent | 服务端已入库并返回 msg_id/seq | 显示已发送 |
| delivered | 至少一个接收方设备已收到 | 私聊可显示送达，群聊默认不展示 |
| read | 对方已读或群内读到指定游标 | 已读标记 |
| failed_retryable | 网络或临时错误，可重试 | 显示失败，可点重试 |
| failed_final | 权限、封禁、禁言、严格加密等最终失败 | 显示失败原因，不自动重试 |
| recalled | 已撤回 | 显示撤回提示 |
| deleted_local | 本地删除 | 当前端隐藏 |

服务端消息状态可以继续保持现有模型，但需要和客户端状态建立清晰映射。

### 4.3 数据契约

#### 4.3.1 发送消息请求

新增或确认字段：

```json
{
  "chat_id": "chat_uuid",
  "client_msg_id": "uuid-generated-by-client",
  "content_type": 1,
  "content": "hello",
  "reply_to_msg_id": "optional",
  "local_created_at": "2026-06-21T12:00:00Z",
  "device_id": "client-device-id"
}
```

要求：

- `client_msg_id` 必填，由客户端生成 UUID。
- 同一用户、同一设备、同一 `client_msg_id` 重复提交，服务端必须返回同一条已创建消息，不重复入库。
- 服务端响应必须返回 `msg_id`、`seq`、`server_created_at`、标准消息体。

#### 4.3.2 发送消息响应

```json
{
  "msg_id": "server-message-uuid",
  "client_msg_id": "client-message-uuid",
  "chat_id": "chat_uuid",
  "seq": 12345,
  "sender_id": "user_uuid",
  "content_type": 1,
  "content": "hello",
  "status": "sent",
  "server_created_at": "2026-06-21T12:00:01Z"
}
```

#### 4.3.3 同步消息接口

建议接口：

```http
GET /api/v1/message/sync?chat_id={chat_id}&after_seq={last_seq}&limit=100
```

返回：

```json
{
  "chat_id": "chat_uuid",
  "from_seq": 100,
  "to_seq": 156,
  "has_more": false,
  "messages": [],
  "server_time": "2026-06-21T12:00:00Z"
}
```

要求：

- `after_seq` 表示只拉取 seq 大于该值的消息。
- 客户端按 chat_id 保存 `last_synced_seq`。
- 如果服务端检测到 seq 缺口，客户端可触发窗口补拉。

### 4.4 客户端去重策略

客户端消息合并 key 优先级：

1. `msg_id`
2. `client_msg_id`
3. `chat_id + seq`

处理规则：

- HTTP 发送响应回来时，如果本地已有同 `client_msg_id` 的 pending 消息，直接替换为服务端消息。
- WS 收到消息时，如果本地已有同 `msg_id` 或 `client_msg_id`，只更新状态和 seq，不追加新气泡。
- 同步接口拉到历史消息时，按 `chat_id + seq` 去重。
- 同一会话消息展示按 `seq ASC`，本地 pending 消息没有 seq 时排在末尾。

### 4.5 乱序处理

客户端每个会话维护：

| 字段 | 说明 |
| --- | --- |
| last_synced_seq | 已完整同步到的最大 seq |
| max_seen_seq | 本地见过的最大 seq |
| missing_ranges | 发现缺口后的待补偿区间 |

处理规则：

- 收到 seq = 105，但本地 max_seen_seq = 102，说明 103-104 可能缺失，加入 `missing_ranges`。
- UI 可以先展示 105，但后台要补拉 103-104。
- 补拉完成后清理缺口。
- 如果补拉返回空且服务端确认无消息，则更新游标，避免无限补拉。

### 4.6 重试策略

| 错误类型 | 是否自动重试 | 用户操作 |
| --- | --- | --- |
| 网络超时 | 是，指数退避 | 可手动重试 |
| 服务器 5xx | 是，最多 3 次 | 可手动重试 |
| 401/登录失效 | 否 | 引导重新登录 |
| 被禁言/无权限 | 否 | 显示最终失败原因 |
| 文件上传失败 | 是，重试上传或复用已上传 URL | 可手动重试 |
| 严格加密失败 | 否 | 展示处理建议 |

指数退避建议：

- 第 1 次：2 秒
- 第 2 次：5 秒
- 第 3 次：15 秒
- 超过次数转 `failed_retryable`

### 4.7 前端改造点

涉及目录：

- `lib/features/chat/providers/message_provider.dart`
- `lib/features/chat/pages/chat_detail_message_list.dart`
- `lib/features/chat/widgets/message_bubble.dart`
- `lib/core/services/offline_message_queue.dart`
- `lib/core/services/api/chat_service.dart`
- `lib/core/services/api/websocket_service.dart`

任务清单：

1. 统一消息状态枚举和 UI 映射。
2. 发送前生成 `client_msg_id`。
3. Pending 消息先入本地列表。
4. HTTP 响应/WS 消息/同步消息走同一 merge 方法。
5. 重试时复用原 `client_msg_id`。
6. 离线队列持久化 `client_msg_id`、chat_id、内容、附件上传状态、retry_count。
7. 消息列表按 seq 排序，pending 消息特殊处理。
8. 发送失败气泡增加“重试/查看原因”入口。

### 4.8 后端改造点

涉及目录：

- `backend/internal/handlers/message_handler.go`
- `backend/internal/services/message_service.go`
- `backend/internal/models/chat.go`
- `backend/internal/ws/`
- `backend/internal/mq/`

任务清单：

1. 消息表/集合增加或确认 `client_msg_id` 唯一约束。
2. 发送接口按 `sender_id + device_id + client_msg_id` 幂等。
3. 服务端响应统一返回标准消息体。
4. WS 推送给发送者其他设备，也推送给发送设备用于状态确认时要保证客户端可去重。
5. 增加按 `after_seq` 的增量同步接口。
6. 发送失败的业务错误要有稳定错误码，便于客户端判断是否可重试。

### 4.9 验收标准

必须通过以下场景：

1. 断网发送 3 条消息，恢复网络后自动按顺序发送，不重复。
2. 连续点击发送同一条消息，不产生重复服务端消息。
3. HTTP 响应和 WS 同时到达，不出现重复气泡。
4. App 后台 10 分钟后回到前台，漏掉的消息能自动补齐。
5. 弱网下发送失败显示可重试，重试后原气泡变为成功。
6. 被禁言时消息不自动重试，显示明确原因。
7. 消息撤回、编辑、反应事件重复到达时，UI 状态不抖动、不重复。

## 5. 通知与多端同步

### 5.1 当前问题要解决

1. 多端同时在线时，已读、未读、置顶、免打扰可能因为本地状态差异而不一致。
2. 离线推送只说明“有消息”，但打开 App 后必须补拉真实消息，不能只依赖通知内容。
3. 用户关闭通知、未上传 token、厂商推送失败时，需要后台可诊断。
4. 会话状态操作要幂等，重复点击或多端同时操作时最终一致。

### 5.2 会话状态同步模型

每个用户对每个会话维护 `user_chat_state`：

| 字段 | 说明 |
| --- | --- |
| user_id | 用户 |
| chat_id | 会话 |
| last_read_seq | 已读到的最大消息 seq |
| unread_count | 服务端计算或缓存的未读数 |
| is_pinned | 是否置顶 |
| pinned_at | 置顶时间，用于排序 |
| is_muted | 是否免打扰 |
| mute_until | 可选，免打扰到期时间 |
| is_archived | 是否归档 |
| is_hidden | 是否从列表隐藏 |
| mark_unread | 用户主动标记未读 |
| draft | 草稿，可 P2 |
| updated_at | 状态更新时间 |
| state_version | 状态版本号 |

### 5.3 同步事件

WebSocket 事件建议统一：

```json
{
  "type": "chat_state.changed",
  "event_id": "uuid",
  "chat_id": "chat_uuid",
  "user_id": "user_uuid",
  "state_version": 42,
  "changes": {
    "last_read_seq": 123,
    "unread_count": 0,
    "is_pinned": true,
    "is_muted": false
  },
  "server_time": "2026-06-21T12:00:00Z"
}
```

要求：

- 所有会话状态操作返回最新 `state_version`。
- 客户端收到旧版本事件时丢弃。
- 当前设备操作成功后，也应通过同一状态 merge 逻辑更新。

### 5.4 未读与已读

规则：

- 服务端按 `last_read_seq` 计算未读。
- 客户端进入会话时，发送 `last_read_seq = max_visible_seq`。
- 只允许 `last_read_seq` 单调递增，不能回退。
- `mark_unread` 是额外用户标记，不应修改 `last_read_seq`。
- 多端已读同步后，其他设备会话列表未读数应清零或更新。

接口建议：

```http
POST /api/v1/message/read
{
  "chat_id": "chat_uuid",
  "last_read_seq": 123,
  "device_id": "device-id"
}
```

### 5.5 置顶/免打扰/隐藏同步

接口建议：

```http
PUT /api/v1/chat/{chat_id}/state
{
  "is_pinned": true,
  "is_muted": false,
  "is_hidden": false,
  "mark_unread": false
}
```

要求：

- 每次更新只提交变更字段。
- 服务端合并后返回完整状态。
- WS 广播给该用户所有设备。
- 会话列表排序用服务端状态，不用纯本地状态。

### 5.6 推送链路

推送不承担最终同步，只负责唤醒和提醒：

1. 新消息入库。
2. WS 推送在线设备。
3. 对离线或后台设备进入推送队列。
4. 推送服务根据设备 token、平台、免打扰、通知预览策略发送。
5. App 被打开或通知点击后，立即触发增量同步。

推送数据建议：

```json
{
  "type": "new_message",
  "chat_id": "chat_uuid",
  "msg_id": "message_uuid",
  "seq": 123,
  "badge": 8,
  "preview": "message preview"
}
```

### 5.7 推送诊断

后台用户诊断页应展示：

| 项 | 说明 |
| --- | --- |
| 最近登录设备 | device_id、平台、App 版本、最后在线 |
| 推送 token | 是否存在、渠道、更新时间 |
| 最近推送结果 | 成功/失败、通道、错误原因 |
| 用户通知设置 | 是否关闭消息预览、是否免打扰 |
| 测试推送 | 后台一键发送测试通知 |

### 5.8 前端改造点

涉及目录：

- `lib/features/chat/providers/chat_provider.dart`
- `lib/features/chat/pages/chat_page.dart`
- `lib/features/chat/pages/chat_detail_page.dart`
- `lib/core/services/api/websocket_service.dart`
- `lib/core/services/push_notification_service.dart`
- `lib/core/services/background_service.dart`
- `lib/features/settings/pages/notification_settings_page.dart`

任务清单：

1. 会话状态统一走 `ChatStateSync` merge 逻辑。
2. 已读回执、置顶、免打扰、标记未读操作都使用服务端返回结果更新。
3. WS `chat_state.changed` 事件统一处理。
4. App resumed、WS reconnected、notification opened 时触发会话状态与消息增量同步。
5. 通知权限关闭时，在通知设置页给明确入口。
6. 会话列表状态错误时显示可重试提示。

### 5.9 后端改造点

涉及目录：

- `backend/internal/handlers/chat_handler.go`
- `backend/internal/handlers/message_handler.go`
- `backend/internal/services/message_service.go`
- `backend/internal/services/push_service.go`
- `backend/internal/ws/`

任务清单：

1. 建立或梳理 `user_chat_state` 的唯一数据源。
2. 已读接口只允许游标递增。
3. 置顶/免打扰/隐藏/标记未读支持局部更新与版本号。
4. 所有状态变更广播到用户所有设备。
5. 推送发送前读取免打扰和预览设置。
6. 推送投递记录落库，支持后台查询。

### 5.10 验收标准

1. A 用户手机和 Windows 同时登录，手机读完消息，Windows 未读数 3 秒内清零。
2. Windows 置顶某会话，手机会话列表同步置顶。
3. 手机设置免打扰，Windows 同步显示免打扰。
4. 用户处于免打扰会话时，新消息不弹系统通知，但会话列表未读数正确。
5. App 被系统回收后，收到推送并点击打开，消息补齐且未读数正确。
6. 删除/隐藏会话后，其他端同步移除或隐藏。
7. 后台可看到设备 token 和最近一次推送失败原因。

## 6. 全局搜索

### 6.1 当前问题要解决

1. 搜索入口分散：联系人搜索、会话内搜索、管理端消息搜索各自独立。
2. 用户需要一个统一入口搜索用户、群、频道、消息、文件、图片、链接。
3. 搜索结果需要可跳转到对应会话和消息上下文。
4. 大量消息时，不能靠客户端全量遍历。

### 6.2 搜索范围

MVP 范围：

| 类型 | 内容 | 优先级 |
| --- | --- | --- |
| contacts | 联系人昵称、用户名、备注、手机号可见字段 | P0 |
| chats | 会话名称、群名、频道名 | P0 |
| messages | 文本消息、文件名、链接标题 | P0 |
| files | 文件名、类型、发送人、会话 | P1 |
| media | 图片/视频备注、文件名、发送人 | P1 |
| links | 链接 URL、标题、描述 | P1 |

P2 范围：

- OCR 图片文字搜索。
- 语音转文字搜索。
- 搜索语法：from:user、type:file、date:2026-06。
- 后台全局审计搜索与用户端搜索权限分离。

### 6.3 搜索架构

建议分两层：

1. 本地快速搜索：联系人、会话、最近消息缓存。
2. 服务端权威搜索：历史消息、文件、链接、跨月份 Mongo 集合。

客户端流程：

```text
用户输入关键词
  -> 100-300ms debounce
  -> 本地结果立即展示
  -> 服务端搜索补齐历史结果
  -> 合并去重并按类型分组
```

### 6.4 接口设计

统一搜索接口：

```http
GET /api/v1/search?q={keyword}&types=contacts,chats,messages,files&limit=20&cursor=xxx
```

响应：

```json
{
  "query": "hello",
  "has_more": true,
  "next_cursor": "cursor",
  "sections": [
    {
      "type": "contacts",
      "items": []
    },
    {
      "type": "messages",
      "items": []
    }
  ]
}
```

消息搜索结果：

```json
{
  "type": "message",
  "msg_id": "message_uuid",
  "chat_id": "chat_uuid",
  "chat_name": "产品群",
  "sender_id": "user_uuid",
  "sender_name": "张三",
  "seq": 123,
  "snippet": "这里是命中的上下文",
  "highlight_ranges": [[3, 5]],
  "created_at": "2026-06-21T12:00:00Z"
}
```

### 6.5 搜索索引

短期可用现有 MySQL/Mongo 查询，P1 建议增加搜索索引表或搜索服务。

#### 方案 A：现有数据库增强

适合短期：

- 联系人、群/频道：MySQL LIKE + 索引字段。
- 消息：MongoDB text index 或现有跨月份搜索。
- 文件/链接：基于已有媒体/链接索引查询。

优点：改动小。  
缺点：大数据量性能有限。

#### 方案 B：独立 search_index 表

新增 `search_index`：

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| owner_user_id | 搜索可见用户 |
| target_type | contact/chat/message/file/link |
| target_id | 对象 ID |
| chat_id | 会话 ID |
| content | 可搜索文本 |
| tokens | 可选分词 |
| created_at | 创建时间 |
| updated_at | 更新时间 |

优点：权限过滤清晰，统一搜索容易做。  
缺点：需要维护索引同步。

#### 方案 C：Meilisearch / Elasticsearch

适合后期：

- 支持高亮、中文分词、权重排序、复杂过滤。
- 需要部署与数据同步。

建议：P0 用方案 A，P1 过渡到方案 B，P2 再考虑方案 C。

### 6.6 排序规则

搜索结果排序：

1. 精确匹配优先。
2. 联系人/会话优先于历史消息。
3. 最近活跃会话优先。
4. 最近消息优先。
5. 官方联系人/官方群可适当提权。

### 6.7 权限规则

- 用户只能搜索自己可见的联系人、会话和消息。
- 已退出的群默认不可搜索退出后的消息。
- 已删除/清空的本地历史是否可搜，要区分“本地删除”和“服务端清空”。
- 黑名单、隐私设置影响用户搜索结果。
- 后台管理端搜索和用户端搜索必须分开授权。

### 6.8 前端改造点

涉及目录：

- `lib/features/chat/pages/search_page.dart`
- `lib/features/chat/pages/chat_detail_search_messages.dart`
- `lib/features/contacts/pages/new_contact_page.dart`
- `lib/features/home/pages/home_desktop_page.dart`
- `lib/core/services/api/chat_service.dart`

任务清单：

1. 定义统一 `GlobalSearchResult` 模型。
2. 搜索页分组展示：联系人、会话、消息、文件、链接。
3. 本地缓存先出结果，服务端结果后补齐。
4. 增加搜索 loading、empty、error、retry 状态。
5. 点击消息结果进入会话并定位到 seq/msg_id。
6. 桌面端支持 Ctrl/Cmd + K 打开统一搜索。
7. 搜索词高亮。

### 6.9 后端改造点

涉及目录：

- `backend/internal/handlers/user_handler.go`
- `backend/internal/handlers/chat_handler.go`
- `backend/internal/handlers/message_handler.go`
- `backend/internal/services/message_service.go`

任务清单：

1. 新增统一搜索 handler。
2. 联系人/用户/公开群频道搜索接入统一响应。
3. 消息搜索支持当前用户可见会话过滤。
4. 文件/链接搜索复用已有媒体索引能力。
5. 搜索接口加入分页 cursor。
6. 搜索日志记录关键词、耗时、结果数量，便于优化。

### 6.10 验收标准

1. 搜索联系人昵称、用户名能命中。
2. 搜索群名、频道名能命中。
3. 搜索历史文本消息能命中并显示上下文。
4. 点击消息结果进入对应会话并定位到消息。
5. 搜索文件名能命中并进入所在会话。
6. 无权限会话消息不出现在结果里。
7. 1 万条消息量下，常见关键词搜索响应低于 1 秒。

## 7. 数据迁移与兼容策略

### 7.1 客户端兼容

- 老版本客户端没有 `client_msg_id` 时，服务端可临时生成，但新版本必须必填。
- 新版本客户端对没有 seq 的旧消息按 server_created_at 排序。
- 本地缓存升级时补 `send_status`、`client_msg_id`、`last_synced_seq` 字段。

### 7.2 服务端兼容

- 消息集合新增字段不破坏旧消息读取。
- 对旧消息搜索时，缺失字段使用默认值。
- 状态同步事件新增字段时，客户端忽略未知字段。

### 7.3 灰度策略

1. 后端先支持新字段和幂等，但不强制。
2. 客户端发布后开始上报 `client_msg_id`。
3. 观察重复消息率、发送失败率。
4. 稳定后服务端强制新版本发送必须有 `client_msg_id`。

## 8. 可观测与后台诊断

建议新增指标：

| 指标 | 说明 |
| --- | --- |
| message_send_success_rate | 消息发送成功率 |
| message_retry_count | 消息重试次数 |
| duplicate_message_dropped | 客户端/服务端去重次数 |
| sync_gap_detected | seq 缺口次数 |
| sync_repair_success_rate | 补偿同步成功率 |
| ws_reconnect_count | WebSocket 重连次数 |
| push_delivery_success_rate | 推送送达成功率 |
| search_latency_p95 | 搜索 P95 延迟 |

后台建议：

- 用户诊断页：设备、推送、最近同步、最近消息失败。
- 会话诊断页：成员状态、最后 seq、未读异常。
- 消息诊断页：按 msg_id/client_msg_id 查询消息链路。

## 9. 测试计划

### 9.1 单元测试

后端：

- 发送接口 client_msg_id 幂等。
- 已读游标只能递增。
- 会话状态 state_version 旧事件不覆盖新状态。
- 搜索权限过滤。

客户端：

- message merge 去重。
- seq 乱序排序。
- retry 状态流转。
- search result merge 去重。

### 9.2 集成测试

1. 双设备登录同一账号。
2. A 设备发送消息，B 设备收到，A 设备不重复。
3. B 设备已读，A 设备会话未读同步。
4. A 设备置顶，B 设备同步置顶。
5. 断网发送，恢复后重试成功。
6. 后台锁屏收到推送，打开后补齐消息。
7. 搜索历史消息并跳转定位。

### 9.3 真机测试

必须覆盖：

- Android 前台、后台、锁屏、进程被杀。
- iOS 前台、后台、APNs 通知点击。
- Windows 桌面端和 Android 同账号多端。
- 弱网、断网、网络切换。
- 大群消息刷屏。

## 10. 里程碑计划

### M1：消息可靠性 P0

交付：

- client_msg_id 幂等。
- 消息状态模型统一。
- 发送失败可重试。
- WS/HTTP/同步消息去重。
- 重连后按 seq 补偿同步。

验收：

- 不漏、不重、不乱序。
- 弱网下发送状态明确。

### M2：多端同步 P0/P1

交付：

- last_read_seq 多端同步。
- unread_count 最终一致。
- 置顶/免打扰/隐藏状态多端同步。
- 推送点击后补偿同步。

验收：

- 手机、桌面、Web 多端状态一致。
- 通知和未读数一致。

### M3：全局搜索 MVP

交付：

- 统一搜索入口。
- 联系人、会话、消息搜索。
- 文件/链接搜索基础能力。
- 搜索结果跳转会话和消息。

验收：

- 用户能从一个入口找人、找群、找消息、找文件。

### M4：诊断与运营

交付：

- 推送诊断。
- 消息链路诊断。
- 搜索耗时和失败日志。
- 后台可靠性看板。

验收：

- 客服/管理员能定位“为什么没收到消息/通知/搜索不到”。

## 11. 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 旧客户端不带 client_msg_id | 幂等不完整 | 灰度期兼容，后续强制升级 |
| Mongo 跨月份搜索慢 | 搜索体验差 | P0 限制范围，P1 建索引表 |
| 多端状态并发更新冲突 | 状态回退 | state_version + 服务端合并 |
| 推送受 ROM 限制 | 到达率不稳定 | 厂商推送 + 打开后补偿同步 |
| 本地缓存迁移失败 | 消息列表异常 | 迁移前备份，失败降级全量同步 |
| 加密消息搜索受限 | 搜不到密文内容 | 兼容模式搜索服务端明文，严格模式只搜本地可解密内容或元数据 |

## 12. 推荐立即开始的任务清单

第一批建议按以下顺序开工：

1. 梳理当前消息字段：`msg_id`、`client_msg_id`、`seq`、`status`、`created_at`。
2. 给发送接口补 `client_msg_id` 幂等测试。
3. 客户端统一消息 merge/去重函数。
4. 客户端离线队列重试复用 `client_msg_id`。
5. WS 重连后按会话执行 `after_seq` 增量同步。
6. 已读接口统一使用 `last_read_seq`。
7. 会话状态接口合并置顶、免打扰、隐藏、标记未读。
8. 搜索页抽象统一结果模型。
9. 后端新增统一搜索接口 MVP。
10. 后台增加推送与消息链路诊断入口。

## 13. 完成定义

这三条主线做到以下程度，才算核心能力完成：

- 消息：任意弱网/重连/重复发送场景下，不漏、不重、不乱序，失败可解释、可重试。
- 多端：同账号多设备的未读、已读、置顶、免打扰在数秒内最终一致。
- 通知：离线通知能到达，打开 App 后能补齐真实消息；失败能诊断。
- 搜索：用户能从一个入口搜索联系人、会话、历史消息、文件，并能准确跳转。
- 运维：后台能查清楚某个用户、某台设备、某条消息、某次推送的问题边界。
