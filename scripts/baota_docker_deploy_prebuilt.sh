#!/usr/bin/env bash
# 使用预编译镜像和静态产物部署通用IM，避免在低配置宝塔主机上现场编译。
# 默认不改写 Nginx；只有显式传入 --write-nginx 才配置反向代理。
# 脚本会写入安装目录和环境配置，生产执行前必须核对域名、端口及管理员密码。
set -Eeuo pipefail

PROJECT_NAME="genericim"
INSTALL_DIR="/www/wwwroot/genericim"
DOMAIN=""
ADMIN_DOMAIN=""
API_DOMAIN=""
H5_DOMAIN=""
KF_DOMAIN=""
PUBLIC_SCHEME="https"
MIRROR_MODE="cn"
API_PORT="18080"
ADMIN_PORT="18084"
H5_PORT="18083"
KF_PORT="18085"
MYSQL_PORT="13306"
MONGO_PORT="17017"
REDIS_PORT="16379"
CREATE_NGINX="0"
ASSUME_YES="0"
INITIAL_ADMIN_PASSWORD=""
ADMIN_PASSWORD_PROVIDED="0"
DEFAULT_INITIAL_ADMIN_PASSWORD="123456"

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  bash scripts/baota_docker_deploy_prebuilt.sh [options]

Options:
  --domain DOMAIN           Single domain for admin and API
  --admin-domain DOMAIN     Admin domain
  --api-domain DOMAIN       API/media domain
  --h5-domain DOMAIN        H5 frontend domain. Leave empty to skip H5 vhost
  --kf-domain DOMAIN        Official service admin domain. Leave empty to skip service vhost
  --install-dir DIR         Deploy directory. Default: /www/wwwroot/genericim
  --scheme http|https       Public scheme. Default: https
  --mirror cn|global        Docker pull mirror hint. Default: cn
  --admin-port PORT         Local admin container port. Default: 18084
  --api-port PORT           Local api container port. Default: 18080
  --h5-port PORT            Local H5 container port. Default: 18083
  --kf-port PORT            Local official service admin container port. Default: 18085
  --mysql-port PORT         Local MySQL bind port. Default: 13306
  --mongo-port PORT         Local MongoDB bind port. Default: 17017
  --redis-port PORT         Local Redis bind port. Default: 16379
  --admin-password PASS     Initial admin password on first deploy. Default: 123456
  --write-nginx             Configure Baota proxy without replacing its site or SSL config
  --no-nginx                Do not write Baota/Nginx vhost config. Default
  -y, --yes                 Non-interactive
  -h, --help                Show this help

Storage environment overrides:
  STORAGE_PROVIDER=aliyun
  STORAGE_ALIYUN_ENDPOINT=oss-cn-hangzhou.aliyuncs.com
  STORAGE_ALIYUN_BUCKET=your-bucket
  STORAGE_ALIYUN_ACCESS_KEY_ID=your-access-key-id
  STORAGE_ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret
  STORAGE_ALIYUN_PUBLIC_BASE_URL=https://media.example.com
EOF
}

quick_random_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -d '=+/[:space:]' | cut -c1-16
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
  fi
}

rand_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    tr -dc 'a-f0-9' </dev/urandom | head -c "$((2 * $1))"
  fi
}

read_env_value() {
  local key="$1"
  local file="${2:-}"
  local value

  read_one_env_file() {
    local env_file="$1"
    [ -f "$env_file" ] || return 0
    awk -v key="$key" '
    BEGIN { FS = "=" }
    $1 == key {
      sub(/^[^=]*=/, "")
      print
      exit
    }
    ' "$env_file"
  }

  if [ -n "$file" ]; then
    read_one_env_file "$file"
    return 0
  fi

  local candidates=()
  [ -n "${INSTALL_DIR:-}" ] && candidates+=("$(dirname "$INSTALL_DIR")/.env.bt")
  [ -n "${SOURCE_DIR:-}" ] && candidates+=("$(dirname "$SOURCE_DIR")/.env.bt")
  candidates+=(".env.bt")
  [ -n "${INSTALL_DIR:-}" ] && candidates+=("$INSTALL_DIR/.env.bt")
  [ -n "${SOURCE_DIR:-}" ] && candidates+=("$SOURCE_DIR/.env.bt")

  local candidate
  for candidate in "${candidates[@]}"; do
    value="$(read_one_env_file "$candidate")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

existing_or_random_hex() {
  local key="$1"
  local bytes="$2"
  local existing
  existing="$(read_env_value "$key")"
  [ -n "$existing" ] && printf '%s' "$existing" || rand_hex "$bytes"
}

existing_or_default() {
  local key="$1"
  local default_value="$2"
  local existing
  existing="$(read_env_value "$key")"
  [ -n "$existing" ] && printf '%s' "$existing" || printf '%s' "$default_value"
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    fail "Docker Compose is unavailable."
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --admin-domain) ADMIN_DOMAIN="${2:-}"; shift 2 ;;
    --api-domain) API_DOMAIN="${2:-}"; shift 2 ;;
    --h5-domain) H5_DOMAIN="${2:-}"; shift 2 ;;
    --kf-domain) KF_DOMAIN="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --scheme) PUBLIC_SCHEME="${2:-}"; shift 2 ;;
    --mirror) MIRROR_MODE="${2:-}"; shift 2 ;;
    --admin-port) ADMIN_PORT="${2:-}"; shift 2 ;;
    --api-port) API_PORT="${2:-}"; shift 2 ;;
    --h5-port) H5_PORT="${2:-}"; shift 2 ;;
    --kf-port) KF_PORT="${2:-}"; shift 2 ;;
    --mysql-port) MYSQL_PORT="${2:-}"; shift 2 ;;
    --mongo-port) MONGO_PORT="${2:-}"; shift 2 ;;
    --redis-port) REDIS_PORT="${2:-}"; shift 2 ;;
    --admin-password) INITIAL_ADMIN_PASSWORD="${2:-}"; ADMIN_PASSWORD_PROVIDED="1"; shift 2 ;;
    --write-nginx) CREATE_NGINX="1"; shift ;;
    --no-nginx) CREATE_NGINX="0"; shift ;;
    -y|--yes) ASSUME_YES="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || fail "Please run as root, or use sudo."
case "$PUBLIC_SCHEME" in http|https) ;; *) fail "--scheme must be http or https." ;; esac
case "$MIRROR_MODE" in cn|global) ;; *) fail "--mirror must be cn or global." ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -d "$SOURCE_DIR/admin-dist" ] || fail "admin-dist is missing. Use the prebuilt package."
[ -d "$SOURCE_DIR/web-dist" ] || fail "web-dist is missing. H5 must be included in the prebuilt package."
[ -d "$SOURCE_DIR/kf-dist" ] || fail "kf-dist is missing. Service admin must be included in the prebuilt package."
[ -f "$SOURCE_DIR/backend/server-linux-amd64" ] || [ -f "$SOURCE_DIR/backend/server-linux-arm64" ] || fail "Prebuilt backend binary is missing."

if [ -n "$DOMAIN" ]; then
  ADMIN_DOMAIN="${ADMIN_DOMAIN:-$DOMAIN}"
  API_DOMAIN="${API_DOMAIN:-$DOMAIN}"
fi
ADMIN_DOMAIN="${ADMIN_DOMAIN:-_}"
API_DOMAIN="${API_DOMAIN:-$ADMIN_DOMAIN}"
H5_DOMAIN="${H5_DOMAIN:-}"
KF_DOMAIN="${KF_DOMAIN:-}"

if [ -z "$INITIAL_ADMIN_PASSWORD" ]; then
  if [ "$ASSUME_YES" = "1" ]; then
    INITIAL_ADMIN_PASSWORD="$DEFAULT_INITIAL_ADMIN_PASSWORD"
  else
    read -r -s -p "Initial admin password, leave empty to use 123456: " INITIAL_ADMIN_PASSWORD
    printf '\n'
    [ -n "$INITIAL_ADMIN_PASSWORD" ] && ADMIN_PASSWORD_PROVIDED="1"
    INITIAL_ADMIN_PASSWORD="${INITIAL_ADMIN_PASSWORD:-$DEFAULT_INITIAL_ADMIN_PASSWORD}"
  fi
fi

if [ "$API_DOMAIN" = "_" ]; then
  PUBLIC_URL="${PUBLIC_SCHEME}://$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ "$PUBLIC_URL" != "${PUBLIC_SCHEME}://" ] || PUBLIC_URL="${PUBLIC_SCHEME}://127.0.0.1"
else
  PUBLIC_URL="${PUBLIC_SCHEME}://${API_DOMAIN}"
fi
if [ "$ADMIN_DOMAIN" = "_" ]; then
  ADMIN_ORIGIN="$PUBLIC_URL"
else
  ADMIN_ORIGIN="${PUBLIC_SCHEME}://${ADMIN_DOMAIN}"
fi
API_ORIGIN="$PUBLIC_URL"
if [ -n "$H5_DOMAIN" ] && [ "$H5_DOMAIN" != "_" ]; then
  H5_ORIGIN="${PUBLIC_SCHEME}://${H5_DOMAIN}"
else
  H5_ORIGIN=""
fi
if [ -n "$KF_DOMAIN" ] && [ "$KF_DOMAIN" != "_" ]; then
  KF_ORIGIN="${PUBLIC_SCHEME}://${KF_DOMAIN}"
else
  KF_ORIGIN=""
fi

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  cat <<EOF

Prebuilt deploy summary:
  source       : $SOURCE_DIR
  install dir  : $INSTALL_DIR
  admin domain : $ADMIN_DOMAIN
  api domain   : $API_DOMAIN
  h5 domain    : ${H5_DOMAIN:-<skip>}
  kf domain    : ${KF_DOMAIN:-<skip>}
  api base url : $PUBLIC_URL
  h5 port      : 127.0.0.1:$H5_PORT
  kf port      : 127.0.0.1:$KF_PORT
  build mode   : prebuilt, no server-side compile

EOF
  read -r -p "Continue? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) fail "Cancelled." ;; esac
}

install_runtime_dependencies() {
  command -v docker >/dev/null 2>&1 || fail "Docker is missing. Install Docker first from Baota or the system package manager."
  docker version >/dev/null 2>&1 || fail "Docker is not running."
  compose_cmd version >/dev/null
  command -v curl >/dev/null 2>&1 || warn "curl is missing; health check may fail."
  log "Docker runtime is ready."
}

sync_source() {
  mkdir -p "$INSTALL_DIR"
  if [ "$(cd "$SOURCE_DIR" && pwd)" = "$(cd "$INSTALL_DIR" && pwd 2>/dev/null || printf '%s' "$INSTALL_DIR")" ]; then
    log "Using current source directory as install directory."
    return 0
  fi
  info "Copying prebuilt package to $INSTALL_DIR ..."
  tar \
    --exclude='.git' \
    --exclude='.DS_Store' \
    -C "$SOURCE_DIR" -cf - . | tar -C "$INSTALL_DIR" -xf -
}

select_backend_binary() {
  cd "$INSTALL_DIR"
  local arch src
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) src="backend/server-linux-amd64" ;;
    aarch64|arm64) src="backend/server-linux-arm64" ;;
    *) fail "Unsupported server arch: $arch. Package includes linux/amd64 and linux/arm64." ;;
  esac
  [ -f "$src" ] || fail "Missing backend binary for $arch: $src"
  cp "$src" backend/server
  chmod +x backend/server
  log "Selected backend binary: $src"
}

write_env_and_config() {
  cd "$INSTALL_DIR"
  mkdir -p docker/genericim

  MYSQL_ROOT_PASSWORD="$(existing_or_random_hex MYSQL_ROOT_PASSWORD 16)"
  MYSQL_PASSWORD="$(existing_or_random_hex MYSQL_PASSWORD 16)"
  MONGO_PASSWORD="$(existing_or_random_hex MONGO_ROOT_PASSWORD 16)"
  JWT_SECRET="$(existing_or_random_hex JWT_SECRET 32)"
  SETTINGS_ENCRYPTION_KEY="$(existing_or_random_hex SETTINGS_ENCRYPTION_KEY 32)"
  MYSQL_DATABASE="$(existing_or_default MYSQL_DATABASE genericim)"
  MYSQL_USER="$(existing_or_default MYSQL_USER genericim)"
  MONGO_ROOT_USERNAME="$(existing_or_default MONGO_ROOT_USERNAME genericim)"
  MONGO_DATABASE="$(existing_or_default MONGO_DATABASE genericim_messages)"
  STORAGE_PROVIDER="${STORAGE_PROVIDER:-$(existing_or_default STORAGE_PROVIDER local)}"
  STORAGE_LOCAL_BASE_URL="${STORAGE_LOCAL_BASE_URL:-$(existing_or_default STORAGE_LOCAL_BASE_URL "$PUBLIC_URL")}"
  STORAGE_ALIYUN_ENDPOINT="${STORAGE_ALIYUN_ENDPOINT:-$(existing_or_default STORAGE_ALIYUN_ENDPOINT "")}"
  STORAGE_ALIYUN_BUCKET="${STORAGE_ALIYUN_BUCKET:-$(existing_or_default STORAGE_ALIYUN_BUCKET "")}"
  STORAGE_ALIYUN_ACCESS_KEY_ID="${STORAGE_ALIYUN_ACCESS_KEY_ID:-$(existing_or_default STORAGE_ALIYUN_ACCESS_KEY_ID "")}"
  STORAGE_ALIYUN_ACCESS_KEY_SECRET="${STORAGE_ALIYUN_ACCESS_KEY_SECRET:-$(existing_or_default STORAGE_ALIYUN_ACCESS_KEY_SECRET "")}"
  STORAGE_ALIYUN_PUBLIC_BASE_URL="${STORAGE_ALIYUN_PUBLIC_BASE_URL:-$(existing_or_default STORAGE_ALIYUN_PUBLIC_BASE_URL "")}"
  STORAGE_ALIYUN_USE_HTTPS="${STORAGE_ALIYUN_USE_HTTPS:-$(existing_or_default STORAGE_ALIYUN_USE_HTTPS true)}"
  STORAGE_QINIU_UPLOAD_URL="${STORAGE_QINIU_UPLOAD_URL:-$(existing_or_default STORAGE_QINIU_UPLOAD_URL "https://upload.qiniup.com")}"
  STORAGE_QINIU_BUCKET="${STORAGE_QINIU_BUCKET:-$(existing_or_default STORAGE_QINIU_BUCKET "")}"
  STORAGE_QINIU_ACCESS_KEY="${STORAGE_QINIU_ACCESS_KEY:-$(existing_or_default STORAGE_QINIU_ACCESS_KEY "")}"
  STORAGE_QINIU_SECRET_KEY="${STORAGE_QINIU_SECRET_KEY:-$(existing_or_default STORAGE_QINIU_SECRET_KEY "")}"
  STORAGE_QINIU_PUBLIC_BASE_URL="${STORAGE_QINIU_PUBLIC_BASE_URL:-$(existing_or_default STORAGE_QINIU_PUBLIC_BASE_URL "")}"
  STORAGE_QINIU_USE_HTTPS="${STORAGE_QINIU_USE_HTTPS:-$(existing_or_default STORAGE_QINIU_USE_HTTPS true)}"
  STORAGE_S3_REGION="${STORAGE_S3_REGION:-$(existing_or_default STORAGE_S3_REGION "")}"
  STORAGE_S3_BUCKET="${STORAGE_S3_BUCKET:-$(existing_or_default STORAGE_S3_BUCKET "")}"
  STORAGE_S3_PUBLIC_BASE_URL="${STORAGE_S3_PUBLIC_BASE_URL:-$(existing_or_default STORAGE_S3_PUBLIC_BASE_URL "")}"
  STORAGE_S3_ENDPOINT="${STORAGE_S3_ENDPOINT:-$(existing_or_default STORAGE_S3_ENDPOINT "")}"
  STORAGE_S3_USE_PATH_STYLE="${STORAGE_S3_USE_PATH_STYLE:-$(existing_or_default STORAGE_S3_USE_PATH_STYLE false)}"
  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(existing_or_default AWS_ACCESS_KEY_ID "")}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(existing_or_default AWS_SECRET_ACCESS_KEY "")}"
  AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-$(existing_or_default AWS_SESSION_TOKEN "")}"

  if [ "$ADMIN_PASSWORD_PROVIDED" != "1" ]; then
    EXISTING_INITIAL_ADMIN_PASSWORD="$(read_env_value INITIAL_ADMIN_PASSWORD)"
    [ -n "$EXISTING_INITIAL_ADMIN_PASSWORD" ] && INITIAL_ADMIN_PASSWORD="$EXISTING_INITIAL_ADMIN_PASSWORD"
  fi

  cat >.env.bt <<EOF
COMPOSE_PROJECT_NAME=$PROJECT_NAME
PUBLIC_URL=$PUBLIC_URL
PUBLIC_ORIGIN=$ADMIN_ORIGIN,$API_ORIGIN${H5_ORIGIN:+,$H5_ORIGIN}${KF_ORIGIN:+,$KF_ORIGIN}
H5_ORIGIN=$H5_ORIGIN
KF_ORIGIN=$KF_ORIGIN
API_PORT=$API_PORT
ADMIN_PORT=$ADMIN_PORT
H5_PORT=$H5_PORT
KF_PORT=$KF_PORT
MYSQL_PORT=$MYSQL_PORT
MONGO_PORT=$MONGO_PORT
REDIS_PORT=$REDIS_PORT
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MONGO_ROOT_USERNAME=$MONGO_ROOT_USERNAME
MONGO_ROOT_PASSWORD=$MONGO_PASSWORD
MONGO_DATABASE=$MONGO_DATABASE
JWT_SECRET=$JWT_SECRET
SETTINGS_ENCRYPTION_KEY=$SETTINGS_ENCRYPTION_KEY
INITIAL_ADMIN_USERNAME=admin
INITIAL_ADMIN_PASSWORD=$INITIAL_ADMIN_PASSWORD
STORAGE_PROVIDER=$STORAGE_PROVIDER
STORAGE_LOCAL_BASE_URL=$STORAGE_LOCAL_BASE_URL
STORAGE_ALIYUN_ENDPOINT=$STORAGE_ALIYUN_ENDPOINT
STORAGE_ALIYUN_BUCKET=$STORAGE_ALIYUN_BUCKET
STORAGE_ALIYUN_ACCESS_KEY_ID=$STORAGE_ALIYUN_ACCESS_KEY_ID
STORAGE_ALIYUN_ACCESS_KEY_SECRET=$STORAGE_ALIYUN_ACCESS_KEY_SECRET
STORAGE_ALIYUN_PUBLIC_BASE_URL=$STORAGE_ALIYUN_PUBLIC_BASE_URL
STORAGE_ALIYUN_USE_HTTPS=$STORAGE_ALIYUN_USE_HTTPS
STORAGE_QINIU_UPLOAD_URL=$STORAGE_QINIU_UPLOAD_URL
STORAGE_QINIU_BUCKET=$STORAGE_QINIU_BUCKET
STORAGE_QINIU_ACCESS_KEY=$STORAGE_QINIU_ACCESS_KEY
STORAGE_QINIU_SECRET_KEY=$STORAGE_QINIU_SECRET_KEY
STORAGE_QINIU_PUBLIC_BASE_URL=$STORAGE_QINIU_PUBLIC_BASE_URL
STORAGE_QINIU_USE_HTTPS=$STORAGE_QINIU_USE_HTTPS
STORAGE_S3_REGION=$STORAGE_S3_REGION
STORAGE_S3_BUCKET=$STORAGE_S3_BUCKET
STORAGE_S3_PUBLIC_BASE_URL=$STORAGE_S3_PUBLIC_BASE_URL
STORAGE_S3_ENDPOINT=$STORAGE_S3_ENDPOINT
STORAGE_S3_USE_PATH_STYLE=$STORAGE_S3_USE_PATH_STYLE
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
EOF

  sed "s|http://10.0.2.2:8080|$PUBLIC_URL|g; s|mode: debug|mode: release|g" \
    docker/genericim/backend-config.yaml >docker/genericim/backend-config.bt.yaml

  cat >compose.bt.yaml <<'EOF'
name: ${COMPOSE_PROJECT_NAME:-genericim}

services:
  mysql:
    image: mysql:8.0
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TZ: Asia/Shanghai
    command:
      - --default-authentication-plugin=mysql_native_password
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    ports:
      - "127.0.0.1:${MYSQL_PORT:-13306}:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u${MYSQL_USER} -p${MYSQL_PASSWORD} --silent"]
      interval: 10s
      timeout: 5s
      retries: 30
    restart: unless-stopped

  mongodb:
    image: mongo:7.0
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-mongodb
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_DATABASE}
      TZ: Asia/Shanghai
    ports:
      - "127.0.0.1:${MONGO_PORT:-17017}:27017"
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--username", "${MONGO_ROOT_USERNAME}", "--password", "${MONGO_ROOT_PASSWORD}", "--authenticationDatabase", "admin", "--eval", "db.adminCommand('ping').ok"]
      interval: 10s
      timeout: 5s
      retries: 30
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-redis
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    ports:
      - "127.0.0.1:${REDIS_PORT:-16379}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 30
    restart: unless-stopped

  api:
    image: alpine:3.19
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-api
    command: ["/app/server"]
    environment:
      TZ: Asia/Shanghai
      GENERIC_IM_CONFIG: /app/config.yaml
      GENERIC_IM_SERVER_MODE: release
      GENERIC_IM_SERVER_BASE_URL: ${PUBLIC_URL}
      GENERIC_IM_REGISTER_BASE_URL: ${PUBLIC_URL}
      GENERIC_IM_ALLOWED_ORIGINS: ${PUBLIC_ORIGIN}
      GENERIC_IM_WS_ALLOWED_ORIGINS: ${PUBLIC_ORIGIN}
      GENERIC_IM_MYSQL_HOST: mysql
      GENERIC_IM_MYSQL_PORT: "3306"
      GENERIC_IM_MYSQL_USER: ${MYSQL_USER}
      GENERIC_IM_MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      GENERIC_IM_MYSQL_DATABASE: ${MYSQL_DATABASE}
      GENERIC_IM_MONGODB_URI: mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@mongodb:27017/?authSource=admin
      GENERIC_IM_MONGODB_DATABASE: ${MONGO_DATABASE}
      GENERIC_IM_REDIS_ADDR: redis:6379
      GENERIC_IM_JWT_SECRET: ${JWT_SECRET}
      GENERIC_IM_SETTINGS_ENCRYPTION_KEY: ${SETTINGS_ENCRYPTION_KEY}
      GENERIC_IM_INITIAL_ADMIN_USERNAME: ${INITIAL_ADMIN_USERNAME}
      GENERIC_IM_INITIAL_ADMIN_PASSWORD: ${INITIAL_ADMIN_PASSWORD}
      GENERIC_IM_STORAGE_PROVIDER: ${STORAGE_PROVIDER:-local}
      GENERIC_IM_STORAGE_LOCAL_BASE_URL: ${STORAGE_LOCAL_BASE_URL:-${PUBLIC_URL}}
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
    ports:
      - "127.0.0.1:${API_PORT:-18080}:8080"
    volumes:
      - ./backend/server:/app/server:ro
      - ./docker/genericim/backend-config.bt.yaml:/app/config.yaml:ro
      - uploads:/app/uploads
    depends_on:
      mysql:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/health >/dev/null 2>&1 || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
    restart: unless-stopped

  admin:
    image: nginx:1.27-alpine
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-admin
    ports:
      - "127.0.0.1:${ADMIN_PORT:-18084}:80"
    volumes:
      - ./admin-dist:/usr/share/nginx/html:ro
      - ./docker/genericim/admin-nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      api:
        condition: service_healthy
    restart: unless-stopped

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

volumes:
  mysql_data:
  mongo_data:
  redis_data:
  uploads:
EOF

  cat >docker/genericim/h5-nginx.conf <<'EOF'
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

  cat >docker/genericim/kf-nginx.conf <<'EOF'
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
}

write_nginx_conf() {
  [ "$CREATE_NGINX" = "1" ] || return 0
  local conf_dir admin_conf api_conf h5_conf kf_conf backup_dir
  if [ -d /www/server/panel/vhost/nginx ]; then
    conf_dir="/www/server/panel/vhost/nginx"
  elif [ -d /etc/nginx/conf.d ]; then
    conf_dir="/etc/nginx/conf.d"
  else
    warn "Nginx config directory not found. Skipping Nginx config."
    return 0
  fi

  admin_conf="$conf_dir/${PROJECT_NAME}-admin.conf"
  api_conf="$conf_dir/${PROJECT_NAME}-api.conf"
  h5_conf="$conf_dir/${PROJECT_NAME}-h5.conf"
  kf_conf="$conf_dir/${PROJECT_NAME}-kf.conf"
  backup_dir="$INSTALL_DIR/nginx-conf-backup-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"

  local admin_server_name="$ADMIN_DOMAIN"
  local api_server_name="$API_DOMAIN"
  local h5_server_name="$H5_DOMAIN"
  local kf_server_name="$KF_DOMAIN"
  [ "$admin_server_name" = "_" ] && admin_server_name="_"
  [ "$api_server_name" = "_" ] && api_server_name="$admin_server_name"
  [ "$h5_server_name" = "_" ] && h5_server_name=""
  [ "$kf_server_name" = "_" ] && kf_server_name=""

  find_baota_site_conf() {
    local domain="$1"
    local candidate
    [ -n "$domain" ] && [ "$domain" != "_" ] || return 1
    for candidate in "$conf_dir"/*.conf; do
      [ -f "$candidate" ] || continue
      case "$candidate" in
        "$admin_conf"|"$api_conf"|"$h5_conf"|"$kf_conf") continue ;;
      esac
      if awk -v domain="$domain" '
        $1 == "server_name" {
          for (i = 2; i <= NF; i++) {
            name = $i
            sub(/;$/, "", name)
            if (name == domain) found = 1
          }
        }
        END { exit(found ? 0 : 1) }
      ' "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    return 1
  }

  backup_file() {
    local source="$1"
    local label="$2"
    [ -f "$source" ] || return 0
    cp -a "$source" "$backup_dir/$label"
  }

  write_proxy_location() {
    local conf="$1"
    local port="$2"
    cat >"$conf" <<EOF
location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        proxy_connect_timeout 5s;
        proxy_send_timeout 120s;
        proxy_read_timeout 86400s;
        proxy_request_buffering on;
        proxy_buffering on;
        proxy_socket_keepalive on;
}
EOF
  }

  write_standalone_proxy_server() {
    local conf="$1"
    local domain="$2"
    local port="$3"
    local cert_dir="/www/server/panel/vhost/cert/$domain"
    [ -n "$domain" ] && [ "$domain" != "_" ] || return 0

    backup_file "$conf" "$(basename "$conf").bak"
    cat >"$conf" <<EOF
server {
    listen 80;
    server_name $domain;
    client_max_body_size 100m;
    client_body_timeout 120s;
    send_timeout 120s;
    keepalive_timeout 75s;
    keepalive_requests 10000;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        proxy_connect_timeout 5s;
        proxy_send_timeout 120s;
        proxy_read_timeout 86400s;
        proxy_request_buffering on;
        proxy_buffering on;
        proxy_socket_keepalive on;
    }
}
EOF

    if [ -s "$cert_dir/fullchain.pem" ] && [ -s "$cert_dir/privkey.pem" ]; then
      cat >>"$conf" <<EOF

server {
    listen 443 ssl;
    http2 on;
    server_name $domain;
    client_max_body_size 100m;
    client_body_timeout 120s;
    send_timeout 120s;
    keepalive_timeout 75s;
    keepalive_requests 10000;
    ssl_certificate $cert_dir/fullchain.pem;
    ssl_certificate_key $cert_dir/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        proxy_connect_timeout 5s;
        proxy_send_timeout 120s;
        proxy_read_timeout 86400s;
        proxy_request_buffering on;
        proxy_buffering on;
        proxy_socket_keepalive on;
    }
}
EOF
      log "Existing Baota certificate detected for $domain; HTTPS proxy enabled."
    else
      warn "No Baota certificate found for $domain; HTTP proxy was created. Apply SSL in Baota after deployment."
    fi
  }

  configure_domain_proxy() {
    local generated_conf="$1"
    local domain="$2"
    local port="$3"
    local site_conf proxy_dir proxy_conf include_line patched_conf
    [ -n "$domain" ] && [ "$domain" != "_" ] || return 0

    site_conf="$(find_baota_site_conf "$domain" || true)"
    if [ -z "$site_conf" ]; then
      write_standalone_proxy_server "$generated_conf" "$domain" "$port"
      return 0
    fi

    # Preserve the Baota-owned site and SSL configuration. Standard Baota
    # vhosts include this directory; only add the include when an older/custom
    # site file does not have it yet.
    proxy_dir="/www/server/panel/vhost/nginx/proxy/$domain"
    proxy_conf="$proxy_dir/${PROJECT_NAME}-docker.conf"
    include_line="include $proxy_dir/*.conf;"

    if grep -Fq "proxy_pass http://127.0.0.1:$port" "$site_conf" 2>/dev/null || \
       grep -RqsF "proxy_pass http://127.0.0.1:$port" "$proxy_dir" 2>/dev/null; then
      rm -f "$generated_conf"
      log "Existing reverse proxy for $domain already points to 127.0.0.1:$port; keeping it unchanged."
      return 0
    fi
    if grep -Fq "proxy_pass " "$site_conf" 2>/dev/null || \
       grep -RqsF "proxy_pass " "$proxy_dir" 2>/dev/null; then
      rm -f "$generated_conf"
      warn "Existing reverse proxy found for $domain. It was not overwritten; verify that it points to http://127.0.0.1:$port."
      return 0
    fi

    mkdir -p "$proxy_dir"
    backup_file "$site_conf" "$(basename "$site_conf").bak"
    backup_file "$proxy_conf" "$(basename "$site_conf").proxy.bak"
    write_proxy_location "$proxy_conf" "$port"

    if ! grep -Fq "$proxy_dir/" "$site_conf"; then
      patched_conf="$(mktemp)"
      awk -v include_line="    $include_line" '
        { lines[NR] = $0 }
        END {
          last = 0
          for (i = NR; i >= 1; i--) {
            if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { last = i; break }
          }
          if (last == 0) exit 2
          for (i = 1; i <= NR; i++) {
            if (i == last) print include_line
            print lines[i]
          }
        }
      ' "$site_conf" >"$patched_conf" || {
        rm -f "$patched_conf"
        fail "Could not add the Baota proxy include to $site_conf"
      }
      cat "$patched_conf" >"$site_conf"
      rm -f "$patched_conf"
    fi

    rm -f "$generated_conf"
    log "Preserved Baota site/SSL for $domain and configured proxy to 127.0.0.1:$port."
  }

  configure_domain_proxy "$admin_conf" "$admin_server_name" "$ADMIN_PORT"

  if [ "$api_server_name" != "$admin_server_name" ]; then
    configure_domain_proxy "$api_conf" "$api_server_name" "$API_PORT"
  else
    rm -f "$api_conf"
  fi

  if [ -n "$h5_server_name" ]; then
    if [ "$h5_server_name" = "$admin_server_name" ] || [ "$h5_server_name" = "$api_server_name" ]; then
      fail "H5 domain must be different from admin/api domain when writing Nginx vhost: $h5_server_name"
    fi

    configure_domain_proxy "$h5_conf" "$h5_server_name" "$H5_PORT"
  else
    rm -f "$h5_conf"
  fi

  if [ -n "$kf_server_name" ]; then
    if [ "$kf_server_name" = "$admin_server_name" ] || [ "$kf_server_name" = "$api_server_name" ] || [ "$kf_server_name" = "$h5_server_name" ]; then
      fail "KF domain must be different from admin/api/h5 domain when writing Nginx vhost: $kf_server_name"
    fi

    configure_domain_proxy "$kf_conf" "$kf_server_name" "$KF_PORT"
  else
    rm -f "$kf_conf"
  fi

  if [ -d /www/server/panel/vhost/rewrite ]; then
    cat >/www/server/panel/vhost/rewrite/${PROJECT_NAME}-admin.conf <<'EOF'
# Docker reverse-proxy deployment.
# The SPA fallback is handled by the admin container Nginx:
# location / { try_files $uri $uri/ /index.html; }
EOF
    if [ "$api_server_name" != "$admin_server_name" ]; then
      cat >/www/server/panel/vhost/rewrite/${PROJECT_NAME}-api.conf <<'EOF'
# Docker API reverse-proxy deployment.
EOF
    fi
    if [ -n "$h5_server_name" ]; then
      cat >/www/server/panel/vhost/rewrite/${PROJECT_NAME}-h5.conf <<'EOF'
# H5 SPA fallback is handled by the h5 container Nginx:
# location / { try_files $uri $uri/ /index.html; }
EOF
    fi
    if [ -n "$kf_server_name" ]; then
      cat >/www/server/panel/vhost/rewrite/${PROJECT_NAME}-kf.conf <<'EOF'
# Official service SPA fallback is handled by the kf container Nginx:
# location / { try_files $uri $uri/ /index.html; }
EOF
    fi
  fi

  if [ -x /www/server/nginx/sbin/nginx ]; then
    /www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
  elif command -v nginx >/dev/null 2>&1; then
    nginx -t && nginx -s reload
  else
    warn "Nginx config written, but reload was skipped."
  fi
  log "Nginx config updated."
}

deploy_stack() {
  cd "$INSTALL_DIR"
  if [ -d "$INSTALL_DIR/backend/uploads" ]; then
    info "Seeding packaged uploads/stickers into Docker volume ..."
    docker volume create "${PROJECT_NAME}_uploads" >/dev/null
    docker run --rm \
      -v "${PROJECT_NAME}_uploads:/target" \
      -v "$INSTALL_DIR/backend/uploads:/source:ro" \
      alpine:3.19 \
      sh -c 'mkdir -p /target && cp -af /source/. /target/'
  fi
  info "Starting Docker services from prebuilt artifacts. No Go/Node build will run on this server."
  compose_cmd --env-file .env.bt -f compose.bt.yaml up -d
}

update_packaged_sticker_catalog() {
  cd "$INSTALL_DIR"
  info "Updating packaged sticker catalog in MySQL ..."
  for _ in $(seq 1 60); do
    if compose_cmd --env-file .env.bt -f compose.bt.yaml exec -T mysql mysqladmin ping -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done

  compose_cmd --env-file .env.bt -f compose.bt.yaml exec -T mysql mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" <<'SQL'
UPDATE emoji_store_pack_catalogs
SET preview_file = REPLACE(preview_file, '.gif', '.json'),
    sticker_files = REPLACE(sticker_files, '.gif', '.json'),
    updated_at = NOW()
WHERE pack_id IN ('cubigator','duck','premium_gifts');
SQL
}

verify_stack() {
  cd "$INSTALL_DIR"
  info "Waiting for services..."
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
  curl -fsS "http://127.0.0.1:${API_PORT}/health" >/dev/null || fail "API health check failed."
  curl -fsS "http://127.0.0.1:${ADMIN_PORT}/" >/dev/null || fail "Admin health check failed."
  curl -fsS "http://127.0.0.1:${H5_PORT}/" >/dev/null || fail "H5 health check failed."
  curl -fsS "http://127.0.0.1:${KF_PORT}/" >/dev/null || fail "KF health check failed."
  log "Docker services are healthy."
}

print_result() {
  cat <<EOF

Prebuilt deployment complete.

Admin URL:
  $ADMIN_ORIGIN

API URL:
  $PUBLIC_URL

H5 URL:
  ${H5_ORIGIN:-<not configured>}

Service admin URL:
  ${KF_ORIGIN:-<not configured>}

Local checks:
  curl http://127.0.0.1:$API_PORT/health
  curl http://127.0.0.1:$ADMIN_PORT/
  curl http://127.0.0.1:$H5_PORT/
  curl http://127.0.0.1:$KF_PORT/

Manage:
  cd $INSTALL_DIR
  docker compose --env-file .env.bt -f compose.bt.yaml ps
  docker compose --env-file .env.bt -f compose.bt.yaml logs -f api

EOF
}

confirm
install_runtime_dependencies
sync_source
select_backend_binary
write_env_and_config
deploy_stack
update_packaged_sticker_catalog
write_nginx_conf
verify_stack
print_result
