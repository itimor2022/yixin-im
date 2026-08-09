# Online Backend Package Rule

线上后端更新包固定使用：

[线上后端预编译打包固定规范](./线上后端预编译打包固定规范.md)

关键规则：

- 必须本地交叉编译 `backend/server`。
- 服务器只运行预编译二进制。
- 不允许服务器拉取 `golang:*` 镜像。
- 不允许服务器执行 `go build`。
- 更新包不得包含 `.env` / `.env.bt` / `.env.example`。
- API 端口固定 `127.0.0.1:18080`。
- Admin 端口固定 `127.0.0.1:18083`。

服务器执行命令固定：

```bash
cd /www/wwwroot/api.example.com
unzip -o genericim-online-backend-prebuilt-*.zip
chmod +x deploy.sh backend/server
API_PORT=18080 ADMIN_PORT=18083 bash deploy.sh
```

## 2026-06-23 overwrite package pitfalls

Future one-click packaging must follow:

```text
docs/online-overwrite-package-pitfalls.md
```

Key hard checks:
- For an already running online service, build an overwrite package only containing `backend/server` and `admin-dist/`.
- Do not include or overwrite `.env`, `.env.bt`, `.env.example`, `compose.bt.yaml`, database data, upload data, or Nginx config.
- Use `npm.cmd run build` for admin on Windows; `npm run build` can be blocked by PowerShell execution policy.
- Do not use `Copy-Item -LiteralPath "admin\dist\*"` or `Compress-Archive -LiteralPath "stage\*"`; `-LiteralPath` does not expand wildcards.
- Verify the archive contains `./backend/server`, `./admin-dist/index.html`, and `./admin-dist/assets/*`.
- Prefer `.tar.gz` for Linux upload; keep `.zip` only as secondary artifact.
- Validate helper scripts with `bash -n` before packaging, or use the manual restart command.
- Preserve current online ports: API `127.0.0.1:18080`, admin `127.0.0.1:18083`.
- When admin uses `https://admin.example.com` and API uses `https://api.example.com`, `.env.bt` must allow both in `PUBLIC_ORIGIN`.
