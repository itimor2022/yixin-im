#!/usr/bin/env python3
"""Verify notification preview privacy against the local Docker backend."""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im345_im357_single_device import (  # noqa: E402
    app_notification_keys,
    notification_blocks,
    run_adb,
)
from run_im400_remaining_api import Actor, Api, response_data, send_text  # noqa: E402
from run_p1_fix_validation import find_private_chat  # noqa: E402


def login(api: Api, username: str, password: str, label: str) -> Actor:
    payload = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": password,
            "device_id": f"im346-real-{label}-{uuid.uuid4().hex[:8]}",
            "device_type": "qa",
            "device_name": f"IM346 Real Device {label}",
        },
    )
    data = response_data(payload)
    if not isinstance(data, dict) or not data.get("token"):
        raise RuntimeError(f"{label} login failed")
    user = data.get("user") if isinstance(data.get("user"), dict) else {}
    return Actor(label, str(user.get("uuid") or ""), str(data["token"]))


def app_blocks(adb: str, serial: str, package: str) -> tuple[str, list[str]]:
    dump = run_adb(adb, serial, "shell", "dumpsys", "notification", "--noredact")
    blocks = [block for block in notification_blocks(dump) if f"pkg={package}" in block]
    return dump, blocks


def wait_for_block(
    adb: str,
    serial: str,
    package: str,
    predicate,
    timeout: int = 25,
) -> tuple[str, str]:
    deadline = time.monotonic() + timeout
    latest_dump = ""
    while time.monotonic() < deadline:
        latest_dump, blocks = app_blocks(adb, serial, package)
        block = next((item for item in blocks if predicate(item)), "")
        if block:
            return latest_dump, block
        time.sleep(2)
    return latest_dump, ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--base", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--password", default="Smoke123")
    args = parser.parse_args()

    run_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, Any] = {
        "case_id": "IM-346",
        "status": "FAIL",
        "base": args.base,
        "serial": args.serial,
        "checks": {},
        "output_dir": str(run_dir),
    }

    api = Api(args.base)
    bob: Actor | None = None
    try:
        alice = login(api, "smoke_alice", args.password, "alice")
        bob = login(api, "smoke_bob", args.password, "bob")
        chat_id = find_private_chat(args.base, alice.token, "smoke_bob")
        result["chat_id"] = chat_id

        run_adb(
            args.adb,
            args.serial,
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            f"{args.package}/.MainActivity",
        )
        time.sleep(3)
        run_adb(args.adb, args.serial, "shell", "input", "keyevent", "KEYCODE_HOME")
        time.sleep(2)

        api.request(
            "PUT",
            "/user/push-settings",
            actor=bob,
            body={"enabled": True, "show_preview": False},
        )
        hidden_marker = f"IM346_HIDDEN_{datetime.now().strftime('%H%M%S')}"
        baseline = app_notification_keys(args.adb, args.serial, args.package)
        send_text(api, alice, chat_id, hidden_marker)
        hidden_dump, hidden_block = wait_for_block(
            args.adb,
            args.serial,
            args.package,
            lambda block: "您收到一条新消息" in block or "新消息" in block,
        )
        (run_dir / "01-preview-off-notification.txt").write_text(
            hidden_dump, encoding="utf-8"
        )
        hidden_keys = app_notification_keys(args.adb, args.serial, args.package) - baseline
        hidden_private = bool(hidden_block) and all(
            value not in hidden_block
            for value in (hidden_marker, "Smoke Alice", "smoke_alice")
        )
        result["preview_off"] = {
            "new_notification_keys": sorted(hidden_keys),
            "generic_notification_found": bool(hidden_block),
            "sender_and_body_absent": hidden_private,
        }

        api.request(
            "PUT",
            "/user/push-settings",
            actor=bob,
            body={"enabled": True, "show_preview": True},
        )
        visible_marker = f"IM346_VISIBLE_{datetime.now().strftime('%H%M%S')}"
        send_text(api, alice, chat_id, visible_marker)
        visible_dump, visible_block = wait_for_block(
            args.adb,
            args.serial,
            args.package,
            lambda block: visible_marker in block,
        )
        (run_dir / "02-preview-on-notification.txt").write_text(
            visible_dump, encoding="utf-8"
        )
        visible_restored = bool(visible_block) and (
            "Smoke Alice" in visible_block or "smoke_alice" in visible_block
        )
        result["preview_on"] = {
            "marker_found": visible_marker in visible_block,
            "sender_found": visible_restored,
        }
        result["checks"] = {
            "preview_off_notification_delivered": bool(hidden_block),
            "preview_off_hides_sender_and_body": hidden_private,
            "preview_on_restores_sender_and_body": visible_restored,
        }
        result["status"] = "PASS" if all(result["checks"].values()) else "FAIL"
    except Exception as error:  # noqa: BLE001
        result["error_type"] = type(error).__name__
        result["error"] = str(error)
    finally:
        if bob is not None:
            try:
                api.request(
                    "PUT",
                    "/user/push-settings",
                    actor=bob,
                    body={"enabled": True, "show_preview": True},
                )
            except Exception:
                pass
        result_path = run_dir / "case-result.json"
        result["result_path"] = str(result_path)
        result_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))

    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
