# 安卓整包更新 SOP

适用场景：

- 改了 `android/**`
- 改了原生权限、签名、包名、插件
- 当前线上安装包不是 Shorebird release 包
- 需要让用户下载安装新的 APK

## 1. 发布前判断

满足以下任一情况，直接走整包更新，不走 Shorebird：

- 改动不只在 `lib/**`
- 需要修改 Android 原生代码或 Gradle 配置
- 需要新增或调整权限
- 需要更换三方原生 SDK

## 2. 构建 APK

项目当前常用命令：

```powershell
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols
```

构建产物：

- APK：`build/app/outputs/flutter-apk/app-release.apk`
- 混淆符号：`build/app/outputs/symbols`

## 3. 准备下载地址

把 `app-release.apk` 上传到可直接下载的 HTTPS 地址。

要求：

- 必须是 APK 直链
- 不要填下载页地址
- 建议文件名带版本号

示例：

```text
https://cdn.example.com/genericim/android/4.0.1+10/app-release.apk
```

## 4. 计算哈希

建议生成 `sha256`，填到后台用于客户端校验。

PowerShell 示例：

```powershell
Get-FileHash .\build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256
```

后台填写格式建议：

```text
sha256:这里填64位小写哈希
```

## 5. 后台新建补丁

后台页面：

- `系统 -> 热更新补丁`

推荐填写：

- `投递模式`：`self_hosted`
- `平台`：`android`
- `渠道`：`stable`
- `补丁版本`：例如 `4.0.1+10-selfhosted-20260511.1`
- `补丁地址`：APK 直链
- `补丁哈希`：`sha256:...`
- `目标版本`：可选
- `App 版本范围 / Build 范围`：按需控制
- `灰度比例`：建议先 `5` 或 `10`
- `强制补丁`：按需开启

注意：

- `self_hosted` 不能选 `全平台`
- Android 和 iOS 要分别建补丁

## 6. 发布顺序

推荐顺序：

1. 后端服务已部署到最新
2. 后台前端已部署到最新
3. 上传 APK 到 CDN
4. 后台新建补丁
5. 先小灰度发布
6. 观察上报记录
7. 没问题后再扩大到 `100%`

## 7. 客户端实际表现

当前项目里的安卓整包更新行为：

1. App 启动请求 `/app/hot-update/check`
2. 后端命中补丁后返回 `self_hosted` 记录
3. 客户端弹窗提示更新
4. 用户确认后下载 APK
5. 校验哈希
6. 拉起系统安装器
7. 客户端上报 `install_started / install_confirmed / apply_failed`

## 8. 发布后检查

重点看后台上报：

- `check_hit`：命中补丁
- `deferred`：用户暂缓
- `install_started`：已开始安装
- `install_confirmed`：已确认安装完成
- `apply_failed`：安装失败

## 9. 常见错误

- 把下载页地址当成 APK 直链
- 后台选成 `shorebird`
- 同一条补丁同时给 Android 和 iOS 共用
- 版本范围没填对，导致旧包/新包都命中异常
- 忘了上传新 APK 就直接发布补丁

## 10. 这条链路需要重新部署什么

- 改 `backend/**`：后端要重新编译并重启
- 改 `admin/**`：后台要重新构建部署
- 改 `lib/**` 但本次选择整包更新：客户端仍需重新发 APK
- 改 `android/**`：必须重新发 APK
