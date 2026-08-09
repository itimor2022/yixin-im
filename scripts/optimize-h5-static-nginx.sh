#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${1:-/www/wwwroot/genericim/genericim-online-server}"
ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env.bt}"
COMPOSE_FILE="${COMPOSE_FILE:-$INSTALL_DIR/compose.bt.yaml}"
H5_PORT="${H5_PORT:-18083}"
WEB_DIR="$INSTALL_DIR/web-dist"
NGINX_CONF="$INSTALL_DIR/docker/genericim/h5-nginx.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_CONF="$NGINX_CONF.bak.$STAMP"
ACTIVATED=0

log() {
  printf '[H5-NGINX] %s\n' "$*"
}

fail() {
  printf '[H5-NGINX][ERROR] %s\n' "$*" >&2
  exit 1
}

[ -d "$INSTALL_DIR" ] || fail "Install directory not found: $INSTALL_DIR"
[ -d "$WEB_DIR" ] || fail "H5 web-dist not found: $WEB_DIR"
[ -f "$COMPOSE_FILE" ] || fail "Compose file not found: $COMPOSE_FILE"
[ -f "$NGINX_CONF" ] || fail "H5 Nginx config not found: $NGINX_CONF"
[ -f "$WEB_DIR/main.dart.js" ] || fail "main.dart.js not found"
[ -f "$WEB_DIR/canvaskit/chromium/canvaskit.wasm" ] || fail "CanvasKit WASM not found"
command -v docker >/dev/null 2>&1 || fail "docker is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v gzip >/dev/null 2>&1 || fail "gzip is required"

compose_h5() {
  local files=(-f "$COMPOSE_FILE")
  [ -f "$INSTALL_DIR/compose.storage.yaml" ] && files+=(-f "$INSTALL_DIR/compose.storage.yaml")
  [ -f "$INSTALL_DIR/compose.h5.yaml" ] && files+=(-f "$INSTALL_DIR/compose.h5.yaml")
  [ -f "$INSTALL_DIR/compose.kf.yaml" ] && files+=(-f "$INSTALL_DIR/compose.kf.yaml")

  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  else
    fail "Docker Compose is unavailable"
  fi
}

rollback() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$ACTIVATED" -eq 1 ]; then
    printf '[H5-NGINX][WARN] Validation failed; restoring previous Nginx config.\n' >&2
    cp -f "$BACKUP_CONF" "$NGINX_CONF"
    compose_h5 up -d --force-recreate h5 >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap rollback EXIT

log "Precompressing main JS and CanvasKit WASM files"
gzip -9 -c "$WEB_DIR/main.dart.js" >"$WEB_DIR/main.dart.js.gz"
while IFS= read -r -d '' wasm_file; do
  gzip -9 -c "$wasm_file" >"$wasm_file.gz"
done < <(find "$WEB_DIR/canvaskit" -type f -name '*.wasm' -print0)
chmod a+r "$WEB_DIR/main.dart.js.gz"
find "$WEB_DIR/canvaskit" -type f -name '*.wasm.gz' -exec chmod a+r {} +

cp -a "$NGINX_CONF" "$BACKUP_CONF"
cat >"$NGINX_CONF" <<'EOF'
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    client_max_body_size 100m;

    gzip on;
    gzip_static on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types application/javascript application/json application/wasm text/css text/javascript;

    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
        try_files /index.html =404;
    }

    location = /flutter_bootstrap.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
        try_files $uri =404;
    }

    location = /flutter_service_worker.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
        try_files $uri =404;
    }

    location = /main.dart.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
        try_files $uri =404;
    }

    location /assets/ {
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        try_files $uri =404;
    }

    location ^~ /canvaskit/ {
        add_header Cache-Control "public, max-age=604800" always;
        try_files $uri =404;
    }

    location /api/ {
        proxy_pass http://api:8080/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400s;
        proxy_buffering off;
    }

    location /uploads/ {
        proxy_pass http://api:8080/uploads/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
        try_files $uri $uri/ /index.html;
    }
}
EOF
chmod 644 "$NGINX_CONF"
ACTIVATED=1

log "Recreating H5 container"
compose_h5 up -d --force-recreate h5

for attempt in $(seq 1 20); do
  if curl -fsS --max-time 5 "http://127.0.0.1:$H5_PORT/" >/dev/null; then
    break
  fi
  [ "$attempt" -lt 20 ] || fail "H5 health check failed on port $H5_PORT"
  sleep 1
done

WASM_HEADERS="$(curl -fsSI --max-time 20 -H 'Accept-Encoding: gzip' \
  "http://127.0.0.1:$H5_PORT/canvaskit/chromium/canvaskit.wasm" | tr -d '\r')"
printf '%s\n' "$WASM_HEADERS" | grep -qi '^Content-Encoding: gzip$' || \
  fail "CanvasKit WASM is still not served with gzip"
printf '%s\n' "$WASM_HEADERS" | grep -qi '^Cache-Control: public, max-age=604800$' || \
  fail "CanvasKit cache header is missing"

ACTIVATED=0
trap - EXIT
log "Optimization completed successfully"
printf '[H5-NGINX] Backup config: %s\n' "$BACKUP_CONF"
printf '[H5-NGINX] Verify URL: http://127.0.0.1:%s/canvaskit/chromium/canvaskit.wasm\n' "$H5_PORT"
