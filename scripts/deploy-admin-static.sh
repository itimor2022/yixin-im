#!/usr/bin/env bash
set -Eeuo pipefail

PAYLOAD_DIR="${1:-}"
INSTALL_DIR="${2:-/www/wwwroot/genericim/genericim-online-server}"
EXPECTED_API_URL="${EXPECTED_API_URL:-/api/v1}"
PUBLIC_ADMIN_URL="${PUBLIC_ADMIN_URL:-https://admin.example.com}"
ADMIN_PORT="${ADMIN_PORT:-18084}"

log() { printf '[ADMIN] %s\n' "$*"; }
fail() { printf '[ADMIN][ERROR] %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Please run with sudo/root"
[ -d "$PAYLOAD_DIR" ] || fail "Admin payload directory not found: $PAYLOAD_DIR"
[ -s "$PAYLOAD_DIR/index.html" ] || fail "Admin payload index.html is missing"
[ -d "$INSTALL_DIR" ] || fail "Install directory not found: $INSTALL_DIR"

if grep -RIql --include='*.js' --include='*.html' 'example\.com' "$PAYLOAD_DIR"; then
  fail "Admin payload still contains a legacy delivery domain"
fi
if [ "$EXPECTED_API_URL" = "/api/v1" ] && \
   grep -RIql --include='*.js' --include='*.html' 'https://api\.example\.com' "$PAYLOAD_DIR"; then
  fail "Admin payload still contains the cross-origin API host api.example.com"
fi
grep -RIql --include='*.js' --include='*.html' -F "$EXPECTED_API_URL" \
  "$PAYLOAD_DIR" || fail "Expected API URL is missing: $EXPECTED_API_URL"

cd "$INSTALL_DIR"
ENV_FILE="$INSTALL_DIR/.env.bt"
files=()
for candidate in compose.bt.yaml compose.yaml docker-compose.yml; do
  if [ -f "$candidate" ]; then
    files=(-f "$candidate")
    break
  fi
done
[ "${#files[@]}" -gt 0 ] || fail "Main Compose file was not found"
for candidate in compose.storage.yaml compose.h5.yaml compose.kf.yaml; do
  [ ! -f "$candidate" ] || files+=(-f "$candidate")
done

compose() {
  if docker compose version >/dev/null 2>&1; then
    if [ -f "$ENV_FILE" ]; then
      docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
    else
      docker compose "${files[@]}" "$@"
    fi
  elif command -v docker-compose >/dev/null 2>&1; then
    if [ -f "$ENV_FILE" ]; then
      docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
    else
      docker-compose "${files[@]}" "$@"
    fi
  else
    fail "Docker Compose is unavailable"
  fi
}

STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_DIR="$INSTALL_DIR/admin-dist"
STAGE_DIR="$INSTALL_DIR/.admin-dist-new-$STAMP"
OLD_DIR="$INSTALL_DIR/.admin-dist-old-$STAMP"
BACKUP_DIR="$INSTALL_DIR/backups/admin-$STAMP"
ACTIVATED=0

rollback() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$ACTIVATED" -eq 1 ]; then
    printf '[ADMIN][WARN] Update failed; restoring previous admin-dist.\n' >&2
    compose rm -sf admin >/dev/null 2>&1 || true
    rm -rf "$TARGET_DIR"
    if [ -d "$OLD_DIR" ]; then
      mv "$OLD_DIR" "$TARGET_DIR"
      compose up -d --force-recreate admin >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$STAGE_DIR"
  exit "$status"
}
trap rollback EXIT

mkdir -p "$STAGE_DIR" "$BACKUP_DIR"
cp -a "$PAYLOAD_DIR/." "$STAGE_DIR/"
chmod -R a+rX "$STAGE_DIR"
if [ -d "$TARGET_DIR" ]; then
  tar -czf "$BACKUP_DIR/admin-dist.tar.gz" -C "$INSTALL_DIR" admin-dist
fi

log "Removing the current admin container before swapping the bind mount"
compose rm -sf admin
if [ -d "$TARGET_DIR" ]; then
  mv "$TARGET_DIR" "$OLD_DIR"
fi
mv "$STAGE_DIR" "$TARGET_DIR"
ACTIVATED=1

compose up -d --force-recreate admin

PROJECT_NAME="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$ENV_FILE" 2>/dev/null | tail -n 1 | tr -d '\r\"')"
PROJECT_NAME="${PROJECT_NAME:-genericim}"
CONTAINER_NAME="${PROJECT_NAME}-admin"
ASSET_FILE="$(find "$TARGET_DIR/assets" -maxdepth 1 -type f -name '*.js' -print -quit)"
[ -n "$ASSET_FILE" ] || fail "Admin JavaScript asset was not found"
ASSET_RELATIVE="${ASSET_FILE#"$TARGET_DIR/"}"

for attempt in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" test -s /usr/share/nginx/html/index.html 2>/dev/null && \
     docker exec "$CONTAINER_NAME" test -s "/usr/share/nginx/html/$ASSET_RELATIVE" 2>/dev/null && \
     curl -fsS --max-time 5 "http://127.0.0.1:$ADMIN_PORT/" >/dev/null; then
    break
  fi
  [ "$attempt" -lt 30 ] || fail "Admin container did not become healthy"
  sleep 1
done

LOCAL_INDEX_HASH="$(curl -fsS --max-time 10 "http://127.0.0.1:$ADMIN_PORT/" | sha256sum | awk '{print $1}')"
HOST_INDEX_HASH="$(sha256sum "$TARGET_DIR/index.html" | awk '{print $1}')"
[ "$LOCAL_INDEX_HASH" = "$HOST_INDEX_HASH" ] || fail "Admin container is serving a stale index.html"

PUBLIC_STATUS="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_ADMIN_URL%/}/")"
[ "$PUBLIC_STATUS" = "200" ] || fail "Public admin returned HTTP $PUBLIC_STATUS"

rm -rf "$OLD_DIR"
ACTIVATED=0
trap - EXIT
log "Deployment completed: public=200 API=$EXPECTED_API_URL"
log "Backup: $BACKUP_DIR/admin-dist.tar.gz"
