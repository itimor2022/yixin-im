#!/usr/bin/env python3
"""Validate Android notification RemoteInput reply on the current APK."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im345_im357_single_device import (  # noqa: E402
    app_notification_keys,
    center,
    notification_blocks,
    run_adb,
)
from run_p1_fix_validation import (  # noqa: E402
    find_private_chat,
    list_messages,
    request_json,
)


def save_ui(adb: str, serial: str, output_dir: Path, name: str) -> ET.Element:
    remote_xml = f"/sdcard/{name}.xml"
    remote_png = f"/sdcard/{name}.png"
    run_adb(adb, serial, "shell", "uiautomator", "dump", remote_xml)
    run_adb(adb, serial, "shell", "screencap", "-p", remote_png)
    run_adb(adb, serial, "pull", remote_xml, str(output_dir / f"{name}.xml"))
    run_adb(adb, serial, "pull", remote_png, str(output_dir / f"{name}.png"))
    return ET.parse(output_dir / f"{name}.xml").getroot()


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
    apk_hash = hashlib.sha256(apk.read_bytes()).hexdigest().upper()

    stamp = datetime.now().strftime("%H%M%S")
    seed_marker = f"IM355_REPLY_SEED_{stamp}"
    reply_marker = f"IM355_QUICK_REPLY_{stamp}"
    client_msg_id = str(uuid.uuid4())
    token = ""
    chat_id = ""
    server_msg_id = client_msg_id
    sent = False
    revoked = False
    trace_remote = (
        f"/sdcard/Android/data/{args.package}/files/qa/"
        "notification-reply-trace.jsonl"
    )

    run_adb(args.adb, args.serial, "logcat", "-c")
    run_adb(
        args.adb,
        args.serial,
        "shell",
        "rm",
        "-f",
        trace_remote,
        check=False,
    )
    try:
        login = request_json(
            args.base,
            "/auth/login",
            data={
                "username": args.username,
                "password": args.password,
                "device_id": f"im355-api-{uuid.uuid4().hex[:8]}",
                "device_type": "android",
                "device_name": "IM355 Quick Reply QA",
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
        baseline_keys = app_notification_keys(args.adb, args.serial, args.package)

        sent_response = request_json(
            args.base,
            "/message/send",
            token,
            {
                "chat_id": chat_id,
                "type": 1,
                "content": {"text": seed_marker},
                "msg_id": client_msg_id,
            },
        )
        if int(sent_response.get("code", -1)) != 0:
            raise RuntimeError(f"seed send failed: {sent_response.get('message')}")
        sent = True
        server_msg_id = str((sent_response.get("data") or {}).get("msg_id") or client_msg_id)
        time.sleep(10)

        notification_dump = run_adb(
            args.adb, args.serial, "shell", "dumpsys", "notification", "--noredact"
        )
        (output_dir / "01-notification-with-reply.txt").write_text(
            notification_dump, encoding="utf-8"
        )
        keys_after_send = app_notification_keys(args.adb, args.serial, args.package)
        new_keys = keys_after_send - baseline_keys
        block = next(
            (
                item
                for item in notification_blocks(notification_dump)
                if "pkg=com.genericim.ma100" in item
                and "channel=genericim_messages" in item
                and '"回复"' in item
                and any(key in item for key in new_keys)
            ),
            "",
        )
        if not block:
            raise RuntimeError("message notification has no quick-reply action")
        notification_key = next(key for key in new_keys if key in block)

        run_adb(args.adb, args.serial, "shell", "cmd", "statusbar", "expand-notifications")
        time.sleep(4)
        shade = save_ui(args.adb, args.serial, output_dir, "02-notification-shade")
        reply_node = next(
            (
                node
                for node in shade.iter("node")
                if node.attrib.get("text") == "回复"
                and node.attrib.get("clickable") == "true"
            ),
            None,
        )
        if reply_node is None:
            collapsed = [
                node
                for node in shade.iter("node")
                if node.attrib.get("content-desc") == "已收起"
            ]
            if collapsed:
                expand = max(collapsed, key=lambda node: center(node.attrib["bounds"])[1])
                x, y = center(expand.attrib["bounds"])
                run_adb(args.adb, args.serial, "shell", "input", "tap", str(x), str(y))
                time.sleep(3)
                shade = save_ui(args.adb, args.serial, output_dir, "02b-notification-expanded")
                reply_node = next(
                    (
                        node
                        for node in shade.iter("node")
                        if node.attrib.get("text") == "回复"
                        and node.attrib.get("clickable") == "true"
                    ),
                    None,
                )
        if reply_node is None:
            raise RuntimeError("quick-reply button is not visible in the notification shade")
        x, y = center(reply_node.attrib["bounds"])
        run_adb(args.adb, args.serial, "shell", "input", "tap", str(x), str(y))
        time.sleep(3)

        expanded = save_ui(args.adb, args.serial, output_dir, "03-reply-input")
        edit = next(
            (
                node
                for node in expanded.iter("node")
                if node.attrib.get("class") == "android.widget.EditText"
            ),
            None,
        )
        if edit is None:
            raise RuntimeError("RemoteInput edit field did not open")
        x, y = center(edit.attrib["bounds"])
        run_adb(args.adb, args.serial, "shell", "input", "tap", str(x), str(y))
        run_adb(args.adb, args.serial, "shell", "input", "text", reply_marker)
        time.sleep(2)
        filled = save_ui(args.adb, args.serial, output_dir, "04-reply-filled")
        send = next(
            (
                node
                for node in filled.iter("node")
                if node.attrib.get("resource-id")
                == "com.android.systemui:id/remote_input_send"
                and node.attrib.get("clickable") == "true"
            ),
            None,
        )
        if send is None:
            raise RuntimeError("RemoteInput send button is not visible")
        x, y = center(send.attrib["bounds"])
        run_adb(args.adb, args.serial, "shell", "input", "tap", str(x), str(y))
        audit_attempts = []
        reply = None
        messages = []
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            time.sleep(2)
            messages = list_messages(args.base, token, chat_id, 50)
            reply = next(
                (
                    item
                    for item in messages
                    if reply_marker
                    in json.dumps(item.get("content") or {}, ensure_ascii=False)
                ),
                None,
            )
            audit_attempts.append(
                {
                    "checked_at": datetime.now().isoformat(timespec="seconds"),
                    "message_count": len(messages),
                    "reply_found": reply is not None,
                }
            )
            if reply is not None:
                break
        (output_dir / "05-server-audit.json").write_text(
            json.dumps(messages, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        (output_dir / "05b-server-poll-audit.json").write_text(
            json.dumps(audit_attempts, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        if reply is None:
            raise RuntimeError("quick reply did not reach the authoritative message list")

        revoke = request_json(
            args.base,
            "/message/revoke",
            token,
            {"chat_id": chat_id, "msg_id": server_msg_id},
        )
        revoked = int(revoke.get("code", -1)) == 0

        logcat = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "time")
        (output_dir / "06-logcat.txt").write_text(logcat, encoding="utf-8")
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
            "case_id": "IM-355",
            "status": "PASS",
            "device_id": args.serial,
            "notification_key": notification_key,
            "reply_marker": reply_marker,
            "remote_input_visible": True,
            "reply_present_in_authoritative_server_history": True,
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
        try:
            logcat = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "time")
            (output_dir / "06-logcat.txt").write_text(logcat, encoding="utf-8")
        except Exception:
            pass
        try:
            run_adb(
                args.adb,
                args.serial,
                "pull",
                trace_remote,
                str(output_dir / "07-notification-reply-trace.jsonl"),
                check=False,
            )
        except Exception:
            pass
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
        run_adb(args.adb, args.serial, "shell", "cmd", "statusbar", "collapse", check=False)
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
