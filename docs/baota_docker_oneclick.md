# 宝塔 Docker 一键部署

本部署方式面向宝塔 Linux 服务器，使用 Docker Compose 一次性启动：

- MySQL
- MongoDB
- Redis
- Go API
- Vue 管理后台 Nginx 容器
- 宝塔 Nginx 对外反向代理

脚本不会复用宝塔面板里的 MySQL/MongoDB/Redis 插件，避免手工建库、授权和版本差异。

## 快速部署

在服务器源码根目录执行：

```bash
sudo bash scripts/baota_docker_deploy.sh --domain im.example.com --mirror cn -y
```

常用参数：

```bash
--domain im.example.com       # 单域名模式：后台和 API 共用域名
--admin-domain imadmin.example.com
--api-domain im.example.com
--mirror cn                   # 国内源：Docker 镜像加速、npm、Go proxy、Alpine 源
--mirror global               # 海外官方源
--mirror auto                 # 自动检测，默认
--scheme https                # 已配置 SSL 后使用
--install-dir /www/wwwroot/genericim
--admin-password 'your-pass'  # 首次创建 admin 管理员密码
--no-nginx                    # 只部署 Docker，不写 Nginx 配置
```

部署完成后访问：

```text
http://im.example.com
```

如果你的线上域名按“后台域名 + 接口域名”拆分，例如：

```text
后台: imadmin.example.com
接口: app.example.com
```

使用：

```bash
sudo bash scripts/baota_docker_deploy.sh \
  --admin-domain imadmin.example.com \
  --api-domain app.example.com \
  --mirror cn \
  -y
```

初始管理员：

```text
username: admin
password: 脚本输出的密码
```

首次登录后请立即修改密码。

## 宝塔 Nginx

脚本会自动写入：

```text
/www/server/panel/vhost/nginx/genericim-admin.conf
/www/server/panel/vhost/nginx/genericim-api.conf
```

后台域名配置内容是反向代理到后台容器：

```text
127.0.0.1:18082
```

接口域名配置内容是反向代理到 API 容器：

```text
127.0.0.1:18080
```

后台容器内部已经处理：

- `/api/v1` 反代到 API 容器
- `/uploads` 反代到 API 容器
- Vue SPA 刷新回落到 `index.html`
- WebSocket Upgrade

如果你已经在宝塔里建了同域名网站，并且不想让脚本覆盖站点配置，可以使用：

```bash
sudo bash scripts/baota_docker_deploy.sh --domain im.example.com --no-nginx
```

然后在宝塔网站配置中手工添加反代到：

```text
http://127.0.0.1:18082
```

## SSL

先在宝塔面板给域名申请 SSL 并开启强制 HTTPS，然后执行：

```bash
sudo bash scripts/baota_docker_deploy.sh --domain im.example.com --scheme https -y
```

双域名模式：

```bash
sudo bash scripts/baota_docker_deploy.sh \
  --admin-domain imadmin.example.com \
  --api-domain app.example.com \
  --scheme https \
  --mirror cn \
  -y
```

这样后端 `base_url`、CORS 和 WebSocket Origin 会按 `https://im.example.com` 写入。

## 端口

默认只绑定本机地址，不对公网暴露数据库：

```text
127.0.0.1:18082 -> 管理后台容器
127.0.0.1:18080 -> API 容器
127.0.0.1:13306 -> MySQL
127.0.0.1:17017 -> MongoDB
127.0.0.1:16379 -> Redis
```

如需改端口：

```bash
sudo bash scripts/baota_docker_deploy.sh \
  --domain im.example.com \
  --admin-port 28082 \
  --api-port 28080 \
  --mysql-port 23306 \
  -y
```

## 运维命令

进入部署目录：

```bash
cd /www/wwwroot/genericim
```

查看状态：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml ps
```

查看 API 日志：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml logs -f api
```

重启：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml restart
```

停止：

```bash
docker compose --env-file .env.bt -f compose.bt.yaml down
```

更新代码后重新构建：

```bash
sudo bash scripts/baota_docker_deploy.sh --domain im.example.com --mirror cn -y
```

## 生成文件

脚本会在部署目录生成：

```text
.env.bt                         # 生产密码、端口、镜像源、域名
compose.bt.yaml                  # 宝塔 Docker Compose 配置
docker/genericim/backend-config.bt.yaml
```

请妥善保存 `.env.bt`，里面包含数据库密码、JWT 密钥和初始管理员密码。
