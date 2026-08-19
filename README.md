# 通用 IM

通用 IM 是一套即时通信系统源码，包含移动/桌面 Flutter 客户端、Go 后端服务、运营管理后台、官方客服后台、H5/PWA 客户端和 Docker 本地部署配置。当前代码以 `/api/v1` REST API + WebSocket 为主链路，消息正文使用 MongoDB 存储，业务关系和运营数据使用 MySQL，在线状态、会话态、限流和缓存使用 Redis。

## 功能范围

- 账号体系：注册、登录、刷新 Token、退出、找回密码、修改密码、手机绑定、设备锁验证、二维码登录。
- 即时通信：私聊、群组、频道、会话置顶/免打扰/未读、群成员管理、群公告、群邀请、入群审核、消息撤回/删除/编辑/转发、消息同步、已读、表情反应、聊天媒体列表。
- 实时通道：WebSocket 在线连接、消息投递、在线状态、弱网重连配合。
- 通讯录：联系人列表、添加/删除好友、备注、黑名单、共同群组。
- 音视频：Agora / LiveKit 双通道配置，支持一对一通话、通话记录、会议创建/加入/邀请/主持人转移/成员静音/踢出。
- 动态广场：发布动态、评论、点赞、话题、屏蔽、搜索、后台审核和违禁词管理。
- 钱包：余额、充值、提现、红包、转账、支付密码、微信/支付宝在线充值回调、后台资金管理。
- 文件与媒体：图片、视频、语音、头像、文件上传；本地存储、阿里云 OSS、七牛云配置入口。
- 运营能力：用户管理、群管理、会话管理、消息搜索、举报、公告、发现页、表情商店、短信网关、支付网关、热更新补丁、系统设置。
- 客服后台：官方客服登录、资料、欢迎语、邀请码、邀请用户和服务数据看板。
- 多端客户端：Android、iOS、Windows、macOS、Web Flutter 客户端，以及独立 Vue H5/PWA 客户端。

## 技术栈

| 模块 | 路径 | 技术 |
| --- | --- | --- |
| 后端 API | `backend/` | Go 1.24、Gin、GORM、MySQL、MongoDB、Redis、JWT、WebSocket |
| Flutter 客户端 | `lib/`、`android/`、`ios/`、`windows/`、`macos/`、`web/` | Flutter、Riverpod、GoRouter、Isar、Dio、WebSocket、Agora、LiveKit |
| 管理后台 | `admin/` | Vue 3、Vite、TypeScript、Element Plus、Pinia、ECharts |
| H5/PWA 客户端 | `h5/` | Vue 3、Vite、TypeScript、Vant、Pinia、Agora Web、LiveKit Web |
| 官方客服后台 | `admin-kf/` | Vue 3、Vite、TypeScript、Element Plus、Pinia |
| 容器部署 | `compose.yaml`、`docker/genericim/` | Docker Compose、MySQL、MongoDB、Redis、Nginx |

## 目录结构

```text
.
├── backend/                 # Go 后端，入口 backend/cmd/server
├── lib/                     # Flutter 业务代码
├── android/ ios/            # Flutter 移动端工程
├── windows/ macos/ web/     # Flutter 桌面/Web 工程
├── admin/                   # 运营管理后台
├── admin-kf/                # 官方客服后台
├── h5/                      # 独立 H5/PWA 客户端
├── docker/genericim/            # Docker 场景的后端配置和后台 Nginx 配置
├── compose.yaml             # 本地一键启动 MySQL/MongoDB/Redis/API/Admin
├── docs/                    # 功能、部署、打包说明
├── scripts/                 # 打包、图标替换、编码检查等脚本
├── assets/                  # Flutter 资源及 assets/branding 品牌设计源文件
└── shorebird.yaml           # Flutter 热更新配置
```

文档分类和入口见 [docs/INDEX.md](docs/INDEX.md)。

根目录维护规则见 [docs/project/ROOT_ORGANIZATION.md](docs/project/ROOT_ORGANIZATION.md)。

## 快速启动

本地最省事的方式是使用 Docker Compose 启动依赖、后端和管理后台：

```powershell
docker compose up -d --build
```

启动后默认地址：

- 后端健康检查：`http://127.0.0.1:8080/health`
- API 前缀：`http://127.0.0.1:8080/api/v1`
- 管理后台：`http://127.0.0.1:8082`
- MySQL：`127.0.0.1:3306`
- MongoDB：`127.0.0.1:27017`
- Redis：`127.0.0.1:6379`

查看运行状态：

```powershell
docker compose ps
docker compose logs -f api
```

停止服务：

```powershell
docker compose down
```

> `compose.yaml` 内置的数据库账号、密码和 JWT 密钥只适合本地开发。生产环境必须替换密码、`GENERIC_IM_JWT_SECRET`、域名、CORS 白名单和第三方服务密钥。

## 后端开发

后端入口为 `backend/cmd/server/main.go`，配置文件默认为 `backend/config.yaml`，也可以用 `GENERIC_IM_CONFIG` 指定。

```powershell
cd backend
go mod download
$env:GENERIC_IM_CONFIG="config.yaml"
go run ./cmd/server
```

常用配置项：

- `server.port` / `GENERIC_IM_SERVER_PORT`：HTTP 端口，默认 `8080`。
- `server.mode` / `GENERIC_IM_SERVER_MODE`：`debug` 或 `release`。
- `server.base_url` / `GENERIC_IM_SERVER_BASE_URL`：后端外部访问地址，用于媒体地址、支付回调等。
- `server.allowed_origins` / `GENERIC_IM_ALLOWED_ORIGINS`：API CORS 白名单。
- `websocket.allowed_origins` / `GENERIC_IM_WS_ALLOWED_ORIGINS`：WebSocket Origin 白名单。
- `mysql.*` / `GENERIC_IM_MYSQL_*`：MySQL 连接。
- `mongodb.*` / `GENERIC_IM_MONGODB_*`：MongoDB 连接。
- `redis.*` / `GENERIC_IM_REDIS_*`：Redis 连接。
- `jwt.secret` / `GENERIC_IM_JWT_SECRET`：JWT 密钥。
- `agora.*` / `GENERIC_IM_AGORA_*`：声网通话配置。
- `livekit.*` / `GENERIC_IM_LIVEKIT_*`：LiveKit 通话/会议配置。

生产模式会做安全校验：`jwt.secret` 不能使用弱默认值，`server.allowed_origins` 和 `websocket.allowed_origins` 必须配置且不能为 `*`。

## Flutter 客户端

Flutter 主入口为 `lib/main.dart`，路由集中在 `lib/core/router/app_router.dart`。默认 Android 模拟器访问后端：

- REST：`http://10.0.2.2:8080/api/v1`
- WebSocket：`ws://10.0.2.2:8080/api/v1/ws`

运行 Android：

```powershell
flutter pub get
flutter run -d android
```

连接其他后端地址时使用 Dart Define：

```powershell
flutter run -d android `
  --dart-define=GENERIC_IM_SERVER_URL=http://192.168.1.10:8080 `
  --dart-define=GENERIC_IM_WS_URL=ws://192.168.1.10:8080/api/v1/ws
```

构建示例：

```powershell
flutter build apk --release
flutter build windows --release
flutter build web --release
```

Android 包名当前为 `com.genericim.ma100`，应用名为 `通用IM`。

## 管理后台

管理后台位于 `admin/`，开发配置在 `admin/.env.development`，生产配置在 `admin/.env.production`。

```powershell
cd admin
pnpm install
pnpm dev
```

构建：

```powershell
pnpm build
```

主要页面包括控制台、用户管理、公告、官方客服、群管理、会话管理、消息搜索、动态广场、钱包、通话记录、举报、发现页、系统设置、热更新、短信网关、支付网关和表情包管理。

## H5/PWA 客户端

H5 客户端位于 `h5/`，使用 `VITE_API_BASE_URL` 和 `VITE_MEDIA_BASE_URL` 指向后端。

```powershell
cd h5
pnpm install
pnpm dev
```

构建：

```powershell
pnpm build
```

H5 路由包含聊天、联系人、发现、个人中心、聊天详情、通话、会议、朋友圈、钱包、资料编辑、隐私、设备、通知、PWA 设置、表情管理、修改密码、黑名单和注销账号。

## 官方客服后台

官方客服后台位于 `admin-kf/`，默认通过 `/api/v1/service-admin` 访问后端客服 API。

```powershell
cd admin-kf
pnpm install
pnpm dev
```

构建：

```powershell
pnpm build
```

## API 概览

后端公开前缀为 `/api/v1`，主要分组如下：

- `/auth`：登录、注册、找回密码、二维码登录、刷新 Token、退出。
- `/user`：当前用户、资料、隐私、手机绑定、设备、会话、推送、黑名单、表情商店。
- `/chat`：会话、群组、频道、成员、入群、公告、置顶、清空和搜索。
- `/message`：消息发送、列表、同步、撤回、删除、编辑、转发、已读、反应、媒体、语音转写。
- `/contact`：联系人管理。
- `/moment`：动态、评论、点赞、话题、屏蔽和搜索。
- `/call`：通话配置、Token、发起/接听/拒绝/结束、心跳、历史。
- `/meeting`：会议创建、加入、成员管理、主持人转移、Token、详情。
- `/upload`：图片、视频、头像、语音、文件上传。
- `/wallet`：钱包、充值、提现、红包、转账、支付密码、在线支付订单。
- `/admin`：运营管理后台 API。
- `/service-admin`：官方客服后台 API。
- `/app`：客户端设置、发现页、热更新、协议、公告。

WebSocket 入口为：

```text
/api/v1/ws
```

## 第三方服务

以下能力默认可以关闭，按需在 YAML、环境变量或管理后台系统设置中启用：

- Agora：一对一音视频通话。
- LiveKit：音视频通话和会议。
- 微信支付 / 支付宝：在线充值和支付回调。
- 短信宝 / 阿里云短信 / 腾讯云短信：手机验证码。
- 阿里云 OSS / 七牛云：媒体对象存储。
- WebPush / Firebase / 厂商推送：多端通知。
- OpenAI API Key：语音转写等 AI 能力。

## 开发检查

后端：

```powershell
cd backend
go test ./...
```

管理后台：

```powershell
cd admin
pnpm typecheck
pnpm build
```

H5：

```powershell
cd h5
pnpm build
```

Flutter：

```powershell
flutter analyze
flutter test
```

## 生产部署注意事项

- 不要提交 `.env`、证书、私钥、支付密钥、短信密钥、JKS 密码等敏感文件。
- `release` 模式必须配置强 `GENERIC_IM_JWT_SECRET`、API CORS 白名单和 WebSocket Origin 白名单。
- 对外部署时同步设置 `server.base_url`、`storage.local.base_url`、支付 `notify_base_url`、前端 `VITE_API_URL` / `VITE_API_BASE_URL`。
- MySQL、MongoDB、Redis 不应使用 `compose.yaml` 中的本地开发账号密码。
- 开启微信/支付宝支付、短信、对象存储、LiveKit、Agora 前，先在管理后台保存完整配置并验证连通性。
- Android 真机调试不要使用 `10.0.2.2`，应通过 `--dart-define` 指向局域网或公网后端地址。
