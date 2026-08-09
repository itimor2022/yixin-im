# Flutter Web 剩余阶段一次性收尾验收

记录时间：2026-06-23 CST。

## 1. 本轮目标

把剩余可自动化完成的 H5/PWA/部署前检查一次性收束：

- full profile 自动化回归实际跑通。
- 视频和二维码前置数据改成可自愈，避免长期测试环境数据累积后失败。
- release 构建独立输出，不覆盖 UI 回归用的 `build/web`。
- PWA manifest、图标、service worker、SPA fallback、静态部署和 API 健康检查形成一键脚本。

## 2. 新增脚本

```bash
scripts/smoke_flutter_web_release_readiness.mjs
```

用途：

- 检查 `build/web` 或指定静态目录的必要构建产物。
- 校验 `manifest.json`、PWA 图标、`index.html`、`flutter_service_worker.js`。
- 临时启动静态服务，验证 `/`、`/manifest.json`、`/flutter_bootstrap.js`、SPA 深链 fallback、缺失静态资源 404。
- 检查后端 `/health`、`/api/v1/ping`、`/api/v1/client/bootstrap`。

默认检查：

```bash
node scripts/smoke_flutter_web_release_readiness.mjs
```

指定 release 产物：

```bash
GENERIC_IM_RELEASE_STATIC_DIR=build/web-release \
  node scripts/smoke_flutter_web_release_readiness.mjs
```

## 3. 本轮修复

### 3.1 视频 smoke 自愈

`scripts/smoke_flutter_web_video.mjs` 已增强：

- 先扩大消息搜索范围，查找历史视频消息。
- 如果没有视频消息，使用 Chrome canvas + `MediaRecorder` 生成 `video/webm` 样本。
- 自动上传 `/api/v1/upload/video`。
- 自动发送 `type=3` 视频消息。
- 再继续验证 `HEAD`、`Range`、CORS 和 Chrome 播放。

单跑结果：

- 生成 `video/webm;codecs=vp8`。
- 大小约 `26037` bytes。
- 分辨率 `160x90`。
- 发送消息 seq=`70`。
- OSS/静态资源返回 `Content-Type=video/webm`、`Range=206`。
- Chrome 播放成功。

### 3.2 二维码群链路自愈

`scripts/smoke_flutter_web_qr_flow.mjs` 已增强：

- 正常情况下继续创建新的 `QR Smoke` 群。
- 如果返回 `创建群组数量已达上限`，自动从 `h5peer` 已有群列表中复用 `QR Smoke` 群。
- 通过 `/chat/{id}` 获取 `invite_link`。
- 继续验证 `genericim://group/{invite_link}` 入群链路。

本轮复用结果：

- 群二维码：`genericim://group/16b809d2`
- 群 ID：`69bc503e-4965-4720-b372-4d554099380b`
- `alreadyJoined=true`
- `requiresApproval=false`

## 4. full profile 实跑结果

命令：

```bash
GENERIC_IM_H5_SUITE_PROFILE=full \
GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 \
GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 \
GENERIC_IM_H5_SUITE_RETRIES=1 \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

结果：

- 总结果：`ok=true`
- 入口地址：base/debug=`http://localhost:5175/`，callUi=`http://localhost:5185/`
- 通过用例：`manual-native`、`manual-call`、`qr-flow`、`qr-image`、`camera`、`voice`、`call-api-voice`、`call-api-video`、`location`、`video`、`call-ui`
- 语音录制：`audio/webm;codecs=opus`
- 位置消息：seq=`82`
- 通话 API/WS：语音 call_id=`55`，视频 call_id=`56`
- 通话 UI：incoming voice=`57`，incoming video=`58`，outgoing voice=`60`，outgoing video=`61`

## 5. release 构建与部署检查

release 构建命令：

```bash
flutter build web --release --no-wasm-dry-run \
  -o build/web-release \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws
```

结果：

- 构建通过。
- release 产物目录：`build/web-release`
- `main.dart.js` 大小约 `8666286` bytes。

release readiness 命令：

```bash
GENERIC_IM_RELEASE_STATIC_DIR=build/web-release \
  node scripts/smoke_flutter_web_release_readiness.mjs
```

结果：

- 总结果：`ok=true`
- manifest：`通用IM`，`display=standalone`
- 图标：192、512、maskable 192、maskable 512 均存在
- service worker 存在
- `/` 返回 `200`
- `/manifest.json` 返回 `200`
- `/flutter_bootstrap.js` 返回 `200`
- `/flutter_service_worker.js` 返回 `200`
- 深链 fallback 返回 `200 text/html`
- 缺失静态资源返回 `404`
- 后端 `/health` 和 `/api/v1/ping` 返回 `200`

当前 warning：

- `/api/v1/client/bootstrap` 仍包含 Android 模拟器地址 `10.0.2.2`。
- Flutter Web 端已有本地保护，会在 Web 环境替换为启动参数地址。
- 线上发布前后端应返回浏览器可访问的 HTTPS/WSS 域名。

## 6. 当前进度判断

按“完整 H5/PWA 自动化与部署前准备”标准：

- 自动化可覆盖部分：已完成。
- release 构建与静态部署检查：已完成。
- H5 当前建议进度：`82%`。

不能自动代替的剩余项：

- iPhone Safari 真机权限弹窗验收。
- Android Chrome 真机权限弹窗验收。
- 真实摄像头扫实物二维码。
- 真实麦克风录音质量。
- Agora 真实远端音视频质量。
- 弱网、切后台、锁屏恢复。
- 线上 HTTPS/WSS 域名、CDN、Nginx 缓存策略。

## 7. 最终上线前命令

自动化全量：

```bash
node --check scripts/smoke_flutter_web_h5_suite.mjs
node --check scripts/smoke_flutter_web_video.mjs
node --check scripts/smoke_flutter_web_qr_flow.mjs
node --check scripts/smoke_flutter_web_release_readiness.mjs

GENERIC_IM_H5_SUITE_PROFILE=full \
GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 \
GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 \
GENERIC_IM_H5_SUITE_RETRIES=1 \
  node scripts/smoke_flutter_web_h5_suite.mjs

flutter build web --release --no-wasm-dry-run \
  -o build/web-release \
  --dart-define=GENERIC_IM_SERVER_URL=https://api.example.com \
  --dart-define=GENERIC_IM_WS_URL=wss://api.example.com/api/v1/ws

GENERIC_IM_RELEASE_STATIC_DIR=build/web-release \
  GENERIC_IM_SERVER_URL=https://api.example.com \
  node scripts/smoke_flutter_web_release_readiness.mjs
```

人工验收启动器：

```bash
node scripts/launch_flutter_web_native_manual_qa.mjs
node scripts/launch_flutter_web_call_manual_qa.mjs
```
