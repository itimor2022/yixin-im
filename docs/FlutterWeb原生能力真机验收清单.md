# Flutter Web 原生能力真机验收清单

记录时间：2026-06-23 18:25 CST。

## 1. 验收目标

确认 Flutter Web 完整 H5 在真实浏览器权限和真实文件/媒体输入下，扫码、录音、定位、拍照/相册、视频选择、文件选择等能力可用，并且权限拒绝时有明确反馈，不出现假入口或卡死。

自动化 smoke 已经覆盖假摄像头、假麦克风、模拟定位、二维码图片解码、媒体上传和消息回查。人工验收只聚焦真实浏览器交互、真实权限弹窗和真实文件选择器。

## 2. 前置条件

- 后端 API 正常：`http://localhost:8080/api/v1`
- Flutter Web 正常：`http://localhost:5175/`
- 测试账号：
  - 操作账号：`h5test / 123456`
  - 会话对端：`h5peer / 123456`
- 当前私聊会话：`710a5471-ab43-4728-9acf-7db3a65e2bea`

建议先跑已有自动化 smoke：

```bash
node scripts/smoke_flutter_web_voice.mjs
node scripts/smoke_flutter_web_location.mjs
node scripts/smoke_flutter_web_camera.mjs
node scripts/smoke_flutter_web_qr_flow.mjs
node scripts/smoke_flutter_web_qr_image.mjs
node scripts/smoke_flutter_web_video.mjs
```

## 3. 双窗口启动器

已新增真实浏览器原生能力验收启动器：

```bash
node scripts/launch_flutter_web_native_manual_qa.mjs
```

脚本会：

- 登录 `h5test`
- 登录 `h5peer` 并创建/复用私聊
- 打开两个独立 Chrome 用户目录
- 第一个窗口进入聊天详情页
- 第二个窗口进入扫码页
- 不使用 fake media
- 不自动授权麦克风、摄像头、定位或文件权限

只检查接口和 URL，不打开浏览器：

```bash
GENERIC_IM_MANUAL_NATIVE_DRY_RUN=1 node scripts/launch_flutter_web_native_manual_qa.mjs
```

如果用静态构建产物验收：

```bash
GENERIC_IM_WEB_URL=http://localhost:5185/ node scripts/launch_flutter_web_native_manual_qa.mjs
```

运行脚本后保持终端不关闭；验收完成按 `Ctrl+C`，脚本会关闭它启动的 Chrome 并清理临时用户目录。

## 4. 聊天媒体能力

| 编号 | 能力 | 操作 | 期望结果 |
| --- | --- | --- | --- |
| WEB-NATIVE-001 | 文本 | 聊天页发送一条文本 | 消息出现在列表，刷新后仍存在 |
| WEB-NATIVE-002 | 图片选择 | 更多菜单选择图片并发送 | 图片可预览、上传、发送，刷新后可查看 |
| WEB-NATIVE-003 | 拍照 | 更多菜单选择拍照并允许摄像头 | 可拍照并进入待发送队列，发送成功 |
| WEB-NATIVE-004 | 视频选择 | 选择本地 MP4/MOV/WebM 视频 | 视频上传成功，气泡可播放 |
| WEB-NATIVE-005 | 文件选择 | 选择 PDF/ZIP/文本等普通文件 | 文件消息发送成功，文件名和大小显示正常 |
| WEB-NATIVE-006 | 语音录制 | 长按/点击录音入口并允许麦克风 | 能录音、停止、上传、发送，音频可播放 |
| WEB-NATIVE-007 | 位置 | 更多菜单选择位置并允许定位 | 发送位置消息，坐标/标题显示正常 |
| WEB-NATIVE-008 | 长按菜单 | 长按消息打开菜单 | 复制、转发、收藏、删除等入口不遮挡、不溢出 |

## 5. 扫码能力

| 编号 | 能力 | 操作 | 期望结果 |
| --- | --- | --- | --- |
| WEB-SCAN-001 | 摄像头扫码 | 扫码页允许摄像头，扫描真实用户二维码 | 能识别并进入用户资料/加好友/发消息流程 |
| WEB-SCAN-002 | 群二维码 | 扫描真实群邀请二维码 | 能进入群资料或入群流程 |
| WEB-SCAN-003 | 登录二维码 | 扫描网页登录二维码 | 能进入确认登录流程 |
| WEB-SCAN-004 | 相册识别 | 从文件选择器选择二维码图片 | `BarcodeDetector` 解码成功，并进入对应业务 |
| WEB-SCAN-005 | 无效二维码 | 扫描普通网址/错误 payload | 有明确错误提示，不跳错页面 |

## 6. 权限拒绝和兼容

| 编号 | 场景 | 期望结果 |
| --- | --- | --- |
| WEB-PERM-001 | 拒绝麦克风 | 录音给出明确提示，页面可继续使用 |
| WEB-PERM-002 | 拒绝摄像头 | 拍照/扫码给出明确提示，页面可返回 |
| WEB-PERM-003 | 拒绝定位 | 位置入口提示授权失败，不发送空位置 |
| WEB-PERM-004 | 取消文件选择 | 不生成空消息，不报错 |
| WEB-PERM-005 | 移动端 Safari | 布局不遮挡，文件/相册/扫码入口可用或有明确降级 |
| WEB-PERM-006 | Android Chrome | 权限弹窗、文件选择、扫码视频流正常 |

## 7. 通过标准

- 聊天页至少完成文本、图片、视频、文件、语音、位置各 1 次成功发送。
- 扫码页至少完成摄像头扫码和相册二维码识别各 1 次。
- 麦克风、摄像头、定位权限拒绝都能明确收口。
- 移动端小屏没有按钮遮挡、输入栏错位、底部安全区被遮住等明显 UI 问题。

## 8. 记录模板

```text
验收时间：
浏览器/设备：
网络环境：
聊天文本：
图片/拍照：
视频：
文件：
语音：
位置：
摄像头扫码：
相册二维码：
权限拒绝：
发现问题：
是否通过：
```
