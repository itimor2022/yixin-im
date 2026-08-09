# Flutter Web 真机 RTC 验收清单

记录时间：2026-06-23 18:21 CST。

## 1. 验收目标

确认 Flutter Web 完整 H5 在真实浏览器权限和真实音视频设备下，语音/视频通话不只是 API 与按钮链路可用，而是具备真实麦克风输入、扬声器输出、摄像头预览、远端画面、状态同步和挂断收口能力。

自动化 smoke 已经覆盖登录态、路由、来电页、通话页、发起、接听、挂断和历史状态。人工验收只聚焦真实设备体验。

## 2. 验收前置条件

- 后端 API 正常：`http://localhost:8080/api/v1`
- Flutter Web 正常：`http://localhost:5175/`
- 测试账号：
  - 主叫：`h5test / 123456`
  - 被叫：`h5peer / 123456`
- 当前私聊会话：`710a5471-ab43-4728-9acf-7db3a65e2bea`
- RTC 配置启用，当前 provider 为 `agora`

先运行自动化通话 UI 套件：

```bash
flutter build web --debug --no-wasm-dry-run \
  --dart-define=GENERIC_IM_SERVER_URL=http://localhost:8080 \
  --dart-define=GENERIC_IM_WS_URL=ws://localhost:8080/api/v1/ws

node scripts/serve_flutter_web_spa.mjs

GENERIC_IM_WEB_URL=http://localhost:5185/ \
  node scripts/smoke_flutter_web_call_ui_suite.mjs
```

自动化套件通过后，再进入人工验收。

## 3. 双窗口启动器

已新增真实浏览器人工验收启动器：

```bash
node scripts/launch_flutter_web_call_manual_qa.mjs
```

脚本会：

- 登录 `h5test` 和 `h5peer`
- 清理双方未结束的 `calling` / `connected` 通话
- 创建或复用双方私聊
- 打开两个独立 Chrome 用户目录
- 主叫窗口直接进入私聊页
- 被叫窗口进入 Flutter Web 首页并等待来电
- 不使用 fake media
- 不自动授权麦克风或摄像头权限

只检查启动参数和接口，不打开浏览器：

```bash
GENERIC_IM_MANUAL_CALL_DRY_RUN=1 node scripts/launch_flutter_web_call_manual_qa.mjs
```

如果用静态构建产物验收：

```bash
GENERIC_IM_WEB_URL=http://localhost:5185/ node scripts/launch_flutter_web_call_manual_qa.mjs
```

运行脚本后保持终端不关闭；验收完成按 `Ctrl+C`，脚本会关闭它启动的 Chrome 并清理临时用户目录。

## 4. 语音通话验收

| 编号 | 操作 | 期望结果 |
| --- | --- | --- |
| CALL-VOICE-001 | 主叫窗口点击语音通话 | 浏览器弹出麦克风权限，允许后进入呼叫中 |
| CALL-VOICE-002 | 被叫窗口收到来电并点击接听 | 双方进入语音通话页 |
| CALL-VOICE-003 | 主叫说话，被叫听声音 | 被叫能听到主叫声音，无明显断续 |
| CALL-VOICE-004 | 被叫说话，主叫听声音 | 主叫能听到被叫声音，无明显断续 |
| CALL-VOICE-005 | 点击静音/取消静音 | UI 状态切换正确，对端声音符合预期 |
| CALL-VOICE-006 | 点击扬声器按钮 | UI 不闪退；桌面浏览器如无系统输出切换能力，应保持可用 |
| CALL-VOICE-007 | 任一方挂断 | 双方退出通话页，聊天/通话历史状态为 ended |

## 5. 视频通话验收

| 编号 | 操作 | 期望结果 |
| --- | --- | --- |
| CALL-VIDEO-001 | 主叫窗口点击视频通话 | 浏览器弹出麦克风/摄像头权限，允许后进入呼叫中 |
| CALL-VIDEO-002 | 被叫窗口收到来电并点击接听 | 双方进入视频通话页 |
| CALL-VIDEO-003 | 查看本地预览 | 本端摄像头画面正常，不黑屏、不拉伸异常 |
| CALL-VIDEO-004 | 查看远端画面 | 对端画面正常显示，方向和比例可接受 |
| CALL-VIDEO-005 | 关闭/开启视频 | 本端 UI 状态切换正确，对端能看到画面关闭/恢复 |
| CALL-VIDEO-006 | 静音/取消静音 | 音频状态正确同步 |
| CALL-VIDEO-007 | 切换摄像头 | 多摄像头设备能切换；单摄像头设备不闪退且有兜底 |
| CALL-VIDEO-008 | 任一方挂断 | 双方退出通话页，聊天/通话历史状态为 ended |

## 6. 异常与权限验收

| 编号 | 场景 | 期望结果 |
| --- | --- | --- |
| CALL-PERM-001 | 首次语音通话拒绝麦克风权限 | 页面提示明确，不能卡死在呼叫中 |
| CALL-PERM-002 | 首次视频通话拒绝摄像头权限 | 页面提示明确，不能卡死在呼叫中 |
| CALL-PERM-003 | 被叫拒接 | 主叫状态收口，双方历史为 rejected |
| CALL-PERM-004 | 主叫呼叫中取消 | 被叫来电页消失，双方历史为 ended/cancelled |
| CALL-PERM-005 | 通话中刷新一端页面 | 另一端不应永久卡住，刷新端可恢复或明确结束 |
| CALL-PERM-006 | 通话中临时断网再恢复 | UI 有重连或结束反馈，不出现无限 loading |
| CALL-PERM-007 | 移动浏览器切后台再回来 | 音视频状态可恢复或明确结束，页面不白屏 |

## 7. 通过标准

- 语音和视频各至少完整通过 1 次主叫发起、被叫接听、双方通话、任一方挂断。
- 双方历史记录最终为 `ended`，不遗留 `calling` 或 `connected`。
- 浏览器权限拒绝、被叫拒接、主叫取消都能明确收口。
- 真机移动浏览器至少验证 Chrome 或 Safari 其中一种；正式上线前建议 Android Chrome 和 iOS Safari 都验。

## 8. 记录模板

```text
验收时间：
浏览器/设备：
网络环境：
主叫账号：
被叫账号：
语音通话结果：
视频通话结果：
权限拒绝结果：
弱网/刷新/切后台结果：
发现问题：
是否通过：
```
