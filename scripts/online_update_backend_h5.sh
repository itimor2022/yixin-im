#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$SCRIPT_DIR/payload}"

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }

if [ -z "$INSTALL_DIR" ]; then
  for candidate in \
    "/www/wwwroot/api.example.com" \
    "/www/wwwroot/genericim"; do
    if [ -f "$candidate/.env.bt" ] && [ -f "$candidate/compose.bt.yaml" ]; then
      INSTALL_DIR="$candidate"
      break
    fi
  done
fi

[ -n "$INSTALL_DIR" ] || fail "未找到线上安装目录，请使用 INSTALL_DIR=/实际目录 bash update.sh。"
[ "$INSTALL_DIR" != "/" ] || fail "INSTALL_DIR 不能是根目录。"
[ -d "$INSTALL_DIR" ] || fail "安装目录不存在：$INSTALL_DIR"

ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env.bt}"
COMPOSE_FILE="${COMPOSE_FILE:-$INSTALL_DIR/compose.bt.yaml}"
BACKUP_ROOT="${BACKUP_ROOT:-$INSTALL_DIR/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/backend-h5-admin-update-$STAMP"

[ -f "$ENV_FILE" ] || fail ".env.bt 不存在：$ENV_FILE"
[ -f "$COMPOSE_FILE" ] || fail "compose.bt.yaml 不存在：$COMPOSE_FILE"
[ -f "$PAYLOAD_DIR/backend/server-linux-amd64" ] || fail "更新包缺少后端二进制。"
[ -f "$PAYLOAD_DIR/web-dist/index.html" ] || fail "更新包缺少 H5 index.html。"
[ -f "$PAYLOAD_DIR/web-dist/main.dart.js" ] || fail "更新包缺少 H5 main.dart.js。"
UPDATE_ADMIN=0
if [ -e "$PAYLOAD_DIR/admin-dist" ]; then
  [ -f "$PAYLOAD_DIR/admin-dist/index.html" ] || fail "管理后台目录存在但缺少 index.html。"
  UPDATE_ADMIN=1
fi

if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
  fail "Docker Compose 不可用。"
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-genericim}"
API_PORT="${API_PORT:-18080}"
H5_PORT="${H5_PORT:-18083}"
ADMIN_PORT="${ADMIN_PORT:-18084}"
MYSQL_DATABASE="${MYSQL_DATABASE:-genericim}"
MONGO_DATABASE="${MONGO_DATABASE:-genericim_messages}"
MYSQL_CONTAINER="${PROJECT_NAME}-mysql"
MONGO_CONTAINER="${PROJECT_NAME}-mongodb"
REDIS_CONTAINER="${PROJECT_NAME}-redis"
H5_CONTAINER="${PROJECT_NAME}-h5"
ADMIN_CONTAINER="${PROJECT_NAME}-admin"
H5_CONTENT_DIR="$INSTALL_DIR/web-dist"
H5_NGINX_CONFIG="$INSTALL_DIR/docker/genericim/h5-nginx.conf"
export H5_CONTENT_DIR H5_NGINX_CONFIG

compose_up() {
  local files=("-f" "$COMPOSE_FILE")
  [ -f "$INSTALL_DIR/compose.storage.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.storage.yaml")
  [ -f "$INSTALL_DIR/compose.h5.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.h5.yaml")
  [ -f "$INSTALL_DIR/compose.kf.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.kf.yaml")

  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  else
    docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  fi
}

require_running_container() {
  local container="$1"
  docker ps --format '{{.Names}}' | grep -qx "$container" \
    || fail "依赖容器未运行：$container；尚未覆盖任何线上文件。"
}

replace_dir() {
  local src="$1"
  local dst="$2"
  local staging="${dst}.update-$STAMP"

  case "$dst" in
    "$INSTALL_DIR/web-dist") ;;
    "$INSTALL_DIR/admin-dist") ;;
    *) fail "拒绝覆盖未授权目录：$dst" ;;
  esac

  rm -rf "$staging"
  mkdir -p "$staging"
  cp -a "$src"/. "$staging"/
  rm -rf "$dst"
  mv "$staging" "$dst"
}

wait_http() {
  local url="$1"
  local label="$2"
  local attempts="${3:-60}"
  local interval="${4:-2}"
  local attempt

  for attempt in $(seq 1 "$attempts"); do
    if curl -fsS --connect-timeout 2 --max-time 5 "$url" >/dev/null 2>&1; then
      log "$label 已就绪 ($attempt/$attempts)"
      return 0
    fi
    sleep "$interval"
  done
  return 1
}

write_h5_runtime_files() {
  mkdir -p "$INSTALL_DIR/docker/genericim"

  cat >"$INSTALL_DIR/docker/genericim/h5-nginx.conf" <<'EOF'
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
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
        try_files $uri =404;
    }

    location ^~ /canvaskit/ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
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

  cat >"$INSTALL_DIR/compose.h5.yaml" <<'EOF'
services:
  h5:
    image: nginx:1.27-alpine
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-h5
    ports:
      - "127.0.0.1:${H5_PORT:-18083}:80"
    volumes:
      - type: bind
        source: "${H5_CONTENT_DIR:?H5_CONTENT_DIR is required}"
        target: /usr/share/nginx/html
        read_only: true
      - type: bind
        source: "${H5_NGINX_CONFIG:?H5_NGINX_CONFIG is required}"
        target: /etc/nginx/conf.d/default.conf
        read_only: true
    depends_on:
      api:
        condition: service_healthy
    restart: unless-stopped
EOF
}

info "安装目录：$INSTALL_DIR"
if [ "$UPDATE_ADMIN" -eq 1 ]; then
  info "本包只更新后端/API、H5 与管理后台。"
else
  info "本包只更新后端/API 与 H5。"
fi

require_running_container "$MYSQL_CONTAINER"
require_running_container "$MONGO_CONTAINER"
require_running_container "$REDIS_CONTAINER"

mkdir -p "$BACKUP_DIR"
info "备份目录：$BACKUP_DIR"

if [ -d "$INSTALL_DIR/backend" ]; then
  mkdir -p "$BACKUP_DIR/backend"
  cp -a "$INSTALL_DIR"/backend/server* "$BACKUP_DIR/backend/" 2>/dev/null || true
fi

if [ -d "$INSTALL_DIR/web-dist" ]; then
  tar -czf "$BACKUP_DIR/web-dist.tar.gz" -C "$INSTALL_DIR" web-dist
elif [ -d "$INSTALL_DIR/h5-dist" ]; then
  tar -czf "$BACKUP_DIR/h5-dist.tar.gz" -C "$INSTALL_DIR" h5-dist
fi
if [ "$UPDATE_ADMIN" -eq 1 ] && [ -d "$INSTALL_DIR/admin-dist" ]; then
  tar -czf "$BACKUP_DIR/admin-dist.tar.gz" -C "$INSTALL_DIR" admin-dist
fi

info "备份 MySQL：$MYSQL_DATABASE"
docker exec "$MYSQL_CONTAINER" sh -lc \
  'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
  >"$BACKUP_DIR/mysql.sql" || fail "MySQL 备份失败，更新已在覆盖前终止。"

info "备份 MongoDB：$MONGO_DATABASE"
docker exec "$MONGO_CONTAINER" mongodump --archive --gzip \
  --username "$MONGO_ROOT_USERNAME" \
  --password "$MONGO_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --db "$MONGO_DATABASE" \
  >"$BACKUP_DIR/mongodb.archive.gz" || fail "MongoDB 备份失败，更新已在覆盖前终止。"

info "备份 Redis"
docker exec "$REDIS_CONTAINER" redis-cli SAVE >/dev/null 2>&1 \
  || fail "Redis SAVE 失败，更新已在覆盖前终止。"
docker cp "$REDIS_CONTAINER:/data/dump.rdb" "$BACKUP_DIR/redis-dump.rdb" >/dev/null 2>&1 \
  || fail "Redis 备份复制失败，更新已在覆盖前终止。"

info "覆盖 H5"
replace_dir "$PAYLOAD_DIR/web-dist" "$INSTALL_DIR/web-dist"
chmod -R a+rX "$INSTALL_DIR/web-dist"

expected_h5_sha="$(sha256sum "$PAYLOAD_DIR/web-dist/main.dart.js" | awk '{print $1}')"
installed_h5_sha="$(sha256sum "$INSTALL_DIR/web-dist/main.dart.js" | awk '{print $1}')"
[ "$expected_h5_sha" = "$installed_h5_sha" ] || fail "H5 覆盖后的 main.dart.js 校验失败。"

if [ "$UPDATE_ADMIN" -eq 1 ]; then
  info "覆盖管理后台"
  replace_dir "$PAYLOAD_DIR/admin-dist" "$INSTALL_DIR/admin-dist"
  chmod -R a+rX "$INSTALL_DIR/admin-dist"

  expected_admin_sha="$(sha256sum "$PAYLOAD_DIR/admin-dist/index.html" | awk '{print $1}')"
  installed_admin_sha="$(sha256sum "$INSTALL_DIR/admin-dist/index.html" | awk '{print $1}')"
  [ "$expected_admin_sha" = "$installed_admin_sha" ] || fail "管理后台覆盖后的 index.html 校验失败。"
fi

info "覆盖后端/API 二进制"
mkdir -p "$INSTALL_DIR/backend"
cp -f "$PAYLOAD_DIR/backend/server-linux-amd64" "$INSTALL_DIR/backend/server-linux-amd64"
cp -f "$PAYLOAD_DIR/backend/server-linux-amd64" "$INSTALL_DIR/backend/server"
chmod 0755 "$INSTALL_DIR/backend/server-linux-amd64" "$INSTALL_DIR/backend/server"

expected_backend_sha="$(sha256sum "$PAYLOAD_DIR/backend/server-linux-amd64" | awk '{print $1}')"
installed_backend_sha="$(sha256sum "$INSTALL_DIR/backend/server" | awk '{print $1}')"
[ "$expected_backend_sha" = "$installed_backend_sha" ] || fail "后端二进制覆盖校验失败。"

write_h5_runtime_files

info "重建 API 容器"
compose_up up -d --no-deps --force-recreate api || {
  compose_up logs --tail=200 api || true
  fail "API 容器重建失败；备份位于 $BACKUP_DIR。"
}

info "启动/更新 H5 容器"
compose_up up -d --no-deps --force-recreate h5 || {
  compose_up logs --tail=120 h5 || true
  fail "H5 容器启动失败；备份位于 $BACKUP_DIR。"
}

if ! docker exec "$H5_CONTAINER" sh -lc \
  'test -s /usr/share/nginx/html/index.html && test -s /usr/share/nginx/html/main.dart.js'; then
  warn "H5 容器没有挂载到本次更新文件，输出挂载诊断："
  docker inspect --format \
    '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' \
    "$H5_CONTAINER" || true
  ls -la "$INSTALL_DIR/web-dist" | head -40 || true
  fail "H5 容器文件挂载失败；备份位于 $BACKUP_DIR。"
fi

if [ "$UPDATE_ADMIN" -eq 1 ]; then
  info "重建管理后台容器"
  compose_up up -d --no-deps --force-recreate admin || {
    compose_up logs --tail=120 admin || true
    fail "管理后台容器重建失败；备份位于 $BACKUP_DIR。"
  }

  if ! docker exec "$ADMIN_CONTAINER" sh -lc \
    'test -s /usr/share/nginx/html/index.html'; then
    warn "管理后台容器没有挂载到本次更新文件，输出挂载诊断："
    docker inspect --format \
      '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' \
      "$ADMIN_CONTAINER" || true
    fail "管理后台容器文件挂载失败；备份位于 $BACKUP_DIR。"
  fi
fi

info "执行健康检查"
wait_http "http://127.0.0.1:${API_PORT}/health" "API" 60 2 || {
  compose_up logs --tail=200 api || true
  fail "API 健康检查失败；备份位于 $BACKUP_DIR。"
}
wait_http "http://127.0.0.1:${H5_PORT}/" "H5" 30 2 || {
  compose_up logs --tail=120 h5 || true
  fail "H5 健康检查失败；备份位于 $BACKUP_DIR。"
}
if [ "$UPDATE_ADMIN" -eq 1 ]; then
  wait_http "http://127.0.0.1:${ADMIN_PORT}/" "管理后台" 30 2 || {
    compose_up logs --tail=120 admin || true
    fail "管理后台健康检查失败；备份位于 $BACKUP_DIR。"
  }
fi

h5_headers="$(curl -fsSI "http://127.0.0.1:${H5_PORT}/main.dart.js")" \
  || fail "H5 main.dart.js 响应头检查失败。"
printf '%s\n' "$h5_headers" | grep -qi '^Cache-Control:.*no-store' \
  || fail "H5 main.dart.js 未设置 no-store。"

served_h5_sha="$(curl -fsS "http://127.0.0.1:${H5_PORT}/main.dart.js?update-check=${expected_h5_sha}" | sha256sum | awk '{print $1}')"
[ "$served_h5_sha" = "$expected_h5_sha" ] \
  || fail "H5 容器仍未提供本次更新的 main.dart.js。"

if [ "$UPDATE_ADMIN" -eq 1 ]; then
  served_admin_sha="$(curl -fsS "http://127.0.0.1:${ADMIN_PORT}/?update-check=${expected_admin_sha}" | sha256sum | awk '{print $1}')"
  [ "$served_admin_sha" = "$expected_admin_sha" ] \
    || fail "管理后台容器仍未提供本次更新的 index.html。"
  log "后端/API、H5 与管理后台覆盖更新完成。"
else
  log "后端/API 与 H5 覆盖更新完成。"
fi
printf 'Backup: %s\n' "$BACKUP_DIR"
printf 'API:    http://127.0.0.1:%s/health\n' "$API_PORT"
printf 'H5:     http://127.0.0.1:%s/\n' "$H5_PORT"
if [ "$UPDATE_ADMIN" -eq 1 ]; then
  printf 'Admin:  http://127.0.0.1:%s/\n' "$ADMIN_PORT"
fi
