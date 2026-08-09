# 线上覆盖更新一键部署包

## 默认用法

上传压缩包到服务器后解压，在包根目录执行：

```bash
sudo bash deploy-online-update.sh
```

默认参数：

```text
API_DOMAIN=api.example.com
ADMIN_DOMAIN=api.example.com
SCHEME=https
INSTALL_DIR=/www/wwwroot/genericim
MIRROR=cn
```

脚本会复用线上已有 `.env.bt` 里的数据库密码、MongoDB 密码、JWT 密钥和初始管理员密码，适合覆盖更新已有数据。

## 修改域名

单域名：

```bash
sudo DOMAIN=im.example.com bash deploy-online-update.sh
```

后台和接口分域名：

```bash
sudo ADMIN_DOMAIN=admin.example.com API_DOMAIN=imapi.example.com bash deploy-online-update.sh
```

## 常用运维命令

```bash
cd /www/wwwroot/genericim
docker compose --env-file .env.bt -f compose.bt.yaml ps
docker compose --env-file .env.bt -f compose.bt.yaml logs -f api
docker compose --env-file .env.bt -f compose.bt.yaml restart
```
