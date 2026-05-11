# Shorebird 不重装补丁 SOP

适用场景：

- 只改了 `lib/**` 里的 Dart 代码
- 不改 `android/**`
- 不改 `ios/**`
- 不改权限、签名、包名、原生插件
- 希望用户不用重装，下载补丁后下次重启生效

## 1. 先确认一个前提

Shorebird 补丁不是对任意 Flutter 安装包都生效。

前提必须满足：

- 线上用户当前安装的基础包，必须是 `shorebird release` 构建出来的包

如果你当前线上发出去的是普通：

```powershell
flutter build apk
```

那它不能直接吃 Shorebird 补丁。

## 2. 当前项目版本号怎么看

项目版本号来自根目录：

- [pubspec.yaml](e:\yi-xin-ai2k\pubspec.yaml)

例如：

```yaml
version: 4.0.1+10
```

这个版本号同时影响：

- Shorebird release version
- 后台补丁版本匹配
- 线上用户所属基础版本

## 3. 第一次接入 Shorebird 的正确顺序

如果现网还不是 Shorebird 包，先做一次基础版本替换：

1. 修改版本号，例如从 `4.0.1+10` 升到 `4.0.2+11`
2. 执行 Shorebird release
3. 把这个基础包发给用户安装
4. 之后才开始发 patch

示例：

```bash
shorebird release android
shorebird release ios
```

## 4. 什么时候可以直接发补丁

只有在下面条件同时成立时：

1. 改动只在 `lib/**`
2. 线上基础包已经是 Shorebird release 包

这时才直接发：

```bash
shorebird patch android --track=stable
shorebird patch ios --track=stable
```

## 5. 当前项目里的渠道规则

这套项目里：

- 客户端补丁检查默认走 `stable`
- 后台 `channel` 会映射到 Shorebird `track`

所以最稳妥的做法是：

- Shorebird patch 用 `stable`
- 后台补丁记录 `channel` 也填 `stable`

如果你发的是：

```bash
shorebird patch android --track=staging
```

但后台补丁还是 `stable`，或者客户端没有切到 `staging`，那就不会按预期生效。

## 6. 标准发布步骤

### 6.1 改代码

只改 `lib/**`。

### 6.2 发补丁

```bash
shorebird patch android --track=stable
shorebird patch ios --track=stable
```

### 6.3 在后台新建补丁记录

虽然 Shorebird 补丁已经发出，但你这套项目仍然必须在后台建一条补丁记录，因为客户端先走你的后端灰度判断。

推荐填写：

- `投递模式`：`shorebird`
- `平台`：`android` 或 `ios`
- `渠道`：`stable`
- `补丁版本`：例如 `4.0.2+11-p1`
- `补丁地址`：留空
- `补丁哈希`：留空
- `灰度比例`：建议先 `5` 或 `10`
- `强制补丁`：按需

## 7. 客户端实际表现

当前项目里的 Shorebird 行为：

1. App 启动请求 `/app/hot-update/check`
2. 后端判断平台、版本、灰度、是否已装过
3. 如果命中且客户端支持 Shorebird，则继续应用
4. 客户端检查 Shorebird update
5. 下载补丁
6. 下次重启生效
7. 上报 `install_started / install_confirmed / apply_success / apply_failed`

说明：

- 用户拒绝可选更新时，会记录 `deferred`
- 已安装成功的补丁不会重复下发

## 8. staging 灰度建议

如果你要先测再放量，可以这样：

```bash
shorebird patch android --track=staging
shorebird patch ios --track=staging
```

测试通过后，再切到 `stable`。

示例：

```bash
shorebird patches set-track --release-version 4.0.1+10 --patch-number 1 --track stable
```

## 9. 什么时候不能走 Shorebird

以下任何一种都不能走：

- 改了 `android/**`
- 改了 `ios/**`
- 改了插件原生层
- 改了权限
- 改了 Firebase / 推送 /原生 SDK 配置
- 改了签名、包名、渠道包

这时要改走：

- `self_hosted`
- 或重新发商店包

## 10. 常见错误

- 用普通 `flutter build` 发出去的包，想直接吃 Shorebird patch
- 后台没建 `shorebird` 补丁记录
- 后台 `channel` 和 Shorebird `track` 不一致
- 改了原生代码还继续发 Shorebird patch
- 以为补丁下载后立刻生效，实际上当前逻辑是下次重启生效

## 11. 这条链路需要重新部署什么

- 只改 `lib/**` 且现网已是 Shorebird 包：可以不重新安装客户端
- 改 `backend/**`：后端仍需重新编译并重启
- 改 `admin/**`：后台仍需重新构建部署
- 改 `android/**` / `ios/**`：不能只发补丁，必须重新发包
