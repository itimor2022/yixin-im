我先说明一下：你的仓库里其实已经存在一份完整的集群改造规划文档 —— docs/plans/IM完整集群部署与改造方案.md（464 行，2026-07-27），并被 docs/ARCHITECTURE.md 引用。但当前代码尚未真正落地任何集群改造。我下面把规划与代码现状对照，给你一份"现状评估 + 改造路线 + 部署架构 + 代码改造清单"的完整答复。

一、现状评估：哪些已经"基本支持集群"，哪些还不行
| 模块 | 当前实现 | 集群适配度 | 风险 |
|------|----------|------------|------|
| REST API | Gin路由，无状态 | ✅ 直接横向扩 | 仅需加 node_id 日志和 /ready |
| JWT / 登录态 | authsession/session_state.go 用 Redis存 session version、token revoked | ✅ 已 Redis化 | 需要 Redis 高可用 |
| 限流 | middleware.RateLimit(cache) 用 Redis | ✅ | 同上 |
| 缓存 | internal/cache 走 Redis | ✅ | 同上 |
| 消息队列 | internal/mq Redis List + 延迟 ZSet | ✅ 任务可被任意节点消费 | 它是"任务队列"，不能用作 WebSocket 广播 |
| WebSocket Hub | internal/ws/hub.go 用户/会话连接全部存进程内 ShardedMap | ❌ 致命 | 用户连 A 节点，发消息的请求落在 B 节点时，B 节点的 Hub 根本不知道这个用户存在 → 消息丢 |
| 在线状态 | hub.IsUserOnline(userID)、GetOnlineCount() 全看本进程内存 | ❌ | 多节点下数字不一致，"是否在线"答案错 |
| 上传文件 | compose.yaml 默认 genericim_uploads 卷 → /app/uploads | ❌ | 多机器之间文件互相看不到 |
| 后台任务 | wallet_cron_service.go、call_cleanup_service.go、媒体处理、聊天自动消息、Redis 延迟轮询 —都在 API 进程内 go ticker | ❌ | 多节点重复执行，可能重复扣款/重复发放 |
| compose.yaml | api 服务写死 container_name: genericim-api、端口 8080:8080 | ❌ | docker compose up --scale api=N 会因端口冲突直接失败 |
| Nginx | 没有，只有 admin-nginx.conf 给后台用 | ❌ | WS 升级和长连接超时没人管 |
| 健康检查 | 只有 /health（固定返回 ok） | ⚠️ 半 | 没有 /ready，且 /health 不查下游依赖 |
| 节点标识 | 完全没有 node_id / instance_id | ❌ | 日志/锁/事件无追溯 |

结论：REST 部分基本可扩，WebSocket 跨节点、上传共享、后台任务单点、运维编排这 4 块是真要做集群的核心改造点。

二、目标架构（两阶段）
阶段一：API 横向扩展 + 数据共享（推荐起步）

                   ┌─────────────────────────────┐ │  Nginx / HAProxy（边缘 LB）  │
                   │  HTTPS + WebSocket Upgrade │
                   │  /api/v1/ws sticky 或 least_conn│
                   └──────────────┬──────────────┘
                                  │
 ┌─────────────────┼─────────────────┐
                │                 │                 │
         ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
         │  api-node-a │   │  api-node-b │   │  api-node-c │  ← 任意扩缩         │  Go + 本地  │   │  Go + 本地  │   │  Go + 本地  │
         │  Hub │   │  Hub        │   │  Hub        │
         └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
                │                 │                 │
                └────────┬────────┴────────┬────────┘
                         │                 │
 ┌────────────▼─┐         ┌─────▼──────────┐
            │  Redis 主从   │         │  MySQL 主库     │  ← 起步可单实例
            │  + Streams │         │  MongoDB 单/副本 │
            │  + 分布式锁   │         └────────────────┘
            └──────────────┘
                         │
                  ┌──────▼───────┐
                  │ S3 / OSS / 七牛│  ← 媒体共享存储
                  └──────────────┘
关键点：

每个 API 节点仍是"无状态"：业务状态全部在 MySQL/Redis/Mongo/S3。
WebSocket Hub 仍然在每个节点进程内，但它不再是消息权威，只负责把"我从事件总线收到的事件"投递到本节点的连接。
真正的"集群"靠 Redis Streams 做跨节点事件总线，详见下文。
阶段二：数据层高可用（可选升级）

Redis Sentinel / Cluster ↓
MySQL InnoDB Cluster / 阿里云 RDS 高可用
MongoDB Replica Set
S3 / OSS
建议：阶段一就直接用云托管的 MySQL/MongoDB/Redis，避免在应用层之外再维护一套选主系统。

三、改造总览（按优先级4 个 P）
P0：集群基础（必做，否则没法 --scale）
config 增加 cluster 段（enabled、node_id、ws_event_backend、lock_prefix）。
启动时若未配置 node_id，自动用 hostname + pid +随机串 生成，保证唯一。
增加 /ready 路由（检查 MySQL db.Ping()、MongoDB Ping、Redis Ping），/health保持简单 ok。
增加优雅停机：SIGTERM → 停止接受新连接 → 等 WebSocket 自然关闭或强制关闭 → 退出。
compose.yaml 去掉 container_name、端口改 "8080" 不映射宿主机（或 "${API_PORT:-8080}:8080"），加 deploy.replicas:2 演示。
日志中间件加 node_id、request_id。
给所有后台 ticker 增加 Redis 分布式锁包装。
P1：WebSocket 跨节点（核心）
新增 internal/wsevent 包，封装 Redis Streams + Pub/Sub 两类后端。
定义统一事件信封：event_id / event_type / chat_id / user_ids / seq / origin_node / occurred_at / payload。
每个节点启动时按 node_id 加入 consumer group（XREADGROUP GROUP genericim:ws-node:<node_id>）。
改造所有"通过 Hub 直接 push"的调用点：改为 写库成功后再 Publish 到 Stream，由所有节点消费再走本地 Hub 投递。
IsUserOnline / GetOnlineCount / GetChatOnlineCount 改为查 Redis 中的 presence:* 集合 + TTL 心跳。
typing、铃状态等瞬时事件走 Pub/Sub。
消费端幂等：SET NX 标记 event_id 已处理，重复到达直接 ACK。
P2：共享媒体 + 后台任务单点化
生产配置强制 storage.provider: s3（OSS/七牛同理）。
媒体处理读取对象存储 URL，不再依赖本地临时文件。
所有后台 ticker（wallet_cron、call_cleanup、media_object、chat_auto_message、MQ 延迟轮询的 processDelayed）都加 Redis 锁（SET NX EX + token，释放时 Lua 校验）。
数据库侧对所有"会被并发执行的 cron任务"加唯一约束做兜底（比如 expired_at 处理过的红包记录打 processed_at，重放时直接跳过）。
倾向：直接把这些 ticker 拆到独立 worker 服务，API 进程不再跑 cron。
P3：数据层高可用
按需做 Redis Sentinel/Cluster、MySQL 主从、Mongo 副本集，并演练切换。

四、代码改造清单（具体到文件）
下面给出可直接落到代码的改动。你说"开始改"，我就可以按这个清单推进。

1) 配置：backend/internal/config/config.go
新增结构体与字段（兼容老配置，无 cluster 段时按单机模式运行）：


type ClusterConfig struct {
    Enabled            bool   `yaml:"enabled"`             // 总开关
    NodeID             string `yaml:"node_id"`              // 留空则自动生成
    WSEventBackend     string `yaml:"ws_event_backend"`     // "redis_streams" | "redis_pubsub" | "local"
    WSStreamKey        string `yaml:"ws_stream_key"`        // 默认 genericim:ws:events
    WSEphemeralChannel string `yaml:"ws_ephemeral_channel"` // 默认 genericim:ws:ephemeral
    LockPrefix         string `yaml:"lock_prefix"`          // 默认 genericim:lock
    PresenceTTL        string `yaml:"presence_ttl"`         // 默认 90s
}

type Config struct {
    Server ServerConfig   `yaml:"server"`
    Cluster ClusterConfig  `yaml:"cluster"`
    // ... 既有字段 ...
}
读取后填充默认值 + ValidateRuntime 里加一段：若 Enabled=true 但 WSStreamKey=""，报错，避免上线忘配。

2) 节点 ID 生成：backend/internal/cluster/nodeid.go（新建）

package cluster

import (
    "os"
    "crypto/rand"
    "encoding/hex"
)

func MustNodeID() string {
    if v := os.Getenv("GENERIC_IM_NODE_ID"); v != "" {
        return sanitize(v)
    }
    host, _ := os.Hostname()
    if host == "" { host = "node" }
    b := make([]byte, 4)
    _, _ = rand.Read(b)
    return host + "-" + hex.EncodeToString(b)
}
3) WebSocket 事件总线：backend/internal/wsevent/（新建）

wsevent/
├── envelope.go         // 事件结构体、序列化
├── bus.go              // Bus 接口 +工厂
├── redis_streams.go    // XADD / XREADGROUP 实现
├── redis_pubsub.go     // 瞬时事件
└── presence.go         // 在线状态 Redis维护
Bus 接口核心方法：


type Bus interface {
    Publish(ctx context.Context, env *Envelope) error
    Subscribe(ctx context.Context, handler func(context.Context, *Envelope) error) error
    PublishEphemeral(ctx context.Context, channel string, payload []byte) error
    SubscribeEphemeral(ctx context.Context, channel string, handler func([]byte)) error
    Close() error
}
Consumer group 命名 genericim:ws-node:<node_id>，确保每节点独立、都能收到完整事件。

幂等消费：


// 处理前ok, _ := redis.SetNX(ctx, "wsevent:processed:"+env.ID, 1, 24*time.Hour).Result()
if !ok { return nil } // 已处理过
// ... 处理 ...
4) Hub 改造：backend/internal/ws/hub.go
保留本地连接管理职责，新增：

-构造函数加 Bus注入：NewHub(db, bus, nodeID)。

Run() 里 go h.consumeEvents() 从 Bus 消费跨节点事件，再走现有 Broadcast/SendToUser/SendToChat。
IsUserOnline 改为查 presence:user:{id}；Hub 只保留 LocalOnlineCount() 用于本地视图。
新增连接/断开时同步 presence 到 Redis：

presence.Set(ctx, "presence:user:"+userID, nodeID+":"+connID, ttl)
5) 调用点改造：所有 hub.SendToUser / SendToChat / SendToUsers / SendToAll
凡是走 Hub 的，写库成功后改走 Bus.Publish（持久事件）或 Bus.PublishEphemeral（瞬时）。SendToAll 类公告广播也要走 Streams，不能只在调用者所在节点广播。

涉及到的典型文件（已查到现网用法，可批量改造）：

backend/internal/handlers/chat_handler.go（消息发送、撤回、群成员变更）
backend/internal/handlers/message_push_batch.go
backend/internal/handlers/broadcast_handler.go（管理端广播）
backend/internal/handlers/call_handler.go（通话事件）
backend/internal/services/message_service.go
backend/internal/services/push_service.go
6) 分布式锁工具：backend/internal/cluster/lock.go（新建）

func Acquire(ctx context.Context, rdb *redis.Client, key, token string, ttl time.Duration) (bool, error)
func Release(ctx context.Context, rdb *redis.Client, key, token string) error
// 释放用 Lua 脚本：if get==token then del end
应用到：

wallet_cron_service.Start 包一层 cluster.WithLock(ctx, "wallet-cron", 50*time.Second, s.tick)。
call_cleanup_service.Start 同理。
chat_auto_message_service 同理。
MQ 的 processDelayed 加锁，避免多个节点重复 ZRem。
7) 上传：compose.yaml 与 backend/config.yaml
生产 storage.provider: s3，凭证走环境变量（已在 compose 里预留 AWS_*）。
删除 genericim_uploads 卷在生产部署里的使用；本地开发可保留为单机模式。
在 cmd/server/main.go 启动时若检测到 cluster.enabled=true && storage.provider=="local"，打印强 warning（不阻断，但写入一条明显的运维日志）。
8) 健康检查 + 优雅停机：backend/cmd/server/main.go

router.GET("/ready", func(c *gin.Context) {
    ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
    defer cancel()
    if err := sqlDB.PingContext(ctx); err != nil { c.JSON(503, ...); return }
    if err := mongoClient.Ping(ctx, nil); err != nil { c.JSON(503, ...); return }
    if err := rdb.Ping(ctx).Err(); err != nil { c.JSON(503, ...); return }
    c.JSON(200, gin.H{"status":"ready","node_id": nodeID})
})
/health 仍然快速返回 ok（负载均衡探活）。

优雅停机：


srv := &http.Server{Addr: ":8080", Handler: router}
go srv.ListenAndServe()
<-sigCh
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
srv.Shutdown(ctx)        // 停止新连接
hub.GracefulClose(25*time.Second)  // 主动踢 WS
bus.Close()
9) Compose：compose.yaml

services:
  api:
    build: ...
    environment:
      GENERIC_IM_CLUSTER__ENABLED: "true"
      GENERIC_IM_CLUSTER__NODE_ID: "" # 留空由程序生成
      GENERIC_IM_CLUSTER__WS_EVENT_BACKEND: "redis_streams"
      GENERIC_IM_CLUSTER__LOCK_PREFIX: "genericim:lock"
    # 删掉 container_name
    # ports 改成由 nginx 访问    expose: ["8080"]
    depends_on: { ... }
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/ready"]
    deploy:
      resources: { limits: { cpus: "2", memory: 2G } }

  nginx:
    image: nginx:1.27-alpine
    volumes:
      - ./docker/genericim/nginx.conf:/etc/nginx/nginx.conf:ro ports: ["8080:80", "8443:443"]
    depends_on:
      api: { condition: service_healthy }
新增 docker/genericim/nginx.conf（含 /api/v1/ws 升级配置，参见下文）。

10) Nginx 模板：docker/genericim/nginx.conf（新建）

upstream genericim_api {
    server api:8080 max_fails=3 fail_timeout=10s;
    keepalive 64;
}

server {
    listen 80;
    server_name _;

    client_max_body_size 200m;

    location /api/v1/ws {
        proxy_pass http://genericim_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
 }

    location /api/ {
        proxy_pass http://genericim_api;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
五、部署架构示意（生产）
单机多进程（最小验证）

docker compose up -d --build
docker compose up -d --scale api=3 # 起 3 个 API 容器
# nginx 在前面，3 个 API 节点共享 Redis/MySQL/Mongo/S3
多机（K8s / Swarm）

# api Deployment
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: api
        env:
        - name: GENERIC_IM_CLUSTER__ENABLED
          value: "true"
        - name: GENERIC_IM_CLUSTER__WS_EVENT_BACKEND
          value: "redis_streams"
        - name: GENERIC_IM_REDIS_ADDR
          value: "redis-cluster:6379"
        - name: GENERIC_IM_MYSQL_HOST
          value: "mysql-primary"
        - name: GENERIC_IM_MONGODB_URI
          value: "mongodb://mongo-0,mongo-1,mongo-2/?replicaSet=rs0"
        readinessProbe:
          httpGet: { path: /ready, port: 8080 }
          periodSeconds: 5
        livenessProbe:
          httpGet: { path: /health, port: 8080 }
          periodSeconds: 15
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh","-c","sleep 15"] # 让 Ingress 先摘流量
Service 用 ClusterIP，外层由 Ingress / 云 LB 暴露；/api/v1/ws 路由在 LB 侧要支持长连接（云 LB 通常默认 60s 超时需要调到 ≥ 1h）。

推荐的最小生产拓扑

Cloud LB (HTTPS, WSS)
    │
Ingress / Nginx (WS upgrade 配置)
    │
    ├── api Pod x N（无状态，HPA）
    ├── worker Pod x M（cron / 媒体处理 / 推送，可独立扩缩）
    │
    ├── Redis（主从或托管）
    ├── MySQL（RDS 或自管 InnoDB Cluster）
    ├── MongoDB（副本集）
    └── S3 / OSS / 七牛
把"API 网关层"和"后台 worker 层"分开，cron 类全部下沉到 worker，API 进程里只剩请求处理和事件总线消费，更干净。

六、关键问题与对策速查
问题	对策
节点 A 上的用户给节点 B 上的用户发消息收不到	Stream写事件 → 所有节点消费 → 本地 Hub 投递
Redis Streams消费慢/积压	每节点独立 consumer group；XPENDING + XCLAIM reclaim死节点任务
同一事件被多个节点处理导致重复投递	event_id SETNX 幂等 + 客户端 message_id/seq 去重
在线状态数字忽多忽少	用 Redis presence:user:{id} SET NX EX，TTL = 心跳周期 × 3
后台 cron 多节点重复执行	Redis 分布式锁 + 数据库唯一约束兜底
WebSocket 连接被 LB 60s 切断	LB/Ingress proxy-read-timeout ≥ 3600s，节点 pong_wait=60s, ping_period=54s
节点发布时新版本与旧版本并存	事件格式预留字段（不删旧字段），cluster.enabled 开关可灰度
单机多实例本机端口冲突	compose 不映射宿主机端口，仅 expose + nginx upstream
滚动发布期间 WS 抖动	preStop sleep 15 +客户端按 seq 自动补偿（已有）
节点时区/时钟不一致	所有节点 NTP 同步；事件 occurred_at 用 UTC
七、落地建议（最小可行版本）
如果资源紧，第一期只做这些就能宣称"支持多节点集群部署"：

✅ cluster 配置 + node_id + 日志字段
✅ /ready + 优雅停机
✅ compose.yaml 去掉固定端口，nginx 服务前置
✅ Redis Streams 事件总线（仅新增包，先不动业务调用点）
✅ 选 1 个 高频写路径（如群消息发送）做端到端改造跑通，作为样板
✅ IsUserOnline / 在线计数 走 Redis presence
✅ 给 wallet_cron、call_cleanup、processDelayed 加分布式锁
✅ 生产环境把 storage切到 S3/OSS
跑通后再批量推广到所有"通过 Hub 投递"的调用点。

