#!/usr/bin/env python3
"""Verify current-source notification privacy and master-switch push policy."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from run_im400_remaining_api import Api, check, create_actor, create_chat, send_text


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


def latest_log_id(container: str, user_uuid: str) -> int:
    rows = mysql_rows(
        container,
        "SELECT COALESCE(MAX(p.id),0) FROM push_delivery_logs p "
        "JOIN users u ON u.id=p.user_id "
        f"WHERE u.uuid='{user_uuid}';",
    )
    return int(rows[0][0]) if rows else 0


def logs_after(container: str, user_uuid: str, log_id: int) -> list[list[str]]:
    return mysql_rows(
        container,
        "SELECT p.id,p.scene,p.channel,p.provider,p.success,p.title,p.body "
        "FROM push_delivery_logs p JOIN users u ON u.id=p.user_id "
        f"WHERE u.uuid='{user_uuid}' AND p.id>{log_id} ORDER BY p.id ASC;",
    )


def wait_for_logs(
    container: str,
    user_uuid: str,
    log_id: int,
    *,
    attempts: int = 20,
) -> list[list[str]]:
    for _ in range(attempts):
        rows = logs_after(container, user_uuid, log_id)
        if rows:
            return rows
        time.sleep(0.5)
    return []


def run(base_url: str, output_dir: Path, mysql_container: str) -> dict[str, Any]:
    api = Api(base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    sender = create_actor(api, "A", run_id)
    recipient = create_actor(api, "B", run_id)
    sender_display_name = "IM400 API A"
    api.request(
        "POST",
        "/user/push-token",
        actor=recipient,
        body={
            "device_id": f"im400-api-b-{run_id}",
            "push_token": f"im346-fake-hms-{uuid.uuid4().hex}",
            "device_type": "android",
            "push_channel": "hms",
            "brand": "HUAWEI",
            "model": "IM346-QA",
            "device_name": "IM346 Privacy Route QA",
        },
    )
    chat_id = create_chat(api, sender, 1, [recipient])

    api.request(
        "PUT",
        "/user/push-settings",
        actor=recipient,
        body={"enabled": True, "show_preview": False},
    )
    hidden_marker = f"IM346_PRIVATE_{run_id}"
    hidden_before = latest_log_id(mysql_container, recipient.user_id)
    send_text(api, sender, chat_id, hidden_marker)
    hidden_logs = wait_for_logs(mysql_container, recipient.user_id, hidden_before)
    check(hidden_logs, "preview-off message did not enter the recipient push route")
    hidden = hidden_logs[0]
    check(hidden[1:4] == ["new_message", "hms", "hms"], f"unexpected hidden route: {hidden}")
    check(hidden[5] == "新消息", f"preview-off title leaked identity: {hidden}")
    check(hidden[6] == "您收到一条新消息", f"preview-off body leaked content: {hidden}")
    check(hidden_marker not in "\t".join(hidden), f"private marker leaked into delivery log: {hidden}")
    check(
        sender_display_name not in "\t".join(hidden),
        f"sender identity leaked into delivery log: {hidden}",
    )

    api.request(
        "PUT",
        "/user/push-settings",
        actor=recipient,
        body={"enabled": False},
    )
    disabled_before = latest_log_id(mysql_container, recipient.user_id)
    send_text(api, sender, chat_id, f"IM349_DISABLED_{run_id}")
    time.sleep(2.0)
    disabled_logs = logs_after(mysql_container, recipient.user_id, disabled_before)
    check(not disabled_logs, f"master-disabled account still generated push delivery logs: {disabled_logs}")

    api.request(
        "PUT",
        "/user/push-settings",
        actor=recipient,
        body={"enabled": True, "show_preview": True},
    )
    visible_marker = f"IM346_VISIBLE_{run_id}"
    visible_before = latest_log_id(mysql_container, recipient.user_id)
    send_text(api, sender, chat_id, visible_marker)
    visible_logs = wait_for_logs(mysql_container, recipient.user_id, visible_before)
    check(visible_logs, "preview-on message did not enter the recipient push route")
    visible = visible_logs[0]
    check(visible[5] == sender_display_name, f"preview-on title was not restored: {visible}")
    check(visible[6] == visible_marker, f"preview-on body was not restored: {visible}")

    report = {
        "case_ids": ["IM-346", "IM-349"],
        "status": "PASS_CURRENT_SOURCE_ROUTE",
        "run_id": run_id,
        "base_url": base_url,
        "chat_id": chat_id,
        "preview_off": {
            "scene": hidden[1],
            "channel": hidden[2],
            "provider": hidden[3],
            "success": hidden[4] == "1",
            "title": hidden[5],
            "body": hidden[6],
            "private_marker_absent": hidden_marker not in "\t".join(hidden),
            "sender_identity_absent": sender_display_name not in "\t".join(hidden),
        },
        "master_disabled_new_log_count": len(disabled_logs),
        "preview_on": {
            "scene": visible[1],
            "channel": visible[2],
            "provider": visible[3],
            "success": visible[4] == "1",
            "title_restored": visible[5] == sender_display_name,
            "body_restored": visible[6] == visible_marker,
        },
        "note": "Provider failure is expected for the isolated fake HMS token; assertions cover current-source policy, privacy shaping and routing, not external delivery.",
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"im346-notification-privacy-{run_id}.json"
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
