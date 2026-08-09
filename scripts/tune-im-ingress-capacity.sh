#!/usr/bin/env sh
set -eu

# Tune the Linux accept queue and Nginx worker file limits used by high fan-in
# IM/WebSocket and upload traffic. The default mode is read-only. Use --apply
# explicitly on the production host after taking a host snapshot.

MODE="${1:-check}"
case "$MODE" in
  check|--check) MODE="check" ;;
  apply|--apply) MODE="apply" ;;
  *)
    echo "Usage: $0 [--check|--apply]" >&2
    exit 2
    ;;
esac

find_nginx() {
  if [ -x /www/server/nginx/sbin/nginx ]; then
    printf '%s\n' /www/server/nginx/sbin/nginx
  elif command -v nginx >/dev/null 2>&1; then
    command -v nginx
  else
    return 1
  fi
}

find_nginx_conf() {
  if [ -f /www/server/nginx/conf/nginx.conf ]; then
    printf '%s\n' /www/server/nginx/conf/nginx.conf
  elif [ -f /etc/nginx/nginx.conf ]; then
    printf '%s\n' /etc/nginx/nginx.conf
  else
    return 1
  fi
}

read_sysctl() {
  sysctl -n "$1" 2>/dev/null || printf '%s\n' unavailable
}

NGINX_BIN="$(find_nginx 2>/dev/null || true)"
NGINX_CONF="$(find_nginx_conf 2>/dev/null || true)"

echo "net.core.somaxconn=$(read_sysctl net.core.somaxconn)"
echo "net.ipv4.tcp_max_syn_backlog=$(read_sysctl net.ipv4.tcp_max_syn_backlog)"
echo "fs.file-max=$(read_sysctl fs.file-max)"

if [ -n "$NGINX_CONF" ]; then
  echo "nginx.conf=$NGINX_CONF"
  grep -E '^[[:space:]]*(worker_rlimit_nofile|worker_connections)[[:space:]]' "$NGINX_CONF" || true
else
  echo "nginx.conf=not-found"
fi

if [ "$MODE" = "check" ]; then
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "--apply must run as root" >&2
  exit 1
fi
if [ -z "$NGINX_BIN" ] || [ -z "$NGINX_CONF" ]; then
  echo "Nginx binary or nginx.conf was not found" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="${NGINX_CONF}.genericim-capacity.${STAMP}.bak"
cp -a "$NGINX_CONF" "$BACKUP"

cat >/etc/sysctl.d/99-genericim-im-capacity.conf <<'EOF'
# GenericIM IM: 500 concurrent WebSocket/upload acceptance baseline.
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 16384
fs.file-max = 1048576
EOF
sysctl --system >/dev/null

TMP_CONF="${NGINX_CONF}.genericim-capacity.tmp"
HAS_RLIMIT=0
if grep -qE '^[[:space:]]*worker_rlimit_nofile[[:space:]]' "$NGINX_CONF"; then
  HAS_RLIMIT=1
fi
awk -v has_rlimit="$HAS_RLIMIT" '
  BEGIN { inserted_rlimit = 0 }
  /^[[:space:]]*worker_rlimit_nofile[[:space:]]/ {
    print "worker_rlimit_nofile 262144;"
    next
  }
  /^[[:space:]]*worker_processes[[:space:]]/ {
    print
    if (!has_rlimit && !inserted_rlimit) {
      print "worker_rlimit_nofile 262144;"
      inserted_rlimit = 1
    }
    next
  }
  /^[[:space:]]*worker_connections[[:space:]]+[0-9]+;/ {
    sub(/[0-9]+;/, "16384;")
    print
    next
  }
  { print }
' "$NGINX_CONF" >"$TMP_CONF"
mv "$TMP_CONF" "$NGINX_CONF"

if ! "$NGINX_BIN" -t; then
  cp -a "$BACKUP" "$NGINX_CONF"
  echo "Nginx validation failed; restored $BACKUP" >&2
  exit 1
fi

"$NGINX_BIN" -s reload
echo "Applied IM ingress capacity tuning; backup=$BACKUP"
