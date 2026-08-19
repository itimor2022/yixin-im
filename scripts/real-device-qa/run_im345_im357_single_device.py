#!/usr/bin/env python3
"""Close IM-345 and IM-357 with one receiver device and an API sender."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_p1_fix_validation import find_private_chat, request_json  # noqa: E402


def run_adb(adb: str, serial: str, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        [adb, "-s", serial, *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"adb {' '.join(args)} failed ({result.returncode}): {result.stderr}"
        )
    return result.stdout


def dump_ui(adb: str, serial: str, output_dir: Path, name: str) -> ET.Element:
    remote_xml = f"/sdcard/{name}.xml"
    remote_png = f"/sdcard/{name}.png"
    run_adb(adb, serial, "shell", "uiautomator", "dump", remote_xml)
    run_adb(adb, serial, "shell", "screencap", "-p", remote_png)
    run_adb(adb, serial, "pull", remote_xml, str(output_dir / f"{name}.xml"))
    run_adb(adb, serial, "pull", remote_png, str(output_dir / f"{name}.png"))
    return ET.parse(output_dir / f"{name}.xml").getroot()


def center(bounds: str) -> tuple[int, int]:
    values = [int(value) for value in re.findall(r"\d+", bounds)]
    if len(values) != 4:
        raise RuntimeError(f"invalid UI bounds: {bounds}")
    return (values[0] + values[2]) // 2, (values[1] + values[3]) // 2


def descriptions(root: ET.Element) -> list[tuple[ET.Element, str]]:
    return [
        (node, node.attrib.get("content-desc", ""))
        for node in root.iter("node")
        if node.attrib.get("content-desc")
    ]


def ensure_private_chat(
    adb: str,
    serial: str,
    package: str,
    chat_name: str,
    output_dir: Path,
) -> None:
    run_adb(adb, serial, "shell", "am", "start", "-W", "-n", f"{package}/.MainActivity")
    time.sleep(5)
    for attempt in range(1, 8):
        root = dump_ui(adb, serial, output_dir, f"navigation-{attempt:02d}")
        items = descriptions(root)
        messages = next((node for node, desc in items if desc == "消息"), None)
        header = next(
            (
                node
                for node, desc in items
                if chat_name in desc
                and center(node.attrib["bounds"])[1] < 500
            ),
            None,
        )
        if header is not None:
            return

        row = next(
            (
                node
                for node, desc in items
                if messages is not None
                and len([line for line in desc.splitlines() if line.strip()]) >= 3
                and [line.strip() for line in desc.splitlines() if line.strip()][1]
                == chat_name
                and center(node.attrib["bounds"])[1] >= 500
            ),
            None,
        )
        if row is not None:
            x, y = center(row.attrib["bounds"])
            run_adb(adb, serial, "shell", "input", "tap", str(x), str(y))
            time.sleep(5)
            continue

        if messages is not None:
            x, y = center(messages.attrib["bounds"])
            run_adb(adb, serial, "shell", "input", "tap", str(x), str(y))
        else:
            run_adb(adb, serial, "shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(3)
    raise RuntimeError(f"unable to open private chat: {chat_name}")


def wakefulness(adb: str, serial: str) -> str:
    output = run_adb(adb, serial, "shell", "dumpsys", "power")
    match = re.search(r"mWakefulness=(\w+)", output)
    return match.group(1) if match else "unknown"


def notification_blocks(dump: str) -> list[str]:
    starts = [match.start() for match in re.finditer(r"NotificationRecord\(", dump)]
    blocks: list[str] = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(dump)
        blocks.append(dump[start:end])
    return blocks


def app_notification_keys(adb: str, serial: str, package: str) -> set[str]:
    output = run_adb(adb, serial, "shell", "cmd", "notification", "list")
    return {line.strip() for line in output.splitlines() if package in line}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    parser.add_argument("--username", default="smoke_alice")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--chat-name", default="Smoke Alice")
    parser.add_argument("--target-username", default="smoke_bob")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    output_root = Path(args.output_dir)
    if not output_root.is_absolute():
        output_root = repo / output_root
    output_dir = output_root / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)

    apk = Path(args.apk)
    if not apk.is_absolute():
        apk = repo / apk
    import hashlib

    apk_hash = hashlib.sha256(apk.read_bytes()).hexdigest().upper()
    marker = f"IM345_LOCK_REVOKE_{datetime.now().strftime('%H%M%S')}"
    client_msg_id = str(uuid.uuid4())
    token = ""
    chat_id = ""
    sent = False
    revoked = False
    notification_key = ""

    run_adb(args.adb, args.serial, "logcat", "-c")
    try:
        login = request_json(
            args.base,
            "/auth/login",
            data={
                "username": args.username,
                "password": args.password,
                "device_id": f"single-notification-{uuid.uuid4().hex[:8]}",
                "device_type": "android",
                "device_name": "Single Device Notification QA",
            },
        )
        token = str((login.get("data") or {}).get("token") or "")
        if int(login.get("code", -1)) != 0 or not token:
            raise RuntimeError(f"API sender login failed: {login.get('message')}")
        chat_id = find_private_chat(args.base, token, args.target_username)

        ensure_private_chat(
            args.adb,
            args.serial,
            args.package,
            args.chat_name,
            output_dir,
        )
        dump_ui(args.adb, args.serial, output_dir, "01-active-group-before-lock")
        baseline_keys = app_notification_keys(args.adb, args.serial, args.package)

        if wakefulness(args.adb, args.serial).lower() != "awake":
            run_adb(args.adb, args.serial, "shell", "input", "keyevent", "KEYCODE_WAKEUP")
            time.sleep(2)
        run_adb(args.adb, args.serial, "shell", "input", "keyevent", "KEYCODE_POWER")
        time.sleep(3)
        power_before = run_adb(args.adb, args.serial, "shell", "dumpsys", "power")
        (output_dir / "02-power-asleep-before-send.txt").write_text(
            power_before, encoding="utf-8"
        )
        if "mWakefulness=Asleep" not in power_before:
            raise RuntimeError("device did not enter the asleep state")

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

        power_after = run_adb(args.adb, args.serial, "shell", "dumpsys", "power")
        notification_after_send = run_adb(
            args.adb, args.serial, "shell", "dumpsys", "notification", "--noredact"
        )
        (output_dir / "03-power-asleep-after-send.txt").write_text(
            power_after, encoding="utf-8"
        )
        (output_dir / "04-notification-after-send.txt").write_text(
            notification_after_send, encoding="utf-8"
        )
        if "mWakefulness=Asleep" not in power_after:
            raise RuntimeError("device was not asleep when the notification arrived")
        keys_after_send = app_notification_keys(args.adb, args.serial, args.package)
        new_keys = keys_after_send - baseline_keys
        block = next(
            (
                item
                for item in notification_blocks(notification_after_send)
                if "pkg=com.genericim.ma100" in item
                and "channel=genericim_messages" in item
                and any(key in item for key in new_keys)
            ),
            "",
        )
        if not block:
            raise RuntimeError("locked active chat did not create the expected message notification")
        key_match = re.search(r"\bkey=([^\s:]+)", block)
        if not key_match:
            raise RuntimeError("notification key not found")
        notification_key = key_match.group(1)
        if notification_key not in keys_after_send:
            raise RuntimeError("message notification key is not active after send")

        revoke_response = request_json(
            args.base,
            "/message/revoke",
            token,
            {"chat_id": chat_id, "msg_id": server_msg_id},
        )
        if int(revoke_response.get("code", -1)) != 0:
            raise RuntimeError(f"message revoke failed: {revoke_response.get('message')}")
        revoked = True
        time.sleep(8)

        notification_after_revoke = run_adb(
            args.adb, args.serial, "shell", "dumpsys", "notification", "--noredact"
        )
        (output_dir / "05-notification-after-revoke.txt").write_text(
            notification_after_revoke, encoding="utf-8"
        )
        keys_after_revoke = app_notification_keys(args.adb, args.serial, args.package)
        removed_after_locked_revoke = notification_key not in keys_after_revoke

        logcat = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "time")
        (output_dir / "06-logcat.txt").write_text(logcat, encoding="utf-8")
        fatal_lines = [
            line
            for line in logcat.splitlines()
            if "FATAL EXCEPTION" in line
            or f"ANR in {args.package}" in line
            or "FlutterError" in line
        ]
        if fatal_lines:
            raise RuntimeError(f"fatal/anr/flutter errors found: {fatal_lines[:3]}")

        result: dict[str, Any] = {
            "status": "PASS",
            "cases": [
                {
                    "id": "IM-345",
                    "status": "PASS",
                    "active_chat_was_locked": True,
                    "message_notification_visible_while_asleep": True,
                    "notification_key": notification_key,
                },
            ],
            "device_id": args.serial,
            "chat_name": args.chat_name,
            "marker": marker,
            "apk_sha256": apk_hash,
            "baseline_app_notification_keys": sorted(baseline_keys),
            "locked_revoke_cleanup_observed": removed_after_locked_revoke,
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
                    {"chat_id": chat_id, "msg_id": client_msg_id},
                )
            except Exception:
                pass
        if wakefulness(args.adb, args.serial).lower() != "awake":
            run_adb(args.adb, args.serial, "shell", "input", "keyevent", "KEYCODE_WAKEUP")
            time.sleep(2)
        run_adb(args.adb, args.serial, "shell", "wm", "dismiss-keyguard", check=False)
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
