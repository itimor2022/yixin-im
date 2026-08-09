#!/usr/bin/env python3
"""Verify that an unread-message revoke enters the HMS control-event route."""

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
    send_text,
)


def mysql_rows(container: str, query: str) -> list[list[str]]:
    completed = subprocess.run(
        [
            "docker",
            "exec",
            container,
            "mysql",
            "--default-character-set=utf8mb4",
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
    sender = create_actor(api, "A", run_id)
    recipient = create_actor(api, "B", run_id)

    api.request(
        "POST",
        "/user/push-token",
        actor=recipient,
        body={
            "device_id": f"im400-api-b-{run_id}",
            "push_token": f"im357-fake-hms-{uuid.uuid4().hex}",
            "device_type": "android",
            "push_channel": "hms",
            "brand": "HUAWEI",
            "model": "IM357-QA",
            "device_name": "IM357 Revoke Route QA",
        },
    )

    # The revoke control event must still be delivered after the recipient
    # disables visible notifications, otherwise an already displayed preview
    # can remain in the shade indefinitely.
    api.request(
        "PUT",
        "/user/push-settings",
        actor=recipient,
        body={"enabled": False, "show_preview": False},
    )

    chat_id = create_chat(api, sender, 1, [recipient])
    message = send_text(api, sender, chat_id, f"IM357_REVOKE_{run_id}")
    message_id = str(message.get("msg_id", "")).strip()
    check(message_id, f"sent message id is missing: {message}")

    api.request(
        "POST",
        "/message/revoke",
        actor=sender,
        body={"chat_id": chat_id, "msg_id": message_id},
    )

    revoke_logs: list[list[str]] = []
    for _ in range(20):
        revoke_logs = mysql_rows(
            mysql_container,
            "SELECT p.scene,p.channel,p.provider,p.success,p.title,p.body "
            "FROM push_delivery_logs p JOIN users u ON u.id=p.user_id "
            f"WHERE u.uuid='{recipient.user_id}' AND p.scene='message_revoked' "
            "ORDER BY p.id DESC LIMIT 5;",
        )
        if revoke_logs:
            break
        time.sleep(0.5)

    check(revoke_logs, "recipient revoke control-event delivery log is missing")
    route_log = revoke_logs[0]
    check(route_log[1:3] == ["hms", "hms"], f"unexpected revoke route: {route_log}")

    sender_logs = mysql_rows(
        mysql_container,
        "SELECT p.scene,p.channel,p.provider,p.success "
        "FROM push_delivery_logs p JOIN users u ON u.id=p.user_id "
        f"WHERE u.uuid='{sender.user_id}' AND p.scene='message_revoked' "
        "ORDER BY p.id DESC LIMIT 5;",
    )
    check(not sender_logs, f"revoker unexpectedly received own control event: {sender_logs}")

    report = {
        "case_id": "IM-357",
        "status": "PASS_CURRENT_SOURCE_ROUTE",
        "run_id": run_id,
        "base_url": base_url,
        "chat_id": chat_id,
        "message_id": message_id,
        "recipient_notifications_enabled": False,
        "recipient_push_route": {
            "scene": route_log[0],
            "channel": route_log[1],
            "provider": route_log[2],
            "success": route_log[3] == "1",
            "title": route_log[4],
            "body": route_log[5],
        },
        "revoker_push_log_count": len(sender_logs),
        "note": "A failed provider send is expected with the isolated fake HMS token; the assertion covers control-event routing, policy bypass and target selection, not external delivery.",
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"im357-revoke-push-{run_id}.json"
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
        report = run(args.base_url, Path(args.output_dir).resolve(), args.mysql_container)
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"status": "FAIL", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
