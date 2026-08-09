# 聊天首页“Windows 已登录”顶部提示开发设计方案

> 目标版本：下一客户端与后端协同版本  
> 适用范围：Flutter Android、iOS 手机端，Windows 桌面端，Go 后端  
> 方案状态：待开发  
> 核心目标：实现类似微信的跨端登录提示——同一账号在 Windows 客户端保持有效登录时，手机聊天首页顶部显示“Windows 已登录”，Windows 退出或被手机终止后提示及时消失。

## 1. 背景

当前项目已经具备多设备登录和设备管理基础能力：

- Flutter 登录时会提交 `device_id`、`device_type`、`device_name`；
- Windows 客户端能上报 `device_type=windows` 和 Windows 电脑名称；
- 后端会把登录设备写入 `user_devices`，把有效登录会话写入 `user_sessions`；
- `/user/devices` 已返回 `is_current`、`session_count`、`has_active_session` 等字段；
- 手机“设置 -> 设备”页面能够读取设备列表，并支持终止指定设备或全部其他设备。

但是当前体验还没有形成微信式闭环：

1. 手机聊天首页没有明显的电脑端登录提示；
2. 设备页优先展示电脑名称，没有统一展示“Windows 已登录”；
3. 客户端设备模型未使用 `has_active_session`，历史设备可能被误放入“活跃会话”；
4. Windows 登录、退出后，没有专门的同账号设备状态事件通知手机立即刷新；
5. “已登录”和“WebSocket 当前在线”没有明确区分，容易造成状态口径混乱。

本方案不新建第二套登录体系，而是在现有设备、会话、WebSocket 能力上补齐展示和实时同步。

## 2. 产品目标

### 2.1 用户故事

用户在 Windows 客户端登录账号后，已经登录同一账号的手机端应在聊天首页顶部看到：

```text
[电脑图标]  Windows 已登录
            DESKTOP-ABC123                    >
```

用户点击提示后进入“登录设备”页面，可以：

- 查看 Windows 设备名、最近活跃时间、IP/地区；
- 终止该 Windows 登录；
- 终止全部其他设备登录。

Windows 正常退出、被手机终止、密码重置或管理员强制下线后，手机端顶部提示应及时消失。

### 2.2 成功标准

- Windows 登录成功后，已在线手机端 3 秒内出现提示；
- 手机冷启动、切回前台、WebSocket 重连后能恢复正确提示；
- Windows 正常退出或被终止后，已在线手机端 3 秒内隐藏提示；
- 历史设备记录没有有效会话时，不显示“Windows 已登录”；
- 当前设备永远不能被识别成“其他 Windows 已登录设备”；
- 多台 Windows 同时登录时，提示不会重复堆叠。

## 3. 范围边界

### 3.1 本期包含

- Android、iOS 聊天首页顶部提示；
- Windows 有效登录会话识别；
- 单台和多台 Windows 登录展示；
- 点击进入现有设备管理页面；
- 登录、退出、终止设备后的 WebSocket 实时刷新；
- 应用前台恢复、下拉刷新、WebSocket 重连时兜底刷新；
- 设备页按有效会话过滤“活跃会话”；
- 简体中文、繁体中文、英文文案；
- 后端和 Flutter 自动化测试、双端手工验收。

### 3.2 本期不包含

- Windows 是否正在操作键鼠等“实时使用中”状态；
- Windows 端远程控制手机；
- 手机端向 Windows 端传输文件的新功能；
- 用 GPS 或 IP 精确定位电脑；
- macOS、Linux、Web 的专属品牌文案。本期保留数据兼容，后续可扩展为“Mac 已登录”“网页端已登录”。

## 4. 状态口径

### 4.1 “Windows 已登录”的唯一判定

一条设备记录必须同时满足以下条件：

```text
device_type == windows
is_current == false
has_active_session == true
device_id 非空
```

才能在手机聊天首页显示为“Windows 已登录”。

禁止仅根据 `user_devices` 中存在 Windows 记录或 `last_active` 较新就判定已登录。`user_devices` 同时承担设备身份、推送和 E2EE 信息保存，设备记录存在不等于登录会话仍然有效。

### 4.2 “已登录”和“在线”的区别

- **已登录**：服务端仍存在可用登录会话，用户无需重新输入账号密码；
- **在线**：该设备当前保持 WebSocket 连接或在很短时间内有心跳；
- **最近活跃**：最近一次登录、刷新 Token、WebSocket 建连或心跳的时间。

聊天首页本期只显示“Windows 已登录”，不显示“在线”。这样即使 Windows 因休眠短暂断网，只要登录会话仍有效，提示仍保持，符合用户对微信式多端登录的认知。

### 4.3 多台 Windows

当有效 Windows 会话只有一台时：

```text
Windows 已登录
DESKTOP-ABC123
```

当有效 Windows 会话超过一台时：

```text
2 台 Windows 设备已登录
点击查看登录设备
```

列表只显示一条汇总提示，避免挤占聊天列表空间。点击后在设备页查看所有设备。

## 5. UI 与交互设计

### 5.1 展示位置

手机聊天首页 Sliver 结构调整为：

1. 顶部标题栏；
2. 搜索框；
3. Windows 已登录提示条；
4. 网络或聊天列表错误提示；
5. 会话列表。

提示条位于搜索框下方、第一条聊天上方，随聊天列表滚动，不占用系统 AppBar 固定高度。编辑聊天模式下隐藏，避免与批量选择操作冲突。

桌面侧边栏模式 `isDesktopSidebar=true` 不显示该提示，防止 Windows 自己提示“Windows 已登录”。

### 5.2 视觉规范

- 外边距：左右 16 px，下方 8 px；
- 高度：单台设备 56-64 px，多台设备 56 px；
- 圆角：10-12 px；
- 浅色背景：接近搜索框的浅灰色，但与聊天项有层级差；
- 深色背景：使用现有深色卡片背景；
- 左侧：电脑图标；
- 中间主标题：`Windows 已登录`；
- 中间副标题：电脑名称，缺失时显示 `Windows PC`；
- 右侧：箭头；
- 不使用红点、告警色，正常多端登录不是安全告警。

如果设备为首次出现或地区/IP 异常，安全告警应由独立的登录安全机制处理，不在本提示条中混用。

### 5.3 点击行为

点击整条提示：

- 手机端进入现有 `DevicesPage`；
- 设备页自动刷新 `/user/devices`；
- Windows 有效会话显示为“Windows 已登录”；
- 用户可点击终止按钮退出该设备；
- 操作成功后返回聊天首页，提示立即刷新或消失。

不在聊天首页直接提供“退出 Windows”按钮，避免误触导致桌面端被强制下线。

### 5.4 文案

| 场景 | 简体中文 | 繁体中文 | 英文 |
| --- | --- | --- | --- |
| 单台 | Windows 已登录 | Windows 已登入 | Windows signed in |
| 多台 | `{n} 台 Windows 设备已登录` | `{n} 台 Windows 裝置已登入` | `{n} Windows devices signed in` |
| 默认设备名 | Windows PC | Windows PC | Windows PC |
| 查看设备 | 点击查看登录设备 | 點擊查看登入裝置 | View signed-in devices |

## 6. 数据模型设计

### 6.1 Flutter 统一模型

将设备页目前的页面内 `DeviceInfo` 模型抽出为共享模型，例如：

```text
lib/features/settings/models/login_device.dart
```

字段建议：

```dart
class LoginDevice {
  final int id;
  final String deviceId;
  final String deviceType;
  final String deviceName;
  final String ip;
  final String location;
  final bool isCurrent;
  final int sessionCount;
  final bool hasActiveSession;
  final DateTime lastActive;
  final DateTime createdAt;
}
```

必须解析 `session_count` 和 `has_active_session`，不能继续丢弃服务端已经返回的有效会话信息。

增加语义属性：

```dart
bool get isDesktop => const {'windows', 'macos', 'linux'}.contains(deviceType);
bool get isActiveWindowsSession =>
    deviceType == 'windows' && !isCurrent && hasActiveSession;
```

### 6.2 Riverpod 状态

新增账号隔离的设备会话 Provider，例如：

```text
lib/features/settings/providers/login_device_provider.dart
```

职责：

- 请求 `/user/devices`；
- 解析、按 `device_id` 去重；
- 只把 `has_active_session=true` 的设备计入活跃设备；
- 暴露 `activeWindowsDevices` 和 `activeWindowsCount`；
- 监听账号切换，立即清空旧账号设备状态；
- 合并并发刷新，避免聊天首页、设置页重复请求；
- 保留上一次成功数据，刷新失败时不让提示频繁闪烁；
- 登出时清空全部内存状态。

聊天首页、设置页设备数量和设备管理页统一使用该 Provider，避免三个页面分别实现不同的设备过滤规则。

## 7. 后端接口设计

### 7.1 继续复用 `/user/devices`

现有接口已经返回本功能所需核心字段，本期不新增重复接口。响应保持向后兼容：

```json
{
  "devices": [
    {
      "device_id": "...",
      "device_type": "windows",
      "device_name": "DESKTOP-ABC123",
      "is_current": false,
      "session_count": 1,
      "has_active_session": true,
      "last_active": "2026-07-17T12:00:00+08:00"
    }
  ]
}
```

### 7.2 有效会话计算

`GetDevices` 继续以 `user_sessions` 按逻辑 `device_id` 聚合：

- `session_count > 0` -> `has_active_session=true`；
- 没有会话 -> `has_active_session=false`；
- 当前设备根据 JWT 的 `device_id` 标记 `is_current=true`；
- 同一物理设备的 APNs、VoIP 等存储行继续按逻辑设备 ID 合并。

需要补充检查：对于已经在 Redis 中撤销、但数据库 `user_sessions` 残留的 Token，应在查询前清理，或在所有撤销路径中同步删除对应会话行。否则数据库行仍可能导致假“已登录”。

### 7.3 WebSocket 设备会话事件

新增消息类型：

```text
device_session_changed
```

建议事件体：

```json
{
  "type": "device_session_changed",
  "action": "login",
  "device_id": "...",
  "device_type": "windows",
  "device_name": "DESKTOP-ABC123",
  "changed_at": "2026-07-17T12:00:00+08:00"
}
```

`action` 取值：

- `login`：新设备登录或二维码登录确认；
- `logout`：设备正常退出；
- `terminated`：被其他设备终止；
- `terminated_others`：终止全部其他设备；
- `invalidated`：密码重置、管理员强制下线、账号禁用等导致会话失效。

事件只作为“需要刷新设备列表”的信号。Flutter 收到事件后重新请求 `/user/devices`，不直接把事件体当作最终状态，避免丢包、乱序或多会话聚合造成错误。

### 7.4 事件发送时机

事件必须在数据库事务提交成功后发送，不能先发事件再落库。覆盖路径：

- 普通账号密码登录；
- 快速注册后自动登录；
- 二维码登录确认；
- Token 刷新不重复发送 `login`；
- 正常退出；
- 终止指定设备；
- 终止全部其他设备；
- 修改或重置密码；
- 管理员强制下线、冻结账号；
- 账号注销。

建议抽出统一的 `DeviceSessionNotifier`，持有 `ws.Hub`，由认证和用户处理器共同调用。不要在每个 Handler 中复制事件结构。

## 8. 客户端刷新策略

### 8.1 主刷新链路

手机端登录完成后：

1. 初始化设备会话 Provider；
2. 请求 `/user/devices`；
3. 找出其他有效 Windows 会话；
4. 聊天首页根据 Provider 自动显示或隐藏提示。

收到 `device_session_changed` 后：

1. 进行 200-500 ms 防抖；
2. 请求 `/user/devices`；
3. 原子替换设备列表；
4. 更新聊天首页和设置页。

### 8.2 兜底刷新

即使 WebSocket 事件丢失，也必须在以下场景重新拉取：

- 手机应用从后台恢复到前台；
- WebSocket 重连成功；
- 聊天首页下拉刷新；
- 进入设备管理页；
- 终止设备操作成功；
- 当前账号发生切换。

不建议长期每几秒轮询。若线上环境 WebSocket 事件暂时无法同步发布，可临时在聊天首页可见期间每 60 秒刷新一次，待事件链路稳定后移除。

### 8.3 错误与闪烁控制

- 首次请求失败：不显示提示，不阻断聊天列表；
- 已有成功数据后的刷新失败：保留旧提示，并在下次生命周期或重连时重试；
- 401：交由现有认证流程处理，并清空设备会话状态；
- 账号切换：先清空旧账号数据，再加载新账号，禁止短暂显示上一账号的 Windows 状态；
- 连续收到多条事件：合并成一次接口请求。

## 9. 设备管理页同步修正

设备管理页需要与聊天首页使用同一状态口径：

- “当前设备”按 `is_current=true` 展示；
- “活跃会话”只展示 `has_active_session=true && is_current=false`；
- 没有有效会话的历史设备不进入“活跃会话”；
- `windows` 使用电脑图标和“Windows”类型文案；
- 主标题优先展示电脑名称；
- 副标题展示 `Windows 已登录 · 最近活跃时间`；
- 终止成功后更新共享 Provider，而不是只删除页面本地数组；
- 设置页显示的设备数量只统计有效登录设备。

对于无活跃会话但仍因推送或 E2EE 身份需要保留的设备记录，本期不在用户界面展示，也不直接删除数据库记录。

## 10. 代码改造范围

### 10.1 Flutter

预计涉及：

- `lib/features/chat/pages/chat_page.dart`
  - 在搜索框与聊天列表之间接入 Windows 登录提示；
  - 手机端显示，桌面侧边栏隐藏；
  - 点击打开设备管理页。
- `lib/features/settings/pages/devices_page.dart`
  - 使用共享设备模型与 Provider；
  - 按 `has_active_session` 过滤；
  - 补充 Windows 类型、图标与状态文案。
- `lib/features/settings/pages/settings_page.dart`
  - 设备数量改为复用共享 Provider。
- `lib/features/settings/models/login_device.dart`
  - 新增统一设备模型。
- `lib/features/settings/providers/login_device_provider.dart`
  - 新增加载、过滤、去重、刷新和账号隔离逻辑。
- `lib/features/settings/widgets/windows_login_banner.dart`
  - 新增可测试的顶部提示组件。
- `lib/core/services/api/websocket_service.dart`
  - 增加 `device_session_changed` 消息类型。
- `lib/core/router/app_router.dart` 或现有页面打开逻辑
  - 为聊天首页提供统一的设备管理导航入口。
- `lib/core/i18n/app_localizations.dart`
  - 增加多语言文案。

### 10.2 Go 后端

预计涉及：

- `backend/internal/handlers/user_handler.go`
  - 保持设备列表字段一致；
  - 终止设备后发送状态事件；
  - 修复所有会话失效路径的一致清理。
- `backend/internal/handlers/auth_handler.go`
  - 登录、退出后发送设备会话事件。
- `backend/internal/handlers/auth_qr_login_handler.go`
  - 二维码登录确认后发送事件。
- `backend/internal/handlers/user_login_session.go`
  - 集中维护设备记录和登录会话；
  - 补充可测试的有效会话清理方法。
- `backend/internal/handlers/device_session_notifier.go`
  - 新增统一事件构造与发送逻辑。
- `backend/cmd/server/main.go`
  - 把现有 `ws.Hub` 注入需要发送设备事件的处理器。

不需要新增数据库表。若审计发现部分会话撤销路径没有数据库状态字段，可优先修正删除逻辑，避免为本功能引入新的重复状态。

## 11. 实施步骤

### 阶段一：统一状态口径

1. 抽取 Flutter 共享设备模型；
2. 解析 `session_count`、`has_active_session`；
3. 新建设备会话 Provider；
4. 设备页和设置页切换到共享 Provider；
5. 修复 Windows 类型名称和图标。

完成标准：手机设备页只把真正有会话的 Windows 设备显示为活跃设备。

### 阶段二：聊天首页提示

1. 实现独立 `WindowsLoginBanner`；
2. 接到聊天首页搜索框下方；
3. 实现单台、多台 Windows 展示；
4. 接入设备管理页导航；
5. 完成深色模式和多语言。

完成标准：刷新聊天首页后能按真实状态显示或隐藏提示。

### 阶段三：实时同步

1. 后端增加 `device_session_changed`；
2. 覆盖登录、退出、终止、强制失效路径；
3. Flutter 注册事件监听并防抖刷新；
4. 接入前台恢复、WebSocket 重连和下拉刷新兜底；
5. 验证多设备同时操作和事件乱序。

完成标准：Windows 登录或退出后，手机无需手动刷新即可在 3 秒内更新提示。

## 12. 自动化测试设计

### 12.1 Go 测试

- 登录 Windows 后创建 `user_devices` 和 `user_sessions`；
- `/user/devices` 返回 Windows `has_active_session=true`；
- 正常退出删除对应会话后返回 `false`；
- 终止指定设备删除对应全部会话；
- 终止其他设备保留当前设备；
- 同一物理设备多存储行能正确去重；
- 登录、退出、终止分别发送正确的 WebSocket 事件；
- 数据库事务失败时不发送事件；
- 密码重置和管理员强制下线不会残留活动会话。

### 12.2 Flutter 单元与组件测试

- `LoginDevice.fromJson` 正确解析缺省字段；
- 仅 Windows + 非当前设备 + 有效会话命中过滤；
- 历史 Windows 设备不显示；
- 当前 Windows 设备不显示自己的提示；
- 单台 Windows 展示电脑名；
- 多台 Windows 展示汇总数量；
- 深色、浅色和三种语言渲染正常；
- 点击提示进入设备管理页；
- WebSocket 事件合并刷新，不重复并发请求；
- 切换账号后旧提示立即清空；
- 编辑聊天模式和桌面侧边栏不显示提示。

## 13. 手工验收矩阵

| 编号 | 前置状态 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| WIN-LOGIN-001 | 手机已登录，Windows 未登录 | Windows 密码登录 | 手机 3 秒内显示“Windows 已登录” |
| WIN-LOGIN-002 | 手机已登录 | Windows 扫码登录 | 确认成功后手机显示提示 |
| WIN-LOGIN-003 | 手机和一台 Windows 已登录 | 第二台 Windows 登录 | 手机显示“2 台 Windows 设备已登录” |
| WIN-LOGIN-004 | Windows 已登录 | Windows 正常退出 | 手机提示 3 秒内消失 |
| WIN-LOGIN-005 | Windows 已登录 | 手机设备页终止 Windows | Windows 被下线，手机提示消失 |
| WIN-LOGIN-006 | 存在历史 Windows 设备，无会话 | 手机打开聊天首页 | 不显示提示 |
| WIN-LOGIN-007 | Windows 已登录 | 手机杀进程后重启 | 冷启动后恢复正确提示 |
| WIN-LOGIN-008 | Windows 已登录 | 手机断网后恢复 | WebSocket 重连后提示正确 |
| WIN-LOGIN-009 | A 账号有 Windows，切换 B 账号 | 切换账号 | B 账号不得短暂显示 A 的提示 |
| WIN-LOGIN-010 | 深色模式 | 登录和退出 Windows | 样式、文字、刷新均正常 |

建议至少使用一台 Android 真机和一台 Windows 客户端完成真实双端验证；iOS 在 Apple 构建环境补充同样验收。

## 14. 验收清单

- [ ] 聊天首页搜索框下方出现微信式 Windows 登录提示；
- [ ] 仅有效 Windows 会话触发提示；
- [ ] 提示显示正确电脑名称或默认名称；
- [ ] 多台 Windows 显示汇总数量；
- [ ] 点击进入设备管理页；
- [ ] 手机可以终止 Windows 会话；
- [ ] Windows 正常退出后提示自动消失；
- [ ] 密码重置、强制下线后不残留；
- [ ] 手机前台恢复和 WebSocket 重连能校准状态；
- [ ] 设置页设备数量与设备页、聊天首页一致；
- [ ] Android、iOS、Windows 不互相显示错误设备状态；
- [ ] Flutter analyze、定向测试和 Go 测试通过；
- [ ] Android + Windows 真实双端登录/退出验收通过。

## 15. 风险与控制

### 风险一：历史设备被误判为已登录

控制：所有 UI 统一使用 `has_active_session`，禁止只判断设备记录存在。

### 风险二：WebSocket 事件丢失

控制：事件只触发刷新；前台恢复、重连、下拉刷新继续通过接口校准最终状态。

### 风险三：账号切换串数据

控制：Provider 以当前账号 ID 为生命周期依赖，账号变化时销毁并清空旧状态。

### 风险四：登录事务未完成就刷新

控制：后端必须在数据库事务提交后发送事件；客户端收到事件后增加短防抖。

### 风险五：不同退出路径清理不一致

控制：正常退出、设备终止、密码重置、强制下线统一调用会话清理与通知方法，并用后端测试覆盖。

## 16. 最终交付物

开发完成后应交付：

1. Flutter 共享设备模型和状态 Provider；
2. 聊天首页 Windows 登录提示组件；
3. 修正后的设备管理页和设置页设备数量；
4. 后端设备会话变更 WebSocket 事件；
5. Go 与 Flutter 自动化测试；
6. Android + Windows 双端验证记录和截图；
7. 如需要发布，重新构建 Android APK 与 Windows 安装包，并验证线上 API/WS 地址。

