# 线上一键部署预编译包

这个包已经在本地完成构建，服务器上不需要再执行 `go build`、`npm install`、`vite build` 或 `flutter build`。

包内包含：

- `backend/server-linux-amd64`：Linux x86_64 后端服务。
- `backend/server-linux-arm64`：Linux ARM64 后端服务。
- `admin-dist`：后台管理端静态文件。
- `web-dist`：H5/PC Web 静态文件。
- `kf-dist`：官方客服后台静态文件。
- `deploy-customer.sh`：推荐使用的一键部署入口。
- `deploy-online-prebuilt.sh`：底层部署脚本。
- `scripts/baota_docker_deploy_prebuilt.sh`：宝塔/Docker 部署脚本。
- `docker/genericim`：Docker 配置。

部署脚本会启动四个对外入口：

- 后台容器：本地 `127.0.0.1:18084`，域名反代到 `admin.example.com`。
- 接口容器：本地 `127.0.0.1:18080`，域名反代到 `api.example.com`。
- H5 容器：本地 `127.0.0.1:18083`，域名反代到 `h5.example.com`。
- 客服后台容器：本地 `127.0.0.1:18085`，域名反代到 `support.example.com`。

## 默认域名

- 后台：`https://admin.example.com`
- 接口：`https://api.example.com`
- H5/PC：`https://h5.example.com`
- 官方客服后台：`https://support.example.com`
- 默认超级管理员：`admin`
- 默认超级管理员密码：`123456`

## 服务器执行

把压缩包上传到：

```bash
/www/wwwroot/api.example.com/
```

如果使用 tar.gz：

```bash
cd /www/wwwroot/api.example.com
mkdir -p genericim-online-prebuilt
tar -xzf genericim-online-prebuilt-*.tar.gz -C genericim-online-prebuilt
cd genericim-online-prebuilt
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

如果使用 zip：

```bash
cd /www/wwwroot/api.example.com
rm -rf genericim-online-prebuilt
unzip -o genericim-online-prebuilt-*.zip -d genericim-online-prebuilt
cd genericim-online-prebuilt
chmod +x deploy-customer.sh deploy-online-prebuilt.sh scripts/baota_docker_deploy_prebuilt.sh
sudo bash deploy-customer.sh
```

## 临时改域名或端口

```bash
sudo API_DOMAIN=api.example.com \
  ADMIN_DOMAIN=admin.example.com \
  H5_DOMAIN=h5.example.com \
  KF_DOMAIN=kf.example.com \
  KF_PORT=18085 \
  H5_PORT=18083 \
  SCHEME=https \
  bash deploy-customer.sh
```

## 启用 OSS 存储语音和媒体

推荐线上把语音、图片、视频和文件统一放到阿里云 OSS。App 仍然只上传到后端 `/upload/voice`、`/upload/image` 等接口，OSS 密钥只在服务器保存。

首次部署时可直接传入：

```bash
sudo STORAGE_PROVIDER=aliyun \
  STORAGE_ALIYUN_ENDPOINT=oss-cn-hangzhou.aliyuncs.com \
  STORAGE_ALIYUN_BUCKET=your-bucket \
  STORAGE_ALIYUN_ACCESS_KEY_ID=your-access-key-id \
  STORAGE_ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret \
  STORAGE_ALIYUN_PUBLIC_BASE_URL=https://media.example.com \
  bash deploy-customer.sh
```

已有线上环境可编辑 `/www/wwwroot/api.example.com/.env.bt` 增加同样变量，然后执行更新包或重启 API。建议 OSS Bucket 配置公开读、HTTPS 域名、CORS 放行 `admin.example.com`、`h5.example.com`、`support.example.com`，并设置语音/临时媒体生命周期清理。

## 宝塔 Nginx 和 SSL

客户一键包默认会自动配置反向代理。已有宝塔站点时，脚本保留原站点配置、SSL 证书和续签设置，只写入宝塔的反向代理片段；没有站点时才创建独立配置，并在检测到宝塔证书文件后自动启用 443。

如果只想更新 Docker 服务、完全不改 Nginx，可执行：

```bash
sudo WRITE_NGINX=0 bash deploy-customer.sh
```

宝塔站点反向代理目标：

宝塔站点反向代理目标：

```text
admin.example.com -> http://127.0.0.1:18084
h5.example.com    -> http://127.0.0.1:18083
support.example.com      -> http://127.0.0.1:18085
api.example.com   -> http://127.0.0.1:18080
```

通用入口脚本需要显式开启自动配置：

```bash
sudo WRITE_NGINX=1 bash deploy-customer.sh
```

## 检查

```bash
curl https://api.example.com/health
curl -I https://admin.example.com/
curl -I https://h5.example.com/
curl -I https://support.example.com/
curl http://127.0.0.1:18083/
curl http://127.0.0.1:18085/
```

查看容器：

```bash
cd /www/wwwroot/api.example.com/genericim-online-server
docker compose --env-file .env.bt -f compose.bt.yaml ps
```
