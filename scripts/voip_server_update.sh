#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$SCRIPT_DIR/payload}"
ENV_FILE="${ENV_FILE:-${INSTALL_DIR:+$INSTALL_DIR/.env.bt}}"
COMPOSE_FILE="${COMPOSE_FILE:-${INSTALL_DIR:+$INSTALL_DIR/compose.bt.yaml}}"
BACKUP_ROOT="${BACKUP_ROOT:-${INSTALL_DIR:+$INSTALL_DIR/backups}}"
STAMP="$(date +%Y%m%d-%H%M%S)"

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }

[ -n "$INSTALL_DIR" ] || fail "INSTALL_DIR is required."

ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env.bt}"
COMPOSE_FILE="${COMPOSE_FILE:-$INSTALL_DIR/compose.bt.yaml}"
BACKUP_ROOT="${BACKUP_ROOT:-$INSTALL_DIR/backups}"
BACKUP_DIR="$BACKUP_ROOT/voip-server-update-$STAMP"
BACKEND_DIR="$INSTALL_DIR/backend"
NEW_BINARY="$PAYLOAD_DIR/backend/server-linux-amd64"

[ -f "$ENV_FILE" ] || fail ".env.bt not found: $ENV_FILE"
[ -f "$COMPOSE_FILE" ] || fail "compose.bt.yaml not found: $COMPOSE_FILE"
[ -f "$NEW_BINARY" ] || fail "VoIP server binary not found: $NEW_BINARY"
[ -d "$BACKEND_DIR" ] || fail "Backend directory not found: $BACKEND_DIR"
command -v docker >/dev/null 2>&1 || fail "Docker is unavailable."
command -v curl >/dev/null 2>&1 || fail "curl is unavailable."
if docker compose version >/dev/null 2>&1; then
  :
elif command -v docker-compose >/dev/null 2>&1; then
  :
else
  fail "Docker Compose is unavailable."
fi

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) fail "This package only supports Linux amd64/x86_64." ;;
esac

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

API_PORT="${API_PORT:-18080}"

compose_exec() {
  local files=("-f" "$COMPOSE_FILE")
  [ -f "$INSTALL_DIR/compose.storage.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.storage.yaml")
  [ -f "$INSTALL_DIR/compose.h5.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.h5.yaml")
  [ -f "$INSTALL_DIR/compose.kf.yaml" ] && files+=("-f" "$INSTALL_DIR/compose.kf.yaml")

  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" "${files[@]}" "$@"
  else
    fail "Docker Compose is unavailable."
  fi
}

wait_api() {
  local attempts="${1:-60}"
  local attempt
  for attempt in $(seq 1 "$attempts"); do
    if curl -fsS --connect-timeout 2 --max-time 5 \
      "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1; then
      log "API is healthy ($attempt/$attempts)"
      return 0
    fi
    sleep 2
  done
  return 1
}

mkdir -p "$BACKUP_DIR/backend"
HAD_AMD64=0
HAD_SERVER=0

if [ -f "$BACKEND_DIR/server-linux-amd64" ]; then
  cp -a "$BACKEND_DIR/server-linux-amd64" "$BACKUP_DIR/backend/"
  HAD_AMD64=1
fi
if [ -f "$BACKEND_DIR/server" ]; then
  cp -a "$BACKEND_DIR/server" "$BACKUP_DIR/backend/"
  HAD_SERVER=1
fi

rollback() {
  warn "VoIP server update failed; restoring the previous backend binary."

  if [ "$HAD_AMD64" -eq 1 ]; then
    cp -af "$BACKUP_DIR/backend/server-linux-amd64" "$BACKEND_DIR/server-linux-amd64"
  else
    rm -f "$BACKEND_DIR/server-linux-amd64"
  fi

  if [ "$HAD_SERVER" -eq 1 ]; then
    cp -af "$BACKUP_DIR/backend/server" "$BACKEND_DIR/server"
  else
    rm -f "$BACKEND_DIR/server"
  fi

  chmod 0755 "$BACKEND_DIR/server-linux-amd64" "$BACKEND_DIR/server" 2>/dev/null || true
  compose_exec up -d --force-recreate api || warn "API recreate after rollback returned non-zero."
  wait_api 30 || warn "API health check after rollback did not recover in time."
  fail "Update rolled back. Backup: $BACKUP_DIR"
}

info "Backup directory: $BACKUP_DIR"
if ! install -m 0755 "$NEW_BINARY" "$BACKEND_DIR/server-linux-amd64.new" ||
  ! cp -f "$NEW_BINARY" "$BACKEND_DIR/server.new" ||
  ! chmod 0755 "$BACKEND_DIR/server.new"; then
  rm -f "$BACKEND_DIR/server-linux-amd64.new" "$BACKEND_DIR/server.new"
  fail "Could not stage the new backend binary; existing binaries were not changed."
fi
if ! mv -f "$BACKEND_DIR/server-linux-amd64.new" "$BACKEND_DIR/server-linux-amd64" ||
  ! mv -f "$BACKEND_DIR/server.new" "$BACKEND_DIR/server"; then
  rollback
fi

info "Recreating API container only"
compose_exec up -d --force-recreate api || rollback

info "Waiting for API health check: http://127.0.0.1:${API_PORT}/health"
if ! wait_api 60; then
  compose_exec ps api || true
  compose_exec logs --tail=120 api || true
  rollback
fi

compose_exec ps api || warn "Could not display API container status."
log "VoIP server-only update complete."
log "No database seed, review-account reset, or frontend update was executed."
log "Backup: $BACKUP_DIR"
