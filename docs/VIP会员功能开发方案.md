# VIP会员功能开发方案

## 1. 目标

在现有 IM 系统里增加类似 Telegram Premium / 飞机会员的 VIP 权益体系，用会员身份控制创建群聊、创建频道、群人数上限、公开群能力、成员保护等高级功能。

一期目标不是做复杂营销系统，而是先跑通商业闭环：

- 后台可配置 VIP 套餐。
- 后台可给用户手动开通、续期、取消 VIP。
- App 可展示用户 VIP 状态和权益。
- 用户可用钱包余额购买 VIP。
- 创建群聊/频道时按 VIP 权益拦截。

## 2. 现有基础

当前项目已有可复用能力：

- 用户体系：`users`、登录态、中间件鉴权。
- 群/频道体系：`chats`、`chat_members`、`chat_admin_permissions`。
- 群创建接口：`POST /api/v1/chat/create`。
- 钱包体系：`wallets`、`transactions`、充值、提现、转账、红包。
- 在线支付入口：已有微信/支付宝通知和钱包在线支付配置基础。
- 后台管理：已有用户管理、钱包管理、系统设置菜单结构。

因此 VIP 应作为一层独立权益服务接入现有功能，而不是重写群聊或支付。

## 3. VIP等级建议

### 免费用户

- 可聊天、加好友、加入群。
- 不允许创建群聊。
- 不允许创建频道。
- 不允许设置公开群用户名。
- 不允许开启成员保护。

### VIP

- 允许创建普通群聊。
- 群数量上限：5 个。
- 单群成员上限：200 或 500。
- 可上传更大的头像/文件。
- 显示 VIP 标识。

### SVIP

- 允许创建群聊和频道。
- 群数量上限：20 个。
- 单群成员上限：1000 或更高。
- 允许设置公开群用户名。
- 允许开启成员保护。
- 可创建公开群/公开频道。
- 显示高级会员标识。

### 管理员特权

- 后台可直接赠送 VIP/SVIP。
- 后台可延长到期时间。
- 后台可取消会员。
- 后台可冻结会员权益。

## 4. 权益清单

一期建议落地这些权益：

| 权益键 | 说明 | 免费 | VIP | SVIP |
| --- | --- | --- | --- | --- |
| `can_create_group` | 是否可创建群聊 | 否 | 是 | 是 |
| `can_create_channel` | 是否可创建频道 | 否 | 否 | 是 |
| `max_owned_groups` | 可创建群聊数量 | 0 | 5 | 20 |
| `max_group_members` | 群成员上限 | 0 | 500 | 1000 |
| `can_set_public_username` | 可设置公开群用户名 | 否 | 否 | 是 |
| `can_enable_member_protection` | 可开启成员保护 | 否 | 否 | 是 |
| `upload_file_limit_mb` | 文件上传上限 | 100 | 500 | 2048 |
| `vip_badge` | 会员标识 | 无 | VIP | SVIP |

权益必须使用配置驱动，不能写死在 App 里。

## 5. 数据库设计

### 5.1 VIP套餐表

表名：`vip_plans`

```sql
CREATE TABLE vip_plans (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,
  name VARCHAR(64) NOT NULL,
  level INT NOT NULL DEFAULT 1,
  duration_days INT NOT NULL DEFAULT 30,
  price DECIMAL(12,2) NOT NULL DEFAULT 0,
  original_price DECIMAL(12,2) NOT NULL DEFAULT 0,
  benefits_json JSON NOT NULL,
  description VARCHAR(500) NOT NULL DEFAULT '',
  sort INT NOT NULL DEFAULT 0,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  deleted_at DATETIME NULL,
  INDEX idx_vip_plans_enabled_sort (enabled, sort),
  INDEX idx_vip_plans_deleted_at (deleted_at)
);
```

`benefits_json` 示例：

```json
{
  "can_create_group": true,
  "can_create_channel": false,
  "max_owned_groups": 5,
  "max_group_members": 500,
  "can_set_public_username": false,
  "can_enable_member_protection": false,
  "upload_file_limit_mb": 500,
  "vip_badge": "VIP"
}
```

### 5.2 用户会员表

表名：`user_vip_memberships`

```sql
CREATE TABLE user_vip_memberships (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL UNIQUE,
  plan_id BIGINT UNSIGNED NULL,
  level INT NOT NULL DEFAULT 0,
  source VARCHAR(32) NOT NULL DEFAULT 'manual',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  started_at DATETIME NOT NULL,
  expired_at DATETIME NOT NULL,
  canceled_at DATETIME NULL,
  remark VARCHAR(500) NOT NULL DEFAULT '',
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  INDEX idx_user_vip_status_expired (status, expired_at),
  INDEX idx_user_vip_plan_id (plan_id)
);
```

状态：

- `active`：有效
- `expired`：已过期
- `canceled`：已取消
- `frozen`：冻结

来源：

- `manual`：后台赠送
- `wallet`：钱包余额购买
- `wechat`：微信支付
- `alipay`：支付宝支付
- `promo`：活动赠送

### 5.3 VIP订单表

表名：`vip_orders`

```sql
CREATE TABLE vip_orders (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_no VARCHAR(64) NOT NULL UNIQUE,
  user_id BIGINT UNSIGNED NOT NULL,
  plan_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  pay_method VARCHAR(32) NOT NULL DEFAULT 'wallet',
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  paid_at DATETIME NULL,
  canceled_at DATETIME NULL,
  transaction_id VARCHAR(64) NOT NULL DEFAULT '',
  remark VARCHAR(500) NOT NULL DEFAULT '',
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  INDEX idx_vip_orders_user_created (user_id, created_at),
  INDEX idx_vip_orders_status_created (status, created_at)
);
```

订单状态：

- `pending`：待支付
- `paid`：已支付
- `canceled`：已取消
- `failed`：失败
- `refunded`：已退款

## 6. 后端模块设计

### 6.1 模型

新增文件：

- `backend/internal/models/vip.go`

模型：

- `VipPlan`
- `UserVipMembership`
- `VipOrder`

### 6.2 权益服务

新增文件：

- `backend/internal/services/vip_service.go`

核心方法：

```go
type VipEntitlements struct {
    Level                     int    `json:"level"`
    Badge                     string `json:"badge"`
    CanCreateGroup            bool   `json:"can_create_group"`
    CanCreateChannel          bool   `json:"can_create_channel"`
    MaxOwnedGroups            int    `json:"max_owned_groups"`
    MaxGroupMembers           int    `json:"max_group_members"`
    CanSetPublicUsername      bool   `json:"can_set_public_username"`
    CanEnableMemberProtection bool   `json:"can_enable_member_protection"`
    UploadFileLimitMB         int    `json:"upload_file_limit_mb"`
}
```

```go
GetUserVipStatus(userID uint64) (*VipStatus, error)
GetUserEntitlements(userID uint64) (*VipEntitlements, error)
CanCreateChat(userID uint64, chatType int8) error
ResolveMaxGroupMembers(userID uint64) int
GrantVip(userID uint64, planID uint64, source string, days int, remark string) error
CancelVip(userID uint64, remark string) error
PurchaseVipWithWallet(userID uint64, planID uint64) (*VipOrder, error)
```

### 6.3 权限拦截位置

必须在后端拦截，不能只靠 App 隐藏按钮。

修改：

- `backend/internal/handlers/chat_handler.go`

在 `CreateChat` 中根据 `req.Type` 判断：

- 群聊：检查 `can_create_group`
- 频道：检查 `can_create_channel`
- 创建数量：检查 `max_owned_groups`
- 群人数上限：创建时写入 `Chat.MaxMembers`

返回示例：

```json
{
  "code": 40301,
  "message": "开通VIP后可创建群聊",
  "data": {
    "required_level": 1,
    "action": "create_group"
  }
}
```

### 6.4 App接口

新增：

```text
GET  /api/v1/vip/status
GET  /api/v1/vip/plans
POST /api/v1/vip/orders
POST /api/v1/vip/orders/:id/pay-wallet
```

接口说明：

- `GET /vip/status`：返回当前用户会员状态、到期时间、权益。
- `GET /vip/plans`：返回可购买套餐。
- `POST /vip/orders`：创建购买订单。
- `POST /vip/orders/:id/pay-wallet`：使用钱包余额支付并开通。

### 6.5 后台接口

新增：

```text
GET    /api/v1/admin/vip/plans
POST   /api/v1/admin/vip/plans
PUT    /api/v1/admin/vip/plans/:id
DELETE /api/v1/admin/vip/plans/:id

GET    /api/v1/admin/vip/users
POST   /api/v1/admin/vip/users/:user_id/grant
POST   /api/v1/admin/vip/users/:user_id/cancel

GET    /api/v1/admin/vip/orders
```

## 7. App端设计

### 7.0 UI风格约束

VIP 页面必须和当前 App 风格保持一致，不做独立营销页风格。

遵循现有页面：

- 设置页：`lib/features/settings/pages/settings_page.dart`
- 钱包页/钱包设置相关页面
- 创建群弹窗：`lib/features/chat/widgets/create_sheets.dart`

设计要求：

- 使用当前 App 的浅灰背景、白色列表分组、普通导航栏和现有字号。
- VIP 入口放在设置页列表里，和“隐私”“通知”“数据存储”等入口一致。
- VIP 中心不要做大面积渐变、大号 Hero、夸张发光卡片、悬浮营销卡。
- 套餐展示可以用普通列表或紧凑分组，不用大片彩色卡片。
- 权益展示使用图标 + 文案列表，图标尺寸和设置页入口一致。
- 开通按钮使用现有主色 `AppColors.primary`，样式和当前 App 按钮一致。
- 弹窗使用现有 `showModalBottomSheet` / 普通 `Dialog` 风格，不做全屏营销弹层。
- 文案要像产品功能说明，不要夸张宣传语，例如避免“尊享”“奢华”“超级特权”等词。
- VIP 标识可以比普通 UI 更有识别度，但只能作为小面积点缀，不能带动整个页面变成营销风。

协调性要求：

- 页面整体优先服从现有 App 的布局、字号、间距、圆角和颜色体系。
- VIP 视觉只能增强识别度，不能改变设置页、资料页、创建群页原本的信息层级。
- 不新增和当前主题冲突的主色。VIP/SVIP 的金色、蓝紫色只能用于徽章和少量状态点缀。
- 同一页面最多出现一种强调视觉，避免套餐、按钮、徽章同时抢焦点。
- 所有 VIP 入口、权益列表、套餐列表都要像系统功能页面，而不是广告页。
- 深色模式必须单独适配，不能只靠浅色模式的渐变直接反转。
- 长昵称、英文、繁体中文下，VIP 标识不能挤压文字，也不能导致换行错乱。

推荐视觉结构：

```text
设置
  账号信息
  VIP会员        VIP · 2026-07-24到期
  通知
  隐私
```

VIP 中心：

```text
VIP会员

当前状态
  VIP
  2026-07-24到期

套餐
  VIP月卡       ¥19.9
  VIP季卡       ¥49.9
  SVIP月卡      ¥39.9

权益
  可创建群聊
  群成员上限 500
  文件上传上限 500MB
```

整体要像 App 原有设置/钱包功能页，而不是广告落地页。

### 7.1 设置页入口

在设置页增加：

```text
VIP会员
```

显示：

- 未开通：`开通VIP，解锁建群等权益`
- 已开通：`VIP · 2026-07-24到期`
- SVIP：`SVIP · 2026-07-24到期`

### 7.2 VIP中心页

新增页面：

- `lib/features/vip/pages/vip_center_page.dart`

内容：

- 当前会员状态
- 到期时间
- 权益列表
- 套餐列表
- 钱包余额支付按钮
- 购买记录入口

页面结构建议：

- `SliverAppBar` 标题：`VIP会员`
- 第一组：当前状态，白色列表分组。
- 第二组：套餐列表，每个套餐是一行，不做大卡片。
- 第三组：权益说明，使用普通 cell。
- 底部支付按钮固定在安全区域上方，和现有创建/保存按钮风格一致。

### 7.3 创建群页拦截

修改：

- `lib/features/chat/widgets/create_sheets.dart`

逻辑：

- 进入创建群页时读取 `vip/status`。
- 无权限时不直接创建，显示开通提示。
- 如果后端返回 VIP 权限错误，弹出开通 VIP 弹窗。

提示文案：

```text
开通VIP后可创建群聊
VIP用户可创建群聊并获得更高群成员上限
```

按钮：

```text
去开通
```

### 7.4 用户资料标识

用户资料页、聊天详情页可显示 VIP 小标识：

- 普通用户：不显示
- VIP：显示 `VIP`
- SVIP：显示 `SVIP`

VIP 标识设计要求：

- 标识本身可以更炫酷，突出付费身份。
- 标识必须和当前 UI 协调，不能比头像、昵称、主按钮更抢视觉重心。
- VIP 使用蓝紫或金色小徽章，SVIP 使用金色/铂金质感小徽章。
- 可以使用轻微渐变、描边、高光，但面积要小。
- 不使用大面积发光、全屏动效、夸张粒子。
- 在头像旁、昵称后、个人资料页标题区展示，尺寸稳定，不挤压昵称。
- 聊天列表和消息气泡里默认不强展示，避免信息噪音；可在个人资料页和群成员列表展示。
- 后台配置可控制是否展示 VIP 标识。
- 同一套 VIP 标识组件必须复用到资料页、成员列表、设置页，避免多个页面各画一套样式。

推荐样式：

```text
昵称  [VIP]
昵称  [SVIP]
```

视觉建议：

- VIP：蓝紫渐变底 + 白色 VIP 字样。
- SVIP：金色渐变底 + 深色 SVIP 字样。
- 圆角胶囊，高度 18-20px。
- App 内使用同一套组件，避免每个页面样式不一致。
- 图标/文字和徽章之间保留 6-8px 间距。
- 标识最大宽度受控，超长等级名不允许撑开列表。
- 徽章阴影只允许极轻微，不能出现浮夸发光边。

标识验收标准：

- 放在昵称后时，昵称仍是第一视觉信息。
- 放在资料页头像附近时，不遮挡头像主体。
- 放在群成员列表时，列表行高不被撑大。
- 浅色/深色模式都清晰，但不刺眼。
- 截图看起来像当前 App 自然扩展出来的功能，而不是另一个设计系统。

一期可先只显示自己的 VIP 状态和个人资料页标识，不急着全量同步所有用户标识。

## 8. 后台设计

### 8.0 后台UI风格约束

后台 VIP 管理必须沿用当前管理台风格，不单独做一套视觉。

遵循现有页面：

- 钱包设置：`admin/src/views/wallet/settings/index.vue`
- 用户钱包：`admin/src/views/wallet/user-wallets/index.vue`
- 系统配置类页面

设计要求：

- 使用 Element Plus 现有 `el-tabs`、`el-form`、`el-table`、`el-dialog`。
- 不做大面积渐变、不做装饰插画、不做营销式统计大屏。
- 套餐配置使用表单项和开关，不让运营直接编辑 JSON。
- 会员用户使用筛选表单 + 表格 + 操作按钮。
- 订单记录使用普通表格。
- 页面文案使用业务语言，例如“套餐配置”“会员用户”“订单记录”“手动开通”。
- 按钮颜色沿用当前后台主色和 Element Plus 默认状态色。

### 8.1 菜单

新增顶级或系统子菜单：

```text
会员管理
  - 套餐配置
  - 会员用户
  - 订单记录
```

### 8.2 套餐配置

字段：

- 套餐名称
- 等级
- 有效天数
- 售价
- 原价
- 是否启用
- 排序
- 权益开关
- 数值权益

权益配置采用表单，不让运营直接编辑 JSON。

### 8.3 会员用户

功能：

- 搜索用户
- 查看会员等级
- 查看到期时间
- 手动开通
- 延期
- 取消
- 冻结

### 8.4 订单记录

字段：

- 订单号
- 用户
- 套餐
- 金额
- 支付方式
- 状态
- 支付时间
- 创建时间

## 9. 钱包支付流程

一期优先钱包余额支付，因为项目已有钱包交易能力。

流程：

1. App 创建 VIP 订单。
2. 用户选择钱包余额支付。
3. 后端开启事务。
4. 校验钱包余额。
5. 扣除余额。
6. 写入交易记录：`vip_purchase`。
7. 更新订单为 `paid`。
8. 开通或延长用户 VIP。
9. 返回最新 VIP 状态。

需要新增交易类型：

```go
TransactionTypeVipPurchase = "vip_purchase"
TransactionTypeVipRefund   = "vip_refund"
```

## 10. 会员续期规则

推荐规则：

- 用户无有效 VIP：从当前时间开始计算。
- 用户已有同等级或更高等级 VIP：从当前到期时间继续顺延。
- 用户从 VIP 升级 SVIP：立即变为 SVIP，剩余 VIP 价值是否折算一期先不做。
- 后台手动开通可以直接指定天数或指定到期时间。

一期不要做复杂折算，避免账务争议。

## 11. 安全与风控

必须后端控制：

- 建群权限
- 建频道权限
- 群数量上限
- 群人数上限
- 公开群用户名
- 成员保护

不能只在 App 隐藏按钮。

需要加事务：

- 钱包扣款和订单支付必须同事务。
- 订单号必须唯一。
- 支付接口必须幂等。

需要定时任务或惰性刷新：

- 用户 VIP 到期后，查询时自动视为过期。
- 可选后台定时把过期会员状态更新为 `expired`。

## 12. 开发阶段

### 阶段一：后端基础

- 新增 VIP 数据表。
- 新增模型。
- 新增 VIP 服务。
- 新增 App VIP 状态和套餐接口。
- 新增后台套餐接口。
- `go test ./...` 通过。

### 阶段二：权限闭环

- 在 `CreateChat` 接入 VIP 权益校验。
- 限制免费用户建群/建频道。
- VIP 创建群时写入更高 `max_members`。
- 增加后端单元测试。

### 阶段三：后台管理

- 新增会员管理菜单。
- 套餐配置页面。
- 会员用户页面。
- 手动开通/续期/取消。
- 订单记录页面。

### 阶段四：App VIP中心

- 设置页加 VIP 入口。
- VIP 中心页。
- 创建群页无权限提示。
- 钱包余额购买 VIP。

### 阶段五：模拟器验收

- 免费用户创建群失败并提示开通 VIP。
- 后台给用户开通 VIP。
- App 刷新后显示 VIP 状态。
- VIP 用户创建群成功。
- VIP 群人数上限正确。
- 钱包余额购买成功后自动开通。

## 13. 验收清单

后端：

- `go test ./...` 通过。
- 免费用户创建群返回权限错误。
- 免费用户创建频道返回权限错误。
- VIP 用户创建群成功。
- SVIP 用户创建频道成功。
- 钱包余额不足时购买失败。
- 钱包余额充足时购买成功，余额扣减、订单支付、会员开通三者一致。

后台：

- 可创建 VIP 套餐。
- 可编辑权益。
- 可禁用套餐。
- 可手动给用户开通 VIP。
- 可取消 VIP。
- 可查看 VIP 订单。

App：

- 设置页显示 VIP 状态。
- VIP 中心能展示套餐。
- 免费用户创建群时出现开通提示。
- VIP 用户创建群成功。
- 模拟器访问本地接口 `10.0.2.2:8080` 正常。

## 14. 建议默认套餐

### VIP月卡

- 价格：19.9
- 有效期：30天
- 可创建群：5个
- 群人数上限：500
- 上传限制：500MB

### VIP季卡

- 价格：49.9
- 有效期：90天
- 权益同 VIP 月卡

### SVIP月卡

- 价格：39.9
- 有效期：30天
- 可创建群：20个
- 可创建频道
- 群人数上限：1000
- 可设置公开群用户名
- 可开启成员保护
- 上传限制：2048MB

## 15. 一期不做的内容

为保证快上线，一期先不做：

- VIP 价值折算升级。
- 自动连续包月。
- 优惠券。
- 复杂推广返佣。
- 多币种。
- 用户之间赠送 VIP。
- 全局 VIP 动态头像框。

这些可以在 VIP 基础闭环稳定后再做。

## 16. 推荐开工顺序

推荐从后端开始：

1. `models/vip.go`
2. SQL 初始化脚本
3. `services/vip_service.go`
4. App VIP 接口
5. 后台 VIP 接口
6. `chat_handler.CreateChat` 权限拦截
7. 后台套餐/用户页面
8. App VIP 中心和创建群提示
9. 模拟器验收

这样开发顺序风险最低，先保证后端权限真实生效，再做页面。
