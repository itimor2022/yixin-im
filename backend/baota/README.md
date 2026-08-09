<!-- 文件用途：baota\README.md 是一个部署、运维或资源说明文档。
     核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。 -->

# 通用 IM 后端 - 宝塔部署指南

## 文件说明

```
baota/
├── server           # 主程序（Linux amd64, 15MB）
├── config.yaml      # 示例配置文件（生产请复制为私有配置或使用环境变量覆盖）
├── init.sql         # MySQL 数据库初始化脚本
├── start.sh         # 启动脚本
├── stop.sh          # 停止脚本
├── restart.sh       # 重启脚本
├── generic-im.service # systemd 服务文件
├── uploads/         # 上传文件目录
└── README.md        # 本文档
```

## 初始管理员

- 用户名: `admin`
- 密码: `123456`（可通过 `GENERIC_IM_INITIAL_ADMIN_PASSWORD` 覆盖）

## 演示管理员

- 用户名: `demo`
- 密码: `demo123`
- 权限: 只能查看，不能新增、删除、修改；敏感密钥返回脱敏值

**首次登录后请立即修改密码！**

## 部署步骤

### 1. 上传文件

将整个 `baota` 目录上传到服务器，建议路径：
```
/www/wwwroot/genericim/
```

### 2. 设置权限

```bash
cd /www/wwwroot/genericim
chmod +x server start.sh stop.sh restart.sh
chmod 755 uploads
```

### 3. 配置数据库

#### MySQL
1. 在宝塔面板创建 MySQL 数据库（如 `genericim`）
2. 导入数据库结构：
   ```bash
   mysql -u 用户名 -p 数据库名 < init.sql
   ```
   或在宝塔面板的 phpMyAdmin 中导入 `init.sql`

3. 修改 `config.yaml` 中的配置：
   ```yaml
   mysql:
     host: localhost
     port: 3306
     user: 你的用户名
     password: 你的密码
     database: 你的数据库名
   ```

#### MongoDB
在宝塔安装 MongoDB，用面板创建数据库（如 `genericim`）及对应用户。**宝塔把用户建在该库下，连接时必须加 `authSource=数据库名`，否则会认证失败。**

修改 `config.yaml`：
```yaml
mongodb:
  uri: mongodb://用户名:密码@localhost:27017/?authSource=数据库名
  database: genericim_messages
```
示例（库名 `genericim`，用户 `genericim`）：
```yaml
mongodb:
  uri: mongodb://genericim:genericim@localhost:27017/?authSource=genericim
  database: genericim_messages
```

**消息库授权**：消息存在 `genericim_messages`，须给用户授予该库权限，否则发消息会 500（`not authorized on genericim_messages`）。宝塔开启安全认证时，须用 root 连接后执行。

在服务器执行（把 `你的root密码` 换成宝塔 MongoDB 的 root 密码）：
```bash
mongosh -u root -p 你的root密码 --authenticationDatabase admin
```
进入 mongosh 后：
```javascript
use genericim
db.grantRolesToUser("genericim", [{ role: "readWrite", db: "genericim_messages" }])
```
看到 `{ ok: 1 }` 即成功。然后 `exit` 退出。

一行执行方式：`mongosh -u root -p 你的root密码 --authenticationDatabase admin --eval 'db.getSiblingDB("genericim").grantRolesToUser("genericim", [{ role: "readWrite", db: "genericim_messages" }])'`

#### Redis
在宝塔安装 Redis，如有密码请修改配置：
```yaml
redis:
  addr: localhost:6379
  password: "你的密码"
```

### 4. 配置 JWT 密钥

**重要**：生产环境必须配置独立 JWT 密钥，推荐使用环境变量，不要把真实密钥提交到仓库。
```yaml
jwt:
  secret: 修改为一个长随机字符串
```

或使用环境变量：
```bash
export GENERIC_IM_JWT_SECRET="$(openssl rand -hex 32)"
```

生成随机密钥：
```bash
openssl rand -hex 32
```

如需使用私有配置文件启动：
```bash
export GENERIC_IM_CONFIG=/www/wwwroot/genericim/config.private.yaml
```

### 5. 配置服务器地址

如果使用域名或反向代理，设置 base_url：
```yaml
server:
  base_url: "https://api.yourdomain.com"
```

### 6. 启动服务

#### 方式一：使用脚本（开发测试）
```bash
./start.sh   # 启动
./stop.sh    # 停止
./restart.sh # 重启
```

#### 方式二：使用 systemd（推荐生产环境）
```bash
# 复制服务文件
cp generic-im.service /etc/systemd/system/

# 修改服务文件中的路径（如果不是 /www/wwwroot/genericim）
vim /etc/systemd/system/generic-im.service

# 重载配置
systemctl daemon-reload

# 启动服务
systemctl start genericim

# 开机自启
systemctl enable genericim

# 查看状态
systemctl status genericim

# 查看日志
journalctl -u genericim -f
```

### 7. 配置反向代理（宝塔 Nginx）

**方法一：使用宝塔反向代理（简单）**
1. 网站设置 → 反向代理 → 添加反向代理
2. 目标URL: `http://127.0.0.1:8080`
3. 发送域名: `$host`

**方法二：使用伪静态配置（推荐，支持 WebSocket）**
1. 网站设置 → 伪静态
2. 将 `nginx.conf` 中的配置复制进去：

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # WebSocket 支持（重要！）
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # 超时设置
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 86400s;
    
    proxy_buffering off;
}

# 静态文件加速
location /uploads/ {
    alias /www/wwwroot/genericim/uploads/;
    expires 30d;
}
```

如果后台管理端由 Nginx 直接托管静态文件，请确保 `index.html` 不缓存，避免浏览器拿旧
`index.html` 去请求已被新版本删除的 `assets/index-*.js` / `assets/index-*.css`，导致后台白屏：

```nginx
root /www/wwwroot/genericim-admin;
index index.html;

location = /index.html {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    add_header Expires "0";
    try_files /index.html =404;
}

location /assets/ {
    expires 30d;
    add_header Cache-Control "public, max-age=2592000, immutable";
    try_files $uri =404;
}

location / {
    try_files $uri $uri/ /index.html;
}
```

每次发布后台时，请上传同一次 `npm run build` 生成的完整 `admin/dist` 目录，不要只覆盖
`index.html` 或只覆盖 `assets`。

3. 如需上传大文件，在网站配置中添加：
```nginx
client_max_body_size 100m;
```

### 8. 配置 SSL

1. 网站设置 → SSL → Let's Encrypt → 申请证书
2. 开启 "强制HTTPS"
3. 修改 `config.yaml` 中的 `base_url`：
```yaml
server:
  base_url: "https://api.yourdomain.com"
```

## 常用命令

```bash
# 查看日志
tail -f /www/wwwroot/genericim/server.log

# 查看进程
ps aux | grep genericim

# 查看端口
netstat -tlnp | grep 8080
```

## 防火墙

确保开放以下端口：
- 8080 (API，如使用反向代理则不需要对外开放)
- 80/443 (HTTP/HTTPS)

## 常见问题

### 1. 启动失败
检查日志文件 `server.log`，常见原因：
- 数据库连接失败
- 端口被占用
- 权限不足

### 2. WebSocket 连接失败
确保 Nginx 配置了 WebSocket 支持。

### 3. 上传文件失败
检查 `uploads` 目录权限：
```bash
chmod 755 uploads
chown www:www uploads
```
