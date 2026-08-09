# api.example.com 根目录部署包

这个包用于直接解压到：

```text
/www/wwwroot/api.example.com
```

## 使用

在宝塔终端执行：

```bash
cd /www/wwwroot/api.example.com
tar -xzf genericim-imapi-root-prebuilt-*.tar.gz
sudo bash deploy.sh
```

如果宝塔 Nginx 已经配好，不想让脚本改 Nginx：

```bash
sudo NO_NGINX=1 bash deploy.sh
```

## 检查

```bash
curl https://api.example.com/health
docker compose --env-file .env.bt -f compose.bt.yaml ps
```

这个包不会在服务器上执行 Go/Node 编译。
