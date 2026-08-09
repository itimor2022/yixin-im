#!/usr/bin/env python3
"""Local Docker load acceptance for the durable message Outbox.

The script uses one dedicated group-load account and temporarily disables the
two message rate-limit settings. Original values are restored in ``finally``.
It is intended only for the local Docker test stack.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import pathlib
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


def run(*args: str) -> str:
    completed = subprocess.run(
        list(args),
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return completed.stdout.strip()


def container_environment(container: str) -> dict[str, str]:
    payload = json.loads(run("docker", "inspect", container))[0]
    result: dict[str, str] = {}
    for item in payload["Config"]["Env"]:
        key, _, value = item.partition("=")
        result[key] = value
    return result


class MySQL:
    def __init__(self) -> None:
        environment = container_environment("genericim-mysql")
        self.user = environment["MYSQL_USER"]
        self.password = environment["MYSQL_PASSWORD"]
        self.database = environment["MYSQL_DATABASE"]

    def query(self, sql: str) -> str:
        return run(
            "docker",
            "exec",
            "genericim-mysql",
            "mysql",
            f"-u{self.user}",
            f"-p{self.password}",
            self.database,
            "-N",
            "-B",
            "-e",
            sql,
        )


def redis_scan_calls() -> int:
    info = run("docker", "exec", "genericim-redis", "redis-cli", "INFO", "commandstats")
    for line in info.splitlines():
        if line.startswith("cmdstat_scan:"):
            for item in line.split(":", 1)[1].split(","):
                if item.startswith("calls="):
                    return int(item.split("=", 1)[1])
    return 0


def redis_delete(*keys: str) -> None:
    if keys:
        run("docker", "exec", "genericim-redis", "redis-cli", "DEL", *keys)


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1))
    return round(ordered[index], 2)


@dataclass
class SendResult:
    message_id: str
    latency_ms: float
    success: bool
    code: int | None
    error: str


def send_message(
    *,
    base_url: str,
    token: str,
    chat_id: str,
    prefix: str,
    release: threading.Event,
    index: int,
    media_id: str = "",
) -> SendResult:
    message_id = str(uuid.uuid4())
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "type": 1,
        "msg_id": message_id,
        "content": {"text": f"{prefix}-{index:04d}-{message_id}"},
    }
    if media_id:
        payload["type"] = 2
        payload["content"] = {
            "media": {
                "media_id": media_id,
                "url": "https://untrusted.invalid/outbox-load.png",
                "size": 1009,
                "mime_type": "image/png",
                "width": 24,
                "height": 24,
            }
        }
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/message/send",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
            # The local gateway rate limiter is intentionally IP-scoped. Model
            # independent clients instead of 500 requests from one loopback IP.
            "X-Forwarded-For": f"10.{(index // 250) + 1}.{(index % 250) + 1}.1",
        },
    )
    release.wait()
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            decoded = json.loads(response.read().decode("utf-8"))
        code = int(decoded.get("code", -1))
        success = code == 0
        error = "" if success else str(decoded.get("message", "unknown API error"))
    except urllib.error.HTTPError as exc:
        code = exc.code
        error = exc.read().decode("utf-8", errors="replace")[:500]
        success = False
    except Exception as exc:  # noqa: BLE001 - load evidence records every failure.
        code = None
        error = f"{type(exc).__name__}: {exc}"[:500]
        success = False
    elapsed = (time.perf_counter() - started) * 1000
    return SendResult(message_id, round(elapsed, 2), success, code, error)


def wait_outbox(mysql: MySQL, message_ids: list[str], timeout_seconds: int = 60) -> dict[str, int]:
    quoted = ",".join(f"'{item}'" for item in message_ids)
    deadline = time.monotonic() + timeout_seconds
    while True:
        raw = mysql.query(
            "SELECT status,COUNT(*) FROM message_outbox_events "
            f"WHERE message_id IN ({quoted}) GROUP BY status ORDER BY status;"
        )
        counts: dict[str, int] = {}
        for line in raw.splitlines():
            status, count = line.split("\t", 1)
            counts[status] = int(count)
        if sum(counts.values()) > 0 and not any(
            status in counts
            for status in ("pending", "processing", "retrying")
        ):
            return counts
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Outbox did not drain: {counts}")
        time.sleep(0.2)


def load_actor(private_path: pathlib.Path, username: str) -> tuple[str, str]:
    payload = json.loads(private_path.read_text(encoding="utf-8"))
    for actor in payload["actors"]:
        if actor["username"] == username:
            return str(actor["token"]), str(actor["user_id"])
    raise RuntimeError(f"Actor {username} not found")


def clone_media_fixtures(mysql: MySQL, fixture_media_id: str, count: int) -> list[str]:
    media_ids = [str(uuid.uuid4()) for _ in range(count)]
    statements = []
    for media_id in media_ids:
        statements.append(
            "INSERT INTO media_objects ("
            "media_id,user_id,admin_id,client_request_id,category,provider,bucket,"
            "object_key,url,original_name,normalized_ext,declared_mime,detected_mime,"
            "size_bytes,checksum_sha256,expected_sha256,upload_mode,remote_upload_id,"
            "part_size_bytes,status,business_type,business_id,business_scope_id,"
            "reference_count,retry_count,last_error,expires_at,next_retry_at,bound_at,"
            "deleted_at,created_at,updated_at"
            ") SELECT "
            f"'{media_id}',user_id,admin_id,'p3-{media_id}',category,provider,bucket,"
            f"CONCAT(object_key,'.p3-{media_id}'),url,original_name,normalized_ext,"
            "declared_mime,detected_mime,size_bytes,checksum_sha256,expected_sha256,"
            "upload_mode,'',0,'uploaded','','','',0,0,'',"
            "UTC_TIMESTAMP() + INTERVAL 1 DAY,NULL,NULL,NULL,UTC_TIMESTAMP(),UTC_TIMESTAMP() "
            f"FROM media_objects WHERE media_id='{fixture_media_id}' LIMIT 1;"
        )
    for offset in range(0, len(statements), 20):
        mysql.query("\n".join(statements[offset : offset + 20]))
    return media_ids


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--chat-id", default="9308452c-4c1a-4f2b-8681-d7537413b10e")
    parser.add_argument("--actor-username", default="gload0729124731003")
    parser.add_argument(
        "--private-actor-path",
        default="artifacts/group-message-load/group-load-0729124731-private.json",
    )
    parser.add_argument("--sizes", default="100,500")
    parser.add_argument("--fixture-media-id", default="")
    parser.add_argument(
        "--output",
        default="artifacts/real-device-qa/message-outbox-p3-20260729/load-result.json",
    )
    args = parser.parse_args()

    sizes = [int(item) for item in args.sizes.split(",") if item.strip()]
    token, user_uuid = load_actor(pathlib.Path(args.private_actor_path), args.actor_username)
    mysql = MySQL()
    original_rows = mysql.query(
        "SELECT `key`,value FROM system_settings "
        "WHERE `key` IN ('ip_rate_limit','user_rate_limit') ORDER BY `key`;"
    )
    originals = dict(line.split("\t", 1) for line in original_rows.splitlines())
    scan_before = redis_scan_calls()
    stages: list[dict[str, Any]] = []

    try:
        mysql.query(
            "UPDATE system_settings SET value='0' "
            "WHERE `key` IN ('ip_rate_limit','user_rate_limit');"
        )
        redis_delete(
            "setting:ip_rate_limit",
            "setting:user_rate_limit",
            f"msg_user:{user_uuid}",
            "msg_ip:127.0.0.1",
        )
        # Populate the two setting cache entries before measuring. Without this
        # request, the first stage measures a deliberate 100-way cold-cache
        # stampede created by the harness itself.
        warm_release = threading.Event()
        warm_release.set()
        warm = send_message(
            base_url=args.base_url,
            token=token,
            chat_id=args.chat_id,
            prefix="p3-outbox-load-warmup",
            release=warm_release,
            index=0,
        )
        if not warm.success:
            raise RuntimeError(f"Warm-up send failed: {warm.code} {warm.error}")
        wait_outbox(mysql, [warm.message_id])

        for size in sizes:
            prefix = f"p3-outbox-load-{size}-{int(time.time() * 1000)}"
            media_ids = (
                clone_media_fixtures(mysql, args.fixture_media_id, size)
                if args.fixture_media_id
                else [""] * size
            )
            release = threading.Event()
            with concurrent.futures.ThreadPoolExecutor(max_workers=size) as executor:
                futures = [
                    executor.submit(
                        send_message,
                        base_url=args.base_url,
                        token=token,
                        chat_id=args.chat_id,
                        prefix=prefix,
                        release=release,
                        index=index,
                        media_id=media_ids[index],
                    )
                    for index in range(size)
                ]
                wall_started = time.perf_counter()
                release.set()
                results = [future.result() for future in futures]
                wall_ms = (time.perf_counter() - wall_started) * 1000

            successful = [item for item in results if item.success]
            outbox_counts = wait_outbox(mysql, [item.message_id for item in successful])
            media_bound = 0
            if args.fixture_media_id:
                quoted_media = ",".join(f"'{item}'" for item in media_ids)
                media_bound = int(
                    mysql.query(
                        "SELECT COUNT(*) FROM media_objects "
                        f"WHERE media_id IN ({quoted_media}) AND status='bound';"
                    )
                    or "0"
                )
            latency = [item.latency_ms for item in successful]
            error_counts: dict[str, int] = {}
            for item in results:
                if not item.success:
                    key = f"{item.code}:{item.error[:120]}"
                    error_counts[key] = error_counts.get(key, 0) + 1
            stages.append(
                {
                    "size": size,
                    "attempted": len(results),
                    "success": len(successful),
                    "failed": len(results) - len(successful),
                    "wall_ms": round(wall_ms, 2),
                    "throughput_per_sec": round(len(successful) / (wall_ms / 1000), 2),
                    "latency": {
                        "p50_ms": percentile(latency, 0.50),
                        "p95_ms": percentile(latency, 0.95),
                        "p99_ms": percentile(latency, 0.99),
                        "max_ms": round(max(latency, default=0.0), 2),
                    },
                    "outbox": outbox_counts,
                    "expected_outbox_events": len(successful) * 2,
                    "actual_outbox_events": sum(outbox_counts.values()),
                    "media_bound": media_bound,
                    "expected_media_bound": len(successful) if args.fixture_media_id else 0,
                    "error_counts": error_counts,
                }
            )
            if args.fixture_media_id:
                stages[-1]["expected_outbox_events"] = len(successful) * 3
            time.sleep(1)
    finally:
        for key, value in originals.items():
            escaped = value.replace("'", "''")
            mysql.query(
                f"UPDATE system_settings SET value='{escaped}' WHERE `key`='{key}';"
            )
        redis_delete(
            "setting:ip_rate_limit",
            "setting:user_rate_limit",
            f"msg_user:{user_uuid}",
            "msg_ip:127.0.0.1",
        )

    scan_after = redis_scan_calls()
    payload = {
        "run_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "model": "one dedicated group member issuing N simultaneous authenticated sends",
        "message_type": "image" if args.fixture_media_id else "text",
        "chat_id": args.chat_id,
        "sizes": sizes,
        "stages": stages,
        "redis_scan": {
            "before": scan_before,
            "after": scan_after,
            "delta": scan_after - scan_before,
        },
        "rate_limits_restored": True,
        "acceptance": {
            "all_sends_succeeded": all(stage["failed"] == 0 for stage in stages),
            "all_outbox_events_completed": all(
                stage["outbox"] == {"completed": stage["expected_outbox_events"]}
                for stage in stages
            ),
            "all_media_bound": all(
                stage["media_bound"] == stage["expected_media_bound"]
                for stage in stages
            ),
            "p95_under_1s": all(stage["latency"]["p95_ms"] < 1000 for stage in stages),
            "redis_scan_delta_zero": scan_after == scan_before,
        },
    }
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if all(payload["acceptance"].values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
