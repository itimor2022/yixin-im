# 通用 IM 后端

> IM 服务端，提供用户、好友、会话、消息、通话、动态、举报、钱包等 REST API 与 WebSocket，使用 MySQL + MongoDB + Redis，支持宝塔与 Docker 部署。

---

## 1. 模块简介 (Overview)

`backend` 在整个 IM 系统中的定位是 **服务端**，为 Flutter 客户端与 Admin 管理后台提供统一接口。主要作用包括：

- **认证与用户**：注册、登录、JWT 刷新、修改密码、用户资料、隐私与黑名单、设备与推送 Token。
- **会话与消息**：单聊/群聊/频道、成员管理、消息收发/同步/撤回/已读、消息搜索与媒体、消息队列与推送。
- **好友与联系人**：好友列表、添加/删除、备注、加入请求与审核。
- **动态与话题**：发动态、点赞评论、话题、违禁词、屏蔽。
- **音视频通话**：Agora / LiveKit 双 RTC 集成、通话创建/接听/拒绝/结束、通话记录。
- **钱包**：充值/提现方式、充值订单、红包/转账、支付密码、钱包锁定、定时退款任务。
- **举报与安全**：用户举报、处理流程；系统设置、官方账号/群组/频道配置。
- **管理端**：管理员登录、用户/会话/动态/举报/钱包/通话等管理接口（供 Admin 前端调用）。

业务数据存 MySQL（GORM 自动迁移），聊天消息存 MongoDB，缓存与消息队列用 Redis；WebSocket 用于在线状态与实时消息。

---

## 2. 技术栈 (Tech Stack)

| 类别           | 技术 |
|----------------|------|
| 语言           | Go 1.24+ |
| Web 框架       | Gin |
| 数据库         | MySQL 8（GORM）、MongoDB（消息存储）、Redis（缓存 + 队列） |
| 认证           | JWT（`pkg/jwt`） |
| 实时           | Gorilla WebSocket（`internal/ws`） |
| 音视频         | Agora / LiveKit（可选，`internal/services/agora_service`、`internal/services/livekit_service`） |
| 配置           | YAML（`config.yaml` + `internal/config`） |

---

## 3. 环境准备 (Prerequisites)

- **Go**：1.24 及以上（见 `go.mod`）。
- **MySQL**：8.0+，创建数据库并执行 `scripts/init.sql` 或 `baota/init.sql` 初始化表结构（部分表由 GORM 自动迁移）。
- **MongoDB**：用于消息存储。
- **Redis**：用于缓存与消息队列。

无需单独安装 Agora SDK 或 LiveKit 服务端在本机；不配置时音视频相关接口可禁用（`config.yaml` 中 `agora.enabled: false`、`livekit.enabled: false`）。

---

## 4. 快速上手 (Getting Started)

### 4.1 配置文件

复制或修改根目录 `config.yaml`，必改项包括：

- **mysql**：host、port、user、password、database
- **mongodb**：uri、database
- **redis**：addr、password（若有）
- **jwt**：secret（生产务必更换）、expire
- **server**：port（默认 8080）、mode（debug/release）、base_url（对外域名，用于生成链接）
- **agora / livekit**（可选）：Agora App ID/证书、LiveKit Server URL/API Key/API Secret、Token 过期时间

### 4.2 安装依赖与运行

```bash
cd backend
go mod download
go run ./cmd/server
```

默认监听 `:8080`。首次启动会执行 GORM 自动迁移并初始化默认管理员（见 `baota/README.md` 默认账号）。

### 4.3 健康检查

- `GET /health`：健康检查
- `GET /api/v1/ping`：API 存活（无需鉴权）

---

## 5. 核心目录结构 (Directory Structure)

```
backend/
├── cmd/server/
│   └── main.go              # 入口：配置加载、MySQL/Mongo/Redis/缓存/WS/队列初始化、路由注册、优雅关闭
├── internal/
│   ├── config/              # 配置结构体与加载
│   ├── handlers/            # HTTP 处理器（auth、user、chat、message、contact、moment、call、upload、wallet、report、setting、admin、ws、stats 等）
│   ├── models/              # GORM 模型（user、chat、message、call、moment、wallet、report、admin、system_setting 等）
│   ├── services/            # 业务服务（message、push、agora、wallet_cron）
│   ├── middleware/          # 鉴权、CORS、限流、日志
│   ├── ws/                  # WebSocket Hub 与 Client
│   ├── mq/                  # Redis 消息队列
│   ├── cache/               # 缓存封装
│   └── shard/               # 分片锁
├── pkg/
│   ├── jwt/                 # JWT 签发与校验
│   └── response/            # 统一响应
├── scripts/
│   └── init.sql             # MySQL 初始化脚本（参考）
├── baota/                   # 宝塔部署：server、config.yaml、init.sql、start/stop/restart、systemd、README
├── deployments/             # Dockerfile、docker-compose
├── config.yaml              # 主配置（生产请改密码与 secret）
├── build.sh                 # 编译脚本（输出到 baota/，支持 -z/-a 打包）
├── go.mod
└── go.sum
```

---

## 6. API 与业务引导 (Key Concepts)

| 关注点           | 说明 |
|------------------|------|
| **路由前缀**     | 业务 API 统一在 `/api/v1`；管理端在 `/api/v1/admin`；WebSocket 为 `/api/v1/ws`（需鉴权）。 |
| **认证**         | 除登录/注册等接口外，请求头需带 `Authorization: Bearer <token>`；`internal/middleware` 中 `Auth`、`RequireRole` 等。 |
| **用户与好友**   | `internal/handlers/auth_handler`、`user_handler`、`contact_handler`；模型 `internal/models/user.go` 等。 |
| **会话与消息**   | `chat_handler`、`message_handler`；消息体存 MongoDB，元数据与已读等用 MySQL；队列与推送见 `internal/services`、`internal/mq`。 |
| **动态与举报**   | `moment_handler`、`report_handler`；管理端 `moment_mgmt_handler`、举报处理。 |
| **通话**         | `call_handler`、`call_admin_handler`；Agora Token 在 `agora_service`，LiveKit Token 在 `livekit_service`。 |
| **钱包**         | `wallet_handler`、`wallet_admin_handler`；定时任务 `wallet_cron_service`（红包/转账过期退款）。 |
| **管理端**       | `admin_handler` 登录；`user_mgmt_handler`、`chat_mgmt_handler`、`setting_handler`、`wallet_admin_handler` 等；需管理员角色。 |
| **上传**         | `upload_handler`；静态文件服务 `/uploads` 对应 `config.server.upload_dir`。 |

整体：**入口与路由在 `cmd/server/main.go`，业务在 `internal/handlers`，数据在 `internal/models`，外部服务与定时任务在 `internal/services`。**

---

## 7. 打包与部署 (Build & Deploy)

### 7.1 本地编译

```bash
# 当前平台
go build -o server ./cmd/server

# Linux 部署（与 build.sh 一致）
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o baota/server ./cmd/server
```

### 7.2 使用 build.sh（宝塔部署）

```bash
./build.sh              # 仅编译到 baota/server
./build.sh -z           # 编译并打 server.zip
./build.sh -a           # 编译并打完整部署包 deploy.zip
```

将 `baota/` 下文件或 zip 上传服务器，按 `baota/README.md` 配置 `config.yaml`、执行 `init.sql`、运行 `start.sh` 或 systemd。

### 7.3 Docker

```bash
cd deployments
docker compose up -d
```

或使用 `Dockerfile` 单独构建镜像；需挂载 `config.yaml` 或通过环境变量覆盖配置（如有扩展）。

### 7.4 生产注意

- 修改 `config.yaml` 中 **mysql**、**redis**、**jwt.secret**、**agora** 等敏感信息。
- **server.base_url** 设为对外访问地址，便于生成推送/链接。
- 上传目录 **server.upload_dir** 需持久化并做好备份。

---

## 附录：常用命令

| 场景         | 命令 |
|--------------|------|
| 安装依赖     | `go mod download` |
| 运行         | `go run ./cmd/server` |
| 编译 Linux   | `./build.sh` 或见 7.1 |
| 健康检查     | `curl http://localhost:8080/health` |

如有问题，可优先查阅本 README、`baota/README.md`、`config.yaml` 注释及 `cmd/server/main.go` 中的路由与初始化顺序。
