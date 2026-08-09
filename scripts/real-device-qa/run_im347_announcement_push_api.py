#!/usr/bin/env python3
"""Verify that group announcements enter the current-source HMS push route."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from run_im400_remaining_api import (
    Api,
    check,
    create_actor,
    create_chat,
    response_data,
)


def mysql_rows(container: str, query: str) -> list[list[str]]:
    completed = subprocess.run(
        [
            "docker",
            "exec",
            container,
            "mysql",
            "-N",
            "-B",
            "-ugenericim",
            "-pgenericim",
            "genericim",
            "-e",
            query,
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=20,
    )
    return [line.split("\t") for line in completed.stdout.splitlines() if line.strip()]


def run(base_url: str, output_dir: Path, mysql_container: str) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    owner = create_actor(api, "A", run_id)
    member = create_actor(api, "B", run_id)
    member_device_id = f"im400-api-b-{run_id}"

    api.request(
        "POST",
        "/user/push-token",
        actor=member,
        body={
            "device_id": member_device_id,
            "push_token": f"im347-fake-hms-{uuid.uuid4().hex}",
            "device_type": "android",
            "push_channel": "hms",
            "brand": "HUAWEI",
            "model": "IM347-QA",
            "device_name": "IM347 Push Route QA",
        },
    )

    chat_id = create_chat(
        api,
        owner,
        2,
        [member],
        f"IM347_{run_id}"[:32],
    )
    announcement = response_data(
        api.request(
            "POST",
            f"/chat/{chat_id}/announcements",
            actor=owner,
            body={"content": f"IM347_ROUTE_{run_id}"},
        )
    )
    check(
        isinstance(announcement, dict) and int(announcement.get("id", 0)) > 0,
        f"announcement create failed: {announcement}",
    )

    member_logs: list[list[str]] = []
    for _ in range(15):
        member_logs = mysql_rows(
            mysql_container,
            "SELECT p.scene,p.channel,p.provider,p.success "
            "FROM push_delivery_logs p JOIN users u ON u.id=p.user_id "
            f"WHERE u.uuid='{member.user_id}' ORDER BY p.id DESC LIMIT 5;",
        )
        if any(row[:2] == ["group_notice", "hms"] for row in member_logs):
            break
        time.sleep(0.5)

    route_log = next(
        (row for row in member_logs if row[:2] == ["group_notice", "hms"]),
        None,
    )
    check(route_log is not None, f"member push route log missing: {member_logs}")

    owner_logs = mysql_rows(
        mysql_container,
        "SELECT p.scene,p.channel,p.provider,p.success "
        "FROM push_delivery_logs p JOIN users u ON u.id=p.user_id "
        f"WHERE u.uuid='{owner.user_id}' AND p.scene='group_notice' ORDER BY p.id DESC LIMIT 5;",
    )
    check(not owner_logs, f"announcement author unexpectedly received own push: {owner_logs}")

    report = {
        "case_id": "IM-347",
        "status": "PASS_CURRENT_SOURCE_ROUTE",
        "run_id": run_id,
        "base_url": base_url,
        "chat_id": chat_id,
        "announcement_id": int(announcement["id"]),
        "member_push_route": {
            "scene": route_log[0],
            "channel": route_log[1],
            "provider": route_log[2],
            "success": route_log[3] == "1",
        },
        "author_push_log_count": len(owner_logs),
        "note": "A failed provider send is expected with the isolated fake HMS token; the assertion covers routing and target selection, not external delivery.",
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"im347-announcement-push-{run_id}.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    report["report_path"] = str(path)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--mysql-container", default="genericim-mysql")
    args = parser.parse_args()
    try:
        report = run(
            args.base_url,
            Path(args.output_dir).resolve(),
            args.mysql_container,
        )
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
