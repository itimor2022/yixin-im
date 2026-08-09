# Docker 一键部署教程（从 0 到 1 小白版）

本文只讲本项目推荐的线上部署方式：**本地生成预编译交付包，服务器上传解压后执行一条命令**。

部署完成后，Docker 会自动启动：

- MySQL 数据库
- MongoDB 消息数据库
- Redis 缓存
- Go 后端 API
- 运营管理后台
- Flutter Web/H5
- 官方客服后台

服务器不需要安装 Go、Node.js、Flutter，也不需要手工创建数据库。

> 一键部署是指：域名、Docker 和部署包准备好以后，服务器只执行 `sudo bash deploy-customer.sh`。域名解析、SSL 证书和上传部署包仍需要先完成。

## 一、先准备什么

### 1. 服务器

推荐配置：

- Ubuntu 22.04/24.04 64 位，或宝塔支持的主流 64 位 Linux。
- 最低 4 核 CPU、8 GB 内存、80 GB 磁盘。
- 推荐安装宝塔面板和宝塔 Nginx。
- 安全组放行 `22`、`80`、`443`。

数据库和程序容器端口只绑定 `127.0.0.1`，不需要在安全组放行 `13306`、`17017`、`16379`、`18080`、`18083`、`18084`、`18085`。

### 2. 四个域名

推荐准备四个不同的二级域名。下面用 `example.com` 举例，部署时必须换成自己的域名：

| 用途 | 示例域名 | Docker 本机端口 |
| --- | --- | --- |
| 后端接口、WebSocket、媒体 | `api.example.com` | `127.0.0.1:18080` |
| 运营管理后台 | `admin.example.com` | `127.0.0.1:18084` |
| Web/H5/PC 页面 | `h5.example.com` | `127.0.0.1:18083` |
| 官方客服后台 | `kf.example.com` | `127.0.0.1:18085` |

接口完整地址不是只写 `/api/v1`，而是：

```text
REST API：https://api.example.com/api/v1
WebSocket：wss://api.example.com/api/v1/ws
健康检查：https://api.example.com/health
```

### 3. 域名解析

进入域名服务商的 DNS 控制台，添加四条 `A` 记录，全部指向服务器公网 IP：

```text
api.example.com    -> 服务器公网 IP
admin.example.com  -> 服务器公网 IP
h5.example.com     -> 服务器公网 IP
kf.example.com     -> 服务器公网 IP
```

在自己电脑检查解析：

```powershell
nslookup api.example.com
nslookup admin.example.com
nslookup h5.example.com
nslookup kf.example.com
```

四个结果都显示服务器公网 IP 后再继续。

## 二、在本地生成一键部署包

这一步在保存源码的 Windows 电脑执行，不在 Linux 服务器执行。

### 1. 打开项目目录

打开 PowerShell 7：

```powershell
cd <PROJECT_ROOT>
```

### 2. 把示例域名替换成真实域名

下面是一整条打包命令。只修改四个域名、客户名称和管理员密码：

```powershell
.\scripts\build-online-prebuilt-package.ps1 `
  -CustomerName "客户名称" `
  -PackageName "genericim-docker-oneclick" `
  -ApiDomain "api.example.com" `
  -AdminDomain "admin.example.com" `
  -H5Domain "h5.example.com" `
  -KfDomain "kf.example.com" `
  -Scheme "https" `
  -InstallDir "/www/wwwroot/genericim" `
  -DefaultAdminPassword "请改成至少16位强密码"
```

脚本会自动完成前端、H5、客服端、Linux 后端的编译和打包。等待窗口出现 `[OK] Online prebuilt package created`。

生成结果位于：

```text
artifacts/genericim-docker-oneclick-日期时间.tar.gz
artifacts/genericim-docker-oneclick-日期时间.zip
```

Linux 服务器优先使用 `.tar.gz`。

> 接口域名必须在这里通过 `-ApiDomain` 写入，因为 Flutter Web/H5 会在编译时写入 API、WebSocket 和启动配置地址。以后正式更换接口域名，最稳妥的方法是用新域名重新执行这条命令，再部署新包。

### 3. App 也要连接同一个接口域名

Docker 部署包不包含 Android APK。需要 APK 时，在本地另执行：

```powershell
.\scripts\build-online-android-apk.ps1 `
  -ServerUrl "https://api.example.com" `
  -WsUrl "wss://api.example.com/api/v1/ws"
```

APK 输出到 `artifacts/online-android-apk-日期时间/`。

## 三、服务器安装 Docker

### 宝塔用户（推荐）

1. 登录宝塔面板。
2. 打开“软件商店”。
3. 搜索并安装“Docker”。
4. 确认 Docker 服务状态为“运行中”。

在宝塔终端执行：

```bash
docker version
docker compose version
```

两个命令都能显示版本号才算安装成功。

### Ubuntu 没有宝塔时

建议按 [Docker 官方 Ubuntu 安装文档](https://docs.docker.com/engine/install/ubuntu/)安装 Docker Engine 和 Compose 插件。安装后执行：

```bash
sudo systemctl enable --now docker
sudo docker run --rm hello-world
docker compose version
```

如果最后两个命令成功，再继续部署。

## 四、在宝塔创建站点和 SSL

在“网站”中创建四个站点：

```text
api.example.com
admin.example.com
h5.example.com
kf.example.com
```

每个站点都按下面操作：

1. 打开站点设置。
2. 打开“SSL”。
3. 选择 Let's Encrypt。
4. 申请证书。
5. 开启强制 HTTPS。

此时出现默认空白页或宝塔默认页是正常的，部署后会被反向代理到 Docker 容器。

## 五、上传并解压部署包

### 1. 上传

在宝塔“文件”中进入：

```text
/www/wwwroot/
```

上传刚生成的：

```text
genericim-docker-oneclick-日期时间.tar.gz
```

### 2. 解压

在宝塔终端执行，把文件名换成实际文件名：

```bash
cd /www/wwwroot
mkdir -p genericim-package
tar -xzf genericim-docker-oneclick-日期时间.tar.gz -C genericim-package
cd /www/wwwroot/genericim-package
```

检查文件：

```bash
ls -la
```

必须能看到：

```text
deploy-customer.sh
deploy-online-prebuilt.sh
admin-dist
web-dist
kf-dist
backend
scripts
```

如果看不到 `deploy-customer.sh`，说明当前目录进错了。用 `find /www/wwwroot/genericim-package -name deploy-customer.sh` 找到它，再 `cd` 到它所在目录。

## 六、执行一键部署

在能够看到 `deploy-customer.sh` 的目录执行：

```bash
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

这就是服务器的一键部署命令。脚本会自动：

1. 检查 Docker 和 Docker Compose。
2. 复制程序到正式安装目录。
3. 按服务器架构选择 AMD64 或 ARM64 后端。
4. 自动生成 MySQL、MongoDB、JWT 随机密码。
5. 生成 `.env.bt` 和 `compose.bt.yaml`。
6. 启动全部 Docker 容器。
7. 初始化管理员账号。
8. 配置宝塔反向代理并保留现有 SSL。
9. 自动检查 API、管理后台、H5 和客服后台。

看到下面的文字表示容器已通过脚本自检：

```text
Prebuilt deployment complete.
Docker services are healthy.
```

正式程序默认安装在打包时生成的安装目录。具体目录会在执行开始时的 `install dir` 和执行结束后的管理命令中显示。

## 七、如果必须在服务器临时改域名

如果交付包中的默认域名需要临时替换，可以用一条命令覆盖：

```bash
sudo env \
  API_DOMAIN="api.example.com" \
  ADMIN_DOMAIN="admin.example.com" \
  H5_DOMAIN="h5.example.com" \
  KF_DOMAIN="kf.example.com" \
  SCHEME="https" \
  ADMIN_PASSWORD="请改成至少16位强密码" \
  WRITE_NGINX="1" \
  bash deploy-customer.sh
```

注意：这条命令会修改后端公开地址、CORS 和反向代理，但不能可靠替换已经编译进 Flutter Web/H5、Android、iOS 或 Windows 客户端中的旧接口。正式更换接口域名时，应该回到“第二步”，用新域名重新生成部署包和客户端安装包。

## 八、部署后检查

### 1. 检查公网地址

浏览器依次打开：

```text
https://api.example.com/health
https://admin.example.com/
https://h5.example.com/
https://kf.example.com/
```

也可以在服务器执行：

```bash
curl https://api.example.com/health
curl -I https://admin.example.com/
curl -I https://h5.example.com/
curl -I https://kf.example.com/
```

`/health` 应返回成功内容，三个网页应返回 `HTTP 200` 或正常的 HTTPS 跳转。

### 2. 检查 Docker

先进入脚本最后显示的正式安装目录。例如：

```bash
cd /www/wwwroot/genericim
docker compose --env-file .env.bt -f compose.bt.yaml ps
```

正常情况下，以下服务都应为 `Up` 或 `healthy`：

```text
mysql
mongodb
redis
api
admin
h5
kf
```

### 3. 登录后台

打开：

```text
https://admin.example.com/
```

默认用户名：

```text
admin
```

密码是本地打包时设置的 `-DefaultAdminPassword`。首次登录后立即修改密码。

## 九、日常运维命令

以下命令都在正式安装目录执行：

```bash
cd /www/wwwroot/genericim
```

查看状态：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml ps
```

查看 API 实时日志，按 `Ctrl+C` 退出日志，不会停止服务：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml logs -f --tail=200 api
```

查看全部服务日志：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=200
```

重启全部服务：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml restart
```

停止服务但保留数据：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml down
```

重新启动：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml up -d
```

> 不要执行 `docker compose down -v`。其中 `-v` 会删除数据库和上传文件卷，可能造成数据丢失。

## 十、升级新版本

1. 在本地用同一组正式域名重新生成预编译包。
2. 备份服务器正式安装目录中的 `.env.bt`。
3. 上传并解压新包到一个新临时目录。
4. 在新包目录再次执行 `sudo bash deploy-customer.sh`。

部署脚本会尽量读取并复用原有 `.env.bt` 中的数据库密码、JWT 和管理员配置。无论如何，升级前都应执行服务器快照或数据库备份。

## 十一、常见问题

### 1. `Docker is missing`

原因：没有安装 Docker。

处理：在宝塔软件商店安装 Docker，或者按 Docker 官方文档安装 Docker Engine。

### 2. `Docker is not running`

执行：

```bash
sudo systemctl enable --now docker
docker version
```

### 3. `Docker Compose is unavailable`

原因：只有 Docker Engine，没有 Compose 插件。

处理：安装 `docker-compose-plugin`，然后确认 `docker compose version` 能运行。注意项目使用的是中间有空格的 `docker compose`。

### 4. 拉取镜像超时

先检查服务器能否访问 Docker 镜像仓库，然后重试：

```bash
docker pull mysql:8.0
docker pull mongo:7.0
docker pull redis:7-alpine
docker pull nginx:1.27-alpine
docker pull alpine:3.19
```

国内服务器可在宝塔 Docker 设置中配置可用的镜像加速地址。不要使用来源不明的镜像。

### 5. `API health check failed`

执行：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml ps
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=300 api
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=200 mysql mongodb redis
```

重点看第一个 `error`、`failed` 或 `connection refused`，不要只看最后一行。

### 6. 域名打开是 502

先检查本机容器：

```bash
curl http://127.0.0.1:18080/health
curl -I http://127.0.0.1:18084/
curl -I http://127.0.0.1:18083/
curl -I http://127.0.0.1:18085/
```

本机正常但公网 502，说明宝塔反向代理配置有问题。四个站点应分别代理到：

```text
api.example.com    -> http://127.0.0.1:18080
admin.example.com  -> http://127.0.0.1:18084
h5.example.com     -> http://127.0.0.1:18083
kf.example.com     -> http://127.0.0.1:18085
```

### 7. 网页能打开，但 App 登录失败

常见原因：APK 仍使用旧接口域名，或者证书无效。

重新构建 APK：

```powershell
.\scripts\build-online-android-apk.ps1 `
  -ServerUrl "https://api.example.com" `
  -WsUrl "wss://api.example.com/api/v1/ws"
```

确认手机能直接访问 `https://api.example.com/health`，而且浏览器不提示证书风险。

### 8. 管理后台刷新后 404

管理后台容器已自带 SPA 回落规则。宝塔站点应做整站反向代理到 `127.0.0.1:18084`，不要再把站点根目录指向部署包里的静态文件。

## 十二、必须保存和备份的文件

正式安装目录里的以下内容必须保护好：

```text
.env.bt
compose.bt.yaml
docker/genericim/backend-config.bt.yaml
Docker volumes（MySQL、MongoDB、Redis、uploads）
```

`.env.bt` 包含数据库密码和 JWT 密钥，不要发到群里、不要提交到 Git、不要放进公开下载包。

## 十三、最短执行清单

已经拿到按正式域名生成的 `.tar.gz` 包时，服务器端最短流程是：

```bash
cd /www/wwwroot
mkdir -p genericim-package
tar -xzf genericim-docker-oneclick-*.tar.gz -C genericim-package
cd genericim-package
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

然后验证：

```bash
curl https://api.example.com/health
```

成功后打开管理后台、H5 和客服后台进行登录测试。
