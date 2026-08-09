#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTALL_DIR="${INSTALL_DIR:-$ROOT_DIR}"
API_DOMAIN="${API_DOMAIN:-api.example.com}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-api.example.com}"
SCHEME="${SCHEME:-https}"
MIRROR="${MIRROR:-cn}"

args=(
  "--install-dir" "$INSTALL_DIR"
  "--api-domain" "$API_DOMAIN"
  "--admin-domain" "$ADMIN_DOMAIN"
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

exec bash "$ROOT_DIR/scripts/baota_docker_deploy_prebuilt.sh" "${args[@]}"
