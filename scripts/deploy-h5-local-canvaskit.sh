#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="20260713-bind-mount-v2"

usage() {
  cat <<'EOF'
Usage:
  sudo bash deploy-h5-local-canvaskit.sh H5_ZIP [INSTALL_DIR]

Example:
  sudo bash deploy-h5-local-canvaskit.sh \
    /tmp/GenericIM-h5-local-canvaskit-20260712-231121.zip \
    /www/wwwroot/genericim

Optional environment variables:
  H5_PORT=18083                 Local H5 port used for health checks
  PUBLIC_H5_URL=https://...     Also verify the public URL after deployment
  ENV_FILE=/path/.env.bt        Docker Compose environment file
  COMPOSE_FILE=/path/file.yaml  Main Docker Compose file
EOF
}

log() {
  printf '[H5] %s\n' "$*"
}

fail() {
  printf '[H5][ERROR] %s\n' "$*" >&2
  exit 1
}

[ "${1:-}" != "-h" ] && [ "${1:-}" != "--help" ] || {
  usage
  exit 0
}

log "Deployment script version: $SCRIPT_VERSION"

ZIP_PATH="${1:-}"
INSTALL_DIR="${2:-/www/wwwroot/genericim}"
[ -n "$ZIP_PATH" ] || {
  usage
  exit 2
}
[ -f "$ZIP_PATH" ] || fail "ZIP not found: $ZIP_PATH"
[ -d "$INSTALL_DIR" ] || fail "Install directory not found: $INSTALL_DIR"

command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v docker >/dev/null 2>&1 || fail "docker is required"

ZIP_PATH="$(cd "$(dirname "$ZIP_PATH")" && pwd)/$(basename "$ZIP_PATH")"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env.bt}"

if [ -z "${COMPOSE_FILE:-}" ]; then
  for candidate in \
    "$INSTALL_DIR/compose.bt.yaml" \
    "$INSTALL_DIR/compose.yaml" \
    "$INSTALL_DIR/docker-compose.yml"; do
    if [ -f "$candidate" ]; then
      COMPOSE_FILE="$candidate"
      break
    fi
  done
fi
[ -n "${COMPOSE_FILE:-}" ] && [ -f "$COMPOSE_FILE" ] || \
  fail "Main Docker Compose file was not found under $INSTALL_DIR"

read_env_value() {
  local key="$1"
  local file="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1 | tr -d '\r' | sed 's/^\"//;s/\"$//'
}

H5_PORT="${H5_PORT:-$(read_env_value H5_PORT "$ENV_FILE")}"
H5_PORT="${H5_PORT:-18083}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(read_env_value COMPOSE_PROJECT_NAME "$ENV_FILE")}"
PROJECT_NAME="${PROJECT_NAME:-genericim}"

compose_h5() {
  local files=(-f "$COMPOSE_FILE")
  [ -f "$INSTALL_DIR/compose.storage.yaml" ] && files+=(-f "$INSTALL_DIR/compose.storage.yaml")
  [ -f "$INSTALL_DIR/compose.h5.yaml" ] && files+=(-f "$INSTALL_DIR/compose.h5.yaml")
  [ -f "$INSTALL_DIR/compose.kf.yaml" ] && files+=(-f "$INSTALL_DIR/compose.kf.yaml")

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
WORK_DIR="$(mktemp -d "$INSTALL_DIR/.h5-deploy-${STAMP}-XXXXXX")"
EXTRACT_DIR="$WORK_DIR/extracted"
STAGE_DIR="$INSTALL_DIR/.web-dist-new-$STAMP"
OLD_DIR="$INSTALL_DIR/.web-dist-old-$STAMP"
BACKUP_DIR="$INSTALL_DIR/backups/h5-$STAMP"
TARGET_DIR="$INSTALL_DIR/web-dist"
ACTIVATED=0

rollback() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$ACTIVATED" -eq 1 ]; then
    printf '[H5][WARN] Deployment failed; restoring the previous web-dist.\n' >&2
    compose_h5 rm -sf h5 >/dev/null 2>&1 || true
    rm -rf "$TARGET_DIR"
    if [ -d "$OLD_DIR" ]; then
      mv "$OLD_DIR" "$TARGET_DIR"
      compose_h5 up -d h5 >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$WORK_DIR" "$STAGE_DIR"
  exit "$status"
}
trap rollback EXIT

mkdir -p "$EXTRACT_DIR" "$BACKUP_DIR"
log "Extracting $(basename "$ZIP_PATH")"
if ! unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR"; then
  log "unzip returned a warning; continuing with strict payload validation"
fi

PAYLOAD_DIR="$EXTRACT_DIR"
if [ ! -f "$PAYLOAD_DIR/index.html" ]; then
  INDEX_FILE="$(find "$EXTRACT_DIR" -mindepth 2 -maxdepth 3 -type f -name index.html -print -quit)"
  [ -n "$INDEX_FILE" ] || fail "index.html was not found in the ZIP"
  PAYLOAD_DIR="$(dirname "$INDEX_FILE")"
fi

for required in \
  index.html \
  open.html \
  flutter_bootstrap.js \
  main.dart.js \
  canvaskit/chromium/canvaskit.wasm; do
  [ -f "$PAYLOAD_DIR/$required" ] || fail "Missing required H5 file: $required"
done

grep -Eq '"useLocalCanvasKit"[[:space:]]*:[[:space:]]*true' \
  "$PAYLOAD_DIR/flutter_bootstrap.js" || \
  fail "This ZIP is not a local-CanvasKit Flutter Web build"

log "CanvasKit validation passed"
if [ -d "$TARGET_DIR" ]; then
  log "Backing up current web-dist to $BACKUP_DIR/web-dist.tar.gz"
  tar -czf "$BACKUP_DIR/web-dist.tar.gz" -C "$INSTALL_DIR" web-dist
fi

mkdir -p "$STAGE_DIR"
cp -a "$PAYLOAD_DIR/." "$STAGE_DIR/"
chmod -R a+rX "$STAGE_DIR"

# A running Docker bind mount keeps referencing the old directory inode after
# an atomic rename. Remove the H5 container before swapping web-dist so the
# next container is guaranteed to mount the new directory rather than the
# soon-to-be-deleted backup directory.
log "Removing current H5 container before activating the new web-dist"
compose_h5 rm -sf h5

if [ -d "$TARGET_DIR" ]; then
  mv "$TARGET_DIR" "$OLD_DIR"
fi
mv "$STAGE_DIR" "$TARGET_DIR"
ACTIVATED=1

log "Restarting H5 service"
compose_h5 up -d h5

H5_CONTAINER="${PROJECT_NAME}-h5"
docker exec "$H5_CONTAINER" test -f /usr/share/nginx/html/index.html || \
  fail "H5 container did not mount web-dist/index.html"
docker exec "$H5_CONTAINER" test -f /usr/share/nginx/html/open.html || \
  fail "H5 container did not mount web-dist/open.html"
docker exec "$H5_CONTAINER" test -f \
  /usr/share/nginx/html/canvaskit/chromium/canvaskit.wasm || \
  fail "H5 container did not mount the local CanvasKit payload"

log "Checking local H5 endpoint on port $H5_PORT"
for attempt in $(seq 1 20); do
  if curl -fsS --max-time 5 "http://127.0.0.1:$H5_PORT/" >/dev/null && \
     curl -fsS --max-time 5 \
       "http://127.0.0.1:$H5_PORT/open.html?type=user&id=smoke-user" \
       -o /dev/null && \
     curl -fsS --max-time 20 \
       "http://127.0.0.1:$H5_PORT/canvaskit/chromium/canvaskit.wasm" \
       -o /dev/null; then
    break
  fi
  [ "$attempt" -lt 20 ] || fail "Local H5 health check failed on port $H5_PORT"
  sleep 1
done

CONTENT_TYPE="$(curl -fsSI --max-time 10 \
  "http://127.0.0.1:$H5_PORT/canvaskit/chromium/canvaskit.wasm" | \
  tr -d '\r' | awk -F ': ' 'tolower($1) == "content-type" {print tolower($2)}' | tail -n 1)"
case "$CONTENT_TYPE" in
  application/wasm*) ;;
  *) fail "Unexpected CanvasKit Content-Type: ${CONTENT_TYPE:-missing}" ;;
esac

if [ -n "${PUBLIC_H5_URL:-}" ]; then
  PUBLIC_H5_URL="${PUBLIC_H5_URL%/}"
  log "Checking public H5 URL: $PUBLIC_H5_URL"
  curl -fsS --max-time 20 "$PUBLIC_H5_URL/" >/dev/null || \
    fail "Public H5 page check failed: $PUBLIC_H5_URL"
  curl -fsS --max-time 20 \
    "$PUBLIC_H5_URL/open.html?type=user&id=smoke-user" \
    -o /dev/null || fail "Public H5 open-link page check failed: $PUBLIC_H5_URL"
  curl -fsS --max-time 60 \
    "$PUBLIC_H5_URL/canvaskit/chromium/canvaskit.wasm" \
    -o /dev/null || fail "Public CanvasKit check failed: $PUBLIC_H5_URL"
fi

rm -rf "$OLD_DIR"
ACTIVATED=0
trap - EXIT
rm -rf "$WORK_DIR"

log "Deployment completed successfully"
printf '[H5] Backup: %s\n' "$BACKUP_DIR/web-dist.tar.gz"
printf '[H5] Local URL: http://127.0.0.1:%s/\n' "$H5_PORT"
if [ -n "${PUBLIC_H5_URL:-}" ]; then
  printf '[H5] Public URL: %s/\n' "$PUBLIC_H5_URL"
fi
