# Shorebird 不重装补丁 SOP

这套热更新是 App 程序层面的热更新：针对 Flutter/Dart UI 和业务逻辑发补丁，让用户不需要重新安装 APK。

它不是后端热更新，也不是万能替代 APK。第一次必须让用户安装一个由 `shorebird release` 构建出来的基线包；之后同一个基线版本上的 Dart/UI 修复，才可以通过 `shorebird patch` 下发。

## 能热更新什么

可以走 Shorebird 补丁：

- `lib/**` 里的 Dart 页面、状态、交互、业务逻辑
- 不涉及原生工程、不涉及新资源文件的 UI 调整
- 当前 App 已安装的是同一版本的 Shorebird 基线包

不能只发 Shorebird 补丁：

- 修改 `android/**`、`ios/**`、Gradle、Kotlin、Swift、权限、签名、包名
- 修改原生插件、推送 SDK、Firebase/HMS/Xiaomi/OPPO 等原生配置
- 新增或替换需要打进 APK 的 assets、字体、图标、启动图
- 升级 Flutter SDK、NDK、minSdk、targetSdk 等构建链路

这些情况仍然要重新发 APK 或走整包更新。

## 当前项目状态

- Shorebird 配置文件：`shorebird.yaml`
- Shorebird app id：交付方自行创建并填写
- Flutter SDK 依赖：`shorebird_code_push`
- App 启动时会请求后端：`/app/hot-update/check`
- 后台补丁投递模式支持：`delivery_mode=shorebird`
- 当前版本来自 `pubspec.yaml`：`4.0.3+14`

客户端已经由 App 层控制补丁检查和安装时机，`shorebird.yaml` 里保持 `auto_update: false` 是正确的。

## 本机工具链

Shorebird CLI 已安装在：

```powershell
<USER_HOME>\.shorebird\bin\shorebird.bat
```

当前用户 PATH 已加入：

```powershell
<USER_HOME>\.shorebird\bin
```

如果新开的终端仍识别不到 `shorebird`，先重新打开 PowerShell，或临时执行：

```powershell
$env:Path="$HOME\.shorebird\bin;$env:Path"
```

国内网络下 `pub.dev` 可能 TLS 失败，脚本默认使用：

```powershell
PUB_HOSTED_URL=https://pub.flutter-io.cn
```

## 第一次接入：发基线 APK

如果用户当前安装的不是 Shorebird 基线包，必须先发一次基线 APK。以后才可以不重装发补丁。

本地开发/模拟器联调用：

```powershell
.\scripts\shorebird-release-android.ps1 -Artifact apk
```

线上正式包要显式传生产地址，例如：

```powershell
.\scripts\shorebird-release-android.ps1 `
  -Artifact apk `
  -ServerUrl "https://imapi.example.com" `
  -WsUrl "wss://imapi.example.com/api/v1/ws"
```

如果只想看命令不真正上传：

```powershell
.\scripts\shorebird-release-android.ps1 -PrintOnly
```

基线包成功后，把生成的 APK 安装/分发给用户一次。普通 `flutter build apk` 构建出来的包不能吃 Shorebird 补丁。

## 后续更新：发补丁

只改 Dart/UI 时，发 Android 补丁：

```powershell
.\scripts\shorebird-patch-android.ps1 -Track stable
```

线上正式补丁同样要带和基线包一致的接口地址：

```powershell
.\scripts\shorebird-patch-android.ps1 `
  -ReleaseVersion "4.0.3+14" `
  -Track stable `
  -ServerUrl "https://imapi.example.com" `
  -WsUrl "wss://imapi.example.com/api/v1/ws"
```

先灰度测试可以发到 `staging`：

```powershell
.\scripts\shorebird-patch-android.ps1 -ReleaseVersion "4.0.3+14" -Track staging
```

补丁下载后通常要下次重启 App 才生效。

## 后台补丁记录

Shorebird 补丁上传成功后，还要在后台热更新管理里建一条记录。因为 App 先走自己的后端灰度判断，再触发 Shorebird SDK 拉取。

推荐字段：

- 投递模式：`shorebird`
- 平台：`android`
- 渠道：和 Shorebird track 保持一致，例如 `stable`
- 最小 App 版本：`4.0.3+14`
- 最大 App 版本：`4.0.3+14`
- 最小 build number：`14`
- 最大 build number：`14`
- 目标 App 版本：`4.0.3+14`
- 补丁版本：例如 `4.0.3+14-p1`
- 补丁地址：留空
- 补丁哈希：留空
- 灰度比例：建议先 `5` 或 `10`
- 强制更新：按需要选择

后台发布后，App 启动会请求 `/app/hot-update/check`，命中后再由客户端调用 Shorebird SDK 下载补丁。

## 常见错误

- 用普通 `flutter build apk` 的包尝试接 Shorebird 补丁
- 没有在后台建 `delivery_mode=shorebird` 的补丁记录
- 后台 `channel` 和 Shorebird `track` 不一致
- 改了 Android/iOS 原生代码还继续发 patch
- 以为下载后立即生效，实际一般需要重启 App
- 基线包和补丁使用了不同的 `GENERIC_IM_SERVER_URL` / `GENERIC_IM_WS_URL`

## 当前阻塞项

本机 `shorebird --version` 已通过，`shorebird doctor` 可运行。当前网络对 `api.shorebird.dev` 和 `oauth2.googleapis.com` 不稳定或不可达，所以真实 `shorebird login`、`shorebird release`、`shorebird patch` 可能会被登录或上传阶段挡住。

另外，`git config --system core.longpaths true` 需要管理员权限；当前已设置用户级 `core.longpaths=true`，但 Shorebird 仍可能提示系统级 long paths 警告。这个警告不等于脚本不能运行，后续如遇 Windows 长路径错误，再用管理员 PowerShell 执行系统级配置。
