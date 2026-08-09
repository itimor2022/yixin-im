#!/usr/bin/env python3
"""Validate notification removal when a background message is revoked."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im345_im357_single_device import (  # noqa: E402
    app_notification_keys,
    notification_blocks,
    run_adb,
)
from run_p1_fix_validation import find_private_chat, request_json  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    parser.add_argument("--username", default="smoke_alice")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--target-username", default="smoke_bob")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    root = Path(args.output_dir)
    if not root.is_absolute():
        root = repo / root
    output_dir = root / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)

    apk = Path(args.apk)
    if not apk.is_absolute():
        apk = repo / apk
    apk_hash = hashlib.sha256(apk.read_bytes()).hexdigest().upper()

    marker = f"IM357_BACKGROUND_REVOKE_{datetime.now().strftime('%H%M%S')}"
    client_msg_id = str(uuid.uuid4())
    token = ""
    chat_id = ""
    server_msg_id = client_msg_id
    sent = False
    revoked = False

    run_adb(args.adb, args.serial, "logcat", "-c")
    try:
        login = request_json(
            args.base,
            "/auth/login",
            data={
                "username": args.username,
                "password": args.password,
                "device_id": f"im357-api-{uuid.uuid4().hex[:8]}",
                "device_type": "android",
                "device_name": "IM357 Background QA",
            },
        )
        token = str((login.get("data") or {}).get("token") or "")
        if int(login.get("code", -1)) != 0 or not token:
            raise RuntimeError(f"API sender login failed: {login.get('message')}")
        chat_id = find_private_chat(args.base, token, args.target_username)

        run_adb(args.adb, args.serial, "shell", "am", "force-stop", args.package)
        run_adb(
            args.adb,
            args.serial,
            "shell",
            "am",
            "start",
            "-S",
            "-W",
            "-n",
            f"{args.package}/.MainActivity",
        )
        time.sleep(10)
        run_adb(args.adb, args.serial, "shell", "input", "keyevent", "KEYCODE_HOME")
        time.sleep(3)
        baseline_keys = app_notification_keys(args.adb, args.serial, args.package)
        (output_dir / "01-baseline-keys.json").write_text(
            json.dumps(sorted(baseline_keys), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        sent_response = request_json(
            args.base,
            "/message/send",
            token,
            {
                "chat_id": chat_id,
                "type": 1,
                "content": {"text": marker},
                "msg_id": client_msg_id,
            },
        )
        if int(sent_response.get("code", -1)) != 0:
            raise RuntimeError(f"message send failed: {sent_response.get('message')}")
        sent = True
        server_msg_id = str((sent_response.get("data") or {}).get("msg_id") or client_msg_id)
        time.sleep(10)

        after_send_dump = run_adb(
            args.adb, args.serial, "shell", "dumpsys", "notification", "--noredact"
        )
        (output_dir / "02-notification-after-send.txt").write_text(
            after_send_dump, encoding="utf-8"
        )
        keys_after_send = app_notification_keys(args.adb, args.serial, args.package)
        new_keys = keys_after_send - baseline_keys
        block = next(
            (
                item
                for item in notification_blocks(after_send_dump)
                if "pkg=com.genericim.app" in item
                and "channel=genericim_messages" in item
                and any(key in item for key in new_keys)
            ),
            "",
        )
        if not block:
            raise RuntimeError("background message notification was not created")
        notification_key = next(key for key in new_keys if key in block)

        revoke_response = request_json(
            args.base,
            "/message/revoke",
            token,
            {"chat_id": chat_id, "msg_id": server_msg_id},
        )
        if int(revoke_response.get("code", -1)) != 0:
            raise RuntimeError(f"message revoke failed: {revoke_response.get('message')}")
        revoked = True
        time.sleep(10)

        after_revoke_dump = run_adb(
            args.adb, args.serial, "shell", "dumpsys", "notification", "--noredact"
        )
        (output_dir / "03-notification-after-revoke.txt").write_text(
            after_revoke_dump, encoding="utf-8"
        )
        keys_after_revoke = app_notification_keys(args.adb, args.serial, args.package)
        if notification_key in keys_after_revoke:
            raise RuntimeError("revoked background message notification remained active")

        logcat = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "time")
        (output_dir / "04-logcat.txt").write_text(logcat, encoding="utf-8")
        fatal_count = sum(
            1
            for line in logcat.splitlines()
            if "FATAL EXCEPTION" in line
            or f"ANR in {args.package}" in line
            or "FlutterError" in line
        )
        if fatal_count:
            raise RuntimeError(f"fatal/anr/flutter error count: {fatal_count}")

        result = {
            "case_id": "IM-357",
            "status": "PASS",
            "device_id": args.serial,
            "marker": marker,
            "notification_key": notification_key,
            "notification_removed_after_revoke": True,
            "apk_sha256": apk_hash,
            "fatal_anr_flutter_error_count": 0,
            "output_dir": str(output_dir),
        }
        (output_dir / "summary.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    finally:
        if sent and not revoked and token and chat_id:
            try:
                request_json(
                    args.base,
                    "/message/revoke",
                    token,
                    {"chat_id": chat_id, "msg_id": server_msg_id},
                )
            except Exception:
                pass
        run_adb(args.adb, args.serial, "shell", "am", "force-stop", args.package, check=False)
        run_adb(
            args.adb,
            args.serial,
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            f"{args.package}/.MainActivity",
            check=False,
        )


if __name__ == "__main__":
    raise SystemExit(main())
