#!/usr/bin/env bash
# 从源码在宝塔 Linux 主机上首次部署或更新通用IM Docker 服务。
# 脚本会创建安装目录、端口映射、环境文件，并可写入 Nginx 站点配置；
# 使用 -y 前必须复核域名、安装目录、公开协议和初始管理员密码。
set -Eeuo pipefail

PROJECT_NAME="genericim"
INSTALL_DIR="/www/wwwroot/genericim"
DOMAIN=""
ADMIN_DOMAIN=""
API_DOMAIN=""
H5_DOMAIN=""
MIRROR_MODE="auto"
PUBLIC_SCHEME="http"
API_PORT="18080"
ADMIN_PORT="18084"
MYSQL_PORT="13306"
MONGO_PORT="17017"
REDIS_PORT="16379"
CREATE_NGINX="1"
ASSUME_YES="0"
SKIP_DOCKER_INSTALL="0"
INITIAL_ADMIN_PASSWORD=""
ADMIN_PASSWORD_PROVIDED="0"
DEFAULT_INITIAL_ADMIN_PASSWORD="123456"

CN_ALPINE_MIRROR="https://mirrors.aliyun.com/alpine"
CN_NPM_REGISTRY="https://registry.npmmirror.com/"
CN_GOPROXY="https://goproxy.cn,direct"
GLOBAL_ALPINE_MIRROR=""
GLOBAL_NPM_REGISTRY="https://registry.npmjs.org/"
GLOBAL_GOPROXY="https://proxy.golang.org,direct"

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }

quick_random_password() {
  # openssl 不可用时才回退到 /dev/urandom，并保持输出仅含字母和数字。
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -d '=+/[:space:]' | cut -c1-16
  else
    set +o pipefail
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
    set -o pipefail
  fi
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/baota_docker_deploy.sh [options]

Options:
  --domain DOMAIN           Backward-compatible single domain for admin and API
  --admin-domain DOMAIN     Admin domain, e.g. imadmin.example.com
  --api-domain DOMAIN       API/media domain, e.g. im.example.com
  --h5-domain DOMAIN        H5 frontend domain. Leave empty to skip H5 vhost
  --install-dir DIR         Deploy directory. Default: /www/wwwroot/genericim
  --mirror auto|cn|global   Download/build mirror mode. Default: auto
  --scheme http|https       Public scheme used in backend base_url. Default: http
  --admin-port PORT         Local admin container port. Default: 18084
  --api-port PORT           Local api container port. Default: 18080
  --mysql-port PORT         Local MySQL bind port. Default: 13306
  --mongo-port PORT         Local MongoDB bind port. Default: 17017
  --redis-port PORT         Local Redis bind port. Default: 16379
  --admin-password PASS     Initial admin password if first admin does not exist. Default: 123456
  --no-nginx                Do not write Baota/Nginx vhost config
  --skip-docker-install     Do not install Docker even if missing
  -y, --yes                 Non-interactive
  -h, --help                Show this help

Example:
  bash scripts/baota_docker_deploy.sh --domain im.example.com --mirror cn -y
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --admin-domain) ADMIN_DOMAIN="${2:-}"; shift 2 ;;
    --api-domain) API_DOMAIN="${2:-}"; shift 2 ;;
    --h5-domain) H5_DOMAIN="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --mirror) MIRROR_MODE="${2:-}"; shift 2 ;;
    --scheme) PUBLIC_SCHEME="${2:-}"; shift 2 ;;
    --admin-port) ADMIN_PORT="${2:-}"; shift 2 ;;
    --api-port) API_PORT="${2:-}"; shift 2 ;;
    --mysql-port) MYSQL_PORT="${2:-}"; shift 2 ;;
    --mongo-port) MONGO_PORT="${2:-}"; shift 2 ;;
    --redis-port) REDIS_PORT="${2:-}"; shift 2 ;;
    --admin-password) INITIAL_ADMIN_PASSWORD="${2:-}"; ADMIN_PASSWORD_PROVIDED="1"; shift 2 ;;
    --no-nginx) CREATE_NGINX="0"; shift ;;
    --skip-docker-install) SKIP_DOCKER_INSTALL="1"; shift ;;
    -y|--yes) ASSUME_YES="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || fail "Please run as root, or use sudo."
case "$MIRROR_MODE" in auto|cn|global) ;; *) fail "--mirror must be auto, cn, or global." ;; esac
case "$PUBLIC_SCHEME" in http|https) ;; *) fail "--scheme must be http or https." ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -f "$SOURCE_DIR/compose.yaml" ] || fail "Run this script from the project source tree."

if [ -n "$DOMAIN" ]; then
  ADMIN_DOMAIN="${ADMIN_DOMAIN:-$DOMAIN}"
  API_DOMAIN="${API_DOMAIN:-$DOMAIN}"
fi

if [ -z "$ADMIN_DOMAIN" ]; then
  if [ "$ASSUME_YES" = "1" ]; then
    ADMIN_DOMAIN="_"
  else
    read -r -p "Admin domain, leave empty to use server IP: " ADMIN_DOMAIN
    ADMIN_DOMAIN="${ADMIN_DOMAIN:-_}"
  fi
fi

if [ -z "$API_DOMAIN" ]; then
  if [ "$ASSUME_YES" = "1" ]; then
    API_DOMAIN="$ADMIN_DOMAIN"
  else
    read -r -p "API domain, leave empty to reuse admin domain: " API_DOMAIN
    API_DOMAIN="${API_DOMAIN:-$ADMIN_DOMAIN}"
  fi
fi

if [ -z "$INITIAL_ADMIN_PASSWORD" ]; then
  if [ "$ASSUME_YES" = "1" ]; then
    INITIAL_ADMIN_PASSWORD="$DEFAULT_INITIAL_ADMIN_PASSWORD"
  else
    read -r -s -p "Initial admin password, leave empty to use 123456: " INITIAL_ADMIN_PASSWORD
    printf '\n'
    [ -n "$INITIAL_ADMIN_PASSWORD" ] && ADMIN_PASSWORD_PROVIDED="1"
    if [ -z "$INITIAL_ADMIN_PASSWORD" ]; then
      INITIAL_ADMIN_PASSWORD="$DEFAULT_INITIAL_ADMIN_PASSWORD"
    fi
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

if [ "$API_DOMAIN" = "_" ]; then
  API_ORIGIN="$PUBLIC_URL"
else
  API_ORIGIN="${PUBLIC_SCHEME}://${API_DOMAIN}"
fi

if [ -n "$H5_DOMAIN" ] && [ "$H5_DOMAIN" != "_" ]; then
  H5_ORIGIN="${PUBLIC_SCHEME}://${H5_DOMAIN}"
else
  H5_ORIGIN=""
fi

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  cat <<EOF

Deploy summary:
  source       : $SOURCE_DIR
  install dir  : $INSTALL_DIR
  admin domain : $ADMIN_DOMAIN
  api domain   : $API_DOMAIN
  h5 domain    : ${H5_DOMAIN:-<skip>}
  api base url : $PUBLIC_URL
  mirror mode  : $MIRROR_MODE
  admin port   : 127.0.0.1:$ADMIN_PORT
  api port     : 127.0.0.1:$API_PORT
  write nginx  : $CREATE_NGINX

EOF
  read -r -p "Continue? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) fail "Cancelled." ;; esac
}

detect_mirror_mode() {
  [ "$MIRROR_MODE" != "auto" ] && return 0
  info "Detecting Docker Hub connectivity..."
  if timeout 6 bash -c '</dev/tcp/registry-1.docker.io/443' >/dev/null 2>&1; then
    MIRROR_MODE="global"
  else
    MIRROR_MODE="cn"
  fi
  info "Mirror mode selected: $MIRROR_MODE"
}

install_basic_packages() {
  info "Installing basic packages..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar gzip openssl git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl tar gzip openssl git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl tar gzip openssl git
  else
    warn "Unknown package manager. Please ensure curl, tar, openssl, and git are installed."
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker is already installed."
  else
    [ "$SKIP_DOCKER_INSTALL" = "0" ] || fail "Docker is missing and --skip-docker-install was set."
    info "Installing Docker..."
    curl -fsSL --connect-timeout 12 --max-time 60 https://get.docker.com -o /tmp/get-docker.sh || {
      [ "$MIRROR_MODE" = "cn" ] || fail "Failed to download Docker installer."
      curl -fsSL --connect-timeout 12 --max-time 60 https://get.daocloud.io/docker -o /tmp/get-docker.sh
    }
    if [ "$MIRROR_MODE" = "cn" ]; then
      sh /tmp/get-docker.sh --mirror Aliyun
    else
      sh /tmp/get-docker.sh
    fi
  fi

  mkdir -p /etc/docker
  if [ "$MIRROR_MODE" = "cn" ]; then
    cat >/etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
  else
    cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
  fi

  systemctl enable docker >/dev/null 2>&1 || true
  systemctl restart docker || service docker restart || true
  sleep 2
  docker version >/dev/null 2>&1 || fail "Docker is not running."

  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose plugin is available."
  elif command -v docker-compose >/dev/null 2>&1; then
    log "docker-compose is available."
  else
    info "Installing Docker Compose plugin..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y docker-compose-plugin
    elif command -v yum >/dev/null 2>&1; then
      yum install -y docker-compose-plugin
    fi
    docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin is unavailable."
  fi
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

sync_source() {
  mkdir -p "$INSTALL_DIR"
  if [ "$(cd "$SOURCE_DIR" && pwd)" = "$(cd "$INSTALL_DIR" && pwd 2>/dev/null || printf '%s' "$INSTALL_DIR")" ]; then
    log "Using current source directory as install directory."
    return 0
  fi
  info "Copying source to $INSTALL_DIR ..."
  tar \
    --exclude='.git' \
    --exclude='.dart_tool' \
    --exclude='build' \
    --exclude='admin/node_modules' \
    --exclude='admin/dist' \
    --exclude='h5/node_modules' \
    --exclude='h5/dist' \
    --exclude='backend/server' \
    -C "$SOURCE_DIR" -cf - . | tar -C "$INSTALL_DIR" -xf -
}

rand_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    set +o pipefail
    tr -dc 'a-f0-9' </dev/urandom | head -c "$((2 * $1))"
    set -o pipefail
  fi
}

read_env_value() {
  local key="$1"
  local file="${2:-.env.bt}"
  [ -f "$file" ] || return 0
  awk -v key="$key" '
    BEGIN { FS = "=" }
    $1 == key {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$file"
}

existing_or_random_hex() {
  local key="$1"
  local bytes="$2"
  local existing
  existing="$(read_env_value "$key")"
  if [ -n "$existing" ]; then
    printf '%s' "$existing"
  else
    rand_hex "$bytes"
  fi
}

existing_or_default() {
  local key="$1"
  local default_value="$2"
  local existing
  existing="$(read_env_value "$key")"
  if [ -n "$existing" ]; then
    printf '%s' "$existing"
  else
    printf '%s' "$default_value"
  fi
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
    if [ -n "$EXISTING_INITIAL_ADMIN_PASSWORD" ]; then
      INITIAL_ADMIN_PASSWORD="$EXISTING_INITIAL_ADMIN_PASSWORD"
    fi
  fi

  if [ "$MIRROR_MODE" = "cn" ]; then
    ALPINE_MIRROR="$CN_ALPINE_MIRROR"
    NODE_REGISTRY="$CN_NPM_REGISTRY"
    GOPROXY_VALUE="$CN_GOPROXY"
  else
    ALPINE_MIRROR="$GLOBAL_ALPINE_MIRROR"
    NODE_REGISTRY="$GLOBAL_NPM_REGISTRY"
    GOPROXY_VALUE="$GLOBAL_GOPROXY"
  fi

  cat >.env.bt <<EOF
COMPOSE_PROJECT_NAME=$PROJECT_NAME
PUBLIC_URL=$PUBLIC_URL
PUBLIC_ORIGIN=$ADMIN_ORIGIN,$API_ORIGIN${H5_ORIGIN:+,$H5_ORIGIN}
H5_ORIGIN=$H5_ORIGIN
API_PORT=$API_PORT
ADMIN_PORT=$ADMIN_PORT
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
ALPINE_MIRROR=$ALPINE_MIRROR
NODE_REGISTRY=$NODE_REGISTRY
GOPROXY=$GOPROXY_VALUE
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
    build:
      context: ./backend
      dockerfile: deployments/Dockerfile
      args:
        ALPINE_MIRROR: ${ALPINE_MIRROR}
        GOPROXY: ${GOPROXY}
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-api
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
    build:
      context: .
      dockerfile: docker/genericim/admin.Dockerfile
      args:
        ALPINE_MIRROR: ${ALPINE_MIRROR}
        NODE_REGISTRY: ${NODE_REGISTRY}
    container_name: ${COMPOSE_PROJECT_NAME:-genericim}-admin
    ports:
      - "127.0.0.1:${ADMIN_PORT:-18084}:80"
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
}

patch_admin_nginx_for_ws() {
  cd "$INSTALL_DIR"
  python3 - <<'PY' 2>/dev/null || true
from pathlib import Path
p = Path("docker/genericim/admin-nginx.conf")
s = p.read_text()
if "proxy_set_header Upgrade $http_upgrade;" not in s:
    s = s.replace(
        "proxy_set_header X-Forwarded-Proto $scheme;\n",
        "proxy_set_header X-Forwarded-Proto $scheme;\n"
        "        proxy_set_header Upgrade $http_upgrade;\n"
        "        proxy_set_header Connection \"upgrade\";\n"
        "        proxy_read_timeout 86400s;\n"
    )
p.write_text(s)
PY
}

write_nginx_conf() {
  [ "$CREATE_NGINX" = "1" ] || return 0
  local conf_dir admin_conf api_conf h5_conf reload_cmd

  if [ -d /www/server/panel/vhost/nginx ]; then
    conf_dir="/www/server/panel/vhost/nginx"
    admin_conf="$conf_dir/${PROJECT_NAME}-admin.conf"
    api_conf="$conf_dir/${PROJECT_NAME}-api.conf"
    h5_conf="$conf_dir/${PROJECT_NAME}-h5.conf"
    reload_cmd="/www/server/nginx/sbin/nginx -s reload"
  else
    conf_dir="/etc/nginx/conf.d"
    admin_conf="$conf_dir/${PROJECT_NAME}-admin.conf"
    api_conf="$conf_dir/${PROJECT_NAME}-api.conf"
    h5_conf="$conf_dir/${PROJECT_NAME}-h5.conf"
    reload_cmd="nginx -s reload"
    if ! command -v nginx >/dev/null 2>&1; then
      warn "Nginx/Baota Nginx was not found. Skipping Nginx config."
      return 0
    fi
  fi

  mkdir -p "$conf_dir"
  if [ -f "$admin_conf" ]; then
    cp "$admin_conf" "${admin_conf}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  if [ -f "$api_conf" ]; then
    cp "$api_conf" "${api_conf}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  if [ -f "$h5_conf" ]; then
    cp "$h5_conf" "${h5_conf}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  local admin_server_name="$ADMIN_DOMAIN"
  local api_server_name="$API_DOMAIN"
  local h5_server_name="$H5_DOMAIN"
  [ "$admin_server_name" = "_" ] && admin_server_name="_"
  [ "$api_server_name" = "_" ] && api_server_name="$admin_server_name"
  [ "$h5_server_name" = "_" ] && h5_server_name=""

  cat >"$admin_conf" <<EOF
server {
    listen 80;
    server_name $admin_server_name;

    client_max_body_size 100m;
    client_body_timeout 120s;
    send_timeout 120s;
    keepalive_timeout 75s;
    keepalive_requests 10000;

    location ^~ /.well-known/acme-challenge/ {
        root /www/wwwroot/$PROJECT_NAME;
        try_files \$uri =404;
    }

    location / {
        proxy_pass http://127.0.0.1:$ADMIN_PORT;
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

  if [ "$api_server_name" != "$admin_server_name" ]; then
    cat >"$api_conf" <<EOF
server {
    listen 80;
    server_name $api_server_name;

    client_max_body_size 100m;
    client_body_timeout 120s;
    send_timeout 120s;
    keepalive_timeout 75s;
    keepalive_requests 10000;

    location ^~ /.well-known/acme-challenge/ {
        root /www/wwwroot/$PROJECT_NAME;
        try_files \$uri =404;
    }

    location / {
        proxy_pass http://127.0.0.1:$API_PORT;
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
  else
    rm -f "$api_conf"
  fi

  local h5_root=""
  if [ -d "$INSTALL_DIR/web-dist" ]; then
    h5_root="$INSTALL_DIR/web-dist"
  elif [ -d "$INSTALL_DIR/h5-dist" ]; then
    h5_root="$INSTALL_DIR/h5-dist"
  elif [ -d "$INSTALL_DIR/h5/dist" ]; then
    h5_root="$INSTALL_DIR/h5/dist"
  elif [ -d "$INSTALL_DIR/build/web" ]; then
    h5_root="$INSTALL_DIR/build/web"
  fi

  if [ -n "$h5_server_name" ] && [ -n "$h5_root" ]; then
    if [ "$h5_server_name" = "$admin_server_name" ] || [ "$h5_server_name" = "$api_server_name" ]; then
      fail "H5 domain must be different from admin/api domain when writing Nginx vhost: $h5_server_name"
    fi

    cat >"$h5_conf" <<EOF
server {
    listen 80;
    server_name $h5_server_name;
    root $h5_root;
    index index.html;

    client_max_body_size 100m;

    location ^~ /.well-known/acme-challenge/ {
        root /www/wwwroot/$PROJECT_NAME;
        try_files \$uri =404;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 86400s;
        proxy_buffering off;
    }

    location /uploads/ {
        proxy_pass http://127.0.0.1:$API_PORT/uploads/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  else
    rm -f "$h5_conf"
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
# H5 SPA fallback is handled in the generated Nginx vhost:
# location / { try_files $uri $uri/ /index.html; }
EOF
    fi
  fi

  if [ -x /www/server/nginx/sbin/nginx ]; then
    /www/server/nginx/sbin/nginx -t && eval "$reload_cmd"
  elif command -v nginx >/dev/null 2>&1; then
    nginx -t && eval "$reload_cmd"
  else
    warn "Nginx config written to $conf_path, but reload was skipped."
  fi
  log "Nginx admin config written: $admin_conf"
  if [ "$api_server_name" != "$admin_server_name" ]; then
    log "Nginx api config written: $api_conf"
  fi
  if [ -n "$h5_server_name" ] && [ -n "$h5_root" ]; then
    log "Nginx h5 config written: $h5_conf"
  fi
}

deploy_stack() {
  cd "$INSTALL_DIR"
  info "Building and starting Docker services. This can take several minutes..."
  timeout 1800 bash -c 'docker compose --env-file .env.bt -f compose.bt.yaml up -d --build' || {
    if command -v docker-compose >/dev/null 2>&1; then
      timeout 1800 docker-compose --env-file .env.bt -f compose.bt.yaml up -d --build
    else
      fail "Docker Compose deployment failed or timed out."
    fi
  }
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
  log "Docker services are healthy."
}

print_result() {
  cat <<EOF

Deployment complete.

Admin URL:
  $ADMIN_ORIGIN

API URL:
  $PUBLIC_URL

Local checks:
  curl http://127.0.0.1:$API_PORT/health
  curl http://127.0.0.1:$ADMIN_PORT/

Admin account:
  username: admin
  password: $INITIAL_ADMIN_PASSWORD

Manage:
  cd $INSTALL_DIR
  docker compose --env-file .env.bt -f compose.bt.yaml ps
  docker compose --env-file .env.bt -f compose.bt.yaml logs -f api
  docker compose --env-file .env.bt -f compose.bt.yaml down

Important:
  If you enable SSL in Baota later, rerun this script with --scheme https
  or update PUBLIC_URL in $INSTALL_DIR/.env.bt and restart the api service.

EOF
}

confirm
detect_mirror_mode
install_basic_packages
install_docker
sync_source
write_env_and_config
patch_admin_nginx_for_ws
deploy_stack
write_nginx_conf
verify_stack
print_result
