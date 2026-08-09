# 深色模式全量排查与改造清单 2026-06-26

## 目标

- 浅色模式保持现有观感不回退。
- 深色模式不再简单套黑底，统一使用高对比文本、卡片、分割线、输入框、按钮和强调色。
- 不等待逐页截图，按路由入口、页面文件和硬编码颜色静态扫描全量推进。

## 统一改造规则

- 主色：页面内 `AppColors.primary` 在深色模式改用 `AppColors.primaryFor(context)` 或主题 `colorScheme.primary`。
- 背景：页面背景用 `AppColors.darkBackground`，卡片/列表容器用 `AppColors.darkCard` 或 `AppColors.darkSurface`。
- 文本：主/次/弱文本分别使用 `AppColors.textPrimaryFor(context)`、`textSecondaryFor`、`textTertiaryFor`，避免 `Colors.white54/38/24` 造成灰字发糊。
- 分割线：深色使用 `AppColors.darkDivider`，避免 `Colors.white12` 弱到看不见。
- 输入与控件：输入框、Switch、Checkbox、Tab、RefreshIndicator 使用深色强调色，避免黑色主色在黑底消失。
- 弹窗/底部弹层：统一跟随主题的 `dialogTheme`、`bottomSheetTheme`，局部硬编码白底要替换。

## 路由入口覆盖

- `/home` 首页/会话列表
- `/contacts` 通讯录与新增联系人
- `/portal` 门户/WebView
- `/discover` 发现页
- `/discover/square` 朋友圈/动态
- `/settings` 设置首页与资料、聊天、个性化、隐私、通知、设备、存储、FAQ、拉黑、贴纸
- `/chat/:chatId` 聊天详情
- `/channel/:channelId` 频道详情
- `/search` 搜索
- `/group/edit/:chatId` 群编辑
- `/user/:userId` 用户资料
- `/group/:groupId/profile` 群资料
- `/channel/:channelId/profile` 频道资料
- `/scan` 扫码
- `/search-users` 新联系人
- `/call` 通话
- `/meeting/:meetingId` 会议
- `/wallet` 钱包与充值、提现、交易、支付结果、支付密码
- `/vip` VIP 会员中心
- `/vip/orders` VIP 购买记录
- `/login`、`/register`、`/forgot-password`、`/bind-phone`

## 模块清单

| 优先级 | 模块/页面 | 主要文件 | 静态风险 | 改造状态 | 验证 |
| --- | --- | --- | --- | --- | --- |
| P0 | 全局主题 | `lib/core/theme/app_colors.dart`, `lib/core/theme/app_theme.dart` | 已有深色 token，但页面大量绕开 token | 已部分完成，继续补缺 | targeted analyze |
| P0 | VIP 会员中心 | `lib/features/vip/pages/vip_center_page.dart` | 黑卡片、弱灰字、主色价格/操作在深色不可读 | 已完成第一批 | `dart analyze` 通过，截图 `tmp-dark-vip-20260626.png` |
| P0 | VIP 订单 | `lib/features/vip/pages/vip_orders_page.dart` | 黑卡片、弱灰字、RefreshIndicator 主色 | 已完成第一批 | `dart analyze` 通过，待截图 |
| P0 | 钱包首页 | `lib/features/wallet/pages/wallet_page.dart` | 多处白底/浅灰容器、深色文字层级不统一 | 已完成第一批 | `dart analyze` 通过，截图 `tmp-dark-wallet-20260626.png` |
| P0 | 充值/提现/转账/红包 | `lib/features/wallet/pages/*.dart`, `lib/features/wallet/widgets/*.dart` | 输入框、金额卡片、密码弹窗、二维码白底需要区分处理 | 已完成金额/密码弹层第一批，页面待继续 | `dart analyze` 通过，待截图 |
| P0 | 设置首页 | `lib/features/settings/pages/settings_page.dart` | 列表容器/图标色/分割线可能仍沿用浅色方案 | 已完成第一批 | `dart analyze` 通过，截图 `tmp-dark-settings-20260626.png` |
| P0 | 设置子页 | `lib/features/settings/pages/*_page.dart` | Switch、输入项、底部弹层、空态弱对比 | 已完成聊天设置公共组件第一批，其他子页待继续 | `dart analyze` 通过，待截图 |
| P0 | 用户资料 | `lib/features/chat/pages/user_profile_page.dart` | 大文件，多处 `AppColors.primary`、白底按钮、弱灰字 | 已完成 P0-2 | `dart analyze` 通过，APK 已安装，待补用户资料截图 |
| P0 | 群资料 | `lib/features/chat/pages/group_profile_page.dart` | 已初改，仍需二次扫硬编码白底/主色 | 已完成 P0-2 | `dart analyze` 通过，截图 `tmp-dark-p0-group-profile-20260626.png` |
| P0 | 频道资料 | `lib/features/chat/pages/channel_profile_page.dart` | 与群资料类似，`iconColor: AppColors.primary`、Switch 主色 | 已完成 P0-2 | `dart analyze` 通过，截图 `tmp-dark-p0-channel-chat-20260626.png` |
| P0 | 聊天列表/详情 | `lib/features/chat/pages/chat_page.dart`, `chat_detail_*`, `chat/widgets/*` | 已初改，仍有菜单、选择态、媒体气泡残留主色 | 已完成 P0-3 第一批 | `dart analyze` 通过，截图 `tmp-dark-p0-chat-list-final-20260626.png`、`tmp-dark-p0-chat-detail-final-20260626.png` |
| P1 | 搜索/收藏/分组编辑 | `lib/features/chat/pages/search_page.dart`, `favorite_messages_page.dart`, `folder_edit_page.dart`, `group_edit_page.dart` | 搜索框、Chip、Switch、空态、操作按钮主色 | 已完成 | `dart analyze` 通过，截图 `tmp-dark-p1-search-20260626.png` |
| P1 | 通讯录/新增联系人 | `lib/features/contacts/pages/*.dart` | 列表、搜索、联系人目录浅色容器 | 已完成 | `dart analyze` 通过，截图 `tmp-dark-p1-contacts2-20260626.png` |
| P1 | 朋友圈/动态 | `lib/features/moments/pages/moments_page.dart` | 单文件超大，硬编码主色/白色/弹层较多 | 已完成第一批 | `dart analyze` 通过，截图 `tmp-dark-p1-moments-20260626.png` |
| P1 | 登录/注册/找回/绑手机 | `lib/features/auth/pages/*.dart`, `lib/features/settings/pages/bind_phone_page.dart` | 登录页有白底按钮，协议弹窗/输入框需复核 | 已完成第一批 | `dart analyze` 通过，绑手机/协议/注册边框按静态覆盖 |
| P1 | 扫码 | `lib/features/chat/pages/qr_scanner_page.dart` | 扫码结果/说明卡片主色与弱灰字 | 已完成第一批 | `dart analyze` 通过，扫码结果弹层按静态覆盖 |
| P2 | 发现/门户 | `lib/features/discover/pages/discover_page.dart`, `lib/features/portal/pages/*.dart` | 卡片与 WebView 外壳浅色风险 | 待处理 | 页面截图 |
| P2 | 通话/会议 | `lib/features/call/pages/*.dart`, `lib/features/meeting/pages/*.dart` | 全屏深色本身较多，弹层/控制条需复核 | 待处理 | 通话/会议截图 |
| P2 | 共享组件 | `lib/shared/widgets/*.dart` | 空态、链接预览、浏览器、桌面布局硬编码色 | 待处理 | 冒烟覆盖 |

## P0 / P1 / P2 执行定义

- P0：主链路和用户高频可见页面。包含已反馈的 VIP、钱包、设置、聊天、个人/群/频道资料。P0 每批都需要 `dart analyze`、构建安装、模拟器深色截图。
- P1：高频功能页，但不是首屏或支付/VIP强链路。包含搜索、通讯录、朋友圈、登录注册、扫码。P1 每批至少需要 `dart analyze` 和关键页面截图。
- P2：低频或独立能力。包含发现/门户、通话会议、共享组件边角。P2 可按模块收尾，验证以冒烟和截图为主。

## 分批处理顺序

1. P0-1：全局主题、VIP、钱包、设置首页/聊天设置公共组件。已完成第一批。
2. P0-2：用户资料、群资料、频道资料。
3. P0-3：聊天列表/详情残留菜单、选择态、媒体气泡。已完成第一批。
4. P1-1：搜索、收藏、分组编辑、通讯录。已完成。
5. P1-2：朋友圈、登录注册找回、绑手机、扫码。已完成第一批。
6. P2-1：发现/门户、通话会议、共享组件收尾。

## 验证记录

- 已执行：`dart format lib/core/theme/app_colors.dart lib/features/vip/pages/vip_center_page.dart lib/features/vip/pages/vip_orders_page.dart lib/features/wallet/pages/wallet_page.dart lib/features/wallet/widgets/amount_input.dart lib/features/wallet/widgets/pay_password_input.dart`
- 已执行：`dart analyze lib/core/theme/app_colors.dart lib/features/vip/pages/vip_center_page.dart lib/features/vip/pages/vip_orders_page.dart lib/features/wallet/pages/wallet_page.dart lib/features/wallet/widgets/amount_input.dart lib/features/wallet/widgets/pay_password_input.dart`，结果 `No issues found!`
- 已执行：`dart format lib/features/settings/pages/settings_page.dart lib/features/settings/pages/chat_settings_page.dart`
- 已执行：`dart analyze lib/features/settings/pages/settings_page.dart lib/features/settings/pages/chat_settings_page.dart`，结果 `No issues found!`
- 已执行：`dart format lib/features/chat/pages/user_profile_page.dart lib/features/chat/pages/group_profile_page.dart lib/features/chat/pages/channel_profile_page.dart`
- 已执行：`dart analyze lib/features/chat/pages/user_profile_page.dart lib/features/chat/pages/group_profile_page.dart lib/features/chat/pages/channel_profile_page.dart`，结果 `No issues found!`
- 已执行：P0-2 二次补漏，修复频道资料 `@demo_official`、资料页操作表、共享媒体列表、成员/订阅者搜索与角色标识在深色下使用浅色主色发黑的问题。
- 已执行：P0-2 二次 `dart format lib/features/chat/pages/user_profile_page.dart lib/features/chat/pages/group_profile_page.dart lib/features/chat/pages/channel_profile_page.dart`
- 已执行：P0-2 二次 `dart analyze lib/features/chat/pages/user_profile_page.dart lib/features/chat/pages/group_profile_page.dart lib/features/chat/pages/channel_profile_page.dart`，结果 `No issues found!`
- 已执行：`scripts/build-local-emulator-apk.ps1`，产物 `artifacts/local-emulator-apk-20260626-222558/genericim-local-emulator-release.apk`，SHA256 `BADC932856CE791E225F25197BD0BDF307B73E665D08A38B85BCF82364FBCDA4`
- 已执行：P0-2 二次 `scripts/build-local-emulator-apk.ps1`，产物 `artifacts/local-emulator-apk-20260626-230313/genericim-local-emulator-release.apk`，SHA256 `E63E04915E366DCC2938822BBA7EC87357676A8BD0B6B51615EFB117A829E07A`
- 已执行：模拟器 `emulator-5554` 切换深色，`cmd uimode night` 返回 `Night mode: yes`
- 已执行：安装 APK 到 `emulator-5554`，安装结果 `Success`
- 已执行：P0-2 二次安装 APK 到 `emulator-5554`，安装结果 `Success`
- 已执行：截图抽查 `tmp-dark-current-20260626.png`、`tmp-dark-settings-20260626.png`、`tmp-dark-vip-20260626.png`、`tmp-dark-wallet-20260626.png`
- 已执行：P0-2 频道资料截图 `tmp-dark-p0-channel-chat-20260626.png`，`@demo_official` 已从黑色修正为深色可读链接蓝。
- 已执行：P0-3 `dart format lib/features/chat/pages/chat_page.dart lib/features/chat/pages/chat_detail_build.dart lib/features/chat/pages/chat_detail_message_list_helpers.dart lib/features/chat/pages/chat_detail_media_file_actions.dart lib/features/chat/widgets/chat_list_item.dart lib/features/chat/widgets/chat_input_bar.dart lib/features/chat/widgets/emoji_picker.dart lib/features/chat/widgets/message_bubble_voice.dart lib/features/chat/widgets/message_context_menu.dart`
- 已执行：P0-3 `dart analyze lib/features/chat/pages/chat_page.dart lib/features/chat/pages/chat_detail_page.dart lib/features/chat/pages/chat_detail_build.dart lib/features/chat/pages/chat_detail_message_list_helpers.dart lib/features/chat/pages/chat_detail_media_file_actions.dart lib/features/chat/widgets/chat_list_item.dart lib/features/chat/widgets/chat_input_bar.dart lib/features/chat/widgets/emoji_picker.dart lib/features/chat/widgets/message_bubble_voice.dart lib/features/chat/widgets/message_context_menu.dart`，结果 `No issues found!`
- 已执行：P0-3 修复聊天列表群聊标题在深色下固定红色、聊天列表右键菜单旧深灰、消息长按菜单旧深灰、输入栏/表情面板激活主色、语音气泡主色、聊天详情空态文字、删除弹层/批量选择按钮/文件超限提示等深色可读性问题。
- 已执行：P0-3 `scripts/build-local-emulator-apk.ps1`，最终产物 `artifacts/local-emulator-apk-20260626-231834/genericim-local-emulator-release.apk`，SHA256 `3862C709B2BDA028FFA77943F5450E48D5895249F1F2F464FB11A8A8E001F138`
- 已执行：P0-3 最终安装 APK 到 `emulator-5554`，安装结果 `Success`，`cmd uimode night` 返回 `Night mode: yes`
- 已执行：P0-3 最终截图 `tmp-dark-p0-chat-list-final-20260626.png`、`tmp-dark-p0-chat-detail-final-20260626.png`；聊天列表群聊标题、搜索框、底部导航、聊天详情空态、输入栏、置顶消息卡片均可读。
- 已执行：P1-1 `dart format lib/features/chat/pages/search_page.dart lib/features/chat/pages/favorite_messages_page.dart lib/features/chat/pages/folder_edit_page.dart lib/features/chat/pages/group_edit_page.dart lib/features/contacts/pages/contacts_page.dart lib/features/contacts/pages/new_contact_page.dart`
- 已执行：P1-1 `dart analyze lib/features/chat/pages/search_page.dart lib/features/chat/pages/favorite_messages_page.dart lib/features/chat/pages/folder_edit_page.dart lib/features/chat/pages/group_edit_page.dart lib/features/contacts/pages/contacts_page.dart lib/features/contacts/pages/new_contact_page.dart`，结果 `No issues found!`
- 已执行：P1-1 修复搜索、收藏消息、分组编辑、群编辑、通讯录、新增联系人里的深色弱灰字、旧主色、输入框和卡片背景残留。
- 已执行：P1-2 `dart format lib/features/moments/pages/moments_page.dart lib/features/auth/pages/agreement_page.dart lib/features/auth/pages/forgot_password_page.dart lib/features/auth/pages/login_page.dart lib/features/auth/pages/register_page.dart lib/features/settings/pages/bind_phone_page.dart lib/features/chat/pages/qr_scanner_page.dart`
- 已执行：P1-2 `dart analyze lib/features/moments/pages/moments_page.dart lib/features/auth/pages/agreement_page.dart lib/features/auth/pages/forgot_password_page.dart lib/features/auth/pages/login_page.dart lib/features/auth/pages/register_page.dart lib/features/settings/pages/bind_phone_page.dart lib/features/chat/pages/qr_scanner_page.dart`，结果 `No issues found!`
- 已执行：P1 全量目标文件 `dart analyze lib/features/chat/pages/search_page.dart lib/features/chat/pages/favorite_messages_page.dart lib/features/chat/pages/folder_edit_page.dart lib/features/chat/pages/group_edit_page.dart lib/features/contacts/pages/contacts_page.dart lib/features/contacts/pages/new_contact_page.dart lib/features/moments/pages/moments_page.dart lib/features/auth/pages/agreement_page.dart lib/features/auth/pages/forgot_password_page.dart lib/features/auth/pages/login_page.dart lib/features/auth/pages/register_page.dart lib/features/settings/pages/bind_phone_page.dart lib/features/chat/pages/qr_scanner_page.dart`，结果 `No issues found!`
- 已执行：P1-2 修复朋友圈首页/卡片/发布页/可见性弹层/话题选择/搜索/通知、登录注册协议边框、绑手机头部卡片、扫码结果弹层的深色 token 使用。
- 已执行：P1 `scripts/build-local-emulator-apk.ps1`，产物 `artifacts/local-emulator-apk-20260626-234243/genericim-local-emulator-release.apk`，SHA256 `F342C7936208687BD71DC2C51B3B8E0153BF23138DB1194367996AC7A9137A39`
- 已执行：P1 APK 安装到 `emulator-5554`，安装结果 `Success`，`cmd uimode night` 返回 `Night mode: yes`
- 已执行：P1 深色截图 `tmp-dark-p1-contacts2-20260626.png`、`tmp-dark-p1-moments-20260626.png`、`tmp-dark-p1-search-20260626.png`；联系人列表、朋友圈广场卡片、全局搜索空态和输入框均可读。
- 已执行：用户截图补漏，修复 `lib/features/discover/pages/discover_page.dart` 中发现页入口图标仍使用黑色主色的问题；修复 `lib/features/chat/widgets/create_sheets.dart` 中新建群组/频道相机、公开/私密类型、选择成员标题和勾选控件仍使用浅色主色或 `lightText*` 的问题。
- 已执行：补漏 `dart format lib/features/discover/pages/discover_page.dart lib/features/chat/widgets/create_sheets.dart`
- 已执行：补漏 `dart analyze lib/features/discover/pages/discover_page.dart lib/features/chat/widgets/create_sheets.dart`，结果 `No issues found!`
- 已新增：全量硬编码风险扫描脚本 `scripts/scan-dark-mode-risk.ps1`，输出 `docs/dark-mode-risk-scan-20260626.md`。当前扫描结果 `MustReview=1393`、`LikelyAllowed=467`，后续不能再只按截图逐点修，必须按扫描报告继续收敛。
