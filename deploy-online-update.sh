#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  sudo bash deploy-online-update.sh

Environment overrides:
  DOMAIN=im.example.com                  Use one domain for admin and API
  ADMIN_DOMAIN=imadmin.example.com       Admin domain
  API_DOMAIN=imapi.example.com           API/media domain
  H5_DOMAIN=imh5.example.com             H5 frontend domain
  SCHEME=https                           Public scheme, http or https
  INSTALL_DIR=/www/wwwroot/genericim       Server install directory
  MIRROR=cn                              cn, global, or auto
  ADMIN_PASSWORD='new-password'          Only needed on first deploy or reset
  NO_NGINX=1                             Skip writing Baota/Nginx vhost config

Examples:
  sudo bash deploy-online-update.sh
  sudo DOMAIN=im.example.com bash deploy-online-update.sh
  sudo ADMIN_DOMAIN=admin.example.com API_DOMAIN=imapi.example.com bash deploy-online-update.sh
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

args=(
  "--install-dir" "$INSTALL_DIR"
  "--admin-domain" "$ADMIN_DOMAIN"
  "--api-domain" "$API_DOMAIN"
  "--h5-domain" "$H5_DOMAIN"
  "--scheme" "$SCHEME"
  "--mirror" "$MIRROR"
  "-y"
)

if [ -n "${ADMIN_PASSWORD:-}" ]; then
  args+=("--admin-password" "$ADMIN_PASSWORD")
fi

if [ "${NO_NGINX:-0}" = "1" ]; then
  args+=("--no-nginx")
fi

exec bash "$ROOT_DIR/scripts/baota_docker_deploy.sh" "${args[@]}"
