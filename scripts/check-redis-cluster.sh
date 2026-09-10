#!/usr/bin/env bash
# scripts/check-redis-cluster.sh
#
# 周期性跑的健康检查脚本（建议 cron 1min）。检查项：
#   - 每个 node 都 PING 通
#   - cluster_state == ok
#   - 所有 16384 个 slot 都被分配
#   - 至少 1 个 master + 1 个 slave（容忍单机宕）
#
# 失败会发到 ALERT_WEBHOOK（可选，Slack / 钉钉 / 企业微信通用）。
#
# 用法：
#   source /etc/redis-cluster.env
#   ./scripts/check-redis-cluster.sh

set -euo pipefail

if [[ -f /etc/redis-cluster.env ]]; then
  # shellcheck disable=SC1091
  source /etc/redis-cluster.env
fi

PASS="${PASS:-}"
REDIS_CLI="${REDIS_CLI:-redis-cli}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"

AUTH_FLAG=()
if [[ -n "$PASS" ]]; then
  AUTH_FLAG=(-a "$PASS" --no-auth-warning)
fi

if [[ -z "${NODES[*]:-}" ]]; then
  echo "[check] NODES not exported; set NODES=('<host:port>' ...)" >&2
  exit 2
fi

problems=()

for node in "${NODES[@]}"; do
  host="${node%:*}"
  port="${node##*:}"

  ping_out="$("$REDIS_CLI" "${AUTH_FLAG[@]}" -h "$host" -p "$port" -t 2 ping 2>&1 || true)"
  if [[ "$ping_out" != "PONG" ]]; then
    problems+=("ping $node failed: $ping_out")
    continue
  fi

  cluster_state="$("$REDIS_CLI" "${AUTH_FLAG[@]}" -h "$host" -p "$port" cluster info 2>/dev/null \
    | grep '^cluster_state' | awk -F: '{print $2}' | tr -d ' \r\n')"
  if [[ "$cluster_state" != "ok" ]]; then
    problems+=("$node cluster_state=$cluster_state (not ok)")
    continue
  fi

  # Count slots assigned across this node's cluster view.
  slot_count="$("$REDIS_CLI" "${AUTH_FLAG[@]}" -h "$host" -p "$port" cluster info 2>/dev/null \
    | grep '^cluster_slots_assigned' | awk -F: '{print $2}' | tr -d ' \r\n')"
  if [[ "$slot_count" != "16384" ]]; then
    problems+=("$node cluster_slots_assigned=$slot_count (expected 16384)")
  fi
done

if [[ "${#problems[@]}" -gt 0 ]]; then
  echo "[check] PROBLEMS:"
  printf '  - %s\n' "${problems[@]}"
  if [[ -n "$ALERT_WEBHOOK" ]]; then
    msg="Redis Cluster healthcheck failed: $(printf '%s; ' "${problems[@]}")"
    # Best-effort webhook delivery; the script must not fail just because
    # the webhook is unreachable.
    curl -fsS -X POST -H 'Content-Type: application/json' \
      --data "{\"text\":\"$msg\"}" "$ALERT_WEBHOOK" >/dev/null 2>&1 || true
  fi
  exit 1
fi

echo "[check] OK: $(printf '%s ' "${NODES[@]}")"