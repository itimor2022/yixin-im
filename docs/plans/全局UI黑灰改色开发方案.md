# 全局 UI 黑灰高级配色改造开发方案

## 1. 目标

将当前全局偏紫色的 UI 视觉体系统一调整为黑色、石墨灰、中性灰为主的高级质感配色。

本次改造不是简单把所有颜色改成纯黑，而是建立统一的品牌主色、背景层级、文字层级、边框层级和图片资源规范，保证 App、H5、后台和资源素材视觉一致。

## 2. 改造原则

1. 主品牌色从紫色切换为石墨黑。
2. 页面背景、卡片、弹窗、输入框使用灰阶层级，不使用大面积纯黑压平界面。
3. 成功、警告、错误、红包、转账、在线状态等业务语义色保留，不强行改黑。
4. 所有紫色装饰、选中态、按钮、图标高亮、渐变背景、活动态统一替换为黑灰体系。
5. PNG 小图标可以批量重染，复杂图片、Logo、启动图、应用图标需要单独导出确认。
6. 修改必须覆盖 Flutter 主端、Flutter Web、H5、admin 后台、admin-kf 后台，避免只改一端导致视觉不一致。
7. 每个阶段修改后必须运行对应构建或静态检查，截图核对关键页面。

## 3. 全局配色规范

### 3.1 品牌主色

| 用途 | 色值 | 说明 |
| --- | --- | --- |
| Primary | `#111827` | 主按钮、主图标、选中态、品牌高亮 |
| Primary Hover | `#374151` | Web/H5/后台悬停态 |
| Primary Pressed | `#030712` | 按下态、强强调 |
| Primary Soft | `rgba(17, 24, 39, 0.10)` | 浅色模式弱高亮背景 |
| Primary Soft Dark | `rgba(249, 250, 251, 0.10)` | 深色模式弱高亮背景 |

### 3.2 主渐变

| 用途 | 色值 |
| --- | --- |
| 标准品牌渐变 | `linear-gradient(135deg, #111827, #3F3F46)` |
| 深色品牌渐变 | `linear-gradient(135deg, #020617, #27272A)` |
| 弱背景渐变 | `linear-gradient(180deg, #F8FAFC, #F3F4F6)` |

### 3.3 浅色模式

| 用途 | 色值 |
| --- | --- |
| 页面背景 | `#F6F7F9` |
| 主卡片 | `#FFFFFF` |
| 次级卡片 | `#FAFAFA` |
| 输入框背景 | `#F1F2F4` |
| 分割线/边框 | `#E5E7EB` |
| 主文字 | `#111827` |
| 次文字 | `#6B7280` |
| 弱文字 | `#9CA3AF` |

### 3.4 深色模式

| 用途 | 色值 |
| --- | --- |
| 页面背景 | `#050505` |
| 页面层 | `#0B0B0C` |
| 主卡片 | `#111113` |
| 次级卡片 | `#18181B` |
| 输入框背景 | `#1F1F23` |
| 分割线/边框 | `#2A2A2E` |
| 主文字 | `#F9FAFB` |
| 次文字 | `#A1A1AA` |
| 弱文字 | `#71717A` |

### 3.5 保留业务语义色

以下颜色不纳入黑灰替换范围，只做必要的明暗适配：

| 类型 | 建议色值 | 说明 |
| --- | --- | --- |
| 成功/在线 | `#22C55E` | 在线、成功、通过 |
| 警告 | `#F59E0B` | 待处理、警告、提醒 |
| 错误/删除 | `#EF4444` | 删除、失败、危险操作 |
| 信息 | `#2563EB` | 可保留为弱蓝，用于少量信息提示 |
| 红包 | `#E84C3D` | 红包业务视觉保留 |
| 转账 | `#F59E0B` 或现有业务色 | 转账业务视觉保留 |

## 4. 代码改造范围

### 4.1 Flutter 主端

重点文件：

- `lib/core/theme/app_colors.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/theme_provider.dart`
- `lib/features/**`
- `lib/shared/widgets/**`

优先修改：

1. `AppColors.primary`
2. `AppColors.primaryLight`
3. `AppColors.primaryDark`
4. `AppColors.primaryGradient`
5. `ThemeData.colorScheme`
6. `BottomNavigationBarThemeData.selectedItemColor`
7. `AppBarTheme.iconTheme`
8. `ElevatedButtonThemeData`
9. `TextButtonThemeData`
10. 页面内硬编码紫色、蓝紫渐变

需要扫描的关键词：

```text
AppColors.primary
Colors.purple
Colors.indigo
0xFF6366F1
0xFF818CF8
0xFF4F46E5
0xFF8B5CF6
0xFF667EEA
0xFF764BA2
```

Flutter 替换建议：

```dart
static const Color primary = Color(0xFF111827);
static const Color primaryLight = Color(0xFF374151);
static const Color primaryDark = Color(0xFF030712);

static const LinearGradient primaryGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF111827), Color(0xFF3F3F46)],
);
```

聊天背景预设中带明显紫色、粉紫、蓝紫的渐变需要替换为灰阶、蓝灰或低饱和商务色。

### 4.2 H5 端

重点文件：

- `h5/src/styles.css`
- `h5/src/views/*.vue`
- `h5/public/assets/icons/*`

优先修改 CSS 变量：

```css
:root {
  --app-primary: #111827;
  --app-primary-dark: #030712;
  --app-primary-soft: rgba(17, 24, 39, 0.1);
}
```

需要扫描的关键词：

```text
#6366f1
#8b5cf6
#7c3aed
#4f46e5
#af52de
#5856d6
purple
indigo
linear-gradient(135deg
```

替换策略：

1. 页面头像默认渐变改为 `#111827 -> #3F3F46`。
2. 主按钮渐变改为黑灰渐变。
3. 设置页、资料页、发现页的紫色功能图标改成灰黑、蓝灰或保留业务语义色。
4. tab active 图标替换成黑色版本。

### 4.3 Admin 后台

重点文件：

- `admin/src/config/index.ts`
- `admin/src/config/setting.ts`
- `admin/src/assets/styles/core/tailwind.css`
- `admin/src/components/core/views/login/LoginLeftView.vue`
- `admin/src/views/**/*.vue`

后台主色改造：

```ts
systemMainColor: [
  '#111827',
  '#374151',
  '#52525B',
  '#2563EB',
  '#22C55E',
  '#F59E0B',
  '#EF4444'
] as const
```

后台处理规则：

1. 默认主题色必须是 `#111827`。
2. 移除默认紫色主题入口。
3. Tailwind 中 `bg-purple-*`、`text-purple-*` 替换为 `bg-gray-*`、`text-gray-*` 或主题变量。
4. 登录页几何装饰中的 `square-purple` 改名或改色为 graphite。
5. 图表主色使用 `--el-color-primary`，避免硬编码紫色。

### 4.4 Admin-kf 后台

重点文件：

- `admin-kf/src/layouts/app-layout.vue`
- `admin-kf/src/views/**/*.vue`
- `admin-kf/src/styles/index.scss`

admin-kf 当前偏绿色较多，不属于紫色主问题，但需要跟随主品牌黑灰体系统一：

1. 品牌标识背景改黑灰渐变。
2. 主要按钮、状态外的强调色改为黑灰。
3. 成功状态、在线状态保留绿色。

## 5. 图片资源改造范围

### 5.1 必改资源

Flutter 资源：

- `assets/icons/tab_chat.png`
- `assets/icons/tab_chat_active.png`
- `assets/icons/tab_contacts.png`
- `assets/icons/tab_contacts_active.png`
- `assets/icons/tab_moments.png`
- `assets/icons/tab_moments_active.png`
- `assets/icons/tab_settings.png`
- `assets/icons/tab_settings_active.png`
- `assets/icons/group_profile/*.png`
- `assets/images/attachment_actions/*.png`

H5 资源：

- `h5/public/assets/icons/tab_*.png`
- `h5/public/assets/logo.png`

品牌和启动资源：

- `assets/logo.png`
- `assets/splash.png`
- `assets/brand/generic-im-icon.png`
- `assets/brand/generic-im-icon.svg`
- `assets/icon_foreground.png`
- `assets/图标/android/**`
- `assets/图标/ios/**`
- `assets/图标/web/**`

### 5.2 图片改色规则

| 类型 | 处理方式 |
| --- | --- |
| 单色 PNG 小图标 | 批量重染 |
| active tab 图标 | `#111827` |
| normal tab 图标 | `#8A8A8A` |
| 群资料小图标 | `#374151` 或 `#6B7280` |
| 附件操作图标 | 主体黑灰，红包/转账等业务图标可保留业务色 |
| SVG | 直接替换 fill/stroke 色值 |
| Logo | 单独导出黑灰版，不用简单滤镜覆盖 |
| 启动图 | 单独设计黑灰版，保证启动页品牌识别 |
| 应用图标 | 单独生成 Android/iOS/Web 全尺寸图标 |

### 5.3 不建议批量改色的资源

以下资源不建议直接批量重染：

- 用户头像
- 表情包
- Lottie 表情
- 红包贴纸
- 转账贴纸
- VIP/SVIP 徽章
- 业务截图类图片
- 第三方素材图片

这些资源有独立业务含义，强行改黑会降低识别度。

## 6. P0-P3 分阶段执行计划

### P0：全局色板和主端基础替换

目标：

先把紫色品牌主色从全局入口切换到黑灰体系，确保大部分按钮、导航、选中态、AppBar 图标和主题变量立即生效。

范围：

- Flutter `lib/core/theme/app_colors.dart`
- Flutter `lib/core/theme/app_theme.dart`
- Flutter `lib/core/theme/theme_provider.dart`
- H5 `h5/src/styles.css`
- Admin `admin/src/config/index.ts`
- Admin `admin/src/config/setting.ts`
- Admin `admin/src/assets/styles/core/tailwind.css`

必须完成：

1. Flutter `AppColors.primary`、`primaryLight`、`primaryDark`、`primaryGradient` 改为黑灰体系。
2. Flutter `ThemeData.colorScheme`、按钮、底部导航、AppBar 继承新主色。
3. H5 `--app-primary`、`--app-primary-dark`、`--app-primary-soft` 改为黑灰体系。
4. Admin `systemMainColor[0]` 默认改为 `#111827`。
5. Admin Element/Tailwind 主色变量跟随黑灰体系。

P0 验收：

- App 主按钮、底部导航选中态、AppBar 图标变为黑灰。
- H5 主按钮、导航、默认头像高亮变为黑灰。
- Admin 默认主题色为黑色。
- 不要求此阶段清完所有页面硬编码紫色。

P0 检查命令：

```powershell
flutter analyze
```

### P1：页面硬编码紫色清理

目标：

清理 Flutter、H5、Admin、Admin-kf 页面中散落的紫色、蓝紫渐变、Tailwind purple 类名，解决“全局改了但页面还紫”的问题。

范围：

- Flutter `lib/features/**`
- Flutter `lib/shared/widgets/**`
- H5 `h5/src/views/*.vue`
- Admin `admin/src/views/**/*.vue`
- Admin `admin/src/components/core/views/login/LoginLeftView.vue`
- Admin-kf `admin-kf/src/layouts/app-layout.vue`
- Admin-kf `admin-kf/src/views/**/*.vue`

必须完成：

1. 替换非业务用途的 `#6366f1`、`#8b5cf6`、`#7c3aed`、`#4f46e5`。
2. 替换 Flutter 内非业务用途的 `Colors.purple`、`Colors.indigo`、`0xFF6366F1` 等。
3. 替换 H5 头像、资料页、发现页、会议页中的紫色渐变。
4. 替换 Admin 中 `bg-purple-*`、`text-purple-*` 等 Tailwind 类。
5. Admin 登录页装饰中的 `square-purple` 改为 graphite 命名或黑灰配色。
6. Admin-kf 品牌区和主要强调色改为黑灰，成功/在线绿色保留。

P1 验收：

- 关键页面不再出现大面积紫色背景、紫色按钮、紫色选中态。
- 紫色扫描结果只剩允许豁免项。
- 业务语义色没有被误伤。

P1 扫描命令：

```powershell
rg -n "6366F1|6366f1|8B5CF6|8b5cf6|7C3AED|7c3aed|4F46E5|4f46e5|667EEA|667eea|764BA2|764ba2|purple|indigo" lib h5/src admin/src admin-kf/src
```

允许豁免：

- `purple_heart.json`
- 表情资源文件名
- 第三方库或示例文本
- 明确业务需要保留的彩色状态

P1 检查命令：

```powershell
flutter analyze
cd h5
npm run build
cd ..\admin
pnpm build
cd ..\admin-kf
pnpm build
```

### P2：小图片、图标、SVG 资源改色

目标：

把紫色小图片、tab active 图标、群资料图标、附件入口图标和 SVG 背景统一换成黑灰版本，解决代码改色后图片仍紫的问题。

范围：

- `assets/icons/tab_*.png`
- `assets/icons/group_profile/*.png`
- `assets/images/attachment_actions/*.png`
- `assets/images/backgrounds/*.svg`
- `assets/brand/generic-im-icon.svg`
- `h5/public/assets/icons/tab_*.png`
- `h5/public/assets/logo.png`

必须完成：

1. active tab 图标重染为 `#111827`。
2. normal tab 图标重染为 `#8A8A8A`。
3. 群资料小图标重染为 `#374151` 或 `#6B7280`。
4. 附件入口图标主体改为黑灰，红包/转账等业务图标可保留业务色。
5. SVG 内紫色 fill/stroke 替换为黑灰体系。
6. Flutter 和 H5 同类图标保持一致。

P2 验收：

- 小图标边缘无明显脏边、毛边。
- active/normal 状态一眼可区分。
- Flutter 和 H5 tab 图标视觉一致。
- 红包、转账、VIP 等业务识别图没有被错误黑化。

P2 检查：

- 启动 App 检查首页 tab、群资料页、聊天附件面板。
- 启动 H5 检查底部 tab、个人页、聊天页。
- 对 SVG 执行紫色关键词扫描。

### P3：品牌资源、全端构建和最终验收

目标：

处理 Logo、启动图、应用图标等品牌资产，完成全端构建和关键页面截图验收，形成可发布版本。

范围：

- `assets/logo.png`
- `assets/splash.png`
- `assets/icon_foreground.png`
- `assets/brand/generic-im-icon.png`
- `assets/图标/android/**`
- `assets/图标/ios/**`
- `assets/图标/web/**`
- `android/app/src/main/res/**/ic_launcher*.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/**`
- `web/icons/**`
- `pubspec.yaml` 的 `flutter_launcher_icons` 配置

必须完成：

1. Logo 单独导出黑灰新版，不用粗暴滤镜覆盖。
2. Splash 单独导出黑灰新版，保证启动页品牌识别。
3. Android/iOS/Web 应用图标全尺寸重新生成。
4. `flutter_launcher_icons` 的背景色和主题色同步为黑灰。
5. 全端构建或静态检查通过。
6. 关键页面截图确认无非业务紫色残留。

P3 验收构建命令：

```powershell
flutter analyze
flutter build apk --debug
flutter build web
cd h5
npm run build
cd ..\admin
pnpm build
cd ..\admin-kf
pnpm build
```

P3 截图验收页面：

1. 登录页
2. 注册页
3. 首页 tab
4. 聊天列表
5. 聊天详情
6. 通讯录
7. 发现页
8. 我的/设置
9. 用户资料页
10. 群资料页
11. 钱包页
12. 会议页
13. H5 首页和个人页
14. Admin 登录页
15. Admin 首页和系统设置页

P3 退出标准：

- 非业务用途紫色扫描无残留。
- 全端构建或静态检查通过。
- 关键页面截图通过。
- Logo、Splash、应用图标完成黑灰新版替换。
- 明确记录所有保留彩色资源的原因。

## 7. 风险和注意事项

1. 纯黑大面积使用会显得廉价，必须用灰阶建立层次。
2. 业务语义色不能全部改黑，否则用户无法区分成功、失败、警告、红包和转账。
3. 图片批量重染前需要备份或生成新文件，避免不可逆覆盖。
4. 应用图标、启动图、Logo 不能用简单滤镜粗暴处理，需要单独设计。
5. 当前仓库有未提交改动，改色实施时只能触碰配色和资源相关文件，不能覆盖聊天、会议、设置等已有功能改动。
6. 文件中存在部分中文注释乱码，改色时不要顺手大面积格式化，避免引入无关 diff。
7. H5 和 Flutter Web 不是同一套 UI，两个入口都要验证。
8. Admin 和 admin-kf 是两套后台，不能只改其中一个。

## 8. 完成标准

满足以下条件才算完成：

1. Flutter 主端全局主色、按钮、导航、选中态均为黑灰体系。
2. H5 全局变量和页面硬编码紫色清理完成。
3. Admin 默认主题色变为黑灰体系。
4. Admin-kf 主视觉跟随黑灰品牌色。
5. 小图标、tab 图标、群资料图标完成黑灰重染。
6. Logo、Splash、应用图标完成黑灰新版替换。
7. 紫色扫描结果只剩下表情、业务无关文件名或明确豁免项。
8. Flutter、H5、Admin、Admin-kf 构建或静态检查通过。
9. 关键页面截图确认无大面积紫色残留。

## 9. 建议最终视觉方向

最终视觉建议采用“石墨黑 + 中性灰 + 少量业务语义色”的设计方向：

- 主品牌识别靠黑灰，而不是紫色渐变。
- 页面质感靠层级、留白、边框和阴影，而不是高饱和颜色。
- 业务操作保持可识别颜色，避免全部黑化。
- 深色模式使用近黑背景和灰色卡片，不使用单一纯黑。
- 浅色模式使用干净灰白背景和黑色高亮，保持高级、克制、清晰。
