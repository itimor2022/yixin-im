# 壹信 IM 后端 - 宝塔部署指南

## 文件说明

```
baota/
├── server           # 主程序（Linux amd64, 15MB）
├── config.yaml      # 配置文件（需修改）
├── init.sql         # MySQL 数据库初始化脚本
├── start.sh         # 启动脚本
├── stop.sh          # 停止脚本
├── restart.sh       # 重启脚本
├── gaoranim.service # systemd 服务文件
├── uploads/         # 上传文件目录
└── README.md        # 本文档
```

## 默认管理员

- 用户名: `admin`
- 密码: `123456`

**首次登录后请立即修改密码！**

## 部署步骤

### 1. 上传文件

将整个 `baota` 目录上传到服务器，建议路径：
```
/www/wwwroot/gaoranim/
```

### 2. 设置权限

```bash
cd /www/wwwroot/gaoranim
chmod +x server start.sh stop.sh restart.sh
chmod 755 uploads
```

### 3. 配置数据库

#### MySQL
1. 在宝塔面板创建 MySQL 数据库（如 `gaoranim`）
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
在宝塔安装 MongoDB，用面板创建数据库（如 `grimimim`）及对应用户。**宝塔把用户建在该库下，连接时必须加 `authSource=数据库名`，否则会认证失败。**

修改 `config.yaml`：
```yaml
mongodb:
  uri: mongodb://用户名:密码@localhost:27017/?authSource=数据库名
  database: grimimim_messages
```
示例（库名 `grimimim`，用户 `grimimim`）：
```yaml
mongodb:
  uri: mongodb://grimimim:grimimim@localhost:27017/?authSource=grimimim
  database: grimimim_messages
```

**消息库授权**：消息存在 `grimimim_messages`，须给用户授予该库权限，否则发消息会 500（`not authorized on grimimim_messages`）。宝塔开启安全认证时，须用 root 连接后执行。

在服务器执行（把 `你的root密码` 换成宝塔 MongoDB 的 root 密码）：
```bash
mongosh -u root -p 你的root密码 --authenticationDatabase admin
```
进入 mongosh 后：
```javascript
use grimimim
db.grantRolesToUser("grimimim", [{ role: "readWrite", db: "grimimim_messages" }])
```
看到 `{ ok: 1 }` 即成功。然后 `exit` 退出。

一行执行方式：`mongosh -u root -p 你的root密码 --authenticationDatabase admin --eval 'db.getSiblingDB("grimimim").grantRolesToUser("grimimim", [{ role: "readWrite", db: "grimimim_messages" }])'`

#### Redis
在宝塔安装 Redis，如有密码请修改配置：
```yaml
redis:
  addr: localhost:6379
  password: "你的密码"
```

### 4. 修改 JWT 密钥

**重要**：必须修改 JWT 密钥！
```yaml
jwt:
  secret: 修改为一个长随机字符串
```

生成随机密钥：
```bash
openssl rand -hex 32
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
cp gaoranim.service /etc/systemd/system/

# 修改服务文件中的路径（如果不是 /www/wwwroot/gaoranim）
vim /etc/systemd/system/gaoranim.service

# 重载配置
systemctl daemon-reload

# 启动服务
systemctl start gaoranim

# 开机自启
systemctl enable gaoranim

# 查看状态
systemctl status gaoranim

# 查看日志
journalctl -u gaoranim -f
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
    alias /www/wwwroot/gaoranim/uploads/;
    expires 30d;
}
```

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
tail -f /www/wwwroot/gaoranim/server.log

# 查看进程
ps aux | grep gaoranim

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
