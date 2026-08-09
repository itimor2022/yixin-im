#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="20260713-bind-mount-repair-v2"

INSTALL_DIR="${1:-/www/wwwroot/genericim/genericim-online-server}"
PUBLIC_H5_URL="${PUBLIC_H5_URL:-https://h5.example.com}"
H5_PORT="${H5_PORT:-18083}"

log() { printf '[H5-REPAIR] %s\n' "$*"; }
fail() { printf '[H5-REPAIR][ERROR] %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Please run with sudo/root"
log "Repair script version: $SCRIPT_VERSION"
[ -d "$INSTALL_DIR" ] || fail "Install directory not found: $INSTALL_DIR"
cd "$INSTALL_DIR"

[ -s web-dist/index.html ] || fail "$INSTALL_DIR/web-dist/index.html is missing or empty"
[ -s web-dist/flutter_bootstrap.js ] || fail "$INSTALL_DIR/web-dist/flutter_bootstrap.js is missing or empty"
chmod -R a+rX web-dist

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

PROJECT_NAME="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$ENV_FILE" 2>/dev/null | tail -n 1 | tr -d '\r\"')"
PROJECT_NAME="${PROJECT_NAME:-genericim}"
CONTAINER_NAME="${PROJECT_NAME}-h5"

log "Host payload is present: $(stat -c '%s bytes' web-dist/index.html)"
log "Removing and force-recreating only the H5 container"
compose rm -sf h5 || true
compose up -d --force-recreate h5

for attempt in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" test -s /usr/share/nginx/html/index.html 2>/dev/null && \
     curl -fsS --max-time 5 "http://127.0.0.1:$H5_PORT/" >/dev/null; then
    break
  fi
  [ "$attempt" -lt 30 ] || {
    docker logs --tail 100 "$CONTAINER_NAME" >&2 || true
    fail "Local H5 did not recover"
  }
  sleep 1
done

log "Container mount source:"
docker inspect --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' \
  "$CONTAINER_NAME"

LOCAL_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$H5_PORT/")"
BOOTSTRAP_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$H5_PORT/flutter_bootstrap.js")"
[ "$LOCAL_STATUS" = "200" ] || fail "Local H5 root returned HTTP $LOCAL_STATUS"
[ "$BOOTSTRAP_STATUS" = "200" ] || fail "Local flutter_bootstrap.js returned HTTP $BOOTSTRAP_STATUS"
log "Local H5 checks passed: root=200 bootstrap=200"

PUBLIC_STATUS="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_H5_URL%/}/")"
PUBLIC_BOOTSTRAP_STATUS="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_H5_URL%/}/flutter_bootstrap.js")"
if [ "$PUBLIC_STATUS" != "200" ] || [ "$PUBLIC_BOOTSTRAP_STATUS" != "200" ]; then
  fail "Container is healthy, but public Nginx still fails: root=$PUBLIC_STATUS bootstrap=$PUBLIC_BOOTSTRAP_STATUS. Check Baota reverse proxy -> 127.0.0.1:$H5_PORT"
fi

log "Repair completed: public root=200 bootstrap=200"
