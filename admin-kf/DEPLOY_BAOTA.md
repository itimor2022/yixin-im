# 官方客服后台部署到宝塔教程

本文适用于当前项目中的 `service-admin` 前端和 `backend` Go 服务。

更新时间：2026-04-13

---

## 一、部署目标

最终建议部署结构：

- 前端：`service-admin` 打包后的静态文件，放到宝塔站点目录
- 后端：`backend` 编译后的 Go 可执行文件，作为常驻进程运行
- Nginx：
  - 直接服务前端静态资源
  - 把 `/api/v1/` 反向代理到 Go 后端

推荐访问方式：

- 前端：`https://你的域名/`
- API：`https://你的域名/api/v1/`

这样前端 `.env.production` 中的：

```env
VITE_API_BASE_URL=/api/v1
VITE_USE_MOCK=false
```

可以保持不变。

---

## 二、宝塔中需要提前准备什么

### 1. 安装运行环境
在宝塔软件商店中准备：

- Nginx
- MySQL
- Redis
- MongoDB
- Node.js 版本管理器
- PM2（可选，不一定要用）

### 2. 服务器系统建议
建议 Linux 服务器，常见为：

- Ubuntu 20+/22+
- CentOS 7+/AlmaLinux

### 3. 域名准备
建议提前解析好域名到服务器，例如：

- `kf.example.com`

---

## 三、上传项目代码

你可以用以下任一种方式上传到服务器：

- 宝塔文件管理直接上传压缩包后解压
- Git 拉取代码
- SFTP / FTP 上传

建议目录结构类似：

```text
/www/wwwroot/
  yi-xin-ai2k/
    backend/
    service-admin/
```

---

## 四、部署前端 `service-admin`

### 1. 进入前端目录

```bash
cd /www/wwwroot/yi-xin-ai2k/service-admin
```

### 2. 检查生产环境变量
当前项目生产环境文件是：

- `service-admin/.env.production`

建议内容如下：

```env
VITE_API_BASE_URL=/api/v1
VITE_USE_MOCK=false
```

如果你的 API 不走同域名反代，而是独立域名，例如 `https://api.example.com/api/v1`，则改成：

```env
VITE_API_BASE_URL=https://api.example.com/api/v1
VITE_USE_MOCK=false
```

### 3. 安装依赖并打包
项目使用 `pnpm`。如果服务器没有 `pnpm`，先安装：

```bash
npm install -g pnpm
```

然后执行：

```bash
pnpm install
pnpm build
```

打包完成后会生成：

```text
service-admin/dist/
```

### 4. 在宝塔中新建站点
在宝塔网站管理中：

1. 新建站点
2. 域名填写你的正式域名
3. 站点目录建议指向：

```text
/www/wwwroot/yi-xin-ai2k/service-admin/dist
```

如果你不想直接指向 `dist`，也可以新建站点目录后，把 `dist` 内容拷贝进去。

---

## 五、部署 Go 后端 `backend`

### 1. 准备配置文件
后端使用：

- `backend/config.yaml`

当前你需要重点修改这些配置：

```yaml
server:
  port: 8080
  mode: release
  base_url: "https://你的域名"

mysql:
  host: 127.0.0.1
  port: 3306
  user: 你的数据库用户
  password: 你的数据库密码
  database: 你的数据库名

mongodb:
  uri: mongodb://127.0.0.1:27017
  database: 你的Mongo数据库名

redis:
  addr: 127.0.0.1:6379
  password: ""
  db: 0

jwt:
  secret: 改成生产环境复杂密钥
  expire: 168h
```

### 2. 特别注意必须改的项

#### `server.mode`
生产环境改为：

```yaml
mode: release
```

#### `jwt.secret`
不要继续使用默认值：

```yaml
your-super-secret-jwt-key-change-in-production
```

请改成你自己的高强度密钥。

### 3. 编译后端
进入目录：

```bash
cd /www/wwwroot/yi-xin-ai2k/backend
```

编译：

```bash
go build -o app ./cmd/server
```

生成文件：

```text
backend/app
```

### 4. 启动方式
你可以用宝塔的“计划任务 / 守护进程 / PM2 / Supervisor”任意一种。

如果用最简单方式测试启动：

```bash
cd /www/wwwroot/yi-xin-ai2k/backend
nohup ./app > runtime.log 2>&1 &
```

建议最终还是使用宝塔的进程守护功能，保证进程异常退出后自动拉起。

---

## 六、Nginx 反向代理配置

如果前端和后端走同一个域名，Nginx 是关键。

### 站点配置核心思路
- `/` 走前端静态资源
- `/api/v1/` 转发到 Go 服务 `127.0.0.1:8080`
- 前端是 Vue Hash 路由，核心仍然建议保留静态首页回退

### 参考配置
把下面内容合并到宝塔站点的 Nginx 配置中：

```nginx
server {
    listen 80;
    server_name 你的域名;

    root /www/wwwroot/yi-xin-ai2k/service-admin/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/v1/ {
        proxy_pass http://127.0.0.1:8080/api/v1/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 如果已经配了 HTTPS
你可以在宝塔里申请 SSL，然后把 80 自动跳 443，443 的 server 中保留同样逻辑即可。

---

## 七、宝塔里数据库准备

### 1. MySQL
确保：

- 数据库已创建
- 用户已授权
- `config.yaml` 中账号密码正确

### 2. MongoDB
确保：

- Mongo 服务可连
- 数据库名已与配置一致

### 3. Redis
确保：

- Redis 正常启动
- 地址端口与 `config.yaml` 一致
- 如果设置了密码，要同步配置

---

## 八、前端更新流程

以后前端代码更新，只需要：

```bash
cd /www/wwwroot/yi-xin-ai2k/service-admin
pnpm install
pnpm build
```

如果站点目录直接指向 `dist`，一般打包后即可生效。

如果你是把 `dist` 内容复制到其他目录，则需要再次复制。

---

## 九、后端更新流程

后端代码更新后：

```bash
cd /www/wwwroot/yi-xin-ai2k/backend
go build -o app ./cmd/server
```

然后重启 Go 进程。

如果你用宝塔守护进程，直接在面板里重启对应进程即可。

---

## 十、部署完成后的检查清单

### 1. 检查前端是否能打开
浏览器访问：

- `https://你的域名/`

### 2. 检查 API 是否通
可以直接访问一个接口，或者在浏览器开发者工具中看请求是否成功。

重点看前端请求是否打到：

- `/api/v1/service-admin/auth/login`
- `/api/v1/service-admin/profile`

### 3. 检查登录是否正常
用真实官方客服账号验证：

- 登录
- 工作台加载
- 我的邀请码
- 我的用户
- 欢迎语保存
- 修改密码
- 绑定手机号

### 4. 检查后端日志
查看：

```bash
cd /www/wwwroot/yi-xin-ai2k/backend
tail -f runtime.log
```

### 5. 检查 Nginx 日志
如果前端能打开但 API 失败，优先查看宝塔站点日志。

---

## 十一、常见问题排查

### 问题 1：前端打开了，但登录接口 404
大概率是 Nginx 没把 `/api/v1/` 代理到 Go 服务。

重点检查：

- `proxy_pass` 是否正确
- Go 服务是否真的运行在 `127.0.0.1:8080`

### 问题 2：接口 502
说明 Nginx 找不到后端服务，通常是：

- Go 进程没启动
- 端口不对
- Go 服务启动失败

### 问题 3：登录成功后页面一直报未授权
重点检查：

- `jwt.secret` 是否在生产环境正确
- Redis 是否正常
- 服务端缓存中的 session/version 是否工作正常
- 浏览器里请求头是否带 `Authorization`

### 问题 4：手机号验证码发不出去
重点检查 `config.yaml` 中：

- `sms.enabled`
- `sms.provider`
- 短信渠道密钥是否正确

### 问题 5：前端请求地址不对
检查：

- `service-admin/.env.production`
- 打包后是否重新执行了 `pnpm build`

---

## 十二、推荐的生产部署做法

为了更稳，建议：

1. Go 后端只监听内网端口，例如 `8080`
2. 对外只暴露 Nginx 80/443
3. 前端和 API 走同域名反向代理
4. `jwt.secret` 使用强随机字符串
5. MySQL / Redis / MongoDB 只开放内网访问
6. 宝塔里开启 SSL
7. 修改默认数据库密码

---

## 十三、最简上线命令汇总

### 前端

```bash
cd /www/wwwroot/yi-xin-ai2k/service-admin
npm install -g pnpm
pnpm install
pnpm build
```

### 后端

```bash
cd /www/wwwroot/yi-xin-ai2k/backend
go build -o app ./cmd/server
nohup ./app > runtime.log 2>&1 &
```

---

## 十四、明天继续前的建议

今晚先完成上线，明天继续开发前建议先确认：

1. 宝塔上线后的正式域名
2. 前端是否能正常调用 `/api/v1`
3. 官方客服账号是否能真实登录
4. MySQL / Redis / MongoDB / 短信服务是否都在生产环境可用

如果这些都正常，明天就可以继续做工作台联动和会话逻辑收口。
