#!/usr/bin/env bash
# 覆盖更新已部署的 Docker 后端、管理端、Flutter Web、H5 和客服端静态产物。
# 执行前要求 payload、.env.bt 和 compose.bt.yaml 均已准备完成；脚本先创建
# 带时间戳的备份，再替换文件并重启服务。INSTALL_DIR、PAYLOAD_DIR 等变量可
# 覆盖默认路径，生产执行前必须确认它们指向目标站点而不是源码仓库。
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$SCRIPT_DIR}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$SCRIPT_DIR/payload}"
ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env.bt}"
COMPOSE_FILE="${COMPOSE_FILE:-$INSTALL_DIR/compose.bt.yaml}"
BACKUP_ROOT="${BACKUP_ROOT:-$INSTALL_DIR/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/update-$STAMP"
DEFAULT_KF_DOMAIN="support.example.com"
DEFAULT_KF_PORT="18085"
DEFAULT_H5_DOMAIN="h5.example.com"

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
  else
    fail "Docker Compose is unavailable."
  fi
}

copy_dir() {
  # 目标目录会被完整替换；可恢复副本由主流程预先写入 BACKUP_DIR。
  local src="$1"
  local dst="$2"
  rm -rf "$dst"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$src"/ "$dst"/
  else
    cp -a "$src"/. "$dst"/
  fi
}

ensure_static_read_permissions() {
  local path
  for path in "$INSTALL_DIR/admin-dist" "$INSTALL_DIR/web-dist" "$INSTALL_DIR/h5-dist" "$INSTALL_DIR/kf-dist" "$INSTALL_DIR/docker/genericim"; do
    [ -e "$path" ] || continue
    chmod -R a+rX "$path" || warn "Failed to adjust read permissions for $path"
  done
}

[ -d "$PAYLOAD_DIR" ] || fail "payload directory not found: $PAYLOAD_DIR"
[ -f "$ENV_FILE" ] || fail ".env.bt not found: $ENV_FILE"
[ -f "$COMPOSE_FILE" ] || fail "compose.bt.yaml not found: $COMPOSE_FILE"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-genericim}"
API_PORT="${API_PORT:-18080}"
ADMIN_PORT="${ADMIN_PORT:-18084}"
H5_PORT="${H5_PORT:-18083}"
KF_PORT="${KF_PORT:-$DEFAULT_KF_PORT}"
KF_DOMAIN="${KF_DOMAIN:-$DEFAULT_KF_DOMAIN}"
H5_DOMAIN="${H5_DOMAIN:-$DEFAULT_H5_DOMAIN}"
MYSQL_DATABASE="${MYSQL_DATABASE:-genericim}"
MONGO_DATABASE="${MONGO_DATABASE:-genericim_messages}"

set_env_value() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { written = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      written = 1
      next
    }
    { print }
    END {
      if (!written) print key "=" value
    }
  ' "$ENV_FILE" >"$tmp"
  mv "$tmp" "$ENV_FILE"
}

public_scheme() {
  local scheme
  case "${PUBLIC_URL:-}" in
    https://*) scheme="https" ;;
    http://*) scheme="http" ;;
    *) scheme="https" ;;
  esac
  printf '%s' "$scheme"
}

append_public_origin() {
  local origin="$1"
  [ -n "$origin" ] || return 0

  case ",${PUBLIC_ORIGIN:-}," in
    *,"$origin",*) ;;
    *)
      PUBLIC_ORIGIN="${PUBLIC_ORIGIN:+$PUBLIC_ORIGIN,}$origin"
      set_env_value PUBLIC_ORIGIN "$PUBLIC_ORIGIN"
      ;;
  esac

  return 0
}

ensure_public_origins_env() {
  local scheme api_origin admin_origin
  scheme="$(public_scheme)"

  if [ -d "$INSTALL_DIR/kf-dist" ] && [ -n "$KF_DOMAIN" ] && [ "$KF_DOMAIN" != "_" ]; then
    KF_ORIGIN="${KF_ORIGIN:-${scheme}://${KF_DOMAIN}}"
    set_env_value KF_ORIGIN "$KF_ORIGIN"
    append_public_origin "$KF_ORIGIN"
  fi
  set_env_value KF_PORT "$KF_PORT"

  if [ -d "$INSTALL_DIR/web-dist" ] || [ -d "$INSTALL_DIR/h5-dist" ]; then
    H5_ORIGIN="${H5_ORIGIN:-${scheme}://${H5_DOMAIN}}"
    set_env_value H5_ORIGIN "$H5_ORIGIN"
    append_public_origin "$H5_ORIGIN"
  fi
  set_env_value H5_PORT "$H5_PORT"
  set_env_value ADMIN_PORT "$ADMIN_PORT"

  api_origin="${PUBLIC_URL:-}"
  [ -n "$api_origin" ] && append_public_origin "$api_origin"

  admin_origin="${ADMIN_ORIGIN:-}"
  [ -n "$admin_origin" ] && append_public_origin "$admin_origin"

  return 0
}

ensure_storage_env_defaults() {
  STORAGE_PROVIDER="${STORAGE_PROVIDER:-local}"
  STORAGE_LOCAL_BASE_URL="${STORAGE_LOCAL_BASE_URL:-${PUBLIC_URL:-}}"
  STORAGE_ALIYUN_ENDPOINT="${STORAGE_ALIYUN_ENDPOINT:-}"
  STORAGE_ALIYUN_BUCKET="${STORAGE_ALIYUN_BUCKET:-}"
  STORAGE_ALIYUN_ACCESS_KEY_ID="${STORAGE_ALIYUN_ACCESS_KEY_ID:-}"
  STORAGE_ALIYUN_ACCESS_KEY_SECRET="${STORAGE_ALIYUN_ACCESS_KEY_SECRET:-}"
  STORAGE_ALIYUN_PUBLIC_BASE_URL="${STORAGE_ALIYUN_PUBLIC_BASE_URL:-}"
  STORAGE_ALIYUN_USE_HTTPS="${STORAGE_ALIYUN_USE_HTTPS:-true}"
  STORAGE_QINIU_UPLOAD_URL="${STORAGE_QINIU_UPLOAD_URL:-https://upload.qiniup.com}"
  STORAGE_QINIU_BUCKET="${STORAGE_QINIU_BUCKET:-}"
  STORAGE_QINIU_ACCESS_KEY="${STORAGE_QINIU_ACCESS_KEY:-}"
  STORAGE_QINIU_SECRET_KEY="${STORAGE_QINIU_SECRET_KEY:-}"
  STORAGE_QINIU_PUBLIC_BASE_URL="${STORAGE_QINIU_PUBLIC_BASE_URL:-}"
  STORAGE_QINIU_USE_HTTPS="${STORAGE_QINIU_USE_HTTPS:-true}"
  STORAGE_S3_REGION="${STORAGE_S3_REGION:-}"
  STORAGE_S3_BUCKET="${STORAGE_S3_BUCKET:-}"
  STORAGE_S3_PUBLIC_BASE_URL="${STORAGE_S3_PUBLIC_BASE_URL:-}"
  STORAGE_S3_ENDPOINT="${STORAGE_S3_ENDPOINT:-}"
  STORAGE_S3_USE_PATH_STYLE="${STORAGE_S3_USE_PATH_STYLE:-false}"
  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

  set_env_value STORAGE_PROVIDER "$STORAGE_PROVIDER"
  set_env_value STORAGE_LOCAL_BASE_URL "$STORAGE_LOCAL_BASE_URL"
  set_env_value STORAGE_ALIYUN_ENDPOINT "$STORAGE_ALIYUN_ENDPOINT"
  set_env_value STORAGE_ALIYUN_BUCKET "$STORAGE_ALIYUN_BUCKET"
  set_env_value STORAGE_ALIYUN_ACCESS_KEY_ID "$STORAGE_ALIYUN_ACCESS_KEY_ID"
  set_env_value STORAGE_ALIYUN_ACCESS_KEY_SECRET "$STORAGE_ALIYUN_ACCESS_KEY_SECRET"
  set_env_value STORAGE_ALIYUN_PUBLIC_BASE_URL "$STORAGE_ALIYUN_PUBLIC_BASE_URL"
  set_env_value STORAGE_ALIYUN_USE_HTTPS "$STORAGE_ALIYUN_USE_HTTPS"
  set_env_value STORAGE_QINIU_UPLOAD_URL "$STORAGE_QINIU_UPLOAD_URL"
  set_env_value STORAGE_QINIU_BUCKET "$STORAGE_QINIU_BUCKET"
  set_env_value STORAGE_QINIU_ACCESS_KEY "$STORAGE_QINIU_ACCESS_KEY"
  set_env_value STORAGE_QINIU_SECRET_KEY "$STORAGE_QINIU_SECRET_KEY"
  set_env_value STORAGE_QINIU_PUBLIC_BASE_URL "$STORAGE_QINIU_PUBLIC_BASE_URL"
  set_env_value STORAGE_QINIU_USE_HTTPS "$STORAGE_QINIU_USE_HTTPS"
  set_env_value STORAGE_S3_REGION "$STORAGE_S3_REGION"
  set_env_value STORAGE_S3_BUCKET "$STORAGE_S3_BUCKET"
  set_env_value STORAGE_S3_PUBLIC_BASE_URL "$STORAGE_S3_PUBLIC_BASE_URL"
  set_env_value STORAGE_S3_ENDPOINT "$STORAGE_S3_ENDPOINT"
  set_env_value STORAGE_S3_USE_PATH_STYLE "$STORAGE_S3_USE_PATH_STYLE"
  set_env_value AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
  set_env_value AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  set_env_value AWS_SESSION_TOKEN "$AWS_SESSION_TOKEN"
}

write_storage_compose_override() {
  cat >"$INSTALL_DIR/compose.storage.yaml" <<'EOF'
services:
  api:
    environment:
      GENERIC_IM_SETTINGS_ENCRYPTION_KEY: ${SETTINGS_ENCRYPTION_KEY:-}
      GENERIC_IM_STORAGE_PROVIDER: ${STORAGE_PROVIDER:-local}
      GENERIC_IM_STORAGE_LOCAL_BASE_URL: ${STORAGE_LOCAL_BASE_URL:-}
      GENERIC_IM_STORAGE_ALIYUN_ENDPOINT: ${STORAGE_ALIYUN_ENDPOINT:-}
      GENERIC_IM_STORAGE_ALIYUN_BUCKET: ${STORAGE_ALIYUN_BUCKET:-}
      GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_ID: ${STORAGE_ALIYUN_ACCESS_KEY_ID:-}
      GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_SECRET: ${STORAGE_ALIYUN_ACCESS_KEY_SECRET:-}
      GENERIC_IM_STORAGE_ALIYUN_PUBLIC_BASE_URL: ${STORAGE_ALIYUN_PUBLIC_BASE_URL:-}
      GENERIC_IM_STORAGE_ALIYUN_USE_HTTPS: ${STORAGE_ALIYUN_USE_HTTPS:-true}
      GENERIC_IM_STORAGE_QINIU_UPLOAD_URL: ${STORAGE_QINIU_UPLOAD_URL:-https://upload.qiniup.com}
      GENERIC_IM_STORAGE_QINIU_BUCKET: ${STORAGE_QINIU_BUCKET:-}
      GENERIC_IM_STORAGE_QINIU_ACCESS_KEY: ${STORAGE_QINIU_ACCESS_KEY:-}
      GENERIC_IM_STORAGE_QINIU_SECRET_KEY: ${STORAGE_QINIU_SECRET_KEY:-}
      GENERIC_IM_STORAGE_QINIU_PUBLIC_BASE_URL: ${STORAGE_QINIU_PUBLIC_BASE_URL:-}
      GENERIC_IM_STORAGE_QINIU_USE_HTTPS: ${STORAGE_QINIU_USE_HTTPS:-true}
      GENERIC_IM_STORAGE_S3_REGION: ${STORAGE_S3_REGION:-}
      GENERIC_IM_STORAGE_S3_BUCKET: ${STORAGE_S3_BUCKET:-}
      GENERIC_IM_STORAGE_S3_PUBLIC_BASE_URL: ${STORAGE_S3_PUBLIC_BASE_URL:-}
      GENERIC_IM_STORAGE_S3_ENDPOINT: ${STORAGE_S3_ENDPOINT:-}
      GENERIC_IM_STORAGE_S3_USE_PATH_STYLE: ${STORAGE_S3_USE_PATH_STYLE:-false}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-}
      AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:-}
EOF
}

write_h5_compose_override() {
  [ -d "$INSTALL_DIR/web-dist" ] || return 0
  mkdir -p "$INSTALL_DIR/docker/genericim"
  # Always replace this file. Older deployments cached main.dart.js for one hour,
  # which kept serving the previous Flutter bundle after an otherwise successful update.
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
      - ./web-dist:/usr/share/nginx/html:ro
      - ./docker/genericim/h5-nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      api:
        condition: service_healthy
    restart: unless-stopped
EOF
}

write_kf_compose_override() {
  [ -d "$INSTALL_DIR/kf-dist" ] || return 0
  mkdir -p "$INSTALL_DIR/docker/genericim"
  if [ ! -f "$INSTALL_DIR/docker/genericim/kf-nginx.conf" ]; then
    cat >"$INSTALL_DIR/docker/genericim/kf-nginx.conf" <<'EOF'
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    client_max_body_size 100m;

    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
        try_files /index.html =404;
    }

    location /assets/ {
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
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
  fi

  cat >"$INSTALL_DIR/compose.kf.yaml" <<'EOF'
services:
  kf:
    image: nginx:1.27-alpine
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-kf
    ports:
      - "127.0.0.1:${KF_PORT:-18085}:80"
    volumes:
      - ./kf-dist:/usr/share/nginx/html:ro
      - ./docker/genericim/kf-nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      api:
        condition: service_healthy
    restart: unless-stopped
EOF
}

write_kf_nginx_vhost() {
  [ -d "$INSTALL_DIR/kf-dist" ] || return 0
  [ -n "$KF_DOMAIN" ] && [ "$KF_DOMAIN" != "_" ] || return 0

  if [ -d /www/server/panel/vhost/rewrite ]; then
    cat >/www/server/panel/vhost/rewrite/${PROJECT_NAME}-kf.conf <<'EOF'
# Official service SPA fallback is handled by the kf container Nginx:
# location / { try_files $uri $uri/ /index.html; }
EOF
  fi

  info "Baota should own SSL/renewal for all public domains. Set $KF_DOMAIN reverse proxy target to http://127.0.0.1:$KF_PORT"
}

compose_up() {
  local files=("-f" "$COMPOSE_FILE")
  [ -f "$INSTALL_DIR/compose.storage.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.storage.yaml")
  [ -f "$INSTALL_DIR/compose.h5.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.h5.yaml")
  [ -f "$INSTALL_DIR/compose.kf.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.kf.yaml")

  if [ "${#files[@]}" -gt 2 ]; then
    if docker compose version >/dev/null 2>&1; then
      docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
      docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
    else
      fail "Docker Compose is unavailable."
    fi
    return 0
  fi
  compose_cmd "$@"
}

wait_http() {
  local url="$1"
  local label="$2"
  local attempts="${3:-60}"
  local interval="${4:-2}"
  local attempt

  for attempt in $(seq 1 "$attempts"); do
    if curl -fsS --connect-timeout 2 --max-time 5 "$url" >/dev/null 2>&1; then
      log "$label is ready ($attempt/$attempts)"
      return 0
    fi
    sleep "$interval"
  done
  return 1
}

mkdir -p "$BACKUP_DIR"
info "Backup directory: $BACKUP_DIR"

if [ -d "$INSTALL_DIR/admin-dist" ]; then
  tar -czf "$BACKUP_DIR/admin-dist.tar.gz" -C "$INSTALL_DIR" admin-dist
fi

if [ -d "$INSTALL_DIR/web-dist" ]; then
  tar -czf "$BACKUP_DIR/web-dist.tar.gz" -C "$INSTALL_DIR" web-dist
elif [ -d "$INSTALL_DIR/h5-dist" ]; then
  tar -czf "$BACKUP_DIR/h5-dist.tar.gz" -C "$INSTALL_DIR" h5-dist
fi

if [ -d "$INSTALL_DIR/kf-dist" ]; then
  tar -czf "$BACKUP_DIR/kf-dist.tar.gz" -C "$INSTALL_DIR" kf-dist
fi

if [ -d "$INSTALL_DIR/backend" ]; then
  mkdir -p "$BACKUP_DIR/backend"
  cp -a "$INSTALL_DIR"/backend/server* "$BACKUP_DIR/backend/" 2>/dev/null || true
fi

MYSQL_CONTAINER="${PROJECT_NAME}-mysql"
MONGO_CONTAINER="${PROJECT_NAME}-mongodb"
REDIS_CONTAINER="${PROJECT_NAME}-redis"

if docker ps --format '{{.Names}}' | grep -qx "$MYSQL_CONTAINER"; then
  info "Backing up MySQL database $MYSQL_DATABASE"
  docker exec "$MYSQL_CONTAINER" sh -lc \
    'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
    > "$BACKUP_DIR/mysql.sql" || fail "MySQL backup failed; update aborted."

  info "Clearing legacy default admin emails"
  docker exec -i "$MYSQL_CONTAINER" sh -lc \
    'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' <<'SQL' || warn "Clear default admin emails failed."
UPDATE admins
SET email = NULL, updated_at = NOW()
WHERE username = 'admin'
  AND (email IS NULL OR email IN ('', 'admin@example.invalid', 'admin@admin.local'));
UPDATE admins
SET email = NULL, updated_at = NOW()
WHERE username = 'demo'
  AND (email IS NULL OR email IN ('', 'demo@example.invalid', 'demo@admin.local'));
SQL
else
  fail "MySQL container is not running; update aborted before overwrite."
fi

if docker ps --format '{{.Names}}' | grep -qx "$MONGO_CONTAINER"; then
  info "Backing up MongoDB database $MONGO_DATABASE"
  docker exec "$MONGO_CONTAINER" mongodump --archive --gzip \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db "$MONGO_DATABASE" \
    > "$BACKUP_DIR/mongodb.archive.gz" || fail "MongoDB backup failed; update aborted."
else
  fail "MongoDB container is not running; update aborted before overwrite."
fi

if docker ps --format '{{.Names}}' | grep -qx "$REDIS_CONTAINER"; then
  info "Backing up Redis dump"
  docker exec "$REDIS_CONTAINER" redis-cli SAVE >/dev/null 2>&1 || fail "Redis SAVE failed; update aborted."
  docker cp "$REDIS_CONTAINER:/data/dump.rdb" "$BACKUP_DIR/redis-dump.rdb" >/dev/null 2>&1 || fail "Redis dump copy failed; update aborted."
else
  fail "Redis container is not running; update aborted before overwrite."
fi

if [ -d "$PAYLOAD_DIR/admin-dist" ]; then
  info "Updating admin-dist"
  copy_dir "$PAYLOAD_DIR/admin-dist" "$INSTALL_DIR/admin-dist"
fi

if [ -d "$PAYLOAD_DIR/web-dist" ]; then
  info "Updating web-dist"
  copy_dir "$PAYLOAD_DIR/web-dist" "$INSTALL_DIR/web-dist"
  cmp -s "$PAYLOAD_DIR/web-dist/main.dart.js" "$INSTALL_DIR/web-dist/main.dart.js" \
    || fail "Installed H5 main.dart.js does not match the update payload."
elif [ -d "$PAYLOAD_DIR/h5-dist" ]; then
  info "Updating h5-dist"
  copy_dir "$PAYLOAD_DIR/h5-dist" "$INSTALL_DIR/h5-dist"
fi

if [ -d "$PAYLOAD_DIR/kf-dist" ]; then
  info "Updating kf-dist"
  copy_dir "$PAYLOAD_DIR/kf-dist" "$INSTALL_DIR/kf-dist"
fi

if [ -f "$PAYLOAD_DIR/docker/genericim/kf-nginx.conf" ]; then
  info "Updating kf nginx config"
  mkdir -p "$INSTALL_DIR/docker/genericim"
  cp -a "$PAYLOAD_DIR/docker/genericim/kf-nginx.conf" "$INSTALL_DIR/docker/genericim/kf-nginx.conf"
fi

if [ -d "$PAYLOAD_DIR/backend" ]; then
  info "Updating backend binary"
  mkdir -p "$INSTALL_DIR/backend"
  cp -a "$PAYLOAD_DIR"/backend/server* "$INSTALL_DIR/backend/" 2>/dev/null || true
  if [ -f "$INSTALL_DIR/backend/server-linux-amd64" ]; then
    cp -f "$INSTALL_DIR/backend/server-linux-amd64" "$INSTALL_DIR/backend/server"
  fi
  chmod +x "$INSTALL_DIR"/backend/server* 2>/dev/null || true
fi

info "Fixing static file permissions"
ensure_static_read_permissions

info "Restarting Docker services"
write_h5_compose_override
write_kf_compose_override
ensure_public_origins_env
ensure_storage_env_defaults
write_storage_compose_override
if ! compose_up up -d --remove-orphans; then
  warn "Docker compose up returned non-zero. Current compose state:"
  compose_up ps || true
  warn "Recent service logs:"
  compose_up logs --tail=120 api admin h5 kf || true
  fail "Docker services failed to start. Check the logs above."
fi
# The API executable is bind-mounted as a single file. Recreate the container so
# Docker cannot keep the previous inode after the binary is replaced on disk.
compose_up up -d --force-recreate api || fail "API container recreation failed."
compose_up restart admin || warn "Docker restart admin returned non-zero; continuing to health checks."
if [ -d "$INSTALL_DIR/web-dist" ]; then
  compose_up restart h5 >/dev/null 2>&1 || true
fi
if [ -d "$INSTALL_DIR/kf-dist" ]; then
  compose_up restart kf >/dev/null 2>&1 || true
fi
write_kf_nginx_vhost

if [ -f "$PAYLOAD_DIR/square-content/seed.sql" ] && [ -d "$PAYLOAD_DIR/square-content/images" ]; then
  API_CONTAINER="${PROJECT_NAME}-api"
  SQUARE_UPLOAD_DIR="/app/uploads/square/release-20260723"
  info "Deploying curated release-note images"
  docker exec "$API_CONTAINER" mkdir -p "$SQUARE_UPLOAD_DIR" \
    || fail "Could not create the curated square image directory."
  docker cp "$PAYLOAD_DIR/square-content/images/." "$API_CONTAINER:$SQUARE_UPLOAD_DIR/" \
    || fail "Could not deploy curated square images."
  docker exec "$API_CONTAINER" chmod -R a+rX "$SQUARE_UPLOAD_DIR" \
    || warn "Could not adjust curated square image permissions."

  info "Importing curated square release notes"
  docker exec -i "$MYSQL_CONTAINER" sh -lc \
    'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
    < "$PAYLOAD_DIR/square-content/seed.sql" \
    || fail "Curated square release-note import failed. Restore from $BACKUP_DIR/mysql.sql if needed."
fi

if [ -f "$PAYLOAD_DIR/appstore-review/account.sql" ] && [ -f "$PAYLOAD_DIR/appstore-review/messages.js" ]; then
  info "Resetting the dedicated App Store review account"
  docker exec -i "$MYSQL_CONTAINER" sh -lc \
    'mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
    < "$PAYLOAD_DIR/appstore-review/account.sql" \
    || fail "App Store review account import failed. Restore from $BACKUP_DIR/mysql.sql if needed."

  info "Importing the two curated review conversations"
  docker exec -i "$MONGO_CONTAINER" mongosh --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    "$MONGO_DATABASE" \
    < "$PAYLOAD_DIR/appstore-review/messages.js" \
    || fail "App Store review messages import failed. Restore from $BACKUP_DIR/mongodb.archive.gz if needed."
fi

info "Waiting for health checks"
if ! wait_http "http://127.0.0.1:${API_PORT}/health" "API" 60 2; then
  warn "API did not become ready within 120 seconds. Current compose state:"
  compose_up ps || true
  warn "Recent API logs:"
  compose_up logs --tail=200 api || true
  fail "API health check failed."
fi
wait_http "http://127.0.0.1:${ADMIN_PORT}/" "Admin" 30 2 || fail "Admin health check failed."
if [ -d "$INSTALL_DIR/web-dist" ] || [ -d "$INSTALL_DIR/h5-dist" ]; then
  wait_http "http://127.0.0.1:${H5_PORT}/" "H5" 30 2 || fail "H5 health check failed."
fi
if [ -d "$INSTALL_DIR/web-dist" ]; then
  h5_main_headers="$(curl -fsSI "http://127.0.0.1:${H5_PORT}/main.dart.js")" \
    || fail "H5 main.dart.js header check failed."
  printf '%s\n' "$h5_main_headers" | grep -qi '^Cache-Control:.*no-store' \
    || fail "H5 main.dart.js is still cacheable; expected Cache-Control no-store."
  expected_h5_sha="$(sha256sum "$INSTALL_DIR/web-dist/main.dart.js" | awk '{print $1}')"
  served_h5_sha="$(curl -fsS "http://127.0.0.1:${H5_PORT}/main.dart.js?update-check=${expected_h5_sha}" | sha256sum | awk '{print $1}')"
  [ "$served_h5_sha" = "$expected_h5_sha" ] \
    || fail "H5 container is not serving the newly installed main.dart.js."
fi
if [ -d "$INSTALL_DIR/kf-dist" ]; then
  wait_http "http://127.0.0.1:${KF_PORT}/" "KF" 30 2 || fail "KF health check failed."
fi

log "Update complete."
printf '\nBackup: %s\n' "$BACKUP_DIR"
printf 'Admin:  %s\n' "${ADMIN_ORIGIN:-}"
printf 'API:    %s\n' "${PUBLIC_URL:-}"
printf 'H5:     %s\n' "${H5_ORIGIN:-}"
printf 'KF:     %s\n' "${KF_ORIGIN:-https://$KF_DOMAIN}"
