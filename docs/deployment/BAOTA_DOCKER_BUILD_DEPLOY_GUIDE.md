# 宝塔 Docker 版编译打包与搭建教程

本文档用于交付“预编译宝塔 Docker 版”。推荐方式是：在本地电脑完成后端、管理端、Web 端、客服端编译，服务器只运行 Docker 容器，不在服务器上执行 `go build`、`npm run build`、`flutter build`。

## 一、四个端标注清单

| 模块 | 源码目录 | 打包产物 | Docker/部署位置 | 默认本地端口 | 默认域名示例 |
| --- | --- | --- | --- | --- | --- |
| 后端 API/媒体服务 | `backend/` | `backend/server-linux-amd64`、`backend/server-linux-arm64` | `api` 容器，运行 `/app/server` | `127.0.0.1:18080` | `https://api.example.com` |
| 管理端 | `admin/` | `admin-dist/` | `admin` Nginx 容器 | `127.0.0.1:18084` | `https://admin.example.com` |
| Web/H5/PC 端 | Flutter 根项目 `lib/`、`web/` | `web-dist/` | `h5` Nginx 容器 | `127.0.0.1:18083` | `https://h5.example.com` |
| 客服端/客服后台 | `admin-kf/` | `kf-dist/` | `kf` Nginx 容器 | `127.0.0.1:18085` | `https://support.example.com` |

依赖服务由同一套 `compose.bt.yaml` 启动：

| 服务 | 容器 | 默认绑定 |
| --- | --- | --- |
| MySQL | `genericim-mysql` | `127.0.0.1:13306` |
| MongoDB | `genericim-mongodb` | `127.0.0.1:17017` |
| Redis | `genericim-redis` | `127.0.0.1:16379` |

## 二、本地编译环境

在本地 Windows 机器执行打包。需要准备：

- Node.js 20.19 或更高版本。
- npm，可直接使用 `npm.cmd`，避免 PowerShell 执行策略拦截 `npm.ps1`。
- Go。
- Flutter。
- 项目依赖已安装，或能访问 npm/go/flutter 依赖源。

快速检查：

```powershell
node -v
npm -v
go version
flutter --version
```

## 三、一键编译宝塔 Docker 预编译包

在项目根目录执行：

```powershell
.\scripts\build-online-prebuilt-package.ps1 `
  -PackageName "genericim-online-prebuilt" `
  -AdminDomain "admin.example.com" `
  -ApiDomain "api.example.com" `
  -H5Domain "h5.example.com" `
  -KfDomain "support.example.com" `
  -Scheme "https" `
  -AdminPort "18084" `
  -H5Port "18083" `
  -KfPort "18085" `
  -DefaultAdminPassword "123456"
```

脚本会依次执行：

1. 编译管理端：`admin/` -> `admin-dist/`。
2. 编译客服端：`admin-kf/` -> `kf-dist/`。
3. 编译 Web/H5/PC 端：Flutter Web -> `web-dist/`。
4. 测试并交叉编译后端：`backend/cmd/server` -> `backend/server-linux-amd64`、`backend/server-linux-arm64`。
5. 复制部署脚本和 Docker 配置。
6. 生成 `.zip` 和 `.tar.gz` 交付包。

成功后在 `artifacts/` 下生成类似文件：

```text
artifacts/genericim-online-prebuilt-YYYYMMDD-HHMMSS/
artifacts/genericim-online-prebuilt-YYYYMMDD-HHMMSS.zip
artifacts/genericim-online-prebuilt-YYYYMMDD-HHMMSS.tar.gz
```

交付服务器优先使用 `.tar.gz`。

## 四、交付包内容说明

解压后的目录至少包含：

```text
admin-dist/                         管理端静态文件
web-dist/                           Web/H5/PC 端静态文件
kf-dist/                            客服端静态文件
backend/server-linux-amd64          Linux x86_64 后端二进制
backend/server-linux-arm64          Linux ARM64 后端二进制
backend/assets/                     后端资源
backend/uploads/                    初始贴纸/上传资源，可选
docker/genericim/backend-config.yaml    后端配置模板
docker/genericim/admin-nginx.conf       管理端容器内 Nginx 配置
scripts/baota_docker_deploy_prebuilt.sh
deploy-online-prebuilt.sh
deploy-customer.sh                  推荐执行入口
README.md
CUSTOMER_DEPLOY_README.md
```

注意：服务器部署时会自动根据 `uname -m` 选择 `server-linux-amd64` 或 `server-linux-arm64`，复制为 `backend/server` 后运行。

## 五、宝塔服务器准备

服务器建议：

- Linux x86_64 或 ARM64。
- 宝塔面板已安装。
- Docker 和 Docker Compose 可用。
- 宝塔 Nginx 可用。
- 域名已解析到服务器公网 IP。

宝塔站点建议建立 4 个站点：

```text
api.example.com     后端 API/媒体
admin.example.com   管理端
h5.example.com      Web/H5/PC 端
support.example.com        客服端/客服后台
```

每个站点都在宝塔面板申请 SSL 证书。部署脚本默认不接管 SSL，证书、HTTPS、续签继续由宝塔管理。

## 六、上传并解压部署包

把 `genericim-online-prebuilt-*.tar.gz` 上传到服务器，例如：

```bash
/www/wwwroot/api.example.com/
```

服务器执行：

```bash
cd /www/wwwroot/api.example.com
rm -rf genericim-online-prebuilt
mkdir -p genericim-online-prebuilt
tar -xzf genericim-online-prebuilt-*.tar.gz -C genericim-online-prebuilt
cd genericim-online-prebuilt
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

如果使用 `.zip`：

```bash
cd /www/wwwroot/api.example.com
rm -rf genericim-online-prebuilt
unzip -o genericim-online-prebuilt-*.zip -d genericim-online-prebuilt
cd genericim-online-prebuilt
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

## 七、按客户域名部署

临时改域名或端口：

```bash
sudo API_DOMAIN=api.example.com \
  ADMIN_DOMAIN=admin.example.com \
  H5_DOMAIN=h5.example.com \
  KF_DOMAIN=kf.example.com \
  SCHEME=https \
  API_PORT=18080 \
  ADMIN_PORT=18084 \
  H5_PORT=18083 \
  KF_PORT=18085 \
  ADMIN_PASSWORD='ChangeMe_123456' \
  bash deploy-customer.sh
```

首次部署后会生成：

```text
/www/wwwroot/genericim/.env.bt
/www/wwwroot/genericim/compose.bt.yaml
/www/wwwroot/genericim/docker/genericim/backend-config.bt.yaml
```

`.env.bt` 中保存数据库密码、JWT 密钥、域名、端口、对象存储配置。更新部署时不要删除这个文件。

## 八、宝塔反向代理配置

推荐在宝塔面板手动配置反向代理，脚本默认不改宝塔 Nginx/SSL。

四个站点的反向代理目标：

```text
api.example.com     -> http://127.0.0.1:18080
admin.example.com   -> http://127.0.0.1:18084
h5.example.com      -> http://127.0.0.1:18083
support.example.com        -> http://127.0.0.1:18085
```

API、管理端、Web 端、客服端都建议打开 WebSocket 支持，Nginx 反代至少需要：

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_read_timeout 86400s;
client_max_body_size 100m;
```

高并发群聊还必须检查宿主机和宝塔 Nginx 的连接入口。应用内部即使 ACK
已经优化，`worker_connections`、accept backlog 或文件句柄太小，仍会在
50 个长连接叠加图片上传时表现为排队、连接拒绝或 502/504。

先只读检查：

```bash
sudo bash scripts/tune-im-ingress-capacity.sh --check
```

建议生产基线为：

```text
net.core.somaxconn                 >= 16384
net.ipv4.tcp_max_syn_backlog       >= 16384
Nginx worker_connections           >= 16384
Nginx worker_rlimit_nofile         >= 262144
```

在已做服务器快照、确认当前 Nginx 配置可回滚后执行：

```bash
sudo bash scripts/tune-im-ingress-capacity.sh --apply
```

脚本会备份 `nginx.conf`、写入 sysctl、执行 `nginx -t`；校验失败会自动
恢复备份。站点反代应保留请求缓冲，让弱网上传先由 Nginx 接收，避免慢
客户端长期占用 Go API 连接：

```nginx
proxy_connect_timeout 5s;
proxy_send_timeout 120s;
proxy_request_buffering on;
proxy_socket_keepalive on;
```

验收时同时观察宝塔访问日志中的 499/502/504、内核 listen overflow、
Nginx active/handled requests 和 API 的 ACK p95。只看手机 ping 或服务
进程 CPU 不能证明入口没有排队。

如果确实要让脚本写基础 HTTP vhost：

```bash
sudo WRITE_NGINX=1 bash deploy-customer.sh
```

仍建议 SSL 在宝塔面板中单独开启和续签。

## 九、OSS/对象存储配置

默认使用 Docker 本地卷保存上传文件。线上推荐改为阿里云 OSS：

```bash
sudo STORAGE_PROVIDER=aliyun \
  STORAGE_ALIYUN_ENDPOINT=oss-cn-hangzhou.aliyuncs.com \
  STORAGE_ALIYUN_BUCKET=your-bucket \
  STORAGE_ALIYUN_ACCESS_KEY_ID=your-access-key-id \
  STORAGE_ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret \
  STORAGE_ALIYUN_PUBLIC_BASE_URL=https://media.example.com \
  bash deploy-customer.sh
```

OSS 建议配置：

- Bucket 允许公开读，或通过 CDN 域名访问。
- CORS 放行管理端、Web 端、客服端域名。
- 图片、语音、视频、文件走 HTTPS。
- 定期清理临时媒体资源。

## 十、部署后检查

检查公网：

```bash
curl https://api.example.com/health
curl -I https://admin.example.com/
curl -I https://h5.example.com/
curl -I https://support.example.com/
```

检查服务器本机端口：

```bash
curl http://127.0.0.1:18080/health
curl -I http://127.0.0.1:18084/
curl -I http://127.0.0.1:18083/
curl -I http://127.0.0.1:18085/
```

查看 Docker 服务：

```bash
cd /www/wwwroot/genericim
docker compose --env-file .env.bt -f compose.bt.yaml ps
docker compose --env-file .env.bt -f compose.bt.yaml logs -f api
```

默认管理账号：

```text
账号：admin
密码：123456
```

如部署时传了 `ADMIN_PASSWORD`，以传入值为准。上线后请立即修改默认密码。

## 十一、更新版本流程

本地重新执行编译打包脚本，上传新的 `genericim-online-prebuilt-*.tar.gz` 到服务器，然后执行：

```bash
cd /www/wwwroot/api.example.com
rm -rf genericim-online-prebuilt
mkdir -p genericim-online-prebuilt
tar -xzf genericim-online-prebuilt-*.tar.gz -C genericim-online-prebuilt
cd genericim-online-prebuilt
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

更新不会主动删除 `/www/wwwroot/genericim/.env.bt`，数据库卷、MongoDB 卷、Redis 卷、上传文件卷会继续保留。

## 十二、常见问题

### 1. 管理端或客服端打开空白

先检查反代目标是否正确：

```bash
curl -I http://127.0.0.1:18084/
curl -I http://127.0.0.1:18085/
```

再检查浏览器控制台是否有 `/api/` 请求跨域或 404。宝塔反代必须保留 `Host`、`X-Forwarded-Proto`、WebSocket 头。

### 2. Web/H5 无法连接 WebSocket

确认部署时 `SCHEME=https`，Flutter Web 会使用：

```text
wss://API_DOMAIN/api/v1/ws
```

同时确认 API 站点反代支持 `Upgrade` 和 `Connection "upgrade"`。

### 3. API 健康检查失败

查看后端日志：

```bash
cd /www/wwwroot/genericim
docker compose --env-file .env.bt -f compose.bt.yaml logs -f api
```

常见原因是 MySQL/MongoDB/Redis 未健康、端口被占用、`.env.bt` 中域名或密码被误改。

### 4. 服务器架构不匹配

脚本支持：

```text
x86_64/amd64 -> backend/server-linux-amd64
aarch64/arm64 -> backend/server-linux-arm64
```

其他架构需要在本地增加对应 `GOOS/GOARCH` 后端二进制。

### 5. 不想让脚本改宝塔站点

默认就是不改。保持 `WRITE_NGINX` 不设置即可，然后在宝塔面板手动做四个反向代理。
