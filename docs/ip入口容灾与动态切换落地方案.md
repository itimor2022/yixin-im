# IP 入口容灾与动态切换落地方案

## 目标

客户担心单个服务器 IP、单个 CDN 入口或单个域名不可访问后，App 用户无法登录、收发消息、加载头像和文件。这个方案的目标不是承诺某个 IP 永远可用，而是把系统做成：

- App 不写死唯一 IP。
- API、WebSocket、资源域名都支持多入口。
- 主入口失败后，客户端自动切换备用入口。
- WebSocket 断线后自动换入口重连，并通过消息同步补齐漏收消息。
- 后端和部署层支持多实例、多地区、多 CDN/高防入口。
- 运维可以不发新版 App 就切换入口。

## 当前没有集群时怎么做

现在系统还没有集群，这不影响第一阶段落地。真正先要解决的是“App 不绑定唯一 IP”，不是一开始就上 Kubernetes 或多后端副本。

当前阶段推荐做成：

```text
App
  |
  | 内置 2-3 个 bootstrap / API 备用地址
  v
域名入口 A / 域名入口 B / 备用 IP 入口
  |
  v
同一台服务器上的 Nginx / Docker Compose
  |
  v
当前单机 backend + MySQL + MongoDB + Redis
```

也就是说，第一版可以先保持单机部署，只增加这些能力：

- 多个域名解析到当前服务器，例如 `api-a.example.com`、`api-b.example.com`。
- 多个 CDN/高防入口回源到当前服务器。
- 准备一个备用服务器 IP 或备用域名，必要时手动切过去。
- App 从 bootstrap 获取入口列表，主入口不可用就自动换备用入口。
- WebSocket 失败后自动换备用 WS 地址重连。

这样即使没有集群，也能解决一大半客户担心的问题：某个域名、某个 CDN、某个 IP 不通时，App 可以切到另一个入口继续访问。

集群是后续增强，主要解决这些问题：

- 单台服务器性能不够。
- 单台服务器故障。
- 多个后端实例同时提供 WebSocket。
- 后端服务要跨地区容灾。

所以推荐路线调整为：

1. **现在先做单机多入口容灾**：成本低，马上提升可用性。
2. **再做 Docker Gateway 规范化**：为以后多副本做准备。
3. **最后再做真正集群**：WebSocket 跨实例广播、worker 拆分、数据库高可用。

## 当前项目基础

当前代码已经具备一些基础能力：

- Flutter API 入口在 `lib/core/services/api/api_client.dart` 的 `ApiConfig.serverUrl`、`ApiConfig.wsUrl`。
- WebSocket 连接在 `lib/core/services/api/websocket_service.dart`，已有重连、心跳、订阅恢复、消息补发队列。
- 后端主路由在 `backend/cmd/server/main.go`，已有 `/health` 和 `/api/v1/ping`。
- Docker Compose 在 `compose.yaml`，已有 MySQL、MongoDB、Redis、api、admin。
- Nginx 管理端代理在 `docker/genericim/admin-nginx.conf`，已经支持 `/api/` 和 WebSocket Upgrade。
- 后端上传已支持本地、阿里云 OSS、七牛云，入口容灾时建议生产环境使用云存储，不依赖某台机器本地目录。

当前缺口：

- App 入口仍以编译期 `GENERIC_IM_SERVER_URL`、`GENERIC_IM_WS_URL` 为主，无法运行时切换。
- 后端没有专门的客户端 bootstrap 配置接口。
- WebSocket Hub 目前是实例内存连接表，多后端副本时需要 Redis Pub/Sub 或 MQ 做跨实例广播。
- 定时任务默认每个 api 实例都会启动，集群化后需要 worker 模式或分布式锁。

## 总体架构

推荐采用四层入口容灾：

```text
App
  |
  | 1. 内置少量 bootstrap 地址
  v
Bootstrap 配置入口
  |
  | 返回 API / WS / CDN 候选列表
  v
Endpoint Manager
  |
  | 自动测速、失败计数、熔断、切换
  v
API Gateway / CDN / 高防 / Nginx
  |
  v
Backend 多副本 + Redis/MQ + MySQL + MongoDB + 对象存储
```

生产入口建议拆成三类：

| 类型 | 例子 | 作用 |
| --- | --- | --- |
| Bootstrap | `https://boot-a.example.com/client/bootstrap` | 返回当前可用入口列表 |
| API | `https://api-a.example.com`、`https://api-b.example.com` | 登录、会话、消息 HTTP 接口 |
| WebSocket | `wss://ws-a.example.com/api/v1/ws`、`wss://ws-b.example.com/api/v1/ws` | 实时消息 |
| Media/CDN | `https://cdn-a.example.com`、`https://cdn-b.example.com` | 头像、图片、文件、热更新包 |

## 后端实现方案

### 1. 新增客户端 Bootstrap 接口

新增公开接口：

```http
GET /api/v1/client/bootstrap
```

不需要登录，不返回敏感密钥，只返回客户端可用入口和策略。

响应示例：

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "version": 12,
    "ttl_seconds": 300,
    "api_endpoints": [
      {
        "id": "api-hk-1",
        "url": "https://api-a.example.com",
        "priority": 10,
        "region": "hk",
        "health_path": "/api/v1/ping"
      },
      {
        "id": "api-sg-1",
        "url": "https://api-b.example.com",
        "priority": 20,
        "region": "sg",
        "health_path": "/api/v1/ping"
      }
    ],
    "ws_endpoints": [
      {
        "id": "ws-hk-1",
        "url": "wss://ws-a.example.com/api/v1/ws",
        "priority": 10,
        "region": "hk"
      },
      {
        "id": "ws-sg-1",
        "url": "wss://ws-b.example.com/api/v1/ws",
        "priority": 20,
        "region": "sg"
      }
    ],
    "media_base_urls": [
      "https://cdn-a.example.com",
      "https://cdn-b.example.com"
    ],
    "strategy": {
      "connect_timeout_ms": 5000,
      "health_timeout_ms": 3000,
      "fail_threshold": 2,
      "cooldown_seconds": 60,
      "prefer_last_success": true
    }
  }
}
```

后端新增配置结构：

```yaml
client_bootstrap:
  enabled: true
  version: 12
  ttl_seconds: 300
  api_endpoints:
    - id: api-hk-1
      url: https://api-a.example.com
      priority: 10
      region: hk
      health_path: /api/v1/ping
    - id: api-sg-1
      url: https://api-b.example.com
      priority: 20
      region: sg
      health_path: /api/v1/ping
  ws_endpoints:
    - id: ws-hk-1
      url: wss://ws-a.example.com/api/v1/ws
      priority: 10
      region: hk
    - id: ws-sg-1
      url: wss://ws-b.example.com/api/v1/ws
      priority: 20
      region: sg
  media_base_urls:
    - https://cdn-a.example.com
    - https://cdn-b.example.com
```

第一阶段可以先从 YAML 环境变量加载，后续再接管理后台设置表。

建议新增文件：

- `backend/internal/models/client_bootstrap.go`
- `backend/internal/handlers/client_bootstrap_handler.go`
- `backend/internal/config/config.go` 增加 `ClientBootstrapConfig`
- `backend/cmd/server/main.go` 注册 `api.GET("/client/bootstrap", handler.GetBootstrap)`

### 2. Bootstrap 接口安全约束

接口公开，但必须做基础防护：

- 只允许 `https://`、`wss://`，本地 debug 才允许 `http://`、`ws://`。
- 不返回源站内网地址、数据库地址、Redis 地址。
- 入口列表长度限制，例如 API 最多 10 个，WS 最多 10 个。
- URL 不允许空格、换行、用户名密码。
- 设置 `Cache-Control: no-store` 或短缓存，避免旧入口长期被缓存。
- 返回 `version`，客户端只在版本更新时刷新本地策略。

### 3. 健康检查接口增强

当前已有：

- `/health`
- `/api/v1/ping`

建议补充：

```http
GET /ready
```

`/health` 只表示进程活着，`/ready` 表示 MySQL、MongoDB、Redis 都可用。负载均衡和容器健康检查用 `/ready` 更准确。

响应示例：

```json
{
  "status": "ok",
  "mysql": "ok",
  "mongodb": "ok",
  "redis": "ok",
  "time": 1782030000
}
```

### 4. WebSocket 多实例广播

这是集群部署最关键的部分。

当前 `backend/internal/ws/hub.go` 的连接表和会话订阅表是单实例内存结构。如果用户 A 连到 `api-1`，用户 B 连到 `api-2`，`api-1` 的 `hub.SendToChat` 只能推给本实例连接，不能直接推给 `api-2` 上的用户。

建议新增 Redis Pub/Sub 桥接：

```text
业务代码调用 hub.SendToChat / SendToUser
  |
  | 本实例先发送给本地连接
  |
  | 同时发布到 Redis channel: ws:broadcast
  v
其他 api 实例收到 Redis Pub/Sub
  |
  | 投递给本实例本地连接
```

实现要点：

- 为每个后端实例生成 `instance_id`。
- Redis 广播消息带 `origin_instance_id`，收到自己发出的消息要跳过，避免重复。
- 广播消息结构复用 `ws.BroadcastMessage`，只保留可 JSON 序列化字段。
- `SendToUser`、`SendToUsers`、`SendToChat`、`SendToAll` 都走统一广播入口。
- 保留本地内存连接表，不把实时连接状态全部搬到 Redis，性能更稳。

建议新增文件：

- `backend/internal/ws/cluster_bus.go`
- `backend/internal/ws/cluster_message.go`

建议新增配置：

```yaml
websocket_cluster:
  enabled: true
  redis_channel: ws:broadcast
  instance_id: "" # 留空自动 hostname + pid
```

### 5. 定时任务集群治理

当前 `backend/cmd/server/main.go` 启动时会直接启动：

- 钱包过期红包/转账定时任务
- 外部媒体清理任务
- MQ worker

多副本后不能让所有 api 都无控制地执行后台任务。

推荐拆三种运行模式：

```yaml
server:
  role: api # api | worker | all
```

规则：

- `api`：只提供 HTTP 和 WebSocket，不跑钱包定时任务。
- `worker`：跑 MQ、钱包定时任务、外部清理，不对外开放 WebSocket。
- `all`：本地开发使用，保持当前行为。

第一阶段如果不想拆进程，可以给钱包定时任务加 Redis 分布式锁：

```text
SET genericim:lock:wallet_cron <instance_id> NX EX 55
```

拿到锁的实例才执行本轮任务。这样多副本下不会重复处理。

### 6. 文件和头像资源容灾

生产环境不要依赖 `genericim_uploads` 这类单机 volume 作为最终存储。建议：

- 头像、图片、视频、文件统一走阿里云 OSS、七牛云或兼容 S3/MinIO。
- 数据库存储公开 URL 或对象 key。
- App 端展示媒体时通过 `EndpointManager.mediaBaseUrls` 做域名替换。
- 热更新包、安装包也放对象存储 + CDN，不绑定源站 IP。

当前 `backend/internal/services/object_storage.go` 已有阿里云和七牛基础，第一阶段优先启用这个能力。

## Flutter 前端实现方案

### 1. 新增 EndpointManager

新增服务：

```text
lib/core/services/api/endpoint_manager.dart
```

职责：

- 读取内置默认入口。
- 请求 bootstrap 接口。
- 缓存 bootstrap 结果到 `SharedPreferences`。
- 记录最近成功 API/WS 入口。
- 失败计数和冷却。
- 对外提供当前 API baseUrl、WS url、media baseUrl。

核心状态：

```dart
class RuntimeEndpointState {
  final String apiBaseUrl;
  final String wsUrl;
  final List<String> mediaBaseUrls;
  final int version;
  final DateTime fetchedAt;
}
```

内置兜底入口：

```dart
const bootstrapUrls = [
  String.fromEnvironment('GENERIC_IM_BOOTSTRAP_URL', defaultValue: ''),
  'https://boot-a.example.com/api/v1/client/bootstrap',
  'https://boot-b.example.com/api/v1/client/bootstrap',
];
```

客户端选择策略：

1. 优先使用上次成功入口。
2. 上次成功入口失败 2 次后进入冷却。
3. 按 priority 依次测试候选入口。
4. API 用 `/api/v1/ping` 测试。
5. WS 连接失败时切换到下一个 WS 入口。
6. 所有远程入口都失败时，回退编译期 `GENERIC_IM_SERVER_URL`、`GENERIC_IM_WS_URL`。

### 2. 改造 ApiConfig

当前 `ApiConfig` 是静态编译期配置：

```dart
static const String serverUrl = String.fromEnvironment(...)
static const String wsUrl = String.fromEnvironment(...)
static String get baseUrl => '$serverUrl/api/v1';
```

建议改成：

```dart
class ApiConfig {
  static const String fallbackServerUrl = String.fromEnvironment(
    'GENERIC_IM_SERVER_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const String fallbackWsUrl = String.fromEnvironment(
    'GENERIC_IM_WS_URL',
    defaultValue: 'ws://10.0.2.2:8080/api/v1/ws',
  );

  static String get serverUrl => EndpointManager.instance.apiServerUrl;
  static String get wsUrl => EndpointManager.instance.wsUrl;
  static String get baseUrl => '$serverUrl/api/v1';
}
```

注意：`ApiClient` 当前在构造函数里固定了 Dio `baseUrl`，运行时入口变更后需要支持重建 Dio 或更新 `BaseOptions.baseUrl`。

推荐做法：

- `EndpointManager` 切换 API 入口后发出事件。
- `ApiClient` 监听事件，执行：

```dart
_dio.options.baseUrl = ApiConfig.baseUrl;
_authDio.options.baseUrl = ApiConfig.baseUrl;
```

### 3. HTTP 请求失败自动切换

在 `ApiClient` 拦截器里识别网络级失败：

- `connectionTimeout`
- `sendTimeout`
- `receiveTimeout`
- `connectionError`
- `badCertificate` 不自动切换，直接报错，避免安全风险被掩盖。

处理流程：

```text
请求失败
  |
  | 判断是否网络错误
  v
EndpointManager.markApiFailure(currentEndpoint)
  |
  | 是否达到 fail_threshold
  v
切换下一个 API endpoint
  |
  | 更新 Dio baseUrl
  v
对幂等请求 GET 自动重试一次
```

非幂等请求如发消息、转账、红包，不建议 HTTP 层盲目重试，避免重复业务。消息发送如果需要重试，要走业务层幂等 ID。

### 4. WebSocket 入口切换

当前 WebSocket 服务已经有重连能力，需要增强为多入口重连：

```text
WS 连接失败 / 心跳超时
  |
  v
EndpointManager.markWsFailure(currentWs)
  |
  v
选择下一个 WS endpoint
  |
  v
重新 connect(token)
  |
  v
重新 subscribeChats
  |
  v
触发 message sync 补拉漏消息
```

当前 `WebSocketService` 已经有：

- `_scheduleReconnect`
- `_triggerForceReconnect`
- `_subscribedChatIds`
- 重连后 `subscribeChats`
- `WSMessageType.reconnected`

因此改造成本不高，重点是把 `_doConnect` 里的 `ApiConfig.wsUrl` 换成 `EndpointManager.instance.wsUrl`，失败时通知 EndpointManager。

### 5. 媒体 URL 容灾

当前 `ApiConfig.getMediaUrl` 会把相对路径拼到 `serverUrl`。入口容灾后建议：

- 绝对 URL 保持原样。
- `/uploads/...` 优先拼 `EndpointManager.mediaBaseUrl`。
- 当前 CDN 加载失败时，头像/图片组件可以替换到下一个 media baseUrl。

第一阶段可以只做 URL 生成层替换，不做每张图失败重试，避免引入复杂 rebuild。

### 6. 客户端缓存策略

缓存内容：

- bootstrap 原始 JSON。
- 最近成功 API endpoint id。
- 最近成功 WS endpoint id。
- 每个 endpoint 的失败次数和冷却截止时间。

缓存 TTL：

- 正常 TTL 使用后端返回的 `ttl_seconds`。
- App 每次启动先用缓存，后台异步刷新 bootstrap。
- 如果缓存过期但远程 bootstrap 不可用，继续使用缓存入口，不要把用户卡死在启动页。

## Docker 与部署实现方案

### 1. 单机 Compose 生产版

第一阶段保持 Compose，但加 gateway：

```text
nginx-gateway
  - /api/ -> api:8080
  - /api/v1/ws -> api:8080
  - /uploads/ -> api:8080 或 CDN
api
mysql
mongodb
redis
admin
```

### 2. 多 API 副本

Compose 本地验证可以这样跑：

```powershell
docker compose up -d --scale api=2
```

但当前 `compose.yaml` 的 `api` 使用了固定 `container_name: genericim-api` 和固定 `ports: "8080:8080"`，多副本前需要调整：

- 移除 `api.container_name`。
- 不让每个 api 都绑定宿主机 8080。
- 只让 gateway 暴露公网端口。
- gateway upstream 指向多个 api 实例。

Nginx upstream 示例：

```nginx
upstream genericim_api {
    server api:8080;
}

server {
    listen 80;

    location /api/ {
        proxy_pass http://genericim_api/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400s;
    }
}
```

### 3. 多入口推荐部署

最小可落地：

```text
入口 A: CDN/高防 A -> gateway-a -> api 集群
入口 B: CDN/高防 B -> gateway-a -> api 集群
入口 C: 备用服务器 gateway-b -> api 备用集群
```

进一步增强：

```text
香港主集群
  MySQL / MongoDB / Redis / API / WS / Admin

新加坡备用集群
  API / WS / 只读或延迟同步数据

对象存储
  OSS / 七牛 / MinIO，多 CDN 域名访问
```

数据库跨地区会复杂很多，第一阶段不建议一上来做双写。先做多入口同源站，解决“单入口不可达”的主要问题。

## 分阶段开发计划

### 第零阶段：当前单机多入口容灾

目标：在没有集群的情况下，先让客户不被单个 IP 或单个域名卡死。

改动：

- 保持当前单机 Docker Compose 架构。
- 准备 2-3 个可访问入口：主域名、备用域名、备用 CDN/高防入口。
- 后端新增 `/api/v1/client/bootstrap` 返回这些入口。
- App 内置 bootstrap 兜底地址。
- App 缓存最近成功入口。

部署形态：

```text
api-a.example.com -> 当前服务器 Nginx -> backend
api-b.example.com -> 当前服务器 Nginx -> backend
高防/CDN 入口 -> 当前服务器 Nginx -> backend
```

验收：

- 主域名不可访问时，App 自动切到备用域名。
- 主 WS 不可访问时，App 自动切到备用 WS。
- 不需要上多副本，不需要改数据库架构。

### 第一阶段：App 运行时入口切换

目标：不动业务表结构，先让 App 不依赖单一 IP。

改动：

- 后端新增 `/api/v1/client/bootstrap`。
- Flutter 新增 `EndpointManager`。
- `ApiConfig` 支持运行时入口。
- `ApiClient` 支持切换 Dio baseUrl。
- `WebSocketService` 支持多 WS endpoint 切换。

测试：

- 本地后端正常，App 能登录、收发消息。
- 手动把主 API 地址改成不可用，App 能切备用 API。
- 手动把主 WS 地址改成不可用，App 能切备用 WS。
- 切换后聊天列表、消息详情、头像加载正常。

### 第二阶段：Docker Gateway 与多入口部署

目标：部署层支持多个域名、多个入口、统一转发。

改动：

- 新增 `deploy/cluster/compose.cluster.yaml`。
- 新增 `deploy/cluster/nginx-gateway.conf`。
- 新增 `.env.cluster.example`。
- `api` 移除固定端口暴露，由 gateway 代理。
- 配置 `GENERIC_IM_ALLOWED_ORIGINS` 和 `GENERIC_IM_WS_ALLOWED_ORIGINS`。

测试：

- `docker compose -f deploy/cluster/compose.cluster.yaml up -d`
- `curl http://127.0.0.1/health`
- `curl http://127.0.0.1/api/v1/ping`
- App 用 gateway 地址登录。

### 第三阶段：WebSocket 跨实例广播

目标：后端 api 副本数大于 1 时，实时消息可靠。

改动：

- 新增 Redis Pub/Sub 广播桥。
- `hub.SendToUser`、`SendToChat`、`SendToAll` 支持跨实例。
- 增加实例 ID，避免重复广播。

测试：

- 启动 `api=2`。
- 两个模拟器分别连到不同 api 实例。
- A 发消息，B 实时收到。
- 群聊、频道、撤回、编辑、已读、typing 都验证。

### 第四阶段：后台任务集群治理

目标：多副本下不重复跑定时任务，不重复扣款或退款。

改动：

- 新增 `server.role`。
- api 容器只跑 HTTP/WS。
- worker 容器跑 MQ 和定时任务。
- 钱包任务加 Redis 分布式锁。

测试：

- 启动 `api=2 worker=1`。
- 过期红包只退款一次。
- 过期转账只退款一次。
- MQ 消息不重复消费。

### 第五阶段：资源 CDN 和对象存储

目标：头像、图片、文件不绑定源站 IP。

改动：

- 生产启用 OSS/七牛。
- bootstrap 返回 `media_base_urls`。
- Flutter 媒体 URL 拼接使用 media endpoint。

测试：

- 头像、聊天图片、语音、文件正常上传和访问。
- 屏蔽主 CDN 域名后，备用媒体域名可用。

## 本地测试方案

### 模拟 API 主入口失败

配置 bootstrap 返回：

```json
"api_endpoints": [
  {"id": "broken", "url": "http://10.0.2.2:18080", "priority": 1},
  {"id": "local", "url": "http://10.0.2.2:8080", "priority": 2}
]
```

预期：

- App 第一次请求 `broken` 失败。
- 自动切到 `local`。
- 登录、聊天列表、发送消息正常。

### 模拟 WS 主入口失败

配置 bootstrap 返回：

```json
"ws_endpoints": [
  {"id": "broken-ws", "url": "ws://10.0.2.2:18080/api/v1/ws", "priority": 1},
  {"id": "local-ws", "url": "ws://10.0.2.2:8080/api/v1/ws", "priority": 2}
]
```

预期：

- WS 第一次连接失败。
- 自动切换 `local-ws`。
- 重连后会话重新订阅。
- 新消息实时到达。

### 模拟入口运行中下线

步骤：

1. App 登录并进入聊天。
2. 停掉主 gateway。
3. 等待 WS 心跳超时或 HTTP 请求失败。
4. App 自动切换备用入口。
5. 发送新消息。

预期：

- 不需要重新登录。
- 顶部可以短暂显示重连中。
- 重连成功后消息同步补齐。

## 真机验收清单

- Android 真机蜂窝网络登录成功。
- iPhone 真机蜂窝网络登录成功。
- 主 API 不可达时，30 秒内切到备用 API。
- 主 WS 不可达时，30 秒内切到备用 WS。
- 切入口后不强制退出登录。
- 切入口后头像、图片、语音、文件正常。
- 单聊实时消息正常。
- 群聊实时消息正常。
- 频道消息正常。
- App 冷启动使用缓存入口，不因 bootstrap 慢而卡住。
- 后台回前台后 WS 能恢复。
- 管理后台修改入口后，App 在 TTL 到期后拿到新配置。

## 风险与边界

- 入口容灾不能保证所有网络环境都可达，只能降低单点不可达造成的影响。
- 如果账号、域名、证书、CDN 厂商全部同时不可用，客户端也无法自动恢复。
- 如果数据库主库不可用，单纯切 API 入口不能解决写入问题。
- WebSocket 多实例必须做跨实例广播，否则集群部署会出现部分用户收不到实时消息。
- 转账、红包、支付等非幂等接口不能在 HTTP 层随便自动重试。

## 推荐优先级

优先做：

1. `/api/v1/client/bootstrap`
2. Flutter `EndpointManager`
3. API/WS 自动切换
4. Docker gateway 多入口
5. WS Redis 跨实例广播

暂缓做：

- 跨地区数据库双写。
- 复杂 Kubernetes。
- 客户端每张图片失败逐个切 CDN。

这个顺序收益最大，风险最小，能最快解决客户担心的“单个 IP 不可访问导致 App 整体不可用”的问题。
