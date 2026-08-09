# Flutter Web 版 H5 与 App 同款开发方案

## 1. 结论

推荐采用 **Flutter Web 作为新版完整 H5 客户端**，保留现有 Vue H5 作为公开资料页、分享落地页和轻量访问页。

原因：

- 当前 App 已经是 Flutter，继续用 Flutter Web 可以最大程度复用 App 页面、组件、状态管理、接口和业务逻辑。
- 目标是“和 App 样式完全一样、功能一样”，用 Vue 手工仿 App 会形成两套前端，后续维护成本高。
- 项目内已经存在 `web/`、`lib/bootstrap/bootstrap_web.dart`、`go_router`、Web 条件编译文件，说明 Flutter Web 不是从零开始。
- Vue H5 已经有公开资料页能力，适合继续承担未登录访问、分享链接、SEO/轻量落地页。

最终形态：

| 端 | 技术 | 职责 |
| --- | --- | --- |
| App | Flutter | Android/iOS 主客户端 |
| 完整 H5 | Flutter Web/PWA | 登录后的完整 IM 体验，尽量和 App 同款 |
| 公开 H5 | Vue | 公开资料页、分享落地页、未登录引导 |
| 管理端 | Vue/Admin | 后台运营与配置 |
| 后端 | Go API | 统一接口、WebSocket、文件、登录、好友、群聊 |

## 2. 当前项目基础

当前代码结构已经具备 Flutter Web 适配基础：

- Flutter App 主入口：`lib/main.dart`
- Flutter App 根组件：`lib/app.dart`
- Web 启动入口：`lib/bootstrap/bootstrap_web.dart`
- Web 静态目录：`web/index.html`、`web/manifest.json`
- 路由：`lib/core/router/app_router.dart`
- API 配置：`lib/core/services/api/api_client.dart`
- Endpoint 动态切换：`lib/core/services/api/endpoint_manager.dart`
- H5 Vue 工程：`h5/`
- 后端服务：`backend/`
- 管理端：`admin/`

已经实现过的 Vue H5 公开资料页能力建议继续保留：

- `GET /api/v1/public/user/:id`
- Vue H5 路由 `/u/:username`
- 未登录公开资料页
- App 分享链接优先使用 `/u/{username}`

## 3. 产品目标

### 3.1 第一目标

把 Flutter App 编译成可访问的 Web H5，并跑通登录后的核心链路：

- 登录
- 首页
- 聊天列表
- 聊天详情
- 用户资料
- 好友资料/加好友
- WebSocket 实时消息
- 图片、文件基础展示

### 3.2 第二目标

让 Flutter Web 在移动浏览器里尽量和 App 一样：

- 页面结构一致
- 底部导航一致
- 聊天气泡一致
- 用户资料页一致
- 设置页一致
- 登录态保持一致
- 分享链接可从 Vue 公开页跳转到 Flutter Web 完整客户端

### 3.3 第三目标

做成可独立部署的 PWA：

- 可添加到手机桌面
- 使用 App 图标和名称
- 移动端全屏体验
- 静态资源缓存
- 基础离线提示

## 4. 推荐 URL 规划

### 4.1 本地开发

| 服务 | 地址 |
| --- | --- |
| 后端 API | `http://localhost:8080/api/v1` |
| 后端 WebSocket | `ws://localhost:8080/api/v1/ws` |
| Vue 公开 H5 | `http://localhost:5173/` |
| 管理端 | `http://localhost:5174/` |
| Flutter Web 完整 H5 | `http://localhost:5175/` |

Flutter Web 本地启动建议：

```bash
flutter run -d chrome \
  --web-port 5175 \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

如果浏览器因为 `localhost`、`127.0.0.1`、Docker 网络导致接口不通，可以统一改成：

```bash
--dart-define=GENERIC_IM_SERVER_URL=http://127.0.0.1:8080
--dart-define=GENERIC_IM_WS_URL=ws://127.0.0.1:8080/api/v1/ws
```

### 4.2 线上部署

推荐域名规划：

| 域名 | 职责 |
| --- | --- |
| `api.example.com` | 后端 API/WebSocket |
| `h5.example.com` | Vue 公开 H5 分享页 |
| `web.example.com` | Flutter Web 完整客户端 |
| `admin.example.com` | 管理端 |

分享链路建议：

1. 用户分享 `https://h5.example.com/u/username`
2. 未登录用户看到 Vue 公开资料页
3. 点击“发消息/加好友/打开通用IM”跳转 `https://web.example.com/user/{id}` 或 `https://web.example.com/login?redirect=...`
4. 登录成功后进入 Flutter Web 同款 App 页面

## 5. 技术路线

### 5.1 不新建 Flutter 项目

直接在当前 Flutter App 工程中适配 Web，原因：

- 能复用现有 `lib/features/*` 页面。
- 能复用现有 `authServiceProvider`、`chatServiceProvider`、WebSocket 服务。
- 能复用已有主题、组件、路由、国际化。
- 能避免 App 和 H5 业务逻辑分裂。

### 5.2 保留 Vue H5

Vue H5 不删除，职责变为：

- 公开资料页
- 用户分享落地页
- 未登录访问页
- SEO 友好页面
- 引导下载 App 或打开 Flutter Web

Vue H5 不继续承担完整聊天体验，避免和 Flutter App 重复开发。

### 5.3 Flutter Web 重点适配项

需要重点处理：

- Web 编译错误
- 移动浏览器布局
- Web 端登录态存储
- WebSocket 连接
- 文件上传/图片选择
- 音频录制权限
- 视频播放
- 浏览器返回键
- 深链接路由
- PWA 缓存
- CORS 和静态资源跨域

## 6. 分期开发计划

### 第 0 期：Web 可编译审计

目标：确认当前 Flutter 工程能否稳定编译 Web。

任务：

- 执行 `flutter build web --debug`
- 处理不支持 Web 的依赖和 `dart:io` 引用
- 检查条件导入是否完整
- 检查 `kIsWeb` 分支是否覆盖原生能力
- 建立 Web 专用启动命令

验收：

- `flutter build web --debug` 通过
- `flutter run -d chrome --web-port 5175` 能打开首页
- 控制台没有阻塞性红色异常

### 第 1 期：登录与基础接口

目标：Flutter Web 能登录并获取当前用户信息。

任务：

- 使用 `GENERIC_IM_SERVER_URL`、`GENERIC_IM_WS_URL` 控制接口地址
- 检查 `EndpointManager` 在 Web 端的默认地址
- 登录页适配移动浏览器
- 登录成功后进入 `/home`
- Token 存储在 Web 可用存储中
- 刷新页面后能恢复登录态
- 处理接口跨域 CORS

验收：

- Web 可使用真实账号登录
- `/api/v1/auth/login` 成功
- `/api/v1/user/me` 成功
- 刷新页面仍保持登录
- 退出登录后回到登录页

### 第 2 期：首页与主导航

目标：Web H5 主界面和 App 一致。

任务：

- 适配 `HomePage`
- 检查底部 Tab：聊天、联系人、发现、设置
- 检查移动端高度、安全区、虚拟键盘遮挡
- 浏览器返回键和 App 返回逻辑对齐
- 桌面宽屏时提供最大内容宽度或双栏布局

验收：

- 移动端浏览器首屏像 App
- 首页、联系人、发现、设置可正常切换
- 页面不横向溢出
- 刷新当前 Tab 后状态恢复合理

### 第 3 期：聊天列表与 WebSocket

目标：登录后能看到聊天列表，并实时收到消息。

任务：

- 初始化 WebSocket
- REST Token 与 WebSocket Token 保持一致
- 聊天列表接口联调
- 未读数、最后一条消息、头像显示
- WebSocket 断线重连
- 浏览器切后台后恢复连接

验收：

- 聊天列表数据和 App 一致
- 另一个客户端发消息，Web 能实时显示
- 断网/刷新后能重连
- Token 刷新后 WebSocket 不失效

### 第 4 期：聊天详情

目标：聊天页达到可用状态。

任务：

- 文本消息发送/接收
- 图片消息展示
- 文件消息展示
- 表情/贴纸基础展示
- 消息长按菜单改为 Web 可用交互
- 输入框、键盘、滚动到底部适配
- 消息撤回、删除、复制基础功能

验收：

- 私聊可正常收发文本
- 群聊可正常收发文本
- 图片可上传和预览
- 文件可上传和下载
- 手机浏览器输入时页面不乱跳

### 第 5 期：资料页与好友链路

目标：Web H5 的用户资料页、好友页和 App 一致。

任务：

- 适配 `/user/:userId`
- 支持从 Vue `/u/:username` 跳转过来
- 用户资料展示：头像、昵称、用户名、签名、共同群
- 好友状态展示
- 加好友、发消息、拉黑、举报
- 未登录跳登录，登录后回到原目标页

验收：

- 公开资料页点击后能进入 Flutter Web
- 已登录时资料页功能和 App 一致
- 未登录时能跳登录并回跳
- 好友申请流程可走通

### 第 6 期：联系人、群聊、设置

目标：补齐 App 高频功能。

任务：

- 联系人列表
- 新朋友/好友申请
- 群资料
- 创建群/编辑群
- 设置页
- 个人资料编辑
- 头像上传
- 隐私与安全设置

验收：

- 联系人数据和 App 一致
- 好友申请可处理
- 群资料可查看
- 个人资料可修改
- 设置项不出现 Web 不支持的死按钮

### 第 7 期：媒体与原生能力降级

目标：把 App 原生能力改造成 Web 可用能力。

需要处理的能力：

| App 能力 | Web 处理方式 |
| --- | --- |
| 系统推送 | PWA Push 后续支持，第一期先用站内 WebSocket |
| 通讯录 | Web 端不默认支持，隐藏或改为手动搜索 |
| 相册保存 | 改为下载文件 |
| 扫码 | 使用浏览器摄像头权限 |
| 录音 | 使用 Web MediaRecorder 或现有 `record_web` |
| 视频通话 | 使用浏览器 WebRTC 能力，优先复用 LiveKit/Agora Web 支持 |
| 后台保活 | Web 不保证后台常驻，使用重连和前台恢复 |
| 生物识别 | Web 第一阶段隐藏，后续接 WebAuthn |

验收：

- Web 不支持的功能不会假装可用
- 不支持项有明确降级或隐藏
- 用户不会点到无反应按钮

### 第 8 期：PWA 与部署

目标：让 Flutter Web 像一个可安装 H5 App。

任务：

- 完善 `web/manifest.json`
- 图标、名称、主题色检查
- 配置 HTTPS
- 配置 Nginx 静态文件托管
- 配置 SPA fallback 到 `index.html`
- 配置 API/WebSocket 反向代理
- 配置缓存策略
- 移动端添加到桌面测试

验收：

- `https://web.example.com` 可访问
- 刷新深链接不 404
- `/user/:id`、`/chat/:chatId` 可直接打开
- PWA 可添加到桌面
- 线上 API 和 WebSocket 正常

## 7. 后端需要配合的内容

后端大部分可以复用，重点检查：

- CORS 允许 Flutter Web 域名
- WebSocket 允许 Flutter Web 域名
- 文件上传支持浏览器 multipart
- 静态资源 `/uploads/*` 支持跨域访问
- 登录接口返回的 Token 可在 Web 使用
- Token 刷新接口可在 Web 使用
- 公开资料接口继续保留
- 深链接跳转需要的用户 ID/username 查询能力稳定

建议新增或确认：

```text
Access-Control-Allow-Origin: https://web.example.com, https://h5.example.com
Access-Control-Allow-Headers: Authorization, Content-Type
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
```

WebSocket 线上建议：

```text
wss://api.example.com/api/v1/ws
```

### 7.1 client/bootstrap 地址注意事项

当前本地 Docker 配置可能会让 `/api/v1/client/bootstrap` 返回 Android 模拟器地址：

```text
http://10.0.2.2:8080
ws://10.0.2.2:8080/api/v1/ws
```

这个地址在浏览器里不可用。Flutter Web 端已加入保护：Web 环境遇到 `10.0.2.2` 会替换成启动参数里的地址：

```bash
--dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080
--dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

后续部署或联调时仍建议从源头修正：

- 本地浏览器开发：bootstrap 返回 `http://localhost:8080` 和 `ws://localhost:8080/api/v1/ws`
- 手机真机访问电脑服务：bootstrap 返回电脑局域网 IP，例如 `http://192.168.x.x:8080`
- 线上部署：bootstrap 返回 HTTPS/WSS 域名，例如 `https://api.example.com` 和 `wss://api.example.com/api/v1/ws`

## 8. 前端路由规划

Flutter Web 复用 App 路由，并补充 Web 深链接：

| 路由 | 页面 |
| --- | --- |
| `/` | 启动页/登录态判断 |
| `/login` | 登录 |
| `/register` | 注册 |
| `/home` | 首页 |
| `/chat/:chatId` | 聊天详情 |
| `/user/:userId` | 用户资料 |
| `/group/:groupId/profile` | 群资料 |
| `/settings` | 设置 |

Vue H5 保留：

| 路由 | 页面 |
| --- | --- |
| `/u/:username` | 公开用户资料 |
| `/user/:id` | 公开用户资料兼容入口 |

跳转规则：

- 未登录访问 Flutter Web 受保护路由：跳 `/login?redirect=原路径`
- 登录成功：回到 `redirect`
- Vue 公开资料页点击“发消息”：跳 Flutter Web `/user/:id`
- 如果用户未登录：Flutter Web 自己处理登录和回跳

## 9. 本地开发命令

### 9.1 启动后端

```bash
docker compose up -d api
```

或按当前后端开发方式启动 Go 服务，确保：

```text
http://localhost:8080/api/v1/ping
```

可访问。

### 9.2 启动 Vue 公开 H5

```bash
cd h5
VITE_API_BASE_URL=http://localhost:8080/api/v1 \
VITE_MEDIA_BASE_URL=http://localhost:8080 \
npm run dev -- --host 0.0.0.0 --port 5173
```

### 9.3 启动 Flutter Web 完整 H5

```bash
flutter run -d chrome \
  --web-port 5175 \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

### 9.4 构建 Flutter Web

```bash
flutter build web --release \
  --dart-define=GENERIC_IM_SERVER_URL=https://api.example.com \
  --dart-define=GENERIC_IM_WS_URL=wss://api.example.com/api/v1/ws
```

构建产物：

```text
build/web/
```

## 10. 验收清单

### 基础验收

- Flutter Web 能启动
- 登录成功
- 刷新后保持登录
- 退出登录正常
- API 地址正确
- WebSocket 连接成功
- 控制台无阻塞异常

### 样式验收

- 登录页和 App 保持一致
- 首页和 App 保持一致
- 聊天列表和 App 保持一致
- 聊天气泡和 App 保持一致
- 用户资料页和 App 保持一致
- 移动端无横向滚动
- 输入框不被键盘遮挡

### 功能验收

- 私聊文本收发
- 群聊文本收发
- 图片展示
- 文件下载
- 好友资料查看
- 加好友
- 发消息
- 拉黑/解除拉黑
- 设置页可用

### 链路验收

- Vue `/u/:username` 可访问公开资料
- 公开资料页能跳 Flutter Web
- Flutter Web 未登录能跳登录
- 登录后能回到原页面
- 深链接刷新不 404

## 11. 风险与处理方案

| 风险 | 处理 |
| --- | --- |
| Flutter Web 包体较大 | 开启 release 构建、资源压缩、CDN、延迟加载 |
| 某些 Flutter 插件不支持 Web | 条件导入、`kIsWeb` 降级、隐藏不支持入口 |
| 移动浏览器键盘导致布局错位 | 聊天页单独适配输入框和滚动 |
| WebSocket 后台断开 | 前台恢复时重连，消息通过增量同步补齐 |
| 浏览器不能像 App 一样后台推送 | 第一期用站内实时消息，后续接 PWA Push |
| 线上刷新深链接 404 | Nginx 配置 SPA fallback |
| API 跨域失败 | 后端 CORS 加入 `web.example.com`、`h5.example.com` |

## 12. 建议开发优先级

优先级从高到低：

1. Flutter Web 编译和启动
2. 登录、用户信息、登录态恢复
3. 首页和主导航
4. 聊天列表和 WebSocket
5. 聊天详情文本消息
6. 用户资料页和好友链路
7. 图片、文件、表情
8. 联系人、群资料、设置
9. PWA 和线上部署
10. 通话、扫码、录音等高级能力

## 13. 最小可上线版本

第一版可以只包含：

- 登录/退出
- 首页
- 聊天列表
- 私聊文本收发
- 群聊文本收发
- 用户资料页
- 加好友/发消息
- Vue 公开资料页跳转 Flutter Web

暂缓：

- 音视频通话
- 系统推送
- 通讯录
- 生物识别
- 复杂媒体编辑
- 完整离线能力

这样可以最快验证“Flutter Web 作为完整 H5”的路线是否可行。

## 14. 下一步执行建议

下一步直接进入开发验证：

1. 启动后端 API。
2. 执行 Flutter Web 本地启动命令。
3. 修复第一批 Web 编译错误。
4. 验证登录。
5. 验证聊天列表。
6. 验证 WebSocket。
7. 再开始逐页对齐 App 样式。

只要第 1 到第 6 步跑通，就可以确认这条路线成立，后续就是逐页适配和补齐功能。

## 15. 后续 AI 开发路线

本章节用于后续把任务一段一段交给 AI 开发。建议每次只让 AI 做一个阶段，不要一次性要求“全部开发完”，否则容易改动过大、问题难定位。

每个阶段的固定流程：

1. 先让 AI 阅读本阶段涉及文件。
2. 让 AI 说明当前项目已有能力和缺口。
3. 让 AI 实施本阶段代码修改。
4. 让 AI 启动或构建验证。
5. 让 AI 给出测试账号、访问地址、已完成内容和未完成风险。

### 阶段 1：Flutter Web 可启动

目标：

- 当前 Flutter App 能以 Web H5 方式启动。
- 本地访问 `http://localhost:5175/` 能看到启动页或登录页。

重点文件：

- `pubspec.yaml`
- `web/index.html`
- `web/manifest.json`
- `lib/main.dart`
- `lib/bootstrap/bootstrap.dart`
- `lib/bootstrap/bootstrap_web.dart`
- `lib/core/services/api/endpoint_manager.dart`

给 AI 的任务提示：

```text
请根据 docs/FlutterWeb版H5与App同款开发方案.md 的阶段 1，检查当前 Flutter 项目 Web 启动能力。
要求：
1. 执行 flutter build web --debug 或 flutter run -d chrome --web-port 5175。
2. 如果出现 Web 编译错误，修复不支持 Web 的 import、插件或 dart:io 问题。
3. 保持 App 原生端逻辑不被破坏，Web 专用逻辑用 kIsWeb 或条件导入处理。
4. 验证 http://localhost:5175/ 可以打开。
5. 最后告诉我启动命令、访问地址、修复了哪些文件。
```

验收命令：

```bash
flutter build web --debug \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

完成标准：

- Web 编译通过。
- Chrome 能打开页面。
- 控制台没有导致白屏的异常。

### 阶段 2：接口地址和登录态

目标：

- Flutter Web 使用正确的本地后端地址。
- Web 能登录、获取用户信息、刷新后保持登录态。

重点文件：

- `lib/core/services/api/api_client.dart`
- `lib/core/services/api/endpoint_manager.dart`
- `lib/core/services/api/auth_service.dart`
- `lib/features/auth/pages/login_page.dart`
- `lib/core/router/app_router.dart`

给 AI 的任务提示：

```text
请开发 Flutter Web 的登录和接口地址验证。
要求：
1. 使用 --dart-define=GENERIC_IM_SERVER_URL 和 --dart-define=GENERIC_IM_WS_URL 控制 Web API 地址。
2. 确认 Web 端登录请求访问 http://localhost:8080/api/v1/auth/login。
3. 登录成功后能访问 /api/v1/user/me。
4. 刷新浏览器后仍保持登录态。
5. 未登录访问受保护路由时跳转登录页。
6. 不影响 Android/iOS 端登录逻辑。
请完成代码修改并启动验证。
```

验收命令：

```bash
flutter run -d chrome \
  --web-port 5175 \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

完成标准：

- 可以用真实账号登录。
- 登录成功进入 `/home`。
- 刷新页面后不掉登录。
- 退出登录后回到登录页。

### 阶段 3：首页和底部导航适配

目标：

- Flutter Web 首页看起来和 App 主界面一致。
- 移动浏览器下底部导航、页面高度、安全区正常。

重点文件：

- `lib/features/home/pages/home_page.dart`
- `lib/features/chat/pages/chat_page.dart`
- `lib/features/contacts/pages/contacts_page.dart`
- `lib/features/discover/pages/discover_page.dart`
- `lib/features/settings/pages/settings_page.dart`
- `lib/core/router/app_router.dart`
- `lib/core/theme/`

给 AI 的任务提示：

```text
请适配 Flutter Web 首页和底部导航。
要求：
1. 登录后 /home 页面在移动浏览器中样式尽量和 App 一致。
2. 聊天、联系人、发现、设置 Tab 可以正常切换。
3. 页面不能横向溢出。
4. 浏览器返回键行为合理。
5. 桌面浏览器宽屏不要过度拉伸，必要时加最大宽度或响应式布局。
6. 不改变 App 原生端已有体验。
请完成修改，并用 Chrome 移动端尺寸验证。
```

完成标准：

- `/home` 可正常打开。
- 四个主 Tab 可切换。
- 移动端尺寸无明显错位。
- 桌面尺寸可用。

### 阶段 4：聊天列表和 WebSocket

目标：

- Web 端能显示聊天列表。
- WebSocket 能连接并实时更新消息。

重点文件：

- `lib/core/services/api/websocket_service.dart`
- `lib/core/services/api/chat_service.dart`
- `lib/features/chat/pages/chat_page.dart`
- `lib/features/chat/providers/`
- `lib/app.dart`

给 AI 的任务提示：

```text
请开发 Flutter Web 聊天列表和 WebSocket 联调。
要求：
1. 登录后聊天列表能从后端加载。
2. WebSocket 使用 ws://localhost:8080/api/v1/ws。
3. Token 刷新后 WebSocket 使用新 Token。
4. 收到新消息时聊天列表能更新最后一条消息和未读数。
5. 断线后能自动重连。
6. 浏览器刷新后能重新连接。
请完成代码修改并用两个账号互发消息验证。
```

完成标准：

- 聊天列表有真实数据。
- WebSocket 连接成功。
- 新消息能实时出现。
- 断线/刷新后能恢复。

### 阶段 5：聊天详情文本消息

目标：

- 私聊和群聊能正常收发文本消息。
- 聊天页移动端输入体验可用。

重点文件：

- `lib/features/chat/pages/chat_detail_page.dart`
- `lib/features/chat/widgets/`
- `lib/features/chat/providers/`
- `lib/core/services/api/chat_service.dart`

给 AI 的任务提示：

```text
请开发 Flutter Web 聊天详情页的基础消息能力。
要求：
1. 私聊能发送和接收文本消息。
2. 群聊能发送和接收文本消息。
3. 消息列表滚动、自动到底部、未读处理正常。
4. 输入框在手机浏览器键盘弹起时不遮挡或错位。
5. 复制、删除、撤回等基础菜单在 Web 可用。
6. 不处理复杂媒体，先保证文本消息稳定。
请完成代码修改并给出验证步骤。
```

完成标准：

- 私聊文本收发成功。
- 群聊文本收发成功。
- 输入框和消息列表在手机尺寸可用。
- 刷新后消息仍能加载。

### 阶段 6：用户资料页和好友链路

目标：

- Flutter Web 用户资料页和 App 资料页一致。
- Vue 公开资料页能跳转 Flutter Web。
- 未登录跳登录，登录后回到原资料页。

重点文件：

- `lib/features/chat/pages/user_profile_page.dart`
- `lib/core/router/app_router.dart`
- `lib/core/services/api/user_service.dart`
- `lib/core/services/api/contact_service.dart`
- `h5/src/views/UserProfileView.vue`
- `h5/src/router/index.ts`

给 AI 的任务提示：

```text
请开发 Flutter Web 用户资料页和好友链路。
要求：
1. Flutter Web 支持 /user/:userId 深链接。
2. 已登录时展示完整用户资料、好友状态、共同群等信息。
3. 支持加好友、发消息、拉黑、举报等 App 已有能力。
4. 未登录访问 /user/:userId 时跳 /login?redirect=原地址。
5. 登录成功后自动回到原资料页。
6. Vue H5 的 /u/:username 页面点击发消息/加好友时跳转到 Flutter Web。
请完成前后端必要修改并验证。
```

完成标准：

- `http://localhost:5175/user/{id}` 可直接打开。
- 未登录能跳登录。
- 登录后能回跳资料页。
- 加好友和发消息链路可走通。

### 阶段 7：图片、文件、表情

目标：

- 聊天页支持基础媒体消息。

重点文件：

- `lib/features/chat/pages/chat_detail_page.dart`
- `lib/features/chat/widgets/`
- `lib/core/services/api/chat_service.dart`
- `lib/core/services/media_cache_manager.dart`
- `lib/shared/widgets/avatar_widget.dart`
- `backend/internal/handlers/`

给 AI 的任务提示：

```text
请补齐 Flutter Web 聊天页的图片、文件、表情基础能力。
要求：
1. 图片可以选择、上传、发送、预览。
2. 文件可以选择、上传、发送、下载。
3. 表情和贴纸能展示，发送能力按现有 App 能力复用。
4. Web 端不支持的本地文件路径逻辑要改成浏览器可用方式。
5. 媒体 URL 统一通过 ApiConfig.getMediaUrl 处理。
6. 不影响 App 原生端媒体能力。
```

完成标准：

- 图片发送和预览可用。
- 文件上传和下载可用。
- 表情展示正常。
- 媒体资源不出现跨域或 404。

### 阶段 8：联系人、群资料、设置

目标：

- 补齐完整 H5 客户端的高频页面。

重点文件：

- `lib/features/contacts/pages/`
- `lib/features/chat/pages/group_profile_page.dart`
- `lib/features/chat/pages/group_edit_page.dart`
- `lib/features/settings/pages/`
- `lib/features/settings/pages/profile_page.dart`

给 AI 的任务提示：

```text
请适配 Flutter Web 的联系人、群资料和设置页。
要求：
1. 联系人列表、新朋友、好友申请可以正常使用。
2. 群资料、群成员、群设置可以查看和编辑。
3. 设置页、个人资料页可以正常打开。
4. 头像上传在 Web 可用。
5. Web 不支持的功能要隐藏、禁用或给出明确提示，不能保留无反应按钮。
6. 页面样式尽量和 App 一致。
```

完成标准：

- 联系人和好友申请可用。
- 群资料可用。
- 设置页可用。
- 个人资料可编辑。

### 阶段 9：Web 专属降级和兼容

目标：

- 把 App 原生能力在 Web 上做合理降级，避免假功能。

重点文件：

- `lib/core/utils/platform_utils.dart`
- `lib/core/services/`
- `lib/features/settings/pages/settings_page.dart`
- `lib/features/chat/pages/qr_scanner_page.dart`
- `lib/features/call/`
- `lib/features/meeting/`

给 AI 的任务提示：

```text
请检查并处理 Flutter Web 不支持的原生能力。
要求：
1. 扫码、录音、相册保存、系统通知、通话、通讯录、生物识别逐项检查。
2. Web 可实现的使用浏览器能力适配。
3. Web 暂不支持的入口要隐藏、禁用或提示。
4. 不允许保留点击无反应的按钮。
5. 不影响 Android/iOS 原有功能。
6. 输出一份 Web 能力支持清单。
```

完成标准：

- Web 上没有明显假按钮。
- 不支持能力有明确处理。
- App 原生端功能不受影响。

### 阶段 10：PWA、部署和线上验收

目标：

- Flutter Web 可以作为独立 H5/PWA 部署。

重点文件：

- `web/index.html`
- `web/manifest.json`
- `Dockerfile` 或部署脚本
- `docker-compose.yml`
- Nginx 配置
- 后端 CORS 配置

给 AI 的任务提示：

```text
请完成 Flutter Web 的 PWA 和部署配置。
要求：
1. flutter build web --release 可以生成 build/web。
2. Nginx 可以部署 build/web。
3. 支持 SPA fallback，刷新 /user/:id、/chat/:chatId 不 404。
4. API 使用 https://api.example.com。
5. WebSocket 使用 wss://api.example.com/api/v1/ws。
6. manifest、图标、标题、主题色正确。
7. 移动浏览器可以添加到桌面。
请给出部署文件、构建命令和验收步骤。
```

完成标准：

- 线上域名能访问 Flutter Web。
- 深链接刷新不 404。
- 登录和聊天可用。
- PWA 可安装。

## 16. AI 开发注意事项

后续让 AI 开发时，建议固定加上这些要求：

```text
开发要求：
1. 先阅读相关文件，不要凭空重写。
2. 优先复用现有 Flutter App 页面、服务、Provider、主题和路由。
3. Web 专用逻辑使用 kIsWeb 或条件导入，不要破坏 Android/iOS。
4. 每次只完成一个阶段，控制改动范围。
5. 修改后必须运行 flutter analyze 或 flutter build web 验证。
6. 如果启动了服务，请告诉我访问地址。
7. 如果某个功能 Web 不支持，请做降级、隐藏或明确提示，不能留假按钮。
8. 不要删除现有 Vue H5，Vue H5 继续负责公开资料页和分享落地页。
```

每次开发完成后，让 AI 输出：

```text
本次完成：
- ...

修改文件：
- ...

验证结果：
- ...

访问地址：
- ...

还没完成/风险：
- ...
```

## 17. 当前开发进度记录

记录时间：2026-06-23 18:42 CST。

已完成：

- Flutter Web 可通过 debug 构建。
- Flutter Web 本地开发服务已按完整 H5 客户端启动。
- 登录重定向已支持 `redirect` 参数，未登录访问受保护路由会跳 `/login?redirect=...`。
- 登录、注册、启动页会保留目标路由，登录成功后回跳原页面。
- Flutter Web 路由初始化不再强制覆盖浏览器初始地址，Web 深链接可交给浏览器/hash route 进入目标页。
- Web 小屏不再强制使用桌面布局，首页、认证页、聊天页、资料页等按宽度使用 App 风格移动布局。
- Web 小屏底部导航已按移动端逻辑保留安全空间。
- Flutter Web 端已处理 bootstrap 返回 `10.0.2.2` 的问题，会替换为 `GENERIC_IM_SERVER_URL` / `GENERIC_IM_WS_URL`。
- 朋友圈页分享函数作用域已满足 Web 构建要求。
- 聊天详情页、顶部栏、输入栏、更多菜单、消息菜单已收敛 Web 相关平台判断；Web 小屏继续走 App 移动样式，物理桌面才走桌面交互。
- WebSocket 连接成功后不会在 Web 上误启动 Android 后台服务。
- Web 端聊天输入栏已重新开放语音录制入口，走浏览器麦克风权限和 `record_web`。
- Web 端相机入口只保留拍照；录像入口暂时隐藏，待后续补齐 Web 视频发送后再开放。
- Web 拍照结果走 bytes 待发送图片队列，可像相册图片一样补文字后发送。
- Web 端附件面板已新增“视频”入口，选择视频后走 bytes 上传并发送 `type=3` 视频消息。
- 消息 Provider 已新增 `sendVideoFromBytes`，Web 不再依赖本地文件路径发送视频。
- Web 端视频气泡已改为优先使用规范化后的网络媒体地址，避免浏览器误走 `File(localPath)`。
- Web 端视频播放页已隐藏“保存到相册”按钮，避免出现浏览器不可用的原生入口。
- 视频播放页加载失败重试时会释放旧 `VideoPlayerController`，减少重复初始化和异步回调串线风险。
- 视频气泡和视频播放页已补稳定测试 Key，便于后续做自动化 UI 验收。
- 已新增 Flutter Web 视频播放烟测脚本：`scripts/smoke_flutter_web_video.mjs`。
- 当前 Flutter 版本直接执行 Web `integration_test` 会提示 `Web devices are not supported for integration tests yet`，Web 自动验收暂改用 Node + Chrome DevTools Protocol。
- Web 端语音录制已接入：浏览器录音使用 `AudioEncoder.opus` 输出 `audio/webm`，停止后读取 blob bytes 上传 `/upload/voice`，并发送 `type=4` 语音消息。
- App 原生端语音录制仍保留原来的本地 `.m4a` 文件上传路径。
- Web 端浏览器不支持录音格式或拒绝麦克风权限时，会给出明确错误提示。
- 已新增 Flutter Web 语音录制烟测脚本：`scripts/smoke_flutter_web_voice.mjs`，默认启动临时 Chrome 假麦克风并通过 CDP 验证 MediaRecorder 录音、上传、发送和音频响应头。
- 语音烟测脚本已扩展为发送后立即在浏览器 `<audio>` 中播放刚上传的 `audio/webm`，验证刷新后播放所需的 MIME、CORS 和解码能力。
- 已新增 Flutter Web 定位烟测脚本：`scripts/smoke_flutter_web_location.mjs`，通过 CDP 授权/覆盖浏览器 Geolocation 坐标，并发送 `type=6` 位置消息后回查消息列表。
- 已新增 Flutter Web 摄像头烟测脚本：`scripts/smoke_flutter_web_camera.mjs`，临时启动假摄像头 Chrome，打开 `/scan` 并验证 `getUserMedia({ video: true })` 能输出 live 视频流。
- 已新增二维码协议单测：`test/core/utils/qr_payload_test.dart`，覆盖 `genericim://user`、`genericim://group`、`genericim://login` 的构建、解析和非法 payload 拒绝。
- 已新增 Flutter Web 二维码业务链路烟测：`scripts/smoke_flutter_web_qr_flow.mjs`，覆盖用户二维码取资料/加好友/打开私聊、群二维码按 invite_link 入群、登录二维码确认并换取 token。
- Web 端扫码页相册识别已改为浏览器 `BarcodeDetector` 解码，不再调用 `mobile_scanner` Web 不支持的 `analyzeImage()`。
- 已新增二维码 SVG 生成工具：`scripts/generate_qr_svg.dart`。
- 已新增 Flutter Web 二维码图片解码烟测：`scripts/smoke_flutter_web_qr_image.mjs`，生成真实二维码图片并在 `/scan` 同源页面用 `BarcodeDetector` 读出 payload。
- 已新增 Flutter Web 通话双端烟测脚本：`scripts/smoke_flutter_web_call.mjs`，覆盖浏览器音视频权限、RTC 配置、双账号 WebSocket、发起、接听、心跳、挂断和通话记录。
- 通话 UI 核心按钮已补稳定 `ValueKey`、`tooltip` 和 `Semantics`：聊天页语音/视频入口、来电接听/拒绝、通话页静音/扬声器/视频开关/切摄像头/最小化/挂断。
- 已新增 Flutter Web 通话 UI 烟测脚本：`scripts/smoke_flutter_web_call_ui.mjs`，通过静态 Web 页面恢复登录态，支持 `incoming` 和 `outgoing` 两种模式：被叫侧可真实展示来电页并点击接听/挂断；主叫侧可从聊天详情页点击真实语音/视频按钮发起，等待被叫接听、历史进入 `connected`，再从主叫通话页点击挂断。
- 已新增 Flutter Web 通话 UI 回归套件：`scripts/smoke_flutter_web_call_ui_suite.mjs`，串行覆盖 incoming 语音、incoming 视频、outgoing 语音、outgoing 视频四条 UI 链路，默认每条失败自动重试 1 次，并输出统一 JSON 汇总。
- 已新增 Flutter Web 真实浏览器 RTC 人工验收启动器：`scripts/launch_flutter_web_call_manual_qa.mjs`。脚本会登录 `h5test` / `h5peer`、清理未结束通话、打开两个独立 Chrome 用户目录，主叫直接进入私聊页，被叫进入 H5 首页等待来电；不使用 fake media，也不自动授权麦克风/摄像头权限。
- 已新增真机 RTC 验收清单：`docs/FlutterWeb真机RTC验收清单.md`，覆盖语音、视频、权限拒绝、拒接、取消、刷新、断网、切后台和通过标准。
- 已新增 Flutter Web 原生能力人工验收启动器：`scripts/launch_flutter_web_native_manual_qa.mjs`。脚本会登录 `h5test`、创建/复用与 `h5peer` 的私聊，打开两个独立 Chrome 用户目录：聊天详情页用于文本、图片、拍照、视频、文件、语音、位置验收，扫码页用于摄像头扫码和相册二维码识别验收；不使用 fake media，也不自动授权麦克风、摄像头、定位或文件权限。
- 已新增原生能力真机验收清单：`docs/FlutterWeb原生能力真机验收清单.md`，覆盖聊天媒体能力、扫码能力、权限拒绝、移动 Safari、Android Chrome 和通过标准。
- 已新增 Flutter Web H5 自动化总回归套件：`scripts/smoke_flutter_web_h5_suite.mjs`。默认 `quick` profile 串行覆盖人工验收启动器 dry-run、二维码业务/图片解码、摄像头、语音、通话 API/WS；`location` / `video` 需要已有 Chrome 调试端口，`call-ui` 需要 5185 静态服务，因此作为显式可选用例。第 20 轮已把入口地址拆成 base/debug/callUi 三类，避免 full profile 同时跑 `5175` 调试页和 `5185` 静态 UI 页时互相覆盖。
- 已新增自动化回归套件说明：`docs/FlutterWeb自动化回归套件说明.md`，记录 profile、指定用例、可选 debug/UI 用例、环境变量和当前验证结果。
- 已新增 Flutter Web SPA 静态服务脚本：`scripts/serve_flutter_web_spa.mjs`，用于静态构建产物的深链/刷新测试；当前 Flutter Web 使用 hash 路由，UI 烟测默认以 `http://localhost:5185/#/chat/...` 打开聊天页。
- 已新增 Flutter Web release/PWA/部署前 readiness 脚本：`scripts/smoke_flutter_web_release_readiness.mjs`，检查构建产物、manifest、PWA 图标、service worker、SPA fallback、静态资源 404、API health/ping 和 client bootstrap 地址风险。
- 已新增剩余阶段一次性收尾验收文档：`docs/FlutterWeb剩余阶段一次性收尾验收.md`，记录 full profile 实跑、release 构建、readiness 检查、当前进度和最终人工项。
- Flutter Web 通话页已修正桌面判断：Web 即使运行在 macOS Chrome，也不再被 `Platform.isMacOS` 误判为桌面通话布局，小屏继续使用 H5/App 移动版通话页。
- Agora Web 引擎初始化已增加短重试，降低首次进入页面后立即发起通话时 `createIrisApiEngine` 尚未就绪导致的初始化失败。
- 视频/语音烟测脚本已改为每次新建专用 Chrome 目标页，避免复用现有标签页导致 `about:blank` 或页面跳转上下文销毁。
- 临时 Chrome 烟测脚本清理用户目录时已增加重试，避免浏览器刚退出时目录尚未释放造成假失败。
- Web 端发送位置已改为浏览器 Geolocation 权限流程，不再尝试打开系统定位设置。
- Web 端扫码页保留浏览器摄像头扫码和相册识别，隐藏闪光灯按钮，避免浏览器不可用能力显示成假入口。
- Android 通知设置入口仍限定在 Android；Web 端不显示 Android 系统设置入口。

Web 原生能力支持清单：

| 能力 | 当前 Web 状态 | 处理方式 |
| --- | --- | --- |
| 登录、聊天列表、聊天详情 | 已支持 | 复用 Flutter App 页面和 API |
| WebSocket 实时消息 | 已支持 | Web 不启动 Android 后台服务 |
| 图片选择/发送 | 已支持 | Web 使用 bytes 上传 |
| 拍照 | 已支持 | Web 相机拍照结果进入待发送图片队列 |
| 录像 | 暂隐藏 | Web 第一阶段不开放相机录像入口 |
| 视频选择/发送 | 已支持 | Web 使用 bytes 上传并发送 `type=3` |
| 视频播放 | 已支持 | 网络 URL 播放，已验 CORS、Range、MIME |
| 文件选择/发送 | 已支持 | Web 使用 bytes 上传 |
| 语音录制/发送 | 已支持 | Web 使用浏览器麦克风 + `audio/webm` bytes 上传 |
| 语音播放 | 已支持 | 浏览器 `<audio>` 实播 `audio/webm` 已验 |
| 保存到相册 | 暂隐藏 | Web 无系统相册能力，避免假按钮 |
| 扫码 | 已支持基础链路 | 摄像头 live 视频流、相册图片解码、二维码协议解析和扫码后业务链路已验；真机摄像头扫实物码待人工验收 |
| 位置 | 已适配 | Web 使用浏览器 Geolocation 权限，位置消息发送/回查已验 |
| 通知 | 已降级 | Android 系统通知设置仅 Android 显示，Web 后续接 PWA Notification |
| 语音/视频通话 | API/WS + 主叫/被叫 UI 按钮链路已验 | 浏览器音视频权限、Agora 配置、发起/接听/心跳/挂断/历史记录已验；被叫来电页接听/挂断、主叫聊天页语音/视频按钮发起、主叫通话页挂断均已通过浏览器 UI smoke，且四链路套件可一键回归；真机远端音视频质量待人工验收 |
| 生物识别 | 暂隐藏 | 后续如需要再评估 WebAuthn |

本次验证：

```bash
flutter test test/core/router/redirect_utils_test.dart
flutter analyze lib/core/router/redirect_utils.dart lib/core/router/app_router.dart lib/features/auth/pages/login_page.dart lib/features/auth/pages/register_page.dart lib/features/splash/pages/splash_page.dart lib/core/utils/platform_utils.dart lib/core/utils/floating_nav_layout.dart lib/core/services/api/endpoint_manager.dart lib/features/home/pages/home_page.dart lib/features/chat/pages/chat_page.dart lib/features/chat/widgets/create_sheets.dart lib/features/chat/widgets/message_context_menu.dart lib/shared/widgets/desktop/auth_desktop_layout.dart lib/shared/widgets/desktop/responsive_scaffold.dart lib/shared/widgets/desktop/desktop_layout.dart lib/features/moments/pages/moments_page.dart
flutter analyze lib/features/chat/widgets/message_bubble.dart lib/features/chat/providers/message_provider.dart lib/features/chat/pages/chat_detail_page.dart
flutter analyze lib/core/services/voice_record_service.dart lib/core/services/voice_record_service_record_web.dart lib/core/services/voice_record_blob_reader.dart lib/core/services/voice_record_blob_reader_web.dart lib/features/chat/providers/message_provider.dart lib/features/chat/pages/chat_detail_page.dart lib/features/chat/widgets/chat_input_bar.dart
flutter analyze lib/features/chat/pages/chat_detail_page.dart lib/features/chat/pages/qr_scanner_page.dart lib/core/services/voice_record_service.dart lib/core/services/voice_record_service_record_web.dart lib/core/services/voice_record_blob_reader.dart lib/core/services/voice_record_blob_reader_web.dart lib/features/chat/providers/message_provider.dart lib/features/chat/widgets/chat_input_bar.dart
flutter analyze lib/features/chat/pages/qr_scanner_page.dart lib/features/chat/services/qr_image_decoder.dart lib/features/chat/services/qr_image_decoder_web.dart
node --check scripts/smoke_flutter_web_video.mjs
node scripts/smoke_flutter_web_video.mjs
node --check scripts/smoke_flutter_web_voice.mjs
node scripts/smoke_flutter_web_voice.mjs
node --check scripts/smoke_flutter_web_location.mjs
node scripts/smoke_flutter_web_location.mjs
node --check scripts/smoke_flutter_web_camera.mjs
node scripts/smoke_flutter_web_camera.mjs
flutter test test/core/utils/qr_payload_test.dart
node --check scripts/smoke_flutter_web_qr_flow.mjs
node scripts/smoke_flutter_web_qr_flow.mjs
dart run scripts/generate_qr_svg.dart genericim://login/test-ticket
node --check scripts/smoke_flutter_web_qr_image.mjs
node scripts/smoke_flutter_web_qr_image.mjs
node --check scripts/smoke_flutter_web_call.mjs
node scripts/smoke_flutter_web_call.mjs
GENERIC_IM_SMOKE_CALL_TYPE=video node scripts/smoke_flutter_web_call.mjs
flutter analyze lib/core/services/call_service.dart lib/core/router/app_router.dart lib/features/chat/pages/chat_detail_header_actions.dart lib/features/call/pages/incoming_call_page.dart lib/features/call/pages/call_page.dart
node --check scripts/smoke_flutter_web_call_ui.mjs
node --check scripts/smoke_flutter_web_call_ui_suite.mjs
node --check scripts/smoke_flutter_web_h5_suite.mjs
node --check scripts/smoke_flutter_web_video.mjs
node --check scripts/smoke_flutter_web_qr_flow.mjs
node --check scripts/smoke_flutter_web_release_readiness.mjs
node --check scripts/launch_flutter_web_call_manual_qa.mjs
node --check scripts/launch_flutter_web_native_manual_qa.mjs
node --check scripts/serve_flutter_web_spa.mjs
flutter build web --debug --no-wasm-dry-run --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
node scripts/serve_flutter_web_spa.mjs
GENERIC_IM_WEB_URL=http://localhost:5185/ node scripts/smoke_flutter_web_call_ui.mjs
GENERIC_IM_WEB_URL=http://localhost:5185/ GENERIC_IM_SMOKE_CALL_TYPE=video node scripts/smoke_flutter_web_call_ui.mjs
GENERIC_IM_WEB_URL=http://localhost:5185/ GENERIC_IM_SMOKE_CALL_UI_MODE=outgoing GENERIC_IM_SMOKE_CALL_TYPE=voice node scripts/smoke_flutter_web_call_ui.mjs
GENERIC_IM_WEB_URL=http://localhost:5185/ GENERIC_IM_SMOKE_CALL_UI_MODE=outgoing GENERIC_IM_SMOKE_CALL_TYPE=video node scripts/smoke_flutter_web_call_ui.mjs
GENERIC_IM_WEB_URL=http://localhost:5185/ node scripts/smoke_flutter_web_call_ui_suite.mjs
GENERIC_IM_MANUAL_CALL_DRY_RUN=1 node scripts/launch_flutter_web_call_manual_qa.mjs
GENERIC_IM_MANUAL_NATIVE_DRY_RUN=1 node scripts/launch_flutter_web_native_manual_qa.mjs
GENERIC_IM_H5_SUITE_DRY_RUN=1 node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_DRY_RUN=1 GENERIC_IM_H5_SUITE_PROFILE=full GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_CASES=manual-native,manual-call node scripts/smoke_flutter_web_h5_suite.mjs
node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_PROFILE=debug node scripts/smoke_flutter_web_h5_suite.mjs
node scripts/smoke_flutter_web_video.mjs
node scripts/smoke_flutter_web_qr_flow.mjs
flutter build web --debug --no-wasm-dry-run --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
node scripts/serve_flutter_web_spa.mjs
GENERIC_IM_H5_SUITE_PROFILE=ui GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL=http://localhost:5185/ node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_PROFILE=full GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 GENERIC_IM_H5_SUITE_RETRIES=1 node scripts/smoke_flutter_web_h5_suite.mjs
flutter build web --release --no-wasm-dry-run -o build/web-release --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
GENERIC_IM_RELEASE_STATIC_DIR=build/web-release node scripts/smoke_flutter_web_release_readiness.mjs
curl -sS -o /dev/null -w 'web %{http_code}\n' http://localhost:5175/
```

注意：共用当前 Flutter Chrome 调试端口的 CDP 烟测脚本建议串行执行；并行执行可能出现临时 `fetch failed` 或执行上下文切换。

注意：`scripts/smoke_flutter_web_call_ui.mjs` 建议配合 `flutter build web --debug` 的静态产物运行。`flutter run -d chrome` 的 debug server 对另起独立 Chrome 进程加载完整 Flutter UI 不稳定；静态服务需使用 `localhost` 访问，`127.0.0.1:5185` 在当前后端 CORS 配置下会导致浏览器端 `/call/config` 不可用，从而接听时被判定 `media_disabled`。当前项目 Web 路由仍为 hash 模式，主叫侧 UI 烟测默认使用 `GENERIC_IM_WEB_ROUTE_MODE=hash`；如果后续切到 path URL strategy，再改为 `GENERIC_IM_WEB_ROUTE_MODE=path` 并确保线上/本地静态服务有 SPA fallback。

注意：做真机/真实浏览器 RTC 人工验收前，建议先运行 `GENERIC_IM_WEB_URL=http://localhost:5185/ node scripts/smoke_flutter_web_call_ui_suite.mjs`。该套件能先排除登录态、路由、按钮语义、来电页、通话页和历史状态这些基础回归问题，人工验收再专注确认真实麦克风、扬声器、摄像头、远端画面和弱网体验。

注意：`scripts/launch_flutter_web_call_manual_qa.mjs` 是人工验收启动器，不是自动化测试。正常运行会打开两个可见 Chrome 窗口并保持进程，验收完成按 `Ctrl+C` 关闭；验证脚本配置时用 `GENERIC_IM_MANUAL_CALL_DRY_RUN=1`，不会打开浏览器。

注意：`scripts/launch_flutter_web_native_manual_qa.mjs` 用于真实浏览器原生能力人工验收。正常运行会打开聊天详情页和扫码页两个可见 Chrome 窗口；验证脚本配置时用 `GENERIC_IM_MANUAL_NATIVE_DRY_RUN=1`，不会打开浏览器。

注意：`scripts/smoke_flutter_web_h5_suite.mjs` 是自动化总入口。默认 quick 不跑依赖现有 Chrome 调试端口的 `location` / `video`，也不跑依赖静态 5185 服务的 `call-ui`；单独跑这些能力可用 `GENERIC_IM_H5_SUITE_PROFILE=debug` 或 `GENERIC_IM_H5_SUITE_PROFILE=ui`，放进 `full` profile 时再用 `GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1` 或 `GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1` 显式打开。地址优先用 `GENERIC_IM_H5_SUITE_WEB_URL`、`GENERIC_IM_H5_SUITE_DEBUG_WEB_URL`、`GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL` 分别控制 base/debug/call-ui；`GENERIC_IM_WEB_URL` 只作为旧脚本兼容和 base 默认值，不建议在 full profile 里全局指到 5185。

接口验证结果：

- `POST /api/v1/auth/login` 使用 `h5test / 123456` 登录成功。
- `GET /api/v1/user/me` 返回当前用户 `h5test`。
- `GET /api/v1/chat/list` 返回成功，当前测试账号会话数为 `0`。
- `ws://localhost:8080/api/v1/ws?device_type=web&token=...` 握手成功，并收到 `pong`。
- 已创建/恢复 `h5test` 与 `h5peer` 的私聊会话。
- `POST /api/v1/message/send` 文本消息发送成功。
- `GET /api/v1/message/list` 可查到刚发送的文本消息。
- peer 用户 WebSocket 已收到 `new_message` 实时推送。
- `POST /api/v1/upload/image` 图片上传成功。
- `POST /api/v1/upload/file` 文件上传成功。
- 图片消息 `type=2` 发送成功，消息列表可查到。
- 文件消息 `type=5` 发送成功，消息列表可查到。
- `POST /api/v1/upload/video` 视频上传成功。
- 视频消息 `type=3` 发送成功，消息列表可查到。
- 使用 macOS 系统视频样本生成真实 MP4/M4V 测试文件并上传成功。
- 最新真实 MP4 视频消息已写入 `h5test` 与 `h5peer` 会话，`chat_id=710a5471-ab43-4728-9acf-7db3a65e2bea`。
- OSS 视频资源 `HEAD` 返回 `200`，`Content-Type: video/mp4`。
- OSS 视频资源 `Range: bytes=0-1023` 返回 `206 Partial Content`，`Accept-Ranges: bytes` 和 `Content-Range` 正常。
- OSS 视频资源 CORS 返回 `Access-Control-Allow-Origin: *`，浏览器跨域播放条件满足。
- Chrome DevTools Protocol 注入 `<video>` 实播验证通过，触发 `loadedmetadata`、`loadeddata`、`canplay`、`playing`，`currentTime` 正常前进。
- `POST /api/v1/upload/voice` 使用 `audio/webm` 上传成功。
- 语音消息 `type=4` 发送成功，消息列表可查到。
- OSS 语音资源 `HEAD` 返回 `200`，`Content-Type: audio/webm`，CORS 返回 `Access-Control-Allow-Origin: *`。
- Chrome DevTools Protocol + 临时 Chrome 假麦克风录音验证通过，录制 `audio/webm;codecs=opus`，最新样本约 1.8 秒、21322 bytes，发送后服务端返回 `seq=13`。
- Chrome DevTools Protocol 注入 `<audio>` 实播最新语音通过，触发 `loadedmetadata`、`loadeddata`、`canplay`、`playing`，`currentTime` 正常前进。
- Chrome DevTools Protocol 模拟浏览器 Geolocation 权限和坐标通过，读取到 `31.230416, 121.473701`，位置消息 `type=6` 发送成功，服务端返回 `seq=14`，消息列表可回查。
- 临时 Chrome 假摄像头打开 `/scan` 后，`getUserMedia({ video: true })` 返回 live 视频流，画面尺寸 `640x480`。
- 二维码 payload 单测通过：用户、群邀请、扫码登录三类 payload 均可构建/解析，非法 scheme/type/空 id 会被拒绝。
- 二维码业务烟测通过：
  - 用户二维码：`genericim://user/592a0893-4c3b-42e1-bcef-55b0ab393486` 可查询 `h5peer` 资料、添加联系人，并打开私聊 `710a5471-ab43-4728-9acf-7db3a65e2bea`。
  - 群二维码：创建测试群 `dc307591-04e8-4f6b-aa30-d53364476951`，通过 `genericim://group/da56a0a4` 加入成功。
  - 登录二维码：创建 ticket `45432fd8-0064-46ff-97e7-2f695d349a85`，扫描端确认后桌面端轮询得到 token，`/user/me` 校验为 `h5test`。
- 二维码图片解码烟测通过：生成 `genericim://user/592a0893-4c3b-42e1-bcef-55b0ab393486` 的真实 SVG 二维码，在 `/scan` 页面用 `BarcodeDetector` 解码成功，图片尺寸 `410x410`。
- 通话双端烟测通过：
  - `/api/v1/call/config` 返回 RTC 已启用，当前 provider 为 `agora`，Agora AppId 已配置。
  - 临时 Chrome 假麦克风/假摄像头验证通过，`navigator.mediaDevices.getUserMedia({ audio, video })` 可获得 live 音频和 `640x480` 视频轨道。
  - 语音通话：`h5test` 向 `h5peer` 发起成功，call_id=`1`；被叫收到 `incoming_call`，接听后主叫收到 `call_accepted`，双方 `/call/heartbeat` 均为 `connected`，挂断后被叫收到 `call_ended`，双方 `/call/history` 均为 `ended`。
  - 视频通话：`h5test` 向 `h5peer` 发起成功，call_id=`2`；被叫收到 `incoming_call`，接听后主叫收到 `call_accepted`，双方 `/call/heartbeat` 均为 `connected`，挂断后被叫收到 `call_ended`，双方 `/call/history` 均为 `ended`。
- 通话 UI 烟测通过：
  - 语音 UI：静态 Flutter Web 页面以 `h5peer` 登录态启动，收到 `h5test` 来电后 AX tree 匹配到 `语音来电... / 拒绝 / 接听`；脚本按语义按钮点击“接听”，主叫收到 `call_accepted`，随后在通话页匹配到 `静音 / 挂断` 并点击“挂断”，主叫收到 `call_ended`，call_id=`6`，双方历史为 `ended`。
  - 视频 UI：同样流程匹配到 `视频来电... / 拒绝 / 接听` 和 `静音 / 关闭视频 / 挂断`；主叫收到 `call_accepted` 与 `call_ended`，call_id=`7`，双方历史为 `ended`。
- 通话主叫侧 UI 烟测通过：
  - 语音 outgoing UI：静态 Flutter Web 页面以 `h5test` 登录态直接打开私聊 `710a5471-ab43-4728-9acf-7db3a65e2bea`，AX button 精确匹配 `语音通话`；点击后 `h5peer` 来电页匹配 `语音来电... / 拒绝 / 接听`，脚本点击接听，caller `/call/history` 进入 `connected`，主叫通话页匹配 `静音 / 扬声器 / 挂断` 并点击挂断，call_id=`18`，双方历史为 `ended`。
  - 视频 outgoing UI：同样流程精确匹配 `视频通话`，被叫来电页匹配 `视频来电... / 拒绝 / 接听`，caller `/call/history` 进入 `connected`，主叫视频通话页匹配 `静音 / 关闭视频 / 切换摄像头 / 挂断` 并点击挂断，call_id=`20`，双方历史为 `ended`。
- 通话被叫侧 UI 回归通过：
  - 语音 incoming UI：call_id=`21`，来电页接听、通话页挂断、主叫收到 `call_accepted` / `call_ended`，双方历史为 `ended`。
  - 视频 incoming UI：call_id=`23`，来电页接听、通话页挂断、主叫收到 `call_accepted` / `call_ended`，双方历史为 `ended`。
- 通话 UI 回归套件通过：
  - `scripts/smoke_flutter_web_call_ui_suite.mjs` 串行覆盖 incoming voice、incoming video、outgoing voice、outgoing video，最终 `ok=true`。
  - 本次通过的 call_id：incoming voice=`24`，incoming video=`26`，outgoing voice=`28`，outgoing video=`30`。
  - 连续测试中出现过临时 `busy/rejected`，套件默认 1 次重试后恢复通过，适合作为后续通话 UI 改动前后的固定回归命令。
- 真实浏览器 RTC 人工验收启动器 dry-run 通过：
  - `GENERIC_IM_MANUAL_CALL_DRY_RUN=1 node scripts/launch_flutter_web_call_manual_qa.mjs` 登录 `h5test` / `h5peer` 成功。
  - `/api/v1/call/config` 返回 RTC enabled，provider=`agora`。
  - 生成主叫深链 `http://localhost:5175/#/chat/710a5471-ab43-4728-9acf-7db3a65e2bea?name=H5%20Peer&type=private`，被叫地址 `http://localhost:5175/`。
  - dry-run 未打开浏览器；真实人工验收时直接运行 `node scripts/launch_flutter_web_call_manual_qa.mjs`。
- 原生能力人工验收启动器 dry-run 通过：
  - `GENERIC_IM_MANUAL_NATIVE_DRY_RUN=1 node scripts/launch_flutter_web_native_manual_qa.mjs` 登录 `h5test` / `h5peer` 成功。
  - 创建/复用私聊 `710a5471-ab43-4728-9acf-7db3a65e2bea`。
  - 生成聊天页深链 `http://localhost:5175/#/chat/710a5471-ab43-4728-9acf-7db3a65e2bea?name=H5%20Peer&type=private`，扫码页深链 `http://localhost:5175/#/scan`。
  - dry-run 未打开浏览器；真实人工验收时直接运行 `node scripts/launch_flutter_web_native_manual_qa.mjs`。
- Flutter Web H5 自动化总回归套件验证通过：
  - `GENERIC_IM_H5_SUITE_DRY_RUN=1 node scripts/smoke_flutter_web_h5_suite.mjs` 输出 quick 默认计划，包含 `manual-native`、`manual-call`、`qr-flow`、`qr-image`、`camera`、`voice`、`call-api-voice`、`call-api-video`。
  - `GENERIC_IM_H5_SUITE_CASES=manual-native,manual-call node scripts/smoke_flutter_web_h5_suite.mjs` 实际调用两个子脚本成功，最终 `ok=true`。
  - 总套件会给子脚本传入固定私聊 `710a5471-ab43-4728-9acf-7db3a65e2bea`，并汇总 stdout JSON、stderr tail、exitCode 和压缩 summary。
- Flutter Web H5 quick 总回归全量通过：
  - `node scripts/smoke_flutter_web_h5_suite.mjs` 执行 8 个默认 case，最终 `ok=true`。
  - `manual-native`、`manual-call`、`qr-flow`、`qr-image`、`camera`、`voice`、`call-api-voice`、`call-api-video` 均通过。
  - 语音录制生成 `audio/webm;codecs=opus`，约 1.8 秒，上传、发送、播放通过。
  - 摄像头 smoke 获得 `640x480` live fake video track。
  - 通话 API/WS 语音 call_id=`31`、视频 call_id=`32`，双方历史均为 `ended`。
- Flutter Web H5 debug profile 回归通过：
  - `GENERIC_IM_H5_SUITE_PROFILE=debug node scripts/smoke_flutter_web_h5_suite.mjs` 执行 `location` 和 `video` 两个用例，最终 `ok=true`。
  - 定位 smoke 通过，浏览器坐标 override 为 `31.230416, 121.473701`，位置消息 `type=6` 发送并回查成功，seq=`49`。
  - 视频 smoke 通过，OSS 视频资源 `HEAD=200`、`Range=206`、`Content-Type=video/mp4`、CORS `Access-Control-Allow-Origin=*`，Chrome 实播播放时间正常前进。
  - 已清理之前遗留的 `genericim-call-ui-smoke` 旧 headless Chrome 临时进程，当前只保留 Flutter 5175 调试 Chrome。
- Flutter Web H5 ui profile 回归通过：
  - 重新执行 `flutter build web --debug --no-wasm-dry-run` 成功，并用 `scripts/serve_flutter_web_spa.mjs` 临时启动 `http://localhost:5185/`。
  - `GENERIC_IM_H5_SUITE_PROFILE=ui GENERIC_IM_WEB_URL=http://localhost:5185/ node scripts/smoke_flutter_web_h5_suite.mjs` 最终 `ok=true`；第 20 轮后推荐改用 `GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL=http://localhost:5185/`。
  - 四路通话 UI 均一次通过：incoming voice call_id=`33`，incoming video call_id=`34`，outgoing voice call_id=`35`，outgoing video call_id=`36`。
  - 主叫/被叫来电页、聊天页语音/视频按钮、接听、通话页挂断、`calling -> connected -> ended` 状态和双方历史 `ended` 均已验证。
  - 临时 5185 静态服务已关闭。
- Flutter Web H5 full profile 地址隔离已完成：
  - `scripts/smoke_flutter_web_h5_suite.mjs` 现在会按用例类型设置子进程 `GENERIC_IM_WEB_URL`，quick/base 用例默认 `http://localhost:5175/`，debug 用例默认跟随 base，`call-ui` 默认 `http://localhost:5185/`。
  - `GENERIC_IM_H5_SUITE_DRY_RUN=1 GENERIC_IM_H5_SUITE_PROFILE=full GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 node scripts/smoke_flutter_web_h5_suite.mjs` 已通过，输出 11 个计划用例：quick 8 个，加 `location`、`video`、`call-ui`。
  - dry-run 输出包含 `webUrls.base`、`webUrls.debug`、`webUrls.callUi` 和每个 case 的 `webUrl`，后续排查环境地址会更直观。
- Flutter Web H5 full profile 实跑通过：
  - 启动 `http://localhost:5185/` 静态服务后，`GENERIC_IM_H5_SUITE_PROFILE=full GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 GENERIC_IM_H5_SUITE_RETRIES=1 node scripts/smoke_flutter_web_h5_suite.mjs` 最终 `ok=true`。
  - 11 个用例全部通过：`manual-native`、`manual-call`、`qr-flow`、`qr-image`、`camera`、`voice`、`call-api-voice`、`call-api-video`、`location`、`video`、`call-ui`。
  - `scripts/smoke_flutter_web_video.mjs` 已增加自生成视频样本兜底：找不到历史视频消息时，会用 Chrome canvas + `MediaRecorder` 生成 `video/webm`，上传 `/upload/video`、发送 `type=3`，再验证 CORS、Range 和 Chrome 播放。本轮单跑生成约 26KB、`160x90` 样本，发送 seq=`70`。
  - `scripts/smoke_flutter_web_qr_flow.mjs` 已增加测试群复用兜底：当 `h5peer` 创建群达到上限时，复用已有 `QR Smoke` 群的 `invite_link` 继续验证群二维码。本轮 full 复用 `genericim://group/16b809d2`，`alreadyJoined=true`。
  - full 本轮语音录制 `audio/webm;codecs=opus`，位置消息 seq=`82`，视频资源 `Content-Type=video/webm`、`Range=206`、Chrome 播放 `160x90`。
  - full 本轮通话 API/WS 语音 call_id=`55`、视频 call_id=`56`；通话 UI 四链路 incoming voice=`57`、incoming video=`58`、outgoing voice=`60`、outgoing video=`61`，均已进入 `ended`。
  - 临时 5185 静态服务已关闭，`http://localhost:5175/` 仍返回 `200`。
- Flutter Web release/PWA/readiness 收尾通过：
  - `flutter build web --release --no-wasm-dry-run -o build/web-release --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws` 构建通过，release 产物目录为 `build/web-release`，`main.dart.js` 约 `8666286` bytes。
  - `GENERIC_IM_RELEASE_STATIC_DIR=build/web-release node scripts/smoke_flutter_web_release_readiness.mjs` 最终 `ok=true`。
  - readiness 已验证构建必需文件、manifest、192/512/maskable 图标、service worker、`/`、`/manifest.json`、`/flutter_bootstrap.js`、`/flutter_service_worker.js`、SPA 深链 fallback、缺失静态资源 404、后端 `/health`、`/api/v1/ping`。
  - 当前 warning：`/api/v1/client/bootstrap` 仍包含 Android 模拟器地址 `10.0.2.2`。Flutter Web 本地已有保护，线上发布前后端应返回浏览器可访问的 HTTPS/WSS 域名。
- Flutter Web debug build 通过，重启后的 `http://localhost:5175/` 和 `http://localhost:5175/scan` 均返回 `200`。
- 重启 Flutter Web 后，`http://localhost:5175/` 返回 `200`，`/tmp/genericim-flutter-web.log` 未发现 `FlutterError`、`RenderFlex`、`Unhandled exception`。

当前本地访问地址：

| 服务 | 地址 |
| --- | --- |
| 后端 API | `http://localhost:8080/api/v1` |
| Flutter Web 完整 H5 | `http://localhost:5175/` |

当前 Flutter Web 启动命令：

```bash
flutter run -d chrome --web-port 5175 --web-hostname 0.0.0.0 \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

下一步建议：

- 当前 H5 完整同款开发进度建议从 75% 更新为 82%；自动化 full profile、release 构建和 PWA/静态部署前 readiness 已打通，下一阶段只剩真机、真实权限、真实 RTC 质量和线上域名/HTTPS/WSS 配置验收。
- 继续做真机/真实浏览器 UI 验收：手动点 `/scan` 相册识别，选择真实二维码图片，确认能进入加好友/进群/扫码登录流程。
- 继续做真机摄像头扫实物二维码验收，确认 `MobileScanner` 视频帧识别在手机浏览器里稳定。
- 继续做真实浏览器 UI 权限验收：手动允许麦克风/定位/摄像头权限，确认录音、位置、扫码在真实权限弹窗下可用。
- 继续做真机双设备 RTC 质量验收：确认 Agora 实际远端音视频画面、音频输入输出、前后台切换、权限弹窗和弱网恢复体验。
- 继续做通话真实浏览器人工验收：主叫/被叫都使用真实 Chrome/Safari 权限弹窗，不使用 fake media，确认语音输入输出、视频预览、远端画面和挂断状态一致。
- 继续从真实浏览器 UI 验收：进入 `h5test` 与 `h5peer` 会话，验证输入框、发送、图片选择/拍照、视频选择、语音录制、文件选择、消息列表滚动、长按菜单。

## 18. 建议时间安排

按当前项目基础预估：

| 阶段 | 内容 | 预计时间 |
| --- | --- | --- |
| 阶段 1 | Flutter Web 可启动 | 0.5-2 天 |
| 阶段 2 | 登录和接口地址 | 1-2 天 |
| 阶段 3 | 首页和底部导航 | 1-2 天 |
| 阶段 4 | 聊天列表和 WebSocket | 2-4 天 |
| 阶段 5 | 聊天详情文本消息 | 2-4 天 |
| 阶段 6 | 用户资料和好友链路 | 2-4 天 |
| 阶段 7 | 图片、文件、表情 | 3-6 天 |
| 阶段 8 | 联系人、群资料、设置 | 4-8 天 |
| 阶段 9 | Web 降级和兼容 | 3-7 天 |
| 阶段 10 | PWA 和部署 | 2-5 天 |

建议节奏：

- 第 1 周：完成阶段 1-4，确认路线可行。
- 第 2 周：完成阶段 5-6，形成 MVP 内测版。
- 第 3-5 周：完成阶段 7-10，逐步接近 App 完整体验。

如果目标是最快上线，先做到阶段 6 即可内测；如果目标是接近完整 App，再继续阶段 7-10。
