#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  sudo bash deploy-online-prebuilt.sh

Environment overrides:
  DOMAIN=im.example.com                  Use one domain for admin and API
  ADMIN_DOMAIN=imadmin.example.com       Admin domain
  API_DOMAIN=imapi.example.com           API/media domain
  H5_DOMAIN=imh5.example.com             H5 frontend domain
  KF_DOMAIN=kf.example.com               Official service admin domain
  H5_PORT=18083                          Local H5 container port
  ADMIN_PORT=18084                       Local admin container port
  KF_PORT=18085                          Local service admin container port
  API_PORT=18080                         Local API container port
  SCHEME=https                           Public scheme, http or https
  INSTALL_DIR=/www/wwwroot/genericim       Server install directory
  MIRROR=cn                              cn or global
  ADMIN_PASSWORD='new-password'          Only needed on first deploy or reset
  STORAGE_PROVIDER=aliyun                Use aliyun OSS for uploaded media. Keep local for local disk
  STORAGE_ALIYUN_ENDPOINT=oss-cn-...     Aliyun OSS endpoint
  STORAGE_ALIYUN_BUCKET=bucket-name      Aliyun OSS bucket
  STORAGE_ALIYUN_ACCESS_KEY_ID=...       Aliyun OSS access key id
  STORAGE_ALIYUN_ACCESS_KEY_SECRET=...   Aliyun OSS access key secret
  STORAGE_ALIYUN_PUBLIC_BASE_URL=...     HTTPS media/CDN domain, optional but recommended
  WRITE_NGINX=1                          Safely configure Baota proxy and reuse existing SSL certificates

This prebuilt package does not run Go/Node builds on the server.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/genericim}"
MIRROR="${MIRROR:-cn}"
SCHEME="${SCHEME:-https}"
DOMAIN="${DOMAIN:-}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-${DOMAIN:-api.example.com}}"
API_DOMAIN="${API_DOMAIN:-${DOMAIN:-api.example.com}}"
H5_DOMAIN="${H5_DOMAIN:-h5.example.com}"
KF_DOMAIN="${KF_DOMAIN:-support.example.com}"
H5_PORT="${H5_PORT:-18083}"
ADMIN_PORT="${ADMIN_PORT:-18084}"
KF_PORT="${KF_PORT:-18085}"
API_PORT="${API_PORT:-18080}"

args=(
  "--install-dir" "$INSTALL_DIR"
  "--admin-domain" "$ADMIN_DOMAIN"
  "--api-domain" "$API_DOMAIN"
  "--h5-domain" "$H5_DOMAIN"
  "--kf-domain" "$KF_DOMAIN"
  "--h5-port" "$H5_PORT"
  "--admin-port" "$ADMIN_PORT"
  "--kf-port" "$KF_PORT"
  "--api-port" "$API_PORT"
  "--scheme" "$SCHEME"
  "--mirror" "$MIRROR"
  "-y"
)

if [ -n "${ADMIN_PASSWORD:-}" ]; then
  args+=("--admin-password" "$ADMIN_PASSWORD")
fi

# Baota owns site, SSL certificate and renewal configuration. Keep Nginx writes
# opt-in so deploy/update packages do not break panel-managed certificates.
if [ "${WRITE_NGINX:-0}" != "1" ]; then
  args+=("--no-nginx")
fi

exec bash "$ROOT_DIR/scripts/baota_docker_deploy_prebuilt.sh" "${args[@]}"
