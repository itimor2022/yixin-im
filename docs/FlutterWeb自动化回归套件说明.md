# Flutter Web 自动化回归套件说明

记录时间：2026-06-23 18:42 CST；第 21 轮补充 full profile 实跑结果。

## 1. 目标

把已有零散 Flutter Web smoke 脚本收成一个总入口，方便后续 AI 或人工在改动 H5 前后快速回归核心能力。

总入口：

```bash
node scripts/smoke_flutter_web_h5_suite.mjs
```

默认 profile 为 `quick`，只选择相对自包含的用例；需要已有 Chrome 调试端口或静态 5185 服务的用例默认不跑，避免环境不满足时误报。

发布/PWA/静态部署前检查使用独立入口：

```bash
GENERIC_IM_RELEASE_STATIC_DIR=build/web-release \
  node scripts/smoke_flutter_web_release_readiness.mjs
```

说明文档见：`docs/FlutterWeb剩余阶段一次性收尾验收.md`。

## 2. 默认 quick 用例

| 用例 | 覆盖内容 |
| --- | --- |
| `manual-native` | 原生能力人工验收启动器 dry-run |
| `manual-call` | RTC 人工验收启动器 dry-run |
| `qr-flow` | 用户/群/登录二维码 API 业务链路 |
| `qr-image` | `/scan` 页面二维码图片解码 |
| `camera` | `/scan` 页面浏览器摄像头流，使用 fake media |
| `voice` | 浏览器录音、上传、发送、播放 |
| `call-api-voice` | 语音通话 API/WS 链路 |
| `call-api-video` | 视频通话 API/WS 链路 |

查看将要执行的用例，不真正运行：

```bash
GENERIC_IM_H5_SUITE_DRY_RUN=1 node scripts/smoke_flutter_web_h5_suite.mjs
```

## 3. 选择指定用例

只跑指定用例：

```bash
GENERIC_IM_H5_SUITE_CASES=manual-native,manual-call \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

常用子集：

```bash
GENERIC_IM_H5_SUITE_CASES=qr-flow,qr-image,camera \
  node scripts/smoke_flutter_web_h5_suite.mjs

GENERIC_IM_H5_SUITE_CASES=voice,call-api-voice,call-api-video \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

## 4. 可选扩展用例

`location` 和 `video` 依赖已有 Flutter Chrome 调试端口，通常需要先用 `flutter run -d chrome` 启动，或显式设置 `GENERIC_IM_CHROME_DEBUG_PORT`。

```bash
GENERIC_IM_H5_SUITE_PROFILE=debug node scripts/smoke_flutter_web_h5_suite.mjs
```

如果要在 `full` profile 里同时包含 debug 用例，需要显式打开：

```bash
GENERIC_IM_H5_SUITE_PROFILE=full \
GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

`call-ui` 依赖 `flutter build web --debug` 静态产物和 `http://localhost:5185/` 静态服务。总套件会给 `call-ui` 单独传 `GENERIC_IM_WEB_URL`，因此 full profile 可以同时保留 `5175` 调试页和 `5185` 静态 UI 页：

```bash
flutter build web --debug --no-wasm-dry-run \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws

node scripts/serve_flutter_web_spa.mjs

GENERIC_IM_H5_SUITE_PROFILE=full \
GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 \
GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL=http://localhost:5185/ \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

只跑 UI profile 时：

```bash
GENERIC_IM_H5_SUITE_PROFILE=ui \
GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL=http://localhost:5185/ \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

需要先确认 full profile 计划，不真正运行：

```bash
GENERIC_IM_H5_SUITE_DRY_RUN=1 \
GENERIC_IM_H5_SUITE_PROFILE=full \
GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 \
GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 \
  node scripts/smoke_flutter_web_h5_suite.mjs
```

## 5. 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `GENERIC_IM_H5_SUITE_PROFILE` | `quick` | `quick` / `debug` / `ui` / `full` |
| `GENERIC_IM_H5_SUITE_CASES` | 空 | 逗号分隔用例名；设置后忽略 profile |
| `GENERIC_IM_H5_SUITE_DRY_RUN` | 空 | `1` 时只打印计划 |
| `GENERIC_IM_H5_SUITE_RETRIES` | `0` | 每个子用例失败后的重试次数 |
| `GENERIC_IM_H5_SUITE_SETTLE_MS` | `1500` | 子用例之间的等待时间 |
| `GENERIC_IM_H5_SUITE_TIMEOUT_MS` | `240000` | 默认单用例超时 |
| `GENERIC_IM_H5_SUITE_CHAT_ID` | 主测试私聊 | 传给子脚本的 `GENERIC_IM_SMOKE_CHAT_ID` |
| `GENERIC_IM_H5_SUITE_WEB_URL` | `GENERIC_IM_WEB_URL` 或 `http://localhost:5175/` | quick/base 用例入口地址 |
| `GENERIC_IM_H5_SUITE_DEBUG_WEB_URL` | `GENERIC_IM_H5_SUITE_WEB_URL` | `location` / `video` 调试用例入口地址 |
| `GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL` | `http://localhost:5185/` | `call-ui` 静态 Flutter Web 入口地址 |
| `GENERIC_IM_WEB_URL` | 空 | 兼容旧脚本；未设置 `GENERIC_IM_H5_SUITE_WEB_URL` 时作为 base 地址 |
| `GENERIC_IM_H5_SUITE_INCLUDE_DEBUG` | 空 | 允许选择 `location` / `video` |
| `GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI` | 空 | 允许选择 `call-ui` |

## 6. 当前验证

已通过：

```bash
node --check scripts/smoke_flutter_web_h5_suite.mjs
node --check scripts/smoke_flutter_web_video.mjs
node --check scripts/smoke_flutter_web_qr_flow.mjs
GENERIC_IM_H5_SUITE_DRY_RUN=1 node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_DRY_RUN=1 GENERIC_IM_H5_SUITE_PROFILE=full GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 node scripts/smoke_flutter_web_h5_suite.mjs
node scripts/smoke_flutter_web_video.mjs
node scripts/smoke_flutter_web_qr_flow.mjs
GENERIC_IM_H5_SUITE_CASES=manual-native,manual-call node scripts/smoke_flutter_web_h5_suite.mjs
node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_PROFILE=debug node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_PROFILE=ui GENERIC_IM_H5_SUITE_CALL_UI_WEB_URL=http://localhost:5185/ node scripts/smoke_flutter_web_h5_suite.mjs
GENERIC_IM_H5_SUITE_PROFILE=full GENERIC_IM_H5_SUITE_INCLUDE_DEBUG=1 GENERIC_IM_H5_SUITE_INCLUDE_CALL_UI=1 GENERIC_IM_H5_SUITE_RETRIES=1 node scripts/smoke_flutter_web_h5_suite.mjs
```

轻量子集结果：`manual-native` 和 `manual-call` 均 `ok=true`，可正常调用子脚本并汇总 JSON。

第 20 轮 full dry-run 结果：

- 输出 `webUrls.base=http://localhost:5175/`、`webUrls.debug=http://localhost:5175/`、`webUrls.callUi=http://localhost:5185/`。
- 计划包含 11 个用例：quick 8 个，加 `location`、`video`、`call-ui`。
- 每个 case 的 `webUrl` 已按用例类型拆分，避免全局 `GENERIC_IM_WEB_URL=5185` 影响 debug/CDP 用例。

第 21 轮 full profile 实跑结果：

- 实际启动 `http://localhost:5185/` 静态服务后，full profile 11 个用例全部通过，最终 `ok=true`。
- `qr-flow` 已增强：如果 `h5peer` 创建群达到上限，会复用已有 `QR Smoke` 群详情中的 `invite_link`，继续验证群二维码入群链路。本轮复用 `genericim://group/16b809d2`，`alreadyJoined=true`。
- `video` 已增强：如果最近消息里没有视频，会用 Chrome canvas + `MediaRecorder` 自生成 `video/webm` 样本，上传 `/upload/video`、发送 `type=3` 后再验证 CORS、Range 和浏览器播放。单测本轮生成约 26KB、`160x90`、`video/webm;codecs=vp8` 样本，发送 seq=`70`。
- full 本轮媒体结果：语音录制 `audio/webm;codecs=opus`，位置消息 seq=`82`，视频资源 `Content-Type=video/webm`、`Range=206`、Chrome 播放 `160x90`。
- full 本轮通话结果：API/WS 语音 call_id=`55`，视频 call_id=`56`；UI 四链路 incoming voice=`57`、incoming video=`58`、outgoing voice=`60`、outgoing video=`61`，均进入 `ended`。
- 临时 5185 静态服务已关闭，`http://localhost:5175/` 仍返回 `200`。

quick 全量结果：

- `manual-native`：通过，生成聊天页 `#/chat/710a5471-ab43-4728-9acf-7db3a65e2bea` 和扫码页 `#/scan`。
- `manual-call`：通过，RTC enabled，provider=`agora`。
- `qr-flow`：通过，用户二维码、群二维码、登录二维码链路均成功。
- `qr-image`：通过，`/scan` 页面 `BarcodeDetector` 解码用户二维码成功。
- `camera`：通过，假摄像头流为 `640x480`，track 状态 `live`。
- `voice`：通过，录制 `audio/webm;codecs=opus`，约 1.8 秒，上传、发送和播放成功。
- `call-api-voice`：通过，call_id=`31`，双方历史为 `ended`。
- `call-api-video`：通过，call_id=`32`，双方历史为 `ended`。

debug profile 结果：

- `location`：通过，浏览器 Geolocation override 为 `31.230416, 121.473701`，位置消息 `type=6` 发送并回查成功，seq=`49`。
- `video`：通过，视频资源 `HEAD=200`，`Range=206`，`Content-Type=video/mp4`，`Access-Control-Allow-Origin=*`；Chrome 实播触发 `loadedmetadata`、`loadeddata`、`canplay`、`playing`，播放时间正常前进。

ui profile 结果：

- `call-ui`：通过，静态 Flutter Web 服务为 `http://localhost:5185/`。
- incoming voice：call_id=`33`，来电页接听、通话页挂断、双方历史 `ended`。
- incoming video：call_id=`34`，来电页接听、通话页挂断、双方历史 `ended`。
- outgoing voice：call_id=`35`，聊天页点击 `语音通话`、被叫接听、主叫通话页挂断、双方历史 `ended`。
- outgoing video：call_id=`36`，聊天页点击 `视频通话`、被叫接听、主叫通话页挂断、双方历史 `ended`。
