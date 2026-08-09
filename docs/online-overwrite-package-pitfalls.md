# Online Overwrite Package Pitfalls

This note records issues hit during the 2026-06-23 online backend/admin overwrite update. Future one-click packaging must treat these as hard checks.

## Package Types

Use two different package modes.

Full prebuilt deploy package:
- Intended for first deploy or controlled redeploy.
- May contain deploy scripts, compose templates, docker config, backend binary, and admin-dist.
- Must not contain `.env`, `.env.bt`, or `.env.example`.
- Must not run `go build`, `npm ci`, or `vite build` on the server.

Overwrite update package:
- Intended for an already running `/www/wwwroot/api.example.com` service.
- Must only overwrite `backend/server` and `admin-dist/`.
- May include a helper restart script only after `bash -n` validation.
- Must not overwrite `.env.bt`, `compose.bt.yaml`, database data, upload data, or Nginx site config.

## Build Rules

Backend must be cross-compiled locally:

```powershell
cd <PROJECT_ROOT>\backend
$env:GOOS='linux'
$env:GOARCH='amd64'
$env:CGO_ENABLED='0'
go build -trimpath -ldflags='-s -w' -o server ./cmd/server
```

Admin must be built locally:

```powershell
cd <PROJECT_ROOT>\admin
npm.cmd run build
```

Do not use `npm run build` in PowerShell. On this machine it can fail because `npm.ps1` is blocked by the execution policy. Use `npm.cmd run build`.

Admin production API must be verified in the build log:

```text
API_URL = https://api.example.com/api/v1
```

## Windows Packaging Traps

PowerShell wildcard handling caused a bad package once. Avoid these forms:

```powershell
Copy-Item -LiteralPath "admin\dist\*" ...
Compress-Archive -LiteralPath "stage\*" ...
```

`-LiteralPath` does not expand `*`. It can create a package where `admin-dist/` exists but `admin-dist/index.html` and assets are missing.

Use either `-Path` for wildcard expansion or enumerate child items explicitly:

```powershell
Copy-Item -Path "$root\admin\dist\*" -Destination "$stage\admin-dist" -Recurse -Force

$items = Get-ChildItem -LiteralPath $stage -Force | ForEach-Object { $_.FullName }
Compress-Archive -Path $items -DestinationPath $zip -Force
```

For Linux deployment, prefer `tar.gz` created from inside the stage directory:

```powershell
Push-Location $stage
tar -czf "$outDir\genericim-online-overwrite-$ts.tar.gz" .
Pop-Location
```

Windows zip files may store backslash paths. A zip can be kept as a secondary convenience artifact, but the primary server upload should be the `.tar.gz`.

## Required Package Verification

Before handing off a package, verify the archive contents.

For overwrite packages:

```powershell
$tarList = tar -tzf artifacts\online-overwrite-YYYYMMDD-HHMMSS\genericim-online-overwrite-YYYYMMDD-HHMMSS.tar.gz
$tarList -contains './backend/server'
$tarList -contains './admin-dist/index.html'
($tarList | Where-Object { $_ -like './admin-dist/assets/*' }).Count
$tarList | Where-Object { $_ -match '(^|/)\.env(\.bt|\.example)?$' }
```

Expected:
- `./backend/server` is present.
- `./admin-dist/index.html` is present.
- `./admin-dist/assets/*` count is greater than zero.
- No `.env`, `.env.bt`, or `.env.example` entry exists.

Also record hashes:

```powershell
Get-FileHash backend\server -Algorithm SHA256
Get-FileHash artifacts\online-overwrite-YYYYMMDD-HHMMSS\genericim-online-overwrite-YYYYMMDD-HHMMSS.tar.gz -Algorithm SHA256
```

## Restart Script Rules

If a helper script is included, it must be ASCII or UTF-8 without BOM, LF line endings, and validated before packaging:

```bash
bash -n overwrite-restart.sh
```

The safe restart command is:

```bash
cd /www/wwwroot/api.example.com
chmod +x backend/server
docker compose --env-file .env.bt -f compose.bt.yaml restart api admin
```

If the helper script fails, do not redeploy. Run the manual restart command above.

## Server Upload And Extraction

Upload the tarball to:

```text
/www/wwwroot/api.example.com/
```

Verify the file exists before extracting:

```bash
cd /www/wwwroot/api.example.com
ls -lh genericim-online-overwrite-*.tar.gz
tar -xzf genericim-online-overwrite-YYYYMMDD-HHMMSS.tar.gz
chmod +x backend/server
docker compose --env-file .env.bt -f compose.bt.yaml restart api admin
```

If `tar` reports `Cannot open: No such file or directory`, the package was not uploaded to the current directory or the filename is different. Run:

```bash
ls -lh *.tar.gz
```

and use the actual filename.

## Ports And Existing Config

For the current online service:
- API container port mapping is `127.0.0.1:18080->8080`.
- Admin container port mapping is `127.0.0.1:18083->80`.
- Overwrite packages must preserve the existing `compose.bt.yaml`.

Do not rerun full deploy scripts for an overwrite update unless the script explicitly preserves or sets `ADMIN_PORT=18083`. Some scripts default to a different admin port; changing it can break the existing Baota reverse proxy.

## Separate Admin Domain CORS

The online admin domain is:

```text
https://admin.example.com
```

The online API domain is:

```text
https://api.example.com
```

If the admin page loads but login/API calls fail, verify CORS:

```bash
curl -i -H "Origin: https://admin.example.com" https://api.example.com/api/v1/ping
```

Expected response header:

```text
Access-Control-Allow-Origin: https://admin.example.com
```

If missing, update `.env.bt` without changing other secrets:

```bash
cd /www/wwwroot/api.example.com
cp .env.bt .env.bt.bak.$(date +%Y%m%d%H%M%S)
grep -q '^PUBLIC_ORIGIN=' .env.bt \
  && sed -i 's#^PUBLIC_ORIGIN=.*#PUBLIC_ORIGIN=https://api.example.com,https://admin.example.com#' .env.bt \
  || echo 'PUBLIC_ORIGIN=https://api.example.com,https://admin.example.com' >> .env.bt
docker compose --env-file .env.bt -f compose.bt.yaml up -d --force-recreate api admin
```

## Online Verification

After deployment:

```bash
cd /www/wwwroot/api.example.com
docker compose --env-file .env.bt -f compose.bt.yaml ps
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=80 admin
docker compose --env-file .env.bt -f compose.bt.yaml logs --tail=120 api
curl -fsS http://127.0.0.1:18080/health
curl -fsS http://127.0.0.1:18083/
curl -i -H "Origin: https://admin.example.com" https://api.example.com/api/v1/ping
```

Expected:
- `genericim-api` is healthy.
- `genericim-admin` is up.
- Admin Nginx access log returns `200` for `/`, main JS, and assets.
- CORS allows `https://admin.example.com`.

If the page still fails after these checks, collect browser DevTools Console errors and failed Network requests. At that point the issue is frontend runtime or API business response, not packaging, container startup, or reverse proxy.
