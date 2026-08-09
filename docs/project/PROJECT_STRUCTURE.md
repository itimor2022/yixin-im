# 项目源码结构与功能说明书

## 第一部分：项目概览
本项目是一个 Telegram 风格的即时通讯系统，包含 Flutter 跨平台客户端、Go 后端服务，以及 Vue3 管理后台。业务目标是提供稳定的消息收发与多端同步，同时覆盖群聊/频道、朋友圈动态、钱包交易（充值/提现/转账/红包）、音视频通话与运营管理后台的审核/统计能力。

核心技术栈：
- 客户端：Flutter/Dart、Riverpod、GoRouter、Dio、Isar、本地通知与 WebSocket、Lottie、Agora RTC、LiveKit、CallKit
- 服务端：Go、Gin、GORM、MySQL + MongoDB + Redis、WebSocket、JWT、APNs、Docker
- 管理端：Vue3 + Vite + TypeScript、Element Plus、Pinia、TailwindCSS、ECharts、Axios

## 第二部分：目录结构树 (Directory Tree)
（已忽略 node_modules、.git、.idea、dist、build、__MACOSX 等非源码目录）
```text
.
|-- admin/                     # Vue3 管理后台
|   |-- src/                   # 源码
|   |   |-- api/               # 管理端 API 封装
|   |   |-- router/            # 路由与权限
|   |   |-- store/             # Pinia 状态管理
|   |   |-- views/             # 业务页面
|   |   |-- components/        # 组件库
|   |   |-- utils/             # 工具/HTTP/存储
|   |   |-- hooks/             # 组合式逻辑
|   |   |-- directives/        # 指令
|   |   |-- locales/           # 国际化
|   |   `-- assets/            # 样式/图片
|   |-- public/                # 静态资源
|   `-- scripts/               # 辅助脚本
|-- backend/                   # Go 服务端
|   |-- cmd/server/            # 服务入口
|   |-- internal/              # 业务代码
|   |   |-- handlers/          # API 处理器
|   |   |-- services/          # 业务服务
|   |   |-- models/            # 数据模型
|   |   |-- ws/                # WebSocket
|   |   |-- mq/                # 消息队列
|   |   |-- cache/             # Redis 缓存
|   |   |-- middleware/        # 中间件
|   |   |-- config/            # 配置加载
|   |   `-- shard/             # 分片锁/Map
|   |-- pkg/                   # 公共包
|   |-- deployments/           # Docker 部署
|   |-- baota/                 # 宝塔部署
|   |-- scripts/               # SQL 脚本
|   `-- uploads/               # 上传文件存储
|-- lib/                       # Flutter 客户端
|   |-- core/                  # 核心模块
|   |-- features/              # 功能模块
|   `-- shared/                # 共享组件/工具
|-- assets/                    # 客户端资源
|   |-- images/                # 图片/背景
|   |-- icons/                 # 图标
|   |-- emoji/                 # Lottie 表情
|   |-- stickers/              # 贴纸/红包
|   |-- sounds/                # 音效
|   |-- fonts/                 # 字体
|   `-- 图标/                  # 平台图标资源
|-- android/                   # Android 工程
|-- ios/                       # iOS 工程
|-- macos/                     # macOS 工程
|-- windows/                   # Windows 工程
|-- linux/                     # Linux 工程
|-- web/                       # Web 工程
|-- test/                      # Flutter 测试
|-- pubspec.yaml               # Flutter 依赖/资源清单
|-- pubspec.lock               # 依赖锁文件
|-- analysis_options.yaml      # Dart 静态分析
|-- build_apk.sh               # Android 打包脚本
|-- install_ios.sh             # iOS 安装脚本
|-- 免责协议.txt               # 法务文档
|-- 安装依赖教程.txt            # 环境/依赖说明
`-- 项目目录结构.txt            # 项目结构说明
```

## 第三部分：详细功能解析 (Detailed Analysis)

### 3.1 根目录与工程配置
#### pubspec.yaml
- Path (Path): `pubspec.yaml`
- Core Responsibility: Flutter 应用依赖与资源清单。
- Key Features: 1) 定义应用名称/版本/SDK 约束; 2) 声明核心依赖 (Riverpod/GoRouter/Dio/Isar/WebSocket/Agora/LiveKit 等); 3) 注册资源目录 (images/icons/emoji/sounds/stickers)。

#### analysis_options.yaml
- Path (Path): `analysis_options.yaml`
- Core Responsibility: Dart/Flutter 静态分析规则配置。
- Key Features: 1) 引入 `flutter_lints` 推荐规则; 2) 允许按需增删 lint; 3) 作为 `flutter analyze` 的规则来源。

#### build_apk.sh
- Path (Path): `build_apk.sh`
- Core Responsibility: Android APK 发布脚本。
- Key Features: 1) 仅构建 android-arm64 release APK; 2) 开启混淆并输出符号文件; 3) 构建后复制到桌面并重命名。

#### install_ios.sh
- Path (Path): `install_ios.sh`
- Core Responsibility: iOS 真机安装/发布脚本。
- Key Features: 1) 清理 iOS build 并编译 release 包; 2) 支持指定设备 ID 安装; 3) 提供签名与无线安装失败的处理提示。

### 3.2 Go 后端服务 (backend)
#### backend/
- Path (Path): `backend/`
- Core Responsibility: Go 服务端主模块，提供 API + WebSocket + 后台管理。
- Key Features: 1) 连接 MySQL/MongoDB/Redis 并进行业务处理; 2) 组织 handlers/services/models 等核心代码; 3) 管理端与客户端 API 共存; 4) 提供上传文件存储目录。

#### backend/cmd/server/main.go
- Path (Path): `backend/cmd/server/main.go`
- Core Responsibility: 服务端入口与运行时编排。
- Key Features: 1) 加载 `config.yaml`; 2) 初始化 MySQL/MongoDB/Redis 并 AutoMigrate; 3) 启动 WebSocket Hub 与 Redis MQ; 4) 初始化消息/推送/钱包定时任务/Agora/LiveKit 服务; 5) 注册路由并优雅关停。

#### backend/internal/config/config.go
- Path (Path): `backend/internal/config/config.go`
- Core Responsibility: 统一配置结构体与 YAML 加载。
- Key Features: 1) 定义 Server/MySQL/MongoDB/Redis/JWT/WebSocket/Queue/Agora/LiveKit 配置结构; 2) YAML 读取并赋值 `GlobalConfig`; 3) 支持超时、上传目录与 base_url 等参数。

#### backend/internal/middleware/
- Path (Path): `backend/internal/middleware/`
- Core Responsibility: HTTP 中间件与鉴权体系。
- Key Features: 1) 请求日志与 CORS; 2) 用户/管理端 JWT 鉴权并注入上下文; 3) 通用与钱包操作限流; 4) 管理员角色与演示账号写保护。

#### backend/internal/cache/
- Path (Path): `backend/internal/cache/`
- Core Responsibility: Redis 缓存与限流封装。
- Key Features: 1) 缓存用户/会话/在线状态; 2) 消息序号自增与读取; 3) 验证码存储; 4) 滑动窗口限流实现。

#### backend/internal/ws/
- Path (Path): `backend/internal/ws/`
- Core Responsibility: WebSocket 连接管理与广播。
- Key Features: 1) Hub 管理连接、订阅与广播; 2) 多设备在线统计与用户在线状态推送; 3) 分片 Map/锁提升并发性能; 4) 支持按用户/会话维度推送消息。

#### backend/internal/mq/
- Path (Path): `backend/internal/mq/`
- Core Responsibility: Redis 消息队列与异步任务。
- Key Features: 1) worker 消费模型; 2) 支持优先级与延迟队列; 3) 失败重试与死信队列; 4) 用于消息同步与推送任务。

#### backend/internal/models/
- Path (Path): `backend/internal/models/`
- Core Responsibility: 业务数据模型定义。
- Key Features: 1) GORM 模型覆盖用户、会话、消息、动态、钱包、通话、系统设置; 2) 状态/类型常量集中管理; 3) 支持 AutoMigrate 表结构。

#### backend/internal/services/
- Path (Path): `backend/internal/services/`
- Core Responsibility: 业务服务层编排与复用。
- Key Features: 1) MessageService 负责消息入库/同步/广播 (MongoDB 按月分表); 2) PushService 处理 APNs 推送; 3) WalletCronService 处理红包/转账过期退款; 4) AgoraService/LiveKitService 生成 RTC Token; 5) 服务层与 Redis/WS/MQ 协作。

#### backend/internal/services/message_service.go
- Path (Path): `backend/internal/services/message_service.go`
- Core Responsibility: 消息存储与同步核心逻辑。
- Key Features: 1) 消息序号自增并写入 MongoDB; 2) 支持撤回/编辑/转发/反应/已读回执; 3) WebSocket 实时广播; 4) 媒体/文件/链接索引与统计。

#### backend/internal/services/push_service.go
- Path (Path): `backend/internal/services/push_service.go`
- Core Responsibility: iOS APNs 推送服务。
- Key Features: 1) 从系统设置读取 APNs 配置; 2) HTTP/2 发送 iOS 推送; 3) JWT token 缓存与轮转; 4) 支持新消息与来电通知。

#### backend/internal/services/wallet_cron_service.go
- Path (Path): `backend/internal/services/wallet_cron_service.go`
- Core Responsibility: 钱包定时任务处理。
- Key Features: 1) 定时扫描过期红包/转账; 2) 自动退款并写入交易流水; 3) 行锁 + 事务保证余额一致性。

#### backend/internal/handlers/
- Path (Path): `backend/internal/handlers/`
- Core Responsibility: REST API 入口与参数校验。
- Key Features: 1) 客户端 API：auth/user/chat/message/contact/moment/call/wallet/upload; 2) 管理端 API：用户、会话、动态、钱包、通话、报表; 3) 结合中间件鉴权与限流; 4) 调用服务层并触发 WS/MQ 通知。

#### backend/internal/handlers/auth_handler.go
- Path (Path): `backend/internal/handlers/auth_handler.go`
- Core Responsibility: 用户认证与设备管理接口。
- Key Features: 1) 注册/登录/用户名可用性检查; 2) JWT 生成与设备记录; 3) 密码修改与 token 刷新; 4) 可选的官方账号自动关注策略。

#### backend/internal/handlers/message_handler.go
- Path (Path): `backend/internal/handlers/message_handler.go`
- Core Responsibility: 消息收发与同步接口。
- Key Features: 1) 发送消息前进行禁言/权限检查; 2) 消息拉取/同步/撤回/编辑/转发/反应; 3) 媒体/文件/链接列表与统计; 4) 离线推送触发。

#### backend/internal/handlers/wallet_handler.go
- Path (Path): `backend/internal/handlers/wallet_handler.go`
- Core Responsibility: 钱包交易与红/转账流程。
- Key Features: 1) 钱包余额与交易流水查询; 2) 充值/提现/转账/红包流程; 3) 支付密码校验与风控限流; 4) 事务 + 行锁保证资金一致性; 5) 系统消息通知。

#### backend/pkg/jwt/jwt.go
- Path (Path): `backend/pkg/jwt/jwt.go`
- Core Responsibility: JWT 生成与解析工具。
- Key Features: 1) 用户与管理端 JWT 生成/解析; 2) 设备绑定信息写入 token; 3) 过期时间与校验逻辑。

#### backend/pkg/response/response.go
- Path (Path): `backend/pkg/response/response.go`
- Core Responsibility: API 响应结构封装。
- Key Features: 1) 统一 JSON 响应结构; 2) 常用错误码封装; 3) 简化 handler 的返回逻辑。

#### backend/deployments/
- Path (Path): `backend/deployments/`
- Core Responsibility: Docker 化部署配置。
- Key Features: 1) Dockerfile 构建 Go 服务镜像; 2) docker-compose 编排 MySQL/MongoDB/Redis/API; 3) 适用于本地或集成环境启动。

#### backend/baota/
- Path (Path): `backend/baota/`
- Core Responsibility: 宝塔面板部署方案。
- Key Features: 1) 宝塔部署说明与脚本; 2) systemd 服务配置与启动/停止/重启脚本; 3) 提供 init.sql 与 Nginx 反代示例。

#### backend/scripts/init.sql
- Path (Path): `backend/scripts/init.sql`
- Core Responsibility: MySQL 初始化脚本。
- Key Features: 1) 表结构初始化; 2) 用于首次部署导入。

#### backend/config.yaml
- Path (Path): `backend/config.yaml`
- Core Responsibility: 服务端运行配置。
- Key Features: 1) 服务端口、超时、上传目录; 2) MySQL/MongoDB/Redis/JWT/WS/Agora/LiveKit 参数; 3) base_url 与环境切换配置。

#### backend/build.sh
- Path (Path): `backend/build.sh`
- Core Responsibility: 后端构建与部署打包脚本。
- Key Features: 1) 交叉编译 Linux amd64 二进制; 2) 生成 server.zip 或 deploy.zip; 3) 与 `baota/` 目录联动产出部署包。

### 3.3 Flutter 客户端 (lib)
#### lib/
- Path (Path): `lib/`
- Core Responsibility: Flutter 客户端源码入口（feature-first 架构）。
- Key Features: 1) `core/` 提供路由/主题/服务; 2) `features/` 拆分业务模块; 3) `shared/` 放置共享组件与工具。

#### lib/main.dart
- Path (Path): `lib/main.dart`
- Core Responsibility: Flutter 应用启动入口。
- Key Features: 1) 初始化 Flutter binding 与 Isar 本地库; 2) 桌面端窗口/托盘/快捷键/通知初始化; 3) 移动端状态栏与屏幕方向设置; 4) 启动离线消息队列与后台服务 (Android)。

#### lib/app.dart
- Path (Path): `lib/app.dart`
- Core Responsibility: App Shell 与全局状态编排。
- Key Features: 1) MaterialApp.router + GoRouter; 2) 主题与多语言设置; 3) Push 通知点击跳转聊天; 4) CallService 监听来电并显示通话界面; 5) 生命周期处理后台保活。

#### lib/core/router/app_router.dart
- Path (Path): `lib/core/router/app_router.dart`
- Core Responsibility: 路由与导航规则。
- Key Features: 1) Splash/Login/Home/Chat/Wallet 等路由声明; 2) 认证状态重定向; 3) Tab + detail 页面混合导航; 4) 自定义转场与 iOS 风格页面。

#### lib/core/services/api/api_client.dart
- Path (Path): `lib/core/services/api/api_client.dart`
- Core Responsibility: API 请求封装与容错。
- Key Features: 1) Dio 客户端配置 (baseUrl/超时/headers); 2) Token 刷新 + 并发锁; 3) 请求去重与节流; 4) 自动重试与错误映射; 5) 文件上传。

#### lib/core/services/api/auth_service.dart
- Path (Path): `lib/core/services/api/auth_service.dart`
- Core Responsibility: 认证状态与用户信息管理。
- Key Features: 1) 登录/注册/获取当前用户; 2) Token 安全存储与迁移; 3) token 过期处理与退出清理; 4) 更新资料并刷新头像缓存; 5) 与推送注册/设置同步。

#### lib/core/services/api/chat_service.dart
- Path (Path): `lib/core/services/api/chat_service.dart`
- Core Responsibility: 会话与消息 API 封装。
- Key Features: 1) Chat/Message 数据模型与解析; 2) 会话 CRUD、成员管理、入群审核; 3) 发送/撤回/编辑/转发消息; 4) 媒体列表/搜索/统计接口; 5) 已读回执与免打扰/置顶状态切换。

#### lib/core/services/api/websocket_service.dart
- Path (Path): `lib/core/services/api/websocket_service.dart`
- Core Responsibility: WebSocket 连接管理。
- Key Features: 1) 连接管理与重连（指数退避）; 2) ping/pong 心跳与队列缓冲; 3) 自动订阅会话与 handler 管理; 4) 网络与生命周期感知; 5) 断线后增量同步触发。

#### lib/core/services/call_service.dart
- Path (Path): `lib/core/services/call_service.dart`
- Core Responsibility: 音视频通话能力整合。
- Key Features: 1) Agora / LiveKit RTC 引擎初始化与通话状态机; 2) CallKit/系统来电集成; 3) 权限申请与设备检测; 4) 发起/接听/拒绝/结束通话; 5) 音视频控制 (静音/扬声器/摄像头)。

#### lib/core/services/background_service.dart
- Path (Path): `lib/core/services/background_service.dart`
- Core Responsibility: Android 后台保活服务。
- Key Features: 1) 前台服务配置与通知; 2) 后台心跳保持; 3) 更新通知内容的控制接口。

#### lib/core/services/offline_message_queue.dart
- Path (Path): `lib/core/services/offline_message_queue.dart`
- Core Responsibility: 离线消息队列与重发。
- Key Features: 1) 离线消息入队与持久化; 2) 网络恢复后自动重发; 3) 失败重试与最大次数控制; 4) 网络状态回调。

#### lib/core/services/storage/models/
- Path (Path): `lib/core/services/storage/models/`
- Core Responsibility: Isar 本地数据模型。
- Key Features: 1) user/chat/message 本地缓存; 2) 提升列表加载与离线可用性; 3) 与 Riverpod 状态同步。

#### lib/core/theme/
- Path (Path): `lib/core/theme/`
- Core Responsibility: 主题系统。
- Key Features: 1) 颜色/字体/文本样式定义; 2) 明暗主题切换; 3) 主题状态 Provider。

#### lib/core/i18n/
- Path (Path): `lib/core/i18n/`
- Core Responsibility: 国际化与语言切换。
- Key Features: 1) 多语言资源映射; 2) Locale 切换; 3) MaterialApp 国际化委托集成。

#### lib/shared/
- Path (Path): `lib/shared/`
- Core Responsibility: 共享组件与通用工具。
- Key Features: 1) widgets 提供头像、骨架屏、Lottie、链接预览等通用组件; 2) utils 提供 SnackBar 等工具; 3) constants 定义响应式断点与通用常量。

#### lib/features/auth/
- Path (Path): `lib/features/auth/`
- Core Responsibility: 用户认证界面与流程。
- Key Features: 1) 登录/注册页面; 2) 用户协议/隐私政策入口; 3) 与 auth_service 联动。

#### lib/features/chat/
- Path (Path): `lib/features/chat/`
- Core Responsibility: 聊天核心功能模块。
- Key Features: 1) 会话列表与聊天详情页面; 2) 群组/频道资料与编辑; 3) 消息气泡/输入栏/语音录制/表情选择; 4) Provider 管理状态并与 Isar/WS 同步; 5) 全局搜索与二维码扫描入口。

#### lib/features/contacts/
- Path (Path): `lib/features/contacts/`
- Core Responsibility: 联系人管理模块。
- Key Features: 1) 联系人列表与分组索引; 2) 添加联系人/搜索用户; 3) Provider 管理数据缓存。

#### lib/features/moments/
- Path (Path): `lib/features/moments/`
- Core Responsibility: 朋友圈动态模块。
- Key Features: 1) 动态流/发布/点赞/评论; 2) 热门话题入口; 3) Provider 管理动态状态并支持刷新。

#### lib/features/wallet/
- Path (Path): `lib/features/wallet/`
- Core Responsibility: 钱包与支付能力模块。
- Key Features: 1) 钱包主页与余额展示; 2) 充值/提现/转账/红包页面; 3) 支付密码设置与校验; 4) 交易流水列表; 5) Provider + Service 调用后端接口。

#### lib/features/call/
- Path (Path): `lib/features/call/`
- Core Responsibility: 通话 UI 与来电处理。
- Key Features: 1) 来电接听与通话页面; 2) 通话悬浮窗 (PiP); 3) 与 CallService 状态联动。

#### lib/features/settings/
- Path (Path): `lib/features/settings/`
- Core Responsibility: 设置与个性化模块。
- Key Features: 1) 个人资料编辑; 2) 隐私与通知设置; 3) 设备管理与数据存储; 4) 个性化与贴纸管理。

#### lib/features/home/
- Path (Path): `lib/features/home/`
- Core Responsibility: 首页与导航容器。
- Key Features: 1) 底部 Tab 主导航; 2) 桌面端三栏布局; 3) 统一承载聊天/联系人/动态/设置入口。

#### lib/features/splash/
- Path (Path): `lib/features/splash/`
- Core Responsibility: 启动流程与状态初始化。
- Key Features: 1) 启动页与认证初始化; 2) 进入应用前的状态准备; 3) 与路由重定向联动。

### 3.4 管理后台 (admin)
#### admin/
- Path (Path): `admin/`
- Core Responsibility: Vue3 管理后台项目根目录。
- Key Features: 1) Vite 构建配置与脚本体系; 2) Element Plus + Pinia 的 UI/状态基础; 3) 与后端管理 API 对接。

#### admin/package.json
- Path (Path): `admin/package.json`
- Core Responsibility: 管理端依赖与脚本配置。
- Key Features: 1) dev/build/lint 等脚本; 2) Node/PNPM 版本约束; 3) Vue3/ElementPlus/Pinia/ECharts/Tailwind 依赖。

#### admin/vite.config.ts
- Path (Path): `admin/vite.config.ts`
- Core Responsibility: 管理端构建与开发配置。
- Key Features: 1) dev server 与 `/api` 代理; 2) 自动导入与组件按需加载; 3) gzip 压缩与 terser 优化; 4) alias 与依赖预构建; 5) Tailwind 集成。

#### admin/src/main.ts
- Path (Path): `admin/src/main.ts`
- Core Responsibility: Vue 应用启动入口。
- Key Features: 1) 创建 Vue 应用实例; 2) 初始化 store/router/i18n; 3) 全局指令与错误处理; 4) 引入基础样式与 Tailwind。

#### admin/src/router/
- Path (Path): `admin/src/router/`
- Core Responsibility: 路由与权限体系。
- Key Features: 1) hash 路由与静态路由表; 2) before/after 守卫与进度条; 3) 动态路由与权限校验模块。

#### admin/src/api/
- Path (Path): `admin/src/api/`
- Core Responsibility: 管理端 API 封装层。
- Key Features: 1) 管理端接口封装 (auth/admin/report/system); 2) 对接后端 `/api/v1/admin` 相关接口; 3) 统一请求与错误处理。

#### admin/src/store/
- Path (Path): `admin/src/store/`
- Core Responsibility: 全局状态管理。
- Key Features: 1) Pinia 模块 (user/menu/setting/worktab/table); 2) 权限、菜单与主题状态持久化; 3) 与路由、UI 布局联动。

#### admin/src/views/
- Path (Path): `admin/src/views/`
- Core Responsibility: 管理后台业务页面集合。
- Key Features: 1) 仪表盘与统计卡片; 2) 系统管理 (用户/会话/设置/举报); 3) 动态管理 (内容/话题/敏感词); 4) 钱包管理 (充值/提现/红包/转账); 5) 通话记录与认证页面。

#### admin/src/components/
- Path (Path): `admin/src/components/`
- Core Responsibility: 复用 UI 组件库。
- Key Features: 1) 表格/表单/图表/布局组件; 2) 封装 Element Plus 风格; 3) 媒体处理与文本特效组件。

#### admin/src/utils/
- Path (Path): `admin/src/utils/`
- Core Responsibility: 通用工具与基础能力封装。
- Key Features: 1) HTTP/Axios 封装与状态码处理; 2) storage/router/navigation/table 等工具; 3) socket/系统工具与版本升级逻辑。

#### admin/src/hooks/
- Path (Path): `admin/src/hooks/`
- Core Responsibility: 组合式逻辑复用。
- Key Features: 1) 权限、布局、表格、主题等 hooks; 2) 抽离业务页面通用逻辑; 3) 提升复用性。

#### admin/src/directives/
- Path (Path): `admin/src/directives/`
- Core Responsibility: 全局指令与权限控制。
- Key Features: 1) 权限/角色指令; 2) ripple/highlight 等交互指令; 3) 全局指令注册入口。

#### admin/src/locales/
- Path (Path): `admin/src/locales/`
- Core Responsibility: 国际化资源管理。
- Key Features: 1) 中英文语言包; 2) vue-i18n 集成; 3) 文案集中维护。

#### admin/src/assets/
- Path (Path): `admin/src/assets/`
- Core Responsibility: 管理端静态资源与样式。
- Key Features: 1) 样式入口与主题文件; 2) SVG/图片资源; 3) UI 皮肤与主题配置资源。

### 3.5 Flutter 资源 (assets)
#### assets/
- Path (Path): `assets/`
- Core Responsibility: Flutter 客户端资源根目录。
- Key Features: 1) 图标/图片/表情/音效/字体集中管理; 2) 与 `pubspec.yaml` 资源声明对应; 3) 支持多端统一资产引用。

#### assets/images/
- Path (Path): `assets/images/`
- Core Responsibility: 图片与背景资源。
- Key Features: 1) 聊天背景/封面图片; 2) UI 插画; 3) 主题与页面视觉元素。

#### assets/icons/
- Path (Path): `assets/icons/`
- Core Responsibility: UI 图标资源。
- Key Features: 1) 底部导航图标; 2) 选中/未选中状态; 3) 与 Tab UI 对应。

#### assets/emoji/lottie/
- Path (Path): `assets/emoji/lottie/`
- Core Responsibility: Lottie 表情动画资源。
- Key Features: 1) JSON 动画库; 2) 与 emoji picker/聊天消息联动; 3) 提升聊天表现力。

#### assets/stickers/
- Path (Path): `assets/stickers/`
- Core Responsibility: 贴纸与红包资源。
- Key Features: 1) 红包/转账贴纸; 2) 聊天气泡内嵌图标。

#### assets/sounds/
- Path (Path): `assets/sounds/`
- Core Responsibility: 音效与铃声资源。
- Key Features: 1) 通知/提示音效; 2) 来电铃声。

#### assets/fonts/
- Path (Path): `assets/fonts/`
- Core Responsibility: 自定义字体资源。
- Key Features: 1) 字体文件集中管理; 2) 用于 UI 标题与品牌字形。

#### assets/图标/
- Path (Path): `assets/图标/`
- Core Responsibility: 平台图标源文件。
- Key Features: 1) Android/iOS/Web 平台图标集合; 2) 多尺寸/多密度图标; 3) 构建时生成 App Icon。

### 3.6 平台工程与测试
#### android/
- Path (Path): `android/`
- Core Responsibility: Android 平台工程与配置。
- Key Features: 1) AndroidManifest 与 Gradle 配置; 2) 资源与启动图; 3) Flutter 插件注册入口。

#### ios/
- Path (Path): `ios/`
- Core Responsibility: iOS 平台工程与配置。
- Key Features: 1) Runner 工程与 Info.plist; 2) Podfile 与签名配置; 3) 插件注册与资源。

#### macos/
- Path (Path): `macos/`
- Core Responsibility: macOS 平台工程。
- Key Features: 1) Runner 工程与 entitlements; 2) 窗口与应用配置; 3) 插件注册入口。

#### windows/
- Path (Path): `windows/`
- Core Responsibility: Windows 平台工程。
- Key Features: 1) CMake 与 Runner 工程; 2) 原生窗口与资源配置; 3) 插件注册文件。

#### linux/
- Path (Path): `linux/`
- Core Responsibility: Linux 平台工程。
- Key Features: 1) CMake 构建配置; 2) 插件注册; 3) 桌面端入口文件。

#### web/
- Path (Path): `web/`
- Core Responsibility: Web 平台宿主工程。
- Key Features: 1) index.html 与 manifest.json; 2) Web 图标与启动资源; 3) Flutter Web 应用入口。

#### test/widget_test.dart
- Path (Path): `test/widget_test.dart`
- Core Responsibility: Flutter Widget 测试示例。
- Key Features: 1) 提供测试入口模板; 2) 可扩展业务组件测试; 3) 与 `flutter test` 集成。

## 第四部分：源码结构汇总表 (Source Code Structure Table)
| 路径 (Path) | 类型 (Type) | 模块名称 (Module Name) | 核心功能描述 (Key Functionality) | 备注 (Notes) |
|---|---|---|---|---|
| `backend/` | 目录 | 后端服务 | Gin API + WebSocket + MQ + 数据层 | 依赖 MySQL/MongoDB/Redis |
| `backend/cmd/server/main.go` | 文件 | 服务入口 | 加载配置、初始化 DB、启动 Hub/MQ | AutoMigrate + 优雅关停 |
| `backend/internal/handlers/` | 目录 | API 处理层 | auth/chat/message/wallet/call/admin | 覆盖 `/api/v1` |
| `backend/internal/services/` | 目录 | 业务服务层 | 消息/推送/钱包定时/Agora/LiveKit Token | Mongo + Redis + WS |
| `backend/internal/ws/` | 目录 | WebSocket Hub | 连接管理、订阅、广播、在线统计 | 分片 Map 提升并发 |
| `backend/internal/mq/` | 目录 | 消息队列 | Redis worker/延迟/重试/死信 | 同步与推送任务 |
| `backend/internal/models/` | 目录 | 数据模型 | 用户/会话/动态/钱包/通话 | GORM AutoMigrate |
| `backend/pkg/jwt/jwt.go` | 文件 | JWT 工具 | 用户/管理端 token 生成与解析 | 绑定 device_id |
| `backend/deployments/docker-compose.yaml` | 文件 | 容器编排 | MySQL/Mongo/Redis/API 启动 | 适合本地/测试 |
| `backend/baota/` | 目录 | 宝塔部署 | systemd + 脚本 + 配置 | 生产部署参考 |
| `backend/scripts/init.sql` | 文件 | 数据库初始化 | MySQL 表结构创建 | 部署必备 |
| `backend/config.yaml` | 文件 | 服务配置 | 端口/DB/JWT/WS/Agora/LiveKit | 环境差异配置 |
| `lib/` | 目录 | Flutter 客户端 | feature-first 架构 | 支持多端 |
| `lib/main.dart` | 文件 | App 入口 | Isar/桌面服务/后台服务初始化 | 启动逻辑 |
| `lib/app.dart` | 文件 | App Shell | 主题/i18n/路由/来电处理 | 生命周期管理 |
| `lib/core/router/app_router.dart` | 文件 | 路由配置 | GoRouter + 认证重定向 | 多层级导航 |
| `lib/core/services/api/api_client.dart` | 文件 | API 客户端 | Token 刷新/重试/去重/上传 | Dio 封装 |
| `lib/core/services/api/websocket_service.dart` | 文件 | WS 管理 | 重连/心跳/消息队列/订阅 | 网络感知 |
| `lib/core/services/call_service.dart` | 文件 | 通话服务 | Agora + LiveKit + CallKit | 音视频控制 |
| `lib/features/chat/` | 目录 | 聊天模块 | 会话列表/消息收发/群频道 | Provider + Isar |
| `lib/features/wallet/` | 目录 | 钱包模块 | 充值/提现/转账/红包 | 支付密码 |
| `lib/features/moments/` | 目录 | 动态模块 | 朋友圈发布/点赞/评论 | Provider |
| `lib/features/settings/` | 目录 | 设置模块 | 隐私/通知/设备/个性化 | 多页面 |
| `lib/shared/widgets/` | 目录 | 共享组件 | 头像/骨架屏/Lottie/预览 | 桌面布局 |
| `admin/` | 目录 | 管理后台 | Vue3 + Vite 项目 | Element Plus |
| `admin/src/views/` | 目录 | 管理页面 | 仪表盘/系统/动态/钱包/通话 | 运营管理 |
| `admin/src/api/` | 目录 | 管理端 API | auth/admin/report/system | Axios 封装 |
| `admin/src/router/` | 目录 | 路由权限 | guards/动态路由 | worktab 支持 |
| `admin/src/store/` | 目录 | 状态管理 | user/menu/setting/worktab | Pinia |
| `assets/` | 目录 | 静态资源 | 图标/图片/表情/音效 | Flutter assets |
| `android/` | 目录 | Android 工程 | Manifest/Gradle/资源 | Flutter runner |
| `ios/` | 目录 | iOS 工程 | Runner/Podfile/资源 | Flutter runner |
| `web/` | 目录 | Web 工程 | index/manifest/icon | Flutter web |
| `test/widget_test.dart` | 文件 | 测试入口 | Widget 测试样例 | 可扩展 |
