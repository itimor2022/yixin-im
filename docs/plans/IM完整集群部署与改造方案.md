# 通用 IM 完整集群部署与改造方案

日期：2026-07-27  
适用项目：`genericim-tongba`  
目标：在不改变客户端协议语义的前提下，让 REST、WebSocket、上传、后台任务和数据层支持多节点部署，并具备滚动发布、故障转移和回滚能力。

## 1. 结论

当前项目具备部分横向扩展基础，但还不能直接宣称完整支持集群：

| 模块 | 当前状态 | 集群风险 |
| --- | --- | --- |
| REST API | 大部分请求使用数据库和 Redis | 可扩展，但需要统一配置和节点标识 |
| 登录、缓存、限流 | 已使用 Redis | 可以共享，但 Redis 需要高可用 |
| WebSocket | `Hub`、用户连接和会话订阅保存在进程内 | 不同 API 节点之间无法完整广播 |
| 消息队列 | Redis 队列用于任务消费 | 不等同于 WebSocket 广播，不能直接复用 |
| 上传文件 | Compose 默认使用本地 volume | 多机器之间文件不可见 |
| 定时任务 | 每个 API 进程启动自己的 ticker | 多节点会重复执行 |
| Docker | `compose.yaml` 只有一个 API，固定 `container_name` 和宿主机端口 | 不能直接 `--scale api=N` |

正式集群上线前必须完成：

1. WebSocket 跨节点事件总线。
2. 共享对象存储。
3. 后台任务分布式锁和幂等保护。
4. 可扩展的反向代理和 WebSocket 配置。
5. 多节点故障、重连、重复消费和滚动发布测试。

## 2. 目标架构

### 2.1 第一阶段：两 API 节点

适用于先提升并发，不立即改造数据库高可用：

```text
                    +-------------------+
                    | Nginx / HAProxy   |
                    | HTTPS + WebSocket |
                    +---------+---------+
                              |
                +-------------+-------------+
                |                           |
        +-------v-------+           +-------v-------+
        | API Node A    |           | API Node B    |
        | Go + local Hub|           | Go + local Hub|
        +---+-------+---+           +---+-------+---+
            |       |                   |       |
            +-------+---------+---------+-------+
                    |
        +-----------+------------+----------------+
        |                        |                |
   MySQL Primary          MongoDB Replica Set   Redis
   (业务写入)              (消息/历史)           (缓存/总线/锁)
                    |
              S3 / OSS / 七牛
              (媒体和附件)
```

第一阶段可以保持 MySQL、MongoDB、Redis 为单实例，但它们必须独立于 API 容器，并且有备份和恢复流程。API 节点之间不能依赖本地文件和本地内存作为权威状态。

### 2.2 第二阶段：数据层高可用

当单节点数据库成为瓶颈或单点故障不可接受时，再升级为：

```text
Nginx / HAProxy
        |
  API Node A/B/C
        |
  Redis Sentinel 或 Redis Cluster
        |
  MySQL InnoDB Cluster / 云数据库高可用
        |
  MongoDB Replica Set
        |
  S3 / OSS
```

优先使用云数据库或托管 Redis，避免在应用集群之外再维护一套复杂的数据库选主系统。

## 3. 当前代码基线

### 3.1 WebSocket

`backend/internal/ws/hub.go` 中的 `Hub` 保存：

- `userID -> ClientSet`
- `chatID -> ClientSet`
- 当前进程在线人数
- 当前进程广播队列

文件注释已经明确说明 Hub 只负责进程内分发。它不是消息权威存储，因此可以保留为本地连接路由器，但必须增加跨节点事件输入。

### 3.2 Redis

`backend/cmd/server/main.go` 已初始化 Redis、缓存和消息队列。`backend/internal/mq/queue.go` 使用 Redis 列表和延迟队列进行任务消费。

Redis 队列是“一个任务由一个消费者处理”的语义，不能直接用于 WebSocket 广播。WebSocket 广播需要“每个 API 节点都收到一份事件”的语义，应增加 Redis Streams 或专用 Pub/Sub。

### 3.3 上传

`compose.yaml` 默认将 `genericim_uploads` 挂载到 API 容器，`backend/config.yaml` 默认 storage provider 为 local。这个方案只适用于单机或共享 NAS，不适用于多台独立服务器。

项目已经有 S3/对象存储抽象，集群生产环境应统一切换到 S3、OSS 或七牛云。

### 3.4 后台任务

以下服务由 API 进程启动或内部 ticker 驱动：

- `wallet_cron_service.go`
- `call_cleanup_service.go`
- `media_object_service.go`
- `chat_auto_message_service.go`
- Redis 延迟消息轮询

多节点后每个节点都会启动一份，必须使用分布式锁、leader 模式或拆分为独立 worker。

## 4. WebSocket 集群改造

### 4.1 事件分类

将 WebSocket 事件分为两类：

| 类型 | 示例 | 推荐机制 | 丢失处理 |
| --- | --- | --- | --- |
| 持久业务事件 | 新消息、撤回、编辑、群成员变化、系统通知 | Redis Streams | 客户端按 `seq` 补偿 |
| 瞬时状态事件 | typing、临时在线状态、呼叫铃状态 | Redis Pub/Sub | 丢失可接受，下一状态覆盖 |

不应把持久业务事件只放在 Redis Pub/Sub，因为订阅断开期间事件会丢失。

### 4.2 事件信封

所有跨节点事件统一使用如下结构：

```json
{
  "event_id": "uuid",
  "event_type": "message.created",
  "chat_id": "uuid",
  "user_ids": ["uuid"],
  "seq": 12345,
  "origin_node": "api-a",
  "occurred_at": "2026-07-27T12:00:00Z",
  "payload": {}
}
```

要求：

- `event_id` 全局唯一。
- `seq` 使用数据库权威序号，不能使用节点本地自增值。
- `origin_node` 用于排查重复和延迟。
- 消费端必须幂等，同一个 `event_id` 重复到达不能造成业务重复。
- 业务写入数据库成功后再发布事件。

### 4.3 Streams 消费组

每个 API 节点使用独立 consumer group，以保证每个节点都收到完整事件：

```text
Stream: genericim:ws:events
Group:  genericim:ws-node:api-a
Group:  genericim:ws-node:api-b
```

每个节点内部仍由当前 `Hub` 将事件路由到本节点的本地连接。节点重启后使用 `XREADGROUP` 和 pending message reclaim 继续消费。

瞬时事件可以使用：

```text
Channel: genericim:ws:ephemeral
```

节点断开期间不要求补发 typing 等瞬时状态。

### 4.4 发送流程

```text
HTTP/WS 请求
    |
    +-- MySQL/MongoDB 持久化
    |
    +-- 写入 Redis Stream
    |
    +-- 所有 API 节点消费
    |
    +-- 每个节点的本地 Hub 路由
    |
    +-- 客户端按 message_id/seq 去重
```

不能只在当前节点调用 `hub.SendToUser` 后结束，否则另一节点上的用户仍然收不到消息。

### 4.5 在线状态

当前 Hub 的在线人数只能代表单节点。集群后：

- Redis 保存 `presence:user:{id}`，使用 TTL。
- 节点连接建立时写入节点和设备信息。
- 心跳续期，断开时只删除当前连接对应的 token。
- “用户是否在线”以 Redis 中是否存在有效连接为准。
- 管理端统计区分 `local_online` 和 `global_online`。

## 5. 上传和媒体处理

### 5.1 生产存储

集群生产环境禁止使用 API 节点本地目录作为公共媒体存储。推荐配置：

```yaml
storage:
  provider: s3
  s3:
    region: ap-southeast-1
    bucket: genericim-media-prod
    public_base_url: https://media.example.com
```

密钥通过环境变量或密钥管理系统注入，不提交到仓库。

### 5.2 媒体处理

媒体处理服务应使用对象存储 URL 或预签名 URL，不依赖某一个 API 节点的本地临时文件。处理结果写回对象存储，并在数据库中原子推进状态：

```text
uploading -> uploaded -> processing -> processed
                         \-> failed
```

同一个媒体对象必须使用数据库幂等键和对象 key，避免多个节点重复生成不可追踪的文件。

## 6. 后台任务和分布式锁

### 6.1 方案选择

优先级如下：

1. 将后台任务拆成独立 `worker` 服务，只部署一个或多个 worker。
2. 过渡阶段在 API 内保留 ticker，但使用 Redis 锁。
3. 所有任务保留数据库幂等约束，锁失效不能导致重复扣款或重复发放。

### 6.2 锁规范

锁 key 示例：

```text
genericim:lock:wallet-cron
genericim:lock:call-cleanup
genericim:lock:media-cleanup
genericim:lock:chat-auto-message
```

要求：

- 使用 Redis `SET NX EX`。
- value 使用 `node_id + random_token`。
- 释放锁必须校验 value，不能无条件 `DEL`。
- 任务执行时间超过 TTL 时需要续期或缩短批次。
- 任务日志记录 `node_id`、锁等待、执行耗时、处理数量。

## 7. 负载均衡配置要求

Nginx/HAProxy 至少需要满足：

```nginx
location /api/v1/ws {
    proxy_pass http://genericim_api;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}

location /api/ {
    proxy_pass http://genericim_api;
    proxy_http_version 1.1;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

说明：

- WebSocket 一条连接建立后会固定在一个节点，短期可以配置粘性会话。
- 粘性会话不是跨节点消息正确性的保证，Redis 事件总线仍然必须存在。
- API 节点必须提供 `/health` 和 `/ready`。
- `/ready` 应检查必要的 MySQL、MongoDB、Redis 连接状态。
- 正在排空的节点先从负载均衡摘除，再等待 WebSocket 连接自然关闭或发送重连提示。

## 8. Compose 和部署改造

当前 `compose.yaml` 需要调整：

1. 删除 API 的固定 `container_name`。
2. 不再为每个 API 实例绑定宿主机 `8080:8080`。
3. 让 API 只暴露 Compose 内部端口，由 Nginx 访问。
4. 增加 `GENERIC_IM_NODE_ID`、Redis Streams consumer group 和集群开关。
5. 将数据库和 Redis 的端口限制在内网。
6. 将 API、worker、Nginx 拆成可独立扩缩容的服务。

单机多实例测试可以使用：

```powershell
docker compose up -d --scale api=2
```

正式多机部署应使用 Kubernetes、Docker Swarm 或云容器服务，并由外部负载均衡器分发流量。

建议增加的配置字段：

```yaml
cluster:
  enabled: true
  node_id: api-a
  ws_event_backend: redis_streams
  ws_stream_key: genericim:ws:events
  ws_ephemeral_channel: genericim:ws:ephemeral
  lock_prefix: genericim:lock
```

## 9. 数据层策略

### 9.1 MySQL

第一阶段使用一个主库，所有 API 节点连接同一个主库。不要在没有读写分离抽象前直接让业务随机读从库，否则会引入刚写入数据不可见的问题。

第二阶段再增加：

- 主从复制或托管高可用。
- 自动故障切换。
- 连接池上限。
- 慢查询和锁等待监控。
- 备份恢复演练。

### 9.2 MongoDB

生产使用 Replica Set，连接串必须包含副本集信息和正确的读写偏好。消息历史写入不能依赖某个 API 节点的本地 Mongo 连接状态。

### 9.3 Redis

第一阶段使用独立 Redis 主节点并做好 AOF、快照和监控。第二阶段根据吞吐选择 Sentinel 或 Cluster。

Redis 同时承担缓存、限流、队列、Streams、Pub/Sub 和分布式锁时，应设置前缀、TTL 和容量上限，避免不同用途互相挤压。

## 10. 安全和隔离

- API、数据库、Redis 只开放内网端口。
- Redis 必须设置密码或 ACL，禁止公网访问。
- 对象存储使用最小权限 IAM。
- WebSocket origin 白名单不能使用 `*`。
- 节点之间的内部事件不携带明文密码、短信验证码或完整 token。
- 日志中只记录 `event_id`、用户 ID 摘要和节点 ID。
- 所有节点使用统一时钟同步。
- 发布包、配置、密钥和数据库备份分离管理。

## 11. 分阶段开发计划

### P0：集群基础

- 增加 `node_id` 和集群配置。
- 删除 Compose API 的固定容器名和宿主机端口冲突。
- 增加 `/health`、`/ready` 和优雅停机。
- 增加跨节点日志字段。
- 增加 API 节点扩缩容脚本。

验收：两个 API 节点同时启动，REST 登录、聊天列表、联系人和管理端请求均正常。

### P1：WebSocket 跨节点

- 新增 Redis Streams 事件总线。
- 将消息、撤回、编辑、成员变化和系统通知接入事件总线。
- 增加每节点独立 consumer group。
- 增加事件幂等和 pending reclaim。
- typing 等瞬时事件接入 Pub/Sub。
- 增加全局在线状态 TTL。

验收：客户端 A 连接 API-1，客户端 B 连接 API-2，双方聊天、撤回、群事件和在线状态均正常。

### P2：共享媒体和后台任务

- 默认生产 storage provider 切换为 S3/OSS。
- 媒体处理改为对象存储输入输出。
- 为所有 cron 增加 Redis 锁或拆分 worker。
- 增加任务幂等和失败重试。

验收：文件上传到 API-1 后从 API-2 下载成功；两个节点同时执行任务时业务只生效一次。

### P3：高可用数据层

- MySQL 高可用或托管主库。
- MongoDB Replica Set。
- Redis Sentinel/Cluster。
- 备份恢复和跨区故障演练。

验收：单个 API 节点、单个 Redis 节点或单个 Mongo 节点故障时，业务按设计恢复，客户端能够重连和补偿。

## 12. 集群验收清单

### 流量和连接

- [ ] HTTP 请求能够在多个 API 节点之间切换。
- [ ] WebSocket Upgrade 和长连接超时配置正确。
- [ ] 节点摘除后客户端能自动重连。
- [ ] 单节点重启不会造成消息永久丢失。

### 消息和状态

- [ ] 跨节点私聊消息可达。
- [ ] 跨节点群消息可达。
- [ ] 撤回、编辑、已读和系统通知可达。
- [ ] `message_id` 和 `seq` 去重有效。
- [ ] 在线状态不会因单节点视角错误显示。
- [ ] typing 丢失不会影响持久业务状态。

### 数据和媒体

- [ ] 多节点读取同一用户、会话和消息数据。
- [ ] 多节点上传和下载同一文件。
- [ ] 媒体转码结果不会覆盖错误对象。
- [ ] 数据库唯一约束阻止重复业务写入。

### 任务和运维

- [ ] 钱包定时任务同一时间只有一个执行者。
- [ ] 清理任务支持重试和断点。
- [ ] Redis、数据库和对象存储故障有明确降级行为。
- [ ] 日志包含 node_id 和 event_id。
- [ ] 有节点摘除、滚动发布和回滚脚本。
- [ ] 有备份恢复演练记录。

## 13. 发布、灰度和回滚

发布顺序：

1. 先部署兼容旧节点的 API 版本。
2. 开启事件写入但暂不启用跨节点消费。
3. 部署所有节点的 Streams/Pub/Sub 消费者。
4. 开启两个节点之间的流量。
5. 观察消息延迟、重复率、Redis pending 和 WebSocket 重连率。
6. 再切换对象存储和后台任务锁。

回滚要求：

- 新旧 API 都能读取同一数据库数据。
- 事件格式向后兼容，新增字段不能改变旧节点解析。
- 可通过配置关闭跨节点广播并恢复单节点模式。
- 回滚不能删除 Redis Stream、数据库业务记录或对象存储文件。

## 14. 最终建议

第一期不要同时改造 API、数据库、Redis 和存储。建议先完成：

```text
2 个 API 节点
1 个 Nginx/HAProxy
1 个共享 Redis
1 个共享 MySQL/Mongo
S3/OSS 媒体存储
Redis Streams WebSocket 总线
Redis 分布式任务锁
```

完成 P0-P2 后，系统才可以对外宣称“支持多节点集群部署”。数据库高可用属于下一阶段的可靠性升级，不应和第一次 API 横向扩展绑定实施。
