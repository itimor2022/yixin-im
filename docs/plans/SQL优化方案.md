# SQL 优化方案

## 目标

本方案针对当前 IM 项目的 MySQL/GORM 数据结构和高频查询路径做优化，重点提升以下场景：

- 聊天列表加载速度
- 群成员、共同群、共同联系人查询速度
- 动态广场、我的动态、后台动态审核列表速度
- 钱包交易流水、充值/提现订单列表速度
- 设备、通知、后台诊断等管理查询稳定性

优化原则：

- 优先补齐高频查询的联合索引。
- 避免对大表使用深分页 `OFFSET`。
- 避免在索引列上使用函数导致索引失效。
- 对搜索、话题、统计类查询做结构化改造，而不是只靠单列索引硬顶。

## 优先级总览

| 优先级 | 优化项 | 影响模块 | 收益 |
| --- | --- | --- | --- |
| P0 | `user_chats` 聊天列表联合索引 | 消息首页 | 很高 |
| P0 | `chat_members` 双向成员索引 | 群/频道、权限、共同群 | 很高 |
| P0 | `moments` 动态列表联合索引 | 发现/动态/后台审核 | 高 |
| P0 | `transactions` 钱包流水联合索引 | 钱包 | 高 |
| P1 | 动态、交易、聊天列表改游标分页 | 所有大列表 | 高 |
| P1 | 统计查询去掉 `DATE(created_at)` | 后台统计 | 中高 |
| P1 | 联系人、设备、订单补组合索引 | 设置/后台/钱包 | 中 |
| P2 | 搜索改 FULLTEXT 或搜索服务 | 全局搜索/动态搜索 | 中高 |
| P2 | 话题 JSON 拆表 | 动态话题 | 中高 |

## 建议索引

以下 SQL 以 MySQL 8 为参考。若 MySQL 版本低于 8，`DESC` 语法即使可写也可能不会真正按降序存储，但联合索引前缀仍然有价值。

### 1. 聊天列表 `user_chats`

当前高频查询：

```sql
SELECT *
FROM user_chats
WHERE user_id = ?
ORDER BY is_pinned DESC, sort_time DESC
LIMIT ?, ?;
```

建议索引：

```sql
CREATE INDEX idx_user_chats_user_pin_sort
ON user_chats (user_id, is_pinned, sort_time DESC, id DESC);

CREATE INDEX idx_user_chats_user_updated
ON user_chats (user_id, updated_at DESC, id DESC);
```

收益：

- 消息首页按置顶和最近消息排序时避免 filesort。
- 后台诊断最近会话查询也能复用索引。

### 2. 群成员 `chat_members`

当前模型已有唯一索引 `(chat_id, user_id)`，适合按群查某个成员，但很多地方也会按 `user_id` 查用户加入的群。

建议索引：

```sql
CREATE INDEX idx_chat_members_user_chat
ON chat_members (user_id, chat_id);

CREATE INDEX idx_chat_members_chat_role_joined
ON chat_members (chat_id, role DESC, joined_at ASC, user_id);
```

收益：

- 优化用户是否在群内、共同群、推送目标成员、会议成员查询。
- 优化成员列表按角色和加入时间排序。

### 3. 动态 `moments`

当前高频查询：

```sql
SELECT *
FROM moments
WHERE status = 1 AND visibility = 1
ORDER BY created_at DESC
LIMIT ?, ?;
```

建议索引：

```sql
CREATE INDEX idx_moments_status_visibility_created
ON moments (status, visibility, created_at DESC, id DESC);

CREATE INDEX idx_moments_user_status_created
ON moments (user_id, status, created_at DESC, id DESC);

CREATE INDEX idx_moments_status_created
ON moments (status, created_at DESC, id DESC);
```

收益：

- 动态广场、我的动态、后台审核列表都会更稳。
- 后台按状态筛选动态时可减少排序成本。

注意：

- `content LIKE '%keyword%'` 不能有效利用普通 BTree 索引。
- `JSON_CONTAINS(topics, ?)` 也很难用普通索引优化，建议见后文“结构化改造”。

### 4. 动态点赞和评论

建议索引：

```sql
CREATE UNIQUE INDEX uk_moment_likes_moment_user
ON moment_likes (moment_id, user_id);

CREATE INDEX idx_moment_likes_user_created
ON moment_likes (user_id, created_at DESC, id DESC);

CREATE INDEX idx_moment_comments_moment_status_created
ON moment_comments (moment_id, status, created_at DESC, id DESC);

CREATE INDEX idx_moment_comments_user_status_created
ON moment_comments (user_id, status, created_at DESC, id DESC);

CREATE INDEX idx_moment_comments_parent_status_created
ON moment_comments (parent_id, status, created_at DESC, id DESC);
```

收益：

- 防止同一用户重复点赞同一动态。
- 优化“我的收到的评论/点赞”、动态详情评论列表。

上线前注意：

- 创建 `uk_moment_likes_moment_user` 前需要先清理历史重复点赞数据。

### 5. 钱包流水 `transactions`

当前高频查询：

```sql
SELECT *
FROM transactions
WHERE user_id = ?
ORDER BY created_at DESC
LIMIT ?, ?;
```

以及：

```sql
SELECT *
FROM transactions
WHERE user_id = ? AND type = ?
ORDER BY created_at DESC
LIMIT ?, ?;
```

建议索引：

```sql
CREATE INDEX idx_transactions_user_created
ON transactions (user_id, created_at DESC, id DESC);

CREATE INDEX idx_transactions_user_type_created
ON transactions (user_id, type, created_at DESC, id DESC);
```

收益：

- 钱包交易明细和后台用户交易明细都会受益。

### 6. 红包、转账、充值、提现

建议索引：

```sql
CREATE INDEX idx_red_packets_status_expired
ON red_packets (status, expired_at, id);

CREATE INDEX idx_red_packets_chat_created
ON red_packets (chat_id, created_at DESC, id DESC);

CREATE INDEX idx_transfers_status_expired
ON transfers (status, expired_at, id);

CREATE INDEX idx_transfers_sender_created
ON transfers (sender_id, created_at DESC, id DESC);

CREATE INDEX idx_transfers_receiver_created
ON transfers (receiver_id, created_at DESC, id DESC);

CREATE INDEX idx_recharge_orders_user_created
ON recharge_orders (user_id, created_at DESC, id DESC);

CREATE INDEX idx_recharge_orders_status_created
ON recharge_orders (status, created_at DESC, id DESC);

CREATE INDEX idx_withdraw_requests_user_created
ON withdraw_requests (user_id, created_at DESC, id DESC);

CREATE INDEX idx_withdraw_requests_status_created
ON withdraw_requests (status, created_at DESC, id DESC);
```

收益：

- 红包/转账过期任务更快。
- 充值提现后台审核列表更快。
- 用户侧订单列表更快。

### 7. 联系人和黑名单

建议索引：

```sql
CREATE UNIQUE INDEX uk_contacts_user_contact
ON contacts (user_id, contact_user_id);

CREATE INDEX idx_contacts_user_status_updated
ON contacts (user_id, status, updated_at DESC, id DESC);

CREATE INDEX idx_contacts_contact_status_user
ON contacts (contact_user_id, status, user_id);

CREATE UNIQUE INDEX uk_user_blocks_user_blocked
ON user_blocks (user_id, blocked_user_id);
```

收益：

- 联系人列表、共同联系人、是否好友校验更快。
- 防止重复联系人和重复拉黑记录。

上线前注意：

- 创建唯一索引前需要先清理重复联系人数据。

### 8. 设备、会话、推送日志

建议索引：

```sql
CREATE UNIQUE INDEX uk_user_devices_user_device
ON user_devices (user_id, device_id);

CREATE INDEX idx_user_devices_user_active
ON user_devices (user_id, last_active DESC, id DESC);

CREATE INDEX idx_user_sessions_user_active
ON user_sessions (user_id, last_active DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_user_occurred
ON push_delivery_logs (user_id, occurred_at DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_success_occurred
ON push_delivery_logs (success, occurred_at DESC, id DESC);
```

收益：

- 设置页设备数量、设备管理、后台用户诊断更快。
- 推送日志排查更快。

## 查询改造建议

### 1. 大列表改游标分页

当前很多列表使用：

```sql
LIMIT offset, page_size
```

数据多后，越翻越慢。建议聊天列表、动态列表、钱包流水改为游标分页。

聊天列表示例：

```sql
SELECT *
FROM user_chats
WHERE user_id = ?
  AND (
    sort_time < ?
    OR (sort_time = ? AND id < ?)
  )
ORDER BY is_pinned DESC, sort_time DESC, id DESC
LIMIT ?;
```

动态列表示例：

```sql
SELECT *
FROM moments
WHERE status = 1
  AND visibility = 1
  AND (
    created_at < ?
    OR (created_at = ? AND id < ?)
  )
ORDER BY created_at DESC, id DESC
LIMIT ?;
```

注意：

- 置顶聊天如果要与普通聊天混排，游标需要同时带上 `is_pinned`、`sort_time`、`id`。
- 前端返回 `next_cursor`，下一页用 cursor 请求。

### 2. 统计查询不要在索引列上套函数

当前后台统计里有类似：

```sql
WHERE DATE(created_at) = CURDATE()
```

这会让 `created_at` 索引失效。建议改为：

```sql
WHERE created_at >= ?
  AND created_at < ?
```

Go 侧传入今天零点和明天零点。

### 3. 列表接口减少无条件 `COUNT(*)`

很多接口每次分页都会先 `COUNT(*)`，数据大时会变慢。

建议：

- 用户侧列表返回 `has_more`，少做总数。
- 后台管理列表可以保留总数，但对复杂筛选做缓存或异步统计。
- 首屏列表优先查 `page_size + 1` 条判断是否还有下一页。

### 4. 搜索改造

当前搜索常见写法：

```sql
LIKE '%keyword%'
```

普通索引无法优化这种前后模糊查询。

建议：

- 用户名、手机号、短 ID 保持精确查询。
- 昵称、备注、动态正文使用 `FULLTEXT` 或独立搜索服务。
- 中文搜索可评估 MySQL ngram FULLTEXT，或后续接 Meilisearch/Elasticsearch。

可选 SQL：

```sql
ALTER TABLE users
ADD FULLTEXT INDEX ft_users_name (username, nickname);

ALTER TABLE moments
ADD FULLTEXT INDEX ft_moments_content (content);
```

### 5. 动态话题 JSON 拆表

当前按话题筛选使用 `JSON_CONTAINS(topics, ?)`，数据增长后会慢。

建议新增表：

```sql
CREATE TABLE moment_topics (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  moment_id BIGINT UNSIGNED NOT NULL,
  topic VARCHAR(100) NOT NULL,
  created_at DATETIME NOT NULL,
  UNIQUE KEY uk_moment_topic (moment_id, topic),
  KEY idx_topic_moment (topic, moment_id)
);
```

发布动态时同步写入 `moment_topics`，查询话题动态时走：

```sql
SELECT m.*
FROM moment_topics mt
JOIN moments m ON m.id = mt.moment_id
WHERE mt.topic = ?
  AND m.status = 1
  AND m.visibility = 1
ORDER BY m.created_at DESC, m.id DESC
LIMIT ?;
```

## 上线步骤

### 第一步：确认慢查询

开启 MySQL 慢查询日志：

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.5;
```

收集至少一天高峰期慢查询，重点看：

- `user_chats`
- `chat_members`
- `moments`
- `transactions`
- `contacts`
- `user_devices`

### 第二步：检查重复数据

创建唯一索引前先查重复。

联系人重复：

```sql
SELECT user_id, contact_user_id, COUNT(*) AS cnt
FROM contacts
GROUP BY user_id, contact_user_id
HAVING cnt > 1;
```

动态点赞重复：

```sql
SELECT moment_id, user_id, COUNT(*) AS cnt
FROM moment_likes
GROUP BY moment_id, user_id
HAVING cnt > 1;
```

设备重复：

```sql
SELECT user_id, device_id, COUNT(*) AS cnt
FROM user_devices
GROUP BY user_id, device_id
HAVING cnt > 1;
```

### 第三步：低峰期创建索引

MySQL 8 可优先尝试在线 DDL：

```sql
ALTER TABLE user_chats
ADD INDEX idx_user_chats_user_pin_sort (user_id, is_pinned, sort_time DESC, id DESC),
ALGORITHM=INPLACE,
LOCK=NONE;
```

不同 MySQL 版本和表结构对在线 DDL 支持不同，执行前需在测试库验证。

### 第四步：验证执行计划

使用：

```sql
EXPLAIN ANALYZE
SELECT *
FROM user_chats
WHERE user_id = 1
ORDER BY is_pinned DESC, sort_time DESC
LIMIT 20;
```

重点看：

- 是否命中预期索引
- 是否仍然出现 `Using filesort`
- 扫描行数是否明显下降

### 第五步：逐步改接口分页

建议顺序：

1. 聊天列表改 cursor
2. 动态列表改 cursor
3. 钱包流水改 cursor
4. 后台列表保留 page/page_size，但增加索引和筛选限制

## 回滚方案

索引回滚示例：

```sql
DROP INDEX idx_user_chats_user_pin_sort ON user_chats;
DROP INDEX idx_chat_members_user_chat ON chat_members;
DROP INDEX idx_moments_status_visibility_created ON moments;
DROP INDEX idx_transactions_user_created ON transactions;
```

查询改造回滚：

- 保留旧分页参数 `page/page_size` 一段时间。
- 新增 `cursor` 参数时兼容旧客户端。
- 后端可根据是否传 `cursor` 决定使用新旧查询。

## 最先推荐执行的 SQL

第一批建议先上这些，风险低、收益明显：

```sql
CREATE INDEX idx_user_chats_user_pin_sort
ON user_chats (user_id, is_pinned, sort_time DESC, id DESC);

CREATE INDEX idx_chat_members_user_chat
ON chat_members (user_id, chat_id);

CREATE INDEX idx_chat_members_chat_role_joined
ON chat_members (chat_id, role DESC, joined_at ASC, user_id);

CREATE INDEX idx_moments_status_visibility_created
ON moments (status, visibility, created_at DESC, id DESC);

CREATE INDEX idx_moments_user_status_created
ON moments (user_id, status, created_at DESC, id DESC);

CREATE INDEX idx_transactions_user_created
ON transactions (user_id, created_at DESC, id DESC);

CREATE INDEX idx_transactions_user_type_created
ON transactions (user_id, type, created_at DESC, id DESC);
```

第二批再处理唯一索引、搜索、话题拆表和游标分页。
