# 客服端 MVP 升级详细开发方案

> 文档状态：待评审
> 适用仓库：`<PROJECT_ROOT>`
> 涉及模块：`admin-kf/`、`backend/`、`admin/`、Flutter 客户端消息链路
> 目标版本：客服端 1.0
> 视觉方向：黑色侧栏、白色内容区、灰阶卡片，风格与总管理后台一致
> 更新时间：2026-07-14

---

## 1. 文档目的

当前 `admin-kf` 已有独立登录、工作台、邀请码、欢迎语、旗下用户和个人中心，但仍然偏向客服账号的辅助管理后台，不是真正可用于日常接待的客服工作台。

本方案将在不重做现有 IM 基础设施的前提下，建设以下五条核心链路：

1. 客服实时接待台。
2. 会话排队、领取、分配、转接和关闭。
3. 快捷回复、标签、备注、用户业务资料和跟进提醒。
4. AI 知识库自动回答与转人工。
5. 客服效率、服务质量和 AI 解决率报表。

方案目标不是增加一个只能演示的聊天页面，而是形成可以真实运营、可以统计、可以审计、可以继续商业化的客服闭环。

---

## 2. 当前系统基础与问题

### 2.1 已有基础

当前仓库已经具备：

- 官方客服账号与启用状态。
- 客服账号独立登录接口和标准 JWT。
- 邀请码绑定客服。
- 注册后自动建立客户与官方客服的私聊。
- 自动发送欢迎语。
- MySQL 会话、成员和会话列表数据。
- MongoDB 消息存储。
- WebSocket 实时消息、会话订阅和用户定向推送。
- 文本、图片、视频、文件、语音等消息类型。
- 用户、钱包、充值、会员和订单数据。
- DeepSeek 翻译和语音转文字接口。
- 管理后台官方客服管理能力。

这些能力意味着实时接待台不需要再造一套聊天协议，应优先复用现有 `Chat`、`UserChat`、`MessageService` 和 `ws.Hub`。

### 2.2 当前主要缺口

当前客服端缺少：

- 待接待队列。
- 客服会话状态。
- 会话负责人。
- 自动分配策略。
- 手动领取和转接。
- 客服在线、忙碌、离线状态。
- 最大并发接待数。
- 会话关闭、重新打开和跟进。
- 内部备注、用户标签和快捷回复。
- 用户钱包、充值、会员等业务摘要。
- 满意度评价。
- 知识库、AI 回答和转人工。
- 首次响应时间、解决时长、SLA 和客服绩效报表。

### 2.3 现有客服端需要清理的产品文案

升级时必须删除或替换以下体验版文案：

- “独立官方客服工作台前端壳子”。
- “已独立部署预留”。
- “后续接真实接口即可投入使用”。
- “当前为列表壳子”。
- “v0.5 体验增强版”。

所有页面应使用真实业务语言，不展示“预留、壳子、后续接入、演示版”等研发状态文案。

---

## 3. 建设目标与成功指标

### 3.1 产品目标

- 客户发送消息后能够自动进入待接待队列。
- 在线客服能够在一个页面完成领取、回复、转接、备注和关闭。
- 客户端继续使用原有聊天页，不新增割裂的客服聊天界面。
- 转接客服后客户侧聊天记录保持连续。
- AI 与人工客服共用同一条会话历史。
- 所有分配和状态变更都有操作记录。
- 管理员能够查看客服服务质量和 AI 效果。

### 3.2 MVP 验收指标

第一期上线至少满足：

| 指标 | MVP 目标 |
|---|---:|
| 新咨询进入客服队列 | 100% |
| 消息实时到达工作台 | 99.9% 业务链路成功率 |
| 重复领取同一会话 | 0 |
| 转接后历史消息丢失 | 0 |
| 分配和状态变更有审计记录 | 100% |
| 首次响应时间可统计 | 100% |
| AI 回复可追溯知识来源 | 100% |
| AI 低置信度自动转人工 | 100% |

以上目标需要通过自动化测试和真实双账号联调验证，不能只以页面可打开作为完成标准。

---

## 4. MVP 范围

### 4.1 本期必须完成

#### 客服接待

- 待接待、我的接待、待跟进、已关闭四类队列。
- 会话列表实时刷新。
- 历史消息分页加载。
- 文本、图片、文件、语音消息收发。
- 未读数、客户输入中和新消息提示。
- 手动领取、释放、转接、关闭、重新打开。
- 客服在线、忙碌、离线状态。
- 最大并发接待数。

#### 运营工具

- 快捷回复分类、搜索和插入。
- 用户标签。
- 内部备注。
- 跟进时间和提醒状态。
- 客户基础资料。
- 钱包余额、充值、提现、VIP 和最近订单摘要。
- 客服操作时间线。

#### AI 知识库

- FAQ 问答维护。
- 文档上传和解析。
- 知识条目启用、停用和版本管理。
- AI 自动回答开关。
- 引用知识来源。
- 低置信度转人工。
- 客户主动要求人工时立即转人工。
- AI 回复次数、命中率和转人工原因记录。

#### 报表

- 今日咨询量。
- 当前排队量。
- 当前接待量。
- 首次响应时间。
- 平均解决时长。
- 未解决量。
- 满意度。
- 客服接待量。
- AI 独立解决率。

### 4.2 本期暂不包含

- 电话呼叫中心和云总机。
- 微信公众号、抖音、WhatsApp 等外部渠道聚合。
- 复杂工单流程设计器。
- AI 自动退款、自动转账等高风险写操作。
- 多租户 SaaS 计费。
- 全量 CRM 和销售漏斗。
- 复杂排班、考勤和薪资计算。

这些能力可以在客服 1.0 稳定后继续扩展，不应阻塞 MVP 上线。

---

## 5. 用户角色与权限

### 5.1 客服角色

| 角色 | 权限范围 |
|---|---|
| 客服 `agent` | 查看公共待接待队列、领取会话、处理自己的会话、使用快捷回复、添加备注和标签 |
| 主管 `supervisor` | 查看团队全部会话、强制分配、转接、关闭、查看团队报表、维护快捷回复和知识库 |
| 总管理员 `admin` | 在总后台管理客服账号、角色、并发数、AI 策略、知识库和全局报表 |
| AI `ai` | 仅在允许的客服会话中读取上下文、检索知识并发送经过审计的回复 |

### 5.2 权限原则

- 客服只能查看公共队列和自己有权接待的会话。
- 普通客服不能查看其他客服的内部备注和完整绩效数据，除非主管授权。
- AI 不能调用钱包扣款、余额调整、退款、封禁等写接口。
- 客服端不得复用总后台管理员权限。
- 所有“代官方客服身份发送”的消息都必须记录真实操作客服。
- 被总后台停用的官方客服应立即失去客服端访问权限和 WebSocket 会话。

---

## 6. 信息架构与菜单

### 6.1 新菜单结构

```text
客服工作台
├─ 实时接待
│  ├─ 待接待
│  ├─ 我的接待
│  ├─ 待跟进
│  └─ 已关闭
├─ 客户管理
├─ 快捷回复
├─ AI 知识库
│  ├─ FAQ
│  ├─ 文档
│  ├─ 未命中问题
│  └─ AI 设置
├─ 数据报表
├─ 邀请运营
│  ├─ 我的邀请码
│  ├─ 邀请用户
│  └─ 欢迎语
└─ 个人中心
```

### 6.2 前端路由建议

| 路由 | 页面 | 权限 |
|---|---|---|
| `/workbench` | 实时接待台 | agent、supervisor |
| `/customers` | 客户管理 | agent、supervisor |
| `/quick-replies` | 快捷回复 | agent 只读、supervisor 管理 |
| `/knowledge/faqs` | FAQ 管理 | supervisor |
| `/knowledge/documents` | 文档知识库 | supervisor |
| `/knowledge/misses` | AI 未命中问题 | supervisor |
| `/reports` | 数据报表 | supervisor |
| `/invite-code` | 我的邀请码 | agent、supervisor |
| `/invitees` | 邀请用户 | agent、supervisor |
| `/welcome-message` | 欢迎语 | agent、supervisor |
| `/profile` | 个人中心 | 全部 |

原 `/dashboard` 可保留为数据概览，也可以重定向到 `/workbench`。推荐保留概览页，但登录后默认进入 `/workbench`。

---

## 7. 黑白 UI 视觉规范

### 7.1 总体方向

客服端现有深蓝绿色渐变风格全部替换为总后台一致的黑白灰设计：

- 左侧导航使用纯黑或近黑色。
- 主内容区域使用浅灰背景。
- 卡片使用白色。
- 文字使用黑色、深灰和中灰三级层次。
- 主操作按钮使用黑色。
- 不再使用绿色渐变作为品牌主色。
- 绿色、橙色、红色只承担成功、等待、异常等语义状态。
- 阴影保持轻量，主要依靠边框和留白区分层级。

### 7.2 设计变量

```scss
:root {
  --kf-bg: #f5f6f8;
  --kf-surface: #ffffff;
  --kf-surface-soft: #f8fafc;
  --kf-sidebar: #111111;
  --kf-sidebar-hover: #242424;
  --kf-text: #171717;
  --kf-text-secondary: #5f6672;
  --kf-text-muted: #9299a5;
  --kf-border: #e4e7ec;
  --kf-border-strong: #d4d8df;
  --kf-primary: #171717;
  --kf-primary-hover: #303030;
  --kf-success: #16a34a;
  --kf-warning: #d97706;
  --kf-danger: #dc2626;
  --kf-info: #475569;
  --kf-radius-sm: 8px;
  --kf-radius-md: 12px;
  --kf-radius-lg: 16px;
}
```

### 7.3 页面布局

- 侧栏宽度：`228px`，支持收起到 `72px`。
- 顶栏高度：`56px`。
- 页面背景：`#f5f6f8`。
- 普通内容最大宽度：`1440px`。
- 接待台不设置最大宽度，占满可用区域。
- 卡片圆角：`12px`，不使用夸张的 `20px+` 圆角。
- 卡片边框：`1px solid #e4e7ec`。
- 卡片阴影：仅使用 `0 4px 16px rgb(15 23 42 / 4%)`。

### 7.4 接待台三栏布局

```text
┌──────────────────────────────────────────────────────────────────────┐
│ 顶栏：在线状态 / 当前接待数 / 搜索 / 通知 / 头像                    │
├───────────────┬────────────────────────────────┬─────────────────────┤
│ 会话队列       │ 当前会话                       │ 客户资料             │
│ 300~340px      │ minmax(480px, 1fr)             │ 300~340px            │
│               │                                │                     │
│ 待接待 12      │ 客户名称 / 状态 / 转接 / 关闭  │ 基础资料             │
│ 我的接待 5     │────────────────────────────────│ 标签与备注           │
│ 待跟进 3       │ 消息历史                       │ 会员与钱包摘要       │
│ 已关闭         │                                │ 跟进提醒             │
│               │────────────────────────────────│ 服务时间线           │
│ 会话搜索       │ 回复输入区 / 快捷回复 / 文件   │                     │
└───────────────┴────────────────────────────────┴─────────────────────┘
```

### 7.5 响应式规则

- `>= 1280px`：完整三栏。
- `960px ~ 1279px`：右侧客户资料改为抽屉。
- `< 960px`：左侧队列和右侧资料均改为抽屉，中间聊天占满。
- 客服工作台以桌面端为第一优先级，移动端保证可处理紧急会话，但不追求同等信息密度。

### 7.6 必备状态设计

每个页面必须设计：

- 首次加载骨架屏。
- 空队列状态。
- 接口失败状态和重试按钮。
- WebSocket 断线提示。
- 正在重连提示。
- 无权限状态。
- 客服账号被停用状态。
- AI 服务不可用降级状态。

---

## 8. 实时接待台详细设计

### 8.1 左侧会话队列

每条队列项展示：

- 客户头像和昵称。
- 最后一条消息摘要。
- 最后消息时间。
- 未读数。
- 等待时长。
- 当前会话状态。
- VIP 标识。
- 优先级。
- 负责客服。
- AI 接待中标识。

支持：

- 按状态切换。
- 按昵称、UUID、手机号后四位搜索。
- 按等待时间、最后消息时间、优先级排序。
- 只看 VIP、超时、未读、AI 转人工会话。
- 实时插入新会话，不刷新整个页面。

### 8.2 中间聊天区

复用现有消息协议，支持：

- 文本。
- 图片。
- 视频。
- 文件。
- 语音。
- 位置卡片只读展示。
- 系统消息。
- 历史消息向上分页。
- 发送失败重试。
- 已读和送达状态。
- 客户输入中状态。

输入区增加：

- 快捷回复面板。
- 文件和图片上传。
- 内部备注模式。
- AI 建议回复。
- 发送快捷键设置。
- 敏感操作二次确认。

内部备注不能写入客户可见的普通消息集合，必须进入独立的内部备注表。

### 8.3 右侧客户资料

按折叠区块展示：

1. 基础资料：昵称、用户名、UUID、手机号、注册时间、最后在线时间。
2. 客服关系：来源邀请码、归属客服、首次咨询时间、最近咨询时间。
3. 标签与备注：支持新增、删除、搜索标签。
4. 业务摘要：钱包余额、VIP 等级、到期时间、充值和提现状态。
5. 最近订单：只展示摘要，点击打开详情抽屉。
6. 跟进提醒：时间、内容、状态。
7. 服务时间线：领取、转接、关闭、重开、评价等事件。

客服端默认只读展示钱包和订单数据。余额调整、退款等写操作继续留在总后台。

---

## 9. 会话状态机

### 9.1 状态定义

```text
waiting   待接待
assigned  已分配，客服尚未领取
serving   接待中
pending   待客户回复或待跟进
closed    已关闭
```

### 9.2 状态流转

```text
客户首次发消息
      │
      ▼
   waiting
      │ 自动分配 / 手动领取
      ▼
   assigned
      │ 客服接受
      ▼
   serving ────────转接────────> assigned
      │
      ├────待客户回复──────────> pending
      │                            │ 客户再次发消息
      │                            └──────────────> serving
      │
      └────解决并关闭──────────> closed
                                   │ 客户再次发消息 / 人工重开
                                   └──────────────> waiting 或 serving
```

### 9.3 强制规则

- `waiting` 会话没有负责人。
- `assigned` 必须有负责人和分配时间。
- `serving` 必须有负责人和接待开始时间。
- `closed` 必须有关闭原因。
- 客户在已关闭会话再次发送消息时，默认创建新一轮服务会话，但继续复用原 IM 私聊和消息历史。
- 每个客户与官方客服身份同一时间只允许存在一个未关闭的服务会话。
- 所有状态变更必须写入事件表。

---

## 10. 分配与流转策略

### 10.1 客服在线状态

```text
online   在线，可自动分配
busy     忙碌，不再自动分配，但可继续处理已有会话
offline  离线，不可分配
```

在线状态应通过心跳和主动切换共同判断：

- 客服每 30 秒发送一次心跳。
- 连续 90 秒无心跳，后端标记离线。
- 浏览器关闭或退出登录时主动上报离线。
- 后端状态是最终事实，不能只使用前端本地状态。

### 10.2 自动分配 MVP 算法

默认使用“最少当前接待数”策略：

1. 筛选 `online` 客服。
2. 排除已达到 `max_concurrent` 的客服。
3. 优先选择当前接待数最少者。
4. 接待数相同，选择最久未分配者。
5. 没有可用客服时保持 `waiting`。

领取和自动分配必须使用数据库事务和条件更新，防止两个客服同时领取：

```sql
UPDATE service_conversations
SET status = 'assigned', assigned_agent_id = ?, assigned_at = NOW()
WHERE id = ? AND status = 'waiting' AND assigned_agent_id IS NULL;
```

只有影响行数为 `1` 才算领取成功。

### 10.3 转接规则

- 客服只能把自己的会话转给在线或忙碌客服。
- 主管可以强制转接任何会话。
- 转接时必须填写原因。
- 转接只修改实际操作客服，不改变客户看到的官方客服身份。
- 转接后完整消息和内部时间线保留。
- 新客服收到 WebSocket 强提醒。

---

## 11. 客服身份与消息复用边界

### 11.1 两种身份必须分离

客服系统需要区分：

- `service_identity_user_id`：客户在客户端看到的官方客服身份。
- `assigned_agent_user_id`：客服后台当前实际处理该会话的操作人。

转接只改变 `assigned_agent_user_id`。否则把私聊从一个官方账号转到另一个账号会导致客户看到新会话和历史断裂。

### 11.2 发送消息规则

客服端不得直接调用普通客户端的发送接口并伪造 `sender_id`。应新增客服专用发送接口：

1. 校验当前客服是否有权处理服务会话。
2. 读取服务会话绑定的官方客服身份。
3. 通过 `MessageService` 以官方客服身份发送。
4. 在消息扩展字段或服务事件中记录真实操作客服。
5. 继续使用原有消息序号、会话预览、推送和 WebSocket 广播。

建议给 MongoDB 消息增加可选字段：

```go
OperatorType string `bson:"operator_type,omitempty" json:"operator_type,omitempty"` // human | ai
OperatorID   string `bson:"operator_id,omitempty" json:"operator_id,omitempty"`
```

普通用户消息不写这两个字段，保持兼容。

### 11.3 服务会话触发点

客户向官方客服身份发送新消息后：

1. 普通消息先按现有链路成功落库。
2. 异步调用 `ServiceConversationService.OnCustomerMessage`。
3. 查找或创建未关闭的服务会话。
4. 更新最后消息、未读数和排队时间。
5. 触发自动分配或 AI 接待。
6. 通过 WebSocket 通知客服队列。

客服元数据更新失败不能导致客户消息发送失败。失败记录应进入重试任务，并通过定时对账补齐服务会话。

---

## 12. 数据模型设计

当前项目使用 GORM `AutoMigrate`。新增模型需加入 `backend/cmd/server/main.go` 的迁移列表，同时为生产发布准备显式建表 SQL 和回滚说明。

### 12.1 `service_agents`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | bigint | 主键 |
| `user_id` | bigint | 登录用户，唯一索引 |
| `default_service_identity_user_id` | bigint | 默认对外官方客服身份 |
| `role` | varchar(20) | agent、supervisor |
| `presence` | varchar(20) | online、busy、offline |
| `max_concurrent` | int | 最大并发接待数，默认 5 |
| `current_serving` | int | 可缓存，最终以会话表统计校正 |
| `auto_assign_enabled` | bool | 是否参与自动分配 |
| `last_assigned_at` | datetime | 上次分配时间 |
| `last_heartbeat_at` | datetime | 最后心跳 |
| `created_at` | datetime | 创建时间 |
| `updated_at` | datetime | 更新时间 |

### 12.2 `service_conversations`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | bigint | 主键 |
| `uuid` | char(36) | 对外会话编号，唯一索引 |
| `chat_id` | bigint | 复用的 IM 私聊 ID |
| `chat_uuid` | char(36) | IM 会话 UUID |
| `customer_user_id` | bigint | 客户用户 ID |
| `service_identity_user_id` | bigint | 客户看到的官方客服身份 |
| `assigned_agent_id` | bigint nullable | 当前处理客服 |
| `status` | varchar(20) | waiting、assigned、serving、pending、closed |
| `priority` | tinyint | 0 普通、1 高、2 紧急 |
| `source` | varchar(30) | invite、direct、system、ai_handoff |
| `round_no` | int | 同一 IM 私聊的第几轮服务 |
| `last_message_id` | varchar(36) | 最后一条消息 ID |
| `last_message_at` | datetime | 最后消息时间 |
| `customer_unread_count` | int | 客户消息未读数 |
| `queued_at` | datetime | 进入队列时间 |
| `assigned_at` | datetime nullable | 分配时间 |
| `accepted_at` | datetime nullable | 客服开始接待时间 |
| `first_response_at` | datetime nullable | 首次回复时间 |
| `closed_at` | datetime nullable | 关闭时间 |
| `close_reason` | varchar(100) | 关闭原因 |
| `ai_status` | varchar(20) | disabled、serving、handoff、done |
| `created_at` | datetime | 创建时间 |
| `updated_at` | datetime | 更新时间 |

关键索引：

- `idx_service_queue(status, priority, queued_at)`。
- `idx_service_agent_queue(assigned_agent_id, status, last_message_at)`。
- `idx_service_customer(customer_user_id, created_at)`。
- `idx_service_chat_round(chat_id, round_no)` 唯一索引。

### 12.3 `service_conversation_events`

记录不可变操作时间线：

- `conversation_id`。
- `event_type`。
- `operator_type`：customer、agent、supervisor、ai、system。
- `operator_id`。
- `from_status`。
- `to_status`。
- `payload_json`。
- `created_at`。

事件类型至少包含：

- created。
- assigned。
- claimed。
- transferred。
- status_changed。
- note_added。
- tag_changed。
- ai_replied。
- ai_handoff。
- closed。
- reopened。
- satisfaction_submitted。

### 12.4 客户运营数据

#### `service_customer_profiles`

- `customer_user_id` 唯一索引。
- `owner_agent_id`。
- `level`。
- `summary`。
- `next_follow_up_at`。
- `last_service_at`。
- `created_at`、`updated_at`。

#### `service_tags`

- 标签名称、颜色、分组、排序、启用状态。

#### `service_customer_tags`

- `customer_user_id + tag_id` 唯一索引。
- 添加人和添加时间。

#### `service_internal_notes`

- 服务会话、客户、客服、备注正文、是否置顶、创建时间。

### 12.5 快捷回复

#### `service_quick_reply_categories`

- 名称、排序、作用范围、创建人。

#### `service_quick_replies`

- 分类、标题、正文、快捷码、个人或团队范围、使用次数、启用状态。

### 12.6 满意度

#### `service_satisfaction_surveys`

- 服务会话。
- 客户。
- 评分 1~5。
- 评价标签 JSON。
- 评价内容。
- 是否匿名。
- 提交时间。

一个服务会话只允许一条有效满意度记录。

### 12.7 AI 知识库

#### `service_knowledge_bases`

- 名称、描述、状态、AI 提示词、回复策略。

#### `service_knowledge_faqs`

- 问题、答案、关键词、分类、优先级、启用状态、版本。

#### `service_knowledge_documents`

- 文件名、文件 URL、MIME、大小、解析状态、错误信息、版本、上传人。

#### `service_knowledge_chunks`

- 文档 ID、段落序号、正文、token 数、检索关键词、向量外部 ID。

#### `service_ai_runs`

- 服务会话。
- 客户问题。
- 检索条目。
- 检索分数。
- 模型。
- token 用量。
- 耗时。
- 回复结果。
- 是否转人工。
- 转人工原因。
- 创建时间。

---

## 13. 后端服务拆分

建议增加以下文件：

```text
backend/internal/models/
├─ service_agent.go
├─ service_conversation.go
├─ service_customer.go
├─ service_quick_reply.go
├─ service_satisfaction.go
└─ service_knowledge.go

backend/internal/services/
├─ service_conversation_service.go
├─ service_assignment_service.go
├─ service_presence_service.go
├─ service_customer_service.go
├─ service_ai_service.go
├─ service_knowledge_service.go
└─ service_report_service.go

backend/internal/handlers/
├─ service_workbench_handler.go
├─ service_customer_handler.go
├─ service_quick_reply_handler.go
├─ service_knowledge_handler.go
└─ service_report_handler.go
```

现有 `service_admin_handler.go` 继续负责登录、个人资料、邀请码、欢迎语和密码，不要继续把所有新接口堆进同一个文件。

---

## 14. API 设计

统一前缀：`/api/v1/service-admin`

### 14.1 在线状态

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/presence` | 获取当前客服状态和接待数 |
| `PUT` | `/presence` | 切换 online、busy、offline |
| `POST` | `/presence/heartbeat` | 上报心跳 |
| `GET` | `/agents/available` | 获取可转接客服 |

### 14.2 会话队列

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/conversations` | 按状态、关键词、标签、时间查询队列 |
| `GET` | `/conversations/:uuid` | 会话详情 |
| `GET` | `/conversations/:uuid/messages` | 历史消息分页 |
| `POST` | `/conversations/:uuid/claim` | 手动领取 |
| `POST` | `/conversations/:uuid/accept` | 接受分配 |
| `POST` | `/conversations/:uuid/transfer` | 转接 |
| `POST` | `/conversations/:uuid/status` | 切换 serving、pending |
| `POST` | `/conversations/:uuid/close` | 关闭 |
| `POST` | `/conversations/:uuid/reopen` | 重新打开 |
| `POST` | `/conversations/:uuid/read` | 清除客服未读 |
| `POST` | `/conversations/:uuid/messages` | 客服专用发送消息 |

### 14.3 用户资料与运营

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/customers` | 客户列表 |
| `GET` | `/customers/:uuid` | 客户完整摘要 |
| `GET` | `/customers/:uuid/business-summary` | 钱包、VIP、订单只读摘要 |
| `PUT` | `/customers/:uuid/profile` | 更新客服摘要和跟进时间 |
| `GET` | `/customers/:uuid/notes` | 内部备注 |
| `POST` | `/customers/:uuid/notes` | 添加内部备注 |
| `GET` | `/tags` | 标签列表 |
| `POST` | `/customers/:uuid/tags` | 添加标签 |
| `DELETE` | `/customers/:uuid/tags/:tag_id` | 删除标签 |

### 14.4 快捷回复

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/quick-replies` | 查询快捷回复 |
| `POST` | `/quick-replies` | 新建 |
| `PUT` | `/quick-replies/:id` | 编辑 |
| `DELETE` | `/quick-replies/:id` | 删除 |
| `POST` | `/quick-replies/:id/use` | 记录使用次数 |

### 14.5 AI 知识库

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET/POST` | `/knowledge/faqs` | FAQ 列表和新建 |
| `PUT/DELETE` | `/knowledge/faqs/:id` | FAQ 编辑和删除 |
| `GET/POST` | `/knowledge/documents` | 文档列表和上传 |
| `POST` | `/knowledge/documents/:id/reparse` | 重新解析 |
| `DELETE` | `/knowledge/documents/:id` | 删除文档及索引 |
| `GET` | `/knowledge/misses` | 未命中问题 |
| `POST` | `/knowledge/test` | 在后台测试问答 |
| `GET/PUT` | `/ai/settings` | AI 接待策略 |

### 14.6 报表

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/reports/overview` | 核心指标 |
| `GET` | `/reports/trend` | 按天或小时趋势 |
| `GET` | `/reports/agents` | 客服绩效 |
| `GET` | `/reports/ai` | AI 效果 |
| `GET` | `/reports/satisfaction` | 满意度 |
| `GET` | `/reports/export` | 导出 CSV/XLSX |

### 14.7 典型会话列表响应

```json
{
  "list": [
    {
      "uuid": "service-conversation-uuid",
      "chat_uuid": "im-chat-uuid",
      "status": "waiting",
      "priority": 1,
      "customer": {
        "uuid": "user-uuid",
        "nickname": "张三",
        "avatar": "https://...",
        "vip_level": 1
      },
      "assigned_agent": null,
      "last_message": {
        "text": "会员为什么没有到账？",
        "type": 1,
        "created_at": "2026-07-14T15:30:00+08:00"
      },
      "unread_count": 2,
      "waiting_seconds": 83,
      "ai_status": "handoff"
    }
  ],
  "total": 12,
  "cursor": "next-cursor"
}
```

会话列表建议使用游标分页，报表和管理列表可以继续使用页码分页。

---

## 15. WebSocket 事件设计

客服端继续连接现有 `/api/v1/ws`，使用标准 JWT，不另建第二套 WebSocket 服务。

新增事件：

| 事件 | 接收方 | 说明 |
|---|---|---|
| `service.conversation.created` | 在线客服队列 | 新咨询进入队列 |
| `service.conversation.assigned` | 被分配客服 | 新会话分配 |
| `service.conversation.claimed` | 团队客服 | 会话已被领取，从公共队列移除 |
| `service.conversation.transferred` | 原客服、新客服 | 转接完成 |
| `service.conversation.status_changed` | 当前客服 | 状态变化 |
| `service.message.new` | 当前客服 | 客户新消息 |
| `service.customer.updated` | 当前客服 | 标签、备注或资料变化 |
| `service.agent.presence_changed` | 主管和队列 | 客服在线状态变化 |
| `service.ai.handoff` | 公共队列或指定客服 | AI 请求转人工 |
| `service.satisfaction.submitted` | 当前客服、主管 | 客户提交评价 |

### 15.1 可靠性要求

- WebSocket 事件只负责实时提示，数据库才是最终状态。
- 客服端重连后必须重新拉取队列和当前会话。
- 每个事件携带 `event_id` 和 `updated_at`，前端去重。
- 前端不得依赖事件到达顺序推导最终状态。
- 关键分配操作必须通过 HTTP 接口提交，不能只通过 WebSocket 修改。

---

## 16. AI 知识库方案

### 16.1 第一阶段检索策略

为了控制运维复杂度，MVP 分两步：

#### 第一步：FAQ 和关键词检索

- FAQ 精确匹配。
- 关键词召回。
- MySQL FULLTEXT 或应用层倒排检索。
- DeepSeek 根据召回内容生成自然语言回复。

#### 第二步：文档语义检索

- 文档切片。
- Embedding。
- 推荐接入 Qdrant 作为可选向量服务。
- Qdrant 不可用时降级为 FAQ 和关键词检索。

不建议在第一版把大规模向量直接塞进 MySQL JSON 后逐条计算余弦距离。

### 16.2 AI 回复流程

```text
客户发送文本
   │
   ├─ 当前已有人工接待 ─────────> 不自动回复，仅生成建议回复
   │
   └─ AI 接待开启
        │
        ├─ 检测“人工、投诉、退款、报警”等强制转人工意图
        │      └───────────────> 转人工
        │
        ├─ 检索 FAQ / 文档 Top K
        │
        ├─ 检索分数低于阈值
        │      └───────────────> 转人工
        │
        └─ 调用模型生成回答
               │
               ├─ 生成失败 / 超时 ─> 转人工
               └─ 发送 AI 回复并记录引用来源
```

### 16.3 转人工条件

以下任一条件满足即转人工：

- 客户明确输入“人工客服、转人工、真人”等。
- 检索最高分低于配置阈值。
- 连续两轮没有命中知识。
- 客户连续表达不满意。
- 涉及退款、封禁、账号申诉、财务争议等高风险意图。
- 模型超时、限流或返回异常。
- AI 单会话回复轮数达到上限。

不要只依赖模型自报“置信度”。转人工应主要依据检索分数、规则和对话结果。

### 16.4 AI 安全边界

- 系统提示词和知识文档分层，禁止客户消息覆盖系统规则。
- 文档解析时过滤脚本和隐藏指令。
- 对手机号、身份证、银行卡等敏感信息脱敏后再写 AI 日志。
- 模型密钥只存后端，客服端永远不返回密钥。
- AI 只能调用白名单只读工具。
- 所有 AI 回复保留模型、耗时、token 和引用来源。
- 提供全局熔断开关和单会话关闭 AI 按钮。

### 16.5 AI 配置不应直接复用翻译配置

现有 DeepSeek 翻译配置只适用于消息翻译。客服 AI 需要独立配置：

- `service_ai_enabled`。
- `service_ai_provider`。
- `service_ai_base_url`。
- `service_ai_model`。
- `service_ai_api_key`。
- `service_ai_system_prompt`。
- `service_ai_retrieval_threshold`。
- `service_ai_max_rounds`。
- `service_ai_timeout_seconds`。
- `service_ai_daily_quota`。

---

## 17. 端到端加密兼容策略

客服 AI 和服务端工作台需要读取客户消息，因此必须明确处理现有 `plain`、`compatible`、`strict` 三种消息加密模式。

推荐规则：

- 普通用户私聊继续遵守全局加密策略。
- 官方客服会话增加明确的 `service_managed` 标识。
- 客户进入官方客服会话时显示“为提供客服服务，本会话可能由客服系统和 AI 处理”的提示。
- `strict` 模式下，如果服务端无法读取正文，则禁用 AI 自动接待并在工作台明确提示，不允许静默失败。
- 不得为了客服功能全局关闭普通用户之间的端到端加密。

该策略需要在正式开发前由产品和合规负责人确认。

---

## 18. 快捷回复与运营工具

### 18.1 快捷回复

支持：

- 团队回复和个人回复。
- 分类和排序。
- 标题、正文和快捷码。
- 输入 `/` 搜索快捷回复。
- 支持变量：`{nickname}`、`{username}`、`{vip_level}`、`{agent_name}`。
- 插入后允许客服二次编辑，默认不直接发送。
- 统计使用次数。

### 18.2 内部备注

- 客户不可见。
- 支持会话备注和客户长期备注。
- 支持置顶。
- 记录创建客服和时间。
- 删除需要主管权限，默认使用软删除。

### 18.3 跟进提醒

- 客服可以设置跟进时间和内容。
- 到期后进入“待跟进”队列。
- 支持完成、延期和取消。
- 客户新消息到达时可自动取消旧的等待提醒，由客服重新安排。

---

## 19. 满意度评价

关闭会话后向客户端发送客服评价卡片：

- 1~5 星。
- 评价标签：响应及时、解决问题、态度良好、未解决、回复慢等。
- 可选文字评价。
- 每轮服务仅提交一次。
- 超过 7 天不可再评价。

AI 独立解决和人工解决应分别统计满意度。

---

## 20. 数据报表口径

### 20.1 核心指标定义

| 指标 | 计算口径 |
|---|---|
| 咨询量 | 时间范围内新建的服务会话轮次 |
| 排队量 | 当前状态为 waiting 的会话数 |
| 接待量 | 当前状态为 assigned、serving、pending 的会话数 |
| 首次响应时间 | `first_response_at - queued_at` |
| 人工首次响应时间 | 第一条人工回复时间减去进入人工队列时间 |
| 平均解决时长 | `closed_at - queued_at` 的平均值 |
| 一次解决率 | 未重新打开且未在设定时间内再次咨询的已关闭会话比例 |
| 未解决量 | 超过 SLA 仍未关闭的会话数 |
| 满意度 | 有效评分平均值和好评率 |
| AI 解决率 | AI 接待后关闭且没有进入人工接待的会话比例 |
| AI 转人工率 | AI 接待后触发 handoff 的会话比例 |

### 20.2 报表筛选

- 今天、昨天、最近 7 天、最近 30 天、自定义时间。
- 全团队或单客服。
- 来源渠道。
- VIP 等级。
- AI、人工或混合接待。
- 会话状态和关闭原因。

### 20.3 报表性能

- 明细事件保留在事件表。
- 日报使用聚合表或定时任务预计算。
- 不允许每次打开报表都全表扫描 MongoDB 消息集合。
- 数据导出异步生成，避免大查询阻塞 API。

---

## 21. 前端目录规划

```text
admin-kf/src/
├─ components/
│  ├─ conversation/
│  │  ├─ conversation-queue.vue
│  │  ├─ conversation-list-item.vue
│  │  ├─ conversation-header.vue
│  │  ├─ message-list.vue
│  │  ├─ message-composer.vue
│  │  └─ transfer-dialog.vue
│  ├─ customer/
│  │  ├─ customer-profile-panel.vue
│  │  ├─ customer-tags.vue
│  │  ├─ customer-business-summary.vue
│  │  └─ follow-up-editor.vue
│  ├─ knowledge/
│  └─ common/
├─ composables/
│  ├─ use-service-websocket.ts
│  ├─ use-conversation-queue.ts
│  ├─ use-current-conversation.ts
│  └─ use-agent-presence.ts
├─ stores/
│  ├─ session.ts
│  ├─ workbench.ts
│  ├─ conversation.ts
│  └─ presence.ts
├─ service/api/
│  ├─ service-admin.ts
│  ├─ conversations.ts
│  ├─ customers.ts
│  ├─ quick-replies.ts
│  ├─ knowledge.ts
│  └─ reports.ts
├─ views/
│  ├─ workbench/index.vue
│  ├─ customers/index.vue
│  ├─ quick-replies/index.vue
│  ├─ knowledge/
│  └─ reports/index.vue
└─ styles/
   ├─ tokens.scss
   ├─ element-overrides.scss
   └─ index.scss
```

### 21.1 前端状态原则

- Pinia 只保存跨页面业务状态。
- 当前输入草稿按会话 UUID 本地缓存。
- WebSocket 事件统一在一个 service 中解析。
- 页面组件不得各自重复创建 WebSocket。
- 队列更新采用按 UUID 增量更新，不整页刷新。
- 切换会话时取消上一会话的未完成请求。
- 图片、文件上传复用现有上传协议。

---

## 22. 总后台配套改造

总后台需要增加“客服中心配置”，但不把日常接待功能塞进总后台。

建议增加：

- 客服角色：客服、主管。
- 最大并发接待数。
- 是否参与自动分配。
- 默认官方服务身份。
- 客服工作时间。
- 自动分配开关。
- 排队超时和 SLA。
- AI 全局开关、模型和额度。
- 满意度开关。
- 标签管理。
- 团队快捷回复管理。
- 团队总报表。

原“官方客服”管理页应升级为客服账号与状态管理入口。

---

## 23. 安全、审计与隐私

### 23.1 鉴权

- 所有 `/service-admin` 接口继续使用 JWT。
- 每次请求重新校验官方客服启用状态或使用短缓存。
- 会话详情、消息和发送接口必须校验客服权限。
- 主管接口单独校验角色。

### 23.2 审计

必须记录：

- 领取、分配、转接、关闭和重开。
- 查看敏感业务资料。
- 添加和删除备注。
- 修改客户标签。
- 导出报表。
- 修改知识库和 AI 配置。
- AI 自动回复和转人工。

### 23.3 数据最小化

- 手机号默认脱敏。
- 身份证和银行卡号不在客服端普通页面展示。
- 钱包和订单默认只读。
- 导出文件设置有效期并记录下载人。
- AI 日志不保存支付密码、验证码和完整银行卡号。

---

## 24. 性能与可靠性

### 24.1 性能目标

- 会话队列接口 P95 小于 300ms。
- 单次历史消息加载 P95 小于 500ms。
- 新消息到客服端显示延迟 P95 小于 1 秒。
- 领取和转接接口 P95 小于 500ms。
- 普通知识库 AI 首字响应目标小于 3 秒。

### 24.2 缓存

Redis 可用于：

- 客服在线状态和心跳 TTL。
- 公共待接待队列排序。
- 客服当前接待数缓存。
- 快捷回复缓存。
- AI 限流和每日额度。

MySQL 仍是会话状态和分配结果的最终事实。

### 24.3 定时任务

- 清理超时在线状态。
- 把超时 `assigned` 会话退回队列。
- 发送跟进提醒。
- 生成日报聚合。
- 对账并修复遗漏的服务会话。
- 清理过期导出文件。

---

## 25. 测试方案

### 25.1 后端单元测试

- 同一会话只能被一个客服领取。
- 达到并发上限后不再自动分配。
- 离线客服不参与分配。
- 转接后旧客服失去发送权限。
- 普通客服不能查看其他客服私有会话。
- 关闭和重开状态流转正确。
- 客户新消息能够创建或恢复服务会话。
- AI 低分、超时和强制关键词正确转人工。
- 满意度不能重复提交。
- 报表时间口径正确。

### 25.2 API 集成测试

- 登录、心跳、切换状态。
- 队列查询、领取、回复、转接、关闭。
- 客户资料、标签和备注。
- 快捷回复 CRUD。
- 知识文档上传、解析、查询和删除。
- AI 问答和转人工。
- 报表权限和导出。

### 25.3 前端测试

- 三栏布局在 1920、1440、1280、1024 宽度下不变形。
- 长昵称、长消息和长标签不撑破布局。
- 会话快速切换不串消息。
- WebSocket 重连后队列恢复。
- 网络失败有明确提示和重试。
- 深色旧变量不再污染黑白主题。
- Element Plus 输入框、下拉框、弹窗和表格风格统一。

### 25.4 真实联调

至少准备：

- 2 个客户账号。
- 2 个客服账号。
- 1 个主管账号。
- 1 个官方服务身份。

必须实际验证：

1. 客户 A 发消息进入公共队列。
2. 客服 1 领取并回复。
3. 客服 1 转给客服 2。
4. 客户侧历史消息保持同一会话。
5. 客服 2 添加标签、备注并关闭。
6. 客户评价。
7. 客户再次发送消息触发新服务轮次。
8. AI 回答知识库命中问题。
9. AI 遇到未知问题转人工。

---

## 26. 分阶段实施计划

以下工期按一名熟悉当前仓库的全栈开发为粗略估算，不包含产品反复改稿和外部模型/支付资质等待时间。

### 阶段 0：设计系统和基础骨架（3~5 个工作日）

- 黑白主题 token。
- 新布局、侧栏、顶栏和路由。
- Element Plus 全局样式覆盖。
- Mock 数据升级。
- 客服角色和权限骨架。

验收：所有旧页面统一黑白风格，桌面和平板不变形。

### 阶段 1：实时接待台（8~12 个工作日）

- 服务会话、客服状态和事件模型。
- 客户消息触发服务会话。
- 待接待和我的接待队列。
- 三栏工作台。
- 消息历史和消息发送。
- WebSocket 增量事件。
- 未读和重连恢复。

验收：两个客户、两个客服可以完成稳定实时接待。

### 阶段 2：分配、流转与运营工具（8~12 个工作日）

- 自动分配和并发上限。
- 领取、接受、转接、待跟进、关闭和重开。
- 标签、备注和跟进提醒。
- 快捷回复。
- 客户业务摘要。
- 操作时间线。

验收：客服日常操作不需要进入总后台。

### 阶段 3：AI 知识库（10~15 个工作日）

- FAQ 管理。
- 文档上传和解析。
- 检索与模型回答。
- AI 建议回复。
- AI 自动接待。
- 转人工规则。
- 未命中问题管理。
- AI 用量和熔断。

验收：标准问题能够自动回答，未知和高风险问题稳定转人工。

### 阶段 4：满意度与数据报表（5~8 个工作日）

- 评价卡片和提交接口。
- 核心指标。
- 客服绩效。
- AI 效果。
- 趋势图和导出。
- 日报聚合任务。

验收：报表数据与抽样会话人工计算一致。

### 阶段 5：灰度上线与稳定性（5~7 个工作日）

- 压测。
- 故障演练。
- 数据对账。
- 灰度客服账号。
- 监控和告警。
- 操作手册和回滚演练。

总工期预估：约 7~11 周。

---

## 27. 推荐开发批次

为减少大改风险，建议按以下批次提交：

1. `admin-kf` 黑白主题与布局，不改业务。
2. 服务数据模型与 AutoMigrate。
3. 客服在线状态和权限。
4. 服务会话创建、队列查询和事件记录。
5. 工作台只读会话和历史消息。
6. 客服专用发送消息。
7. 领取、分配和并发控制。
8. 转接、关闭、重开和跟进。
9. 客户标签、备注和业务摘要。
10. 快捷回复。
11. FAQ 知识库和 AI 建议回复。
12. AI 自动接待和转人工。
13. 满意度和报表。
14. 灰度、压测和上线文档。

每一批必须独立可构建、可回滚、可验证，避免一次提交同时修改所有前后端链路。

---

## 28. 上线与回滚

### 28.1 灰度策略

- 增加 `service_workbench_v1_enabled` 总开关。
- 增加客服账号级灰度开关。
- 第一批只开放给内部主管和 1~2 名客服。
- AI 自动回复默认关闭，先启用建议回复。
- 报表先只读，不影响接待主链路。

### 28.2 降级策略

- 工作台异常时客户仍可通过原 IM 私聊发送消息。
- AI 异常立即转人工，不阻塞客户消息。
- Redis 异常时在线状态和队列退化到 MySQL 查询。
- WebSocket 异常时前端使用短轮询恢复队列。
- 向量服务异常时退化到 FAQ 和关键词检索。

### 28.3 回滚边界

- 新数据表不与现有聊天表互相覆盖。
- 新增消息操作字段必须为可选字段。
- 关闭客服工作台开关后，现有普通聊天链路继续工作。
- 回滚前端不删除服务数据，便于重新上线。

---

## 29. 监控与告警

至少增加以下监控：

- 当前排队会话数。
- 最长等待时长。
- 在线客服数。
- 自动分配失败数。
- WebSocket 在线数和丢弃消息数。
- 客服消息发送失败率。
- AI 调用成功率、P95 耗时和 token 用量。
- AI 转人工率。
- 文档解析失败数。
- 报表聚合任务状态。

告警建议：

- 等待超过 SLA。
- 所有客服离线但仍有排队会话。
- AI 连续失败。
- 消息发送失败率异常。
- 服务会话和 IM 会话对账不一致。

---

## 30. 主要风险与处理

| 风险 | 影响 | 处理方式 |
|---|---|---|
| 转接时直接更换聊天成员 | 客户历史断裂 | 分离对外服务身份与实际操作客服 |
| 两个客服同时领取 | 重复回复客户 | 条件更新、事务和影响行数校验 |
| WebSocket 事件丢失 | 队列显示不一致 | 数据库为准，重连后全量校正 |
| AI 幻觉 | 错误承诺或误导 | 只基于知识库回答，低分转人工，显示引用 |
| AI 读取敏感信息 | 隐私风险 | 脱敏、白名单字段和日志审计 |
| 严格加密消息无法被服务端读取 | 工作台或 AI 不可用 | 明确客服会话加密策略和客户端提示 |
| 报表直接扫描消息库 | 性能下降 | 事件表和日报聚合 |
| 旧绿色主题局部残留 | 视觉不统一 | 全局 token、颜色扫描和截图验收 |
| 客服端拥有过大财务权限 | 资金风险 | 钱包、订单默认只读，写操作留总后台 |

---

## 31. 完成定义

只有同时满足以下条件，客服 MVP 才可标记完成：

- 黑白 UI 已覆盖登录、布局、工作台、客户、知识库和报表。
- 客服页面不再出现体验版和壳子文案。
- 客户咨询能够稳定进入队列。
- 领取和分配不存在并发重复。
- 消息收发和历史记录通过真实双账号验证。
- 转接后客户侧会话和历史保持连续。
- 标签、备注、快捷回复和跟进可用。
- AI 未知问题和高风险问题能够转人工。
- 报表口径通过抽样核对。
- 后端单元测试、API 集成测试和前端构建通过。
- Docker 本地环境完成端到端冒烟。
- 生产部署包包含最新 `kf-dist`、后端模型和配置说明。
- 已提供升级、回滚和客服操作文档。

---

## 32. 开工前需要确认的产品决策

建议采用以下默认决策：

| 决策项 | 推荐默认值 |
|---|---|
| 客服端主风格 | 黑色侧栏 + 白色内容区 |
| 登录后默认页 | 实时接待台 |
| 默认分配策略 | 在线客服中当前接待数最少者 |
| 默认最大并发 | 5 个会话 |
| 客户再次发言 | 已关闭则创建新服务轮次 |
| 转接后的客户身份 | 保持原官方服务身份不变 |
| AI 上线方式 | 先建议回复，再灰度自动回复 |
| AI 未命中 | 立即转人工并记录问题 |
| 钱包和订单权限 | 客服端只读 |
| 知识库向量服务 | 第二阶段可选 Qdrant，首期可降级 FAQ 检索 |
| 满意度 | 会话关闭后发送一次 |
| 加密策略 | 普通聊天不变，客服会话单独明确策略 |

确认这些决策后，可以直接从“阶段 0：黑白主题和客服工作台骨架”开始实施。
