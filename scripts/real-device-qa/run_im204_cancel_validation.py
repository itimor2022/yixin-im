#!/usr/bin/env python3
"""Focused dual-device validation for cancelling a file while it uploads."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_p1_fix_validation import (  # noqa: E402
    P1Harness,
    find_private_chat,
    list_messages,
    request_json,
)
from run_p2b4_file_revoke_validation import (  # noqa: E402
    long_press_node,
    node_containing,
    open_file_picker,
    wait_until,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--sender", required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    parser.add_argument("--username", default="smoke_alice")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument(
        "--remote-source",
        default="/sdcard/Download/IM204-CANCEL-RAW99-99MB.zip",
    )
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_dir = Path(args.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    sender = P1Harness(repo, run_dir / args.sender, args.adb, args.sender, args.package)
    receiver = P1Harness(
        repo, run_dir / args.receiver, args.adb, args.receiver, args.package
    )
    for harness in (sender, receiver):
        harness.adb_run("logcat", "-c")

    login = request_json(
        args.base,
        "/auth/login",
        data={
            "username": args.username,
            "password": args.password,
            "device_id": "im204-focused-validation",
            "device_type": "android",
            "device_name": "IM204 Focused Validation",
        },
    )
    login_data = login.get("data") or {}
    if int(login.get("code", -1)) != 0 or not login_data.get("token"):
        raise RuntimeError(f"QA API login failed: {login.get('message')}")
    token = str(login_data["token"])
    chat_id = find_private_chat(args.base, token, "smoke_bob")
    stamp = datetime.now().strftime("%H%M%S")
    file_name = f"IM204-CANCEL-{stamp}-99MB.zip"
    remote_target = f"/sdcard/Download/{file_name}"
    sender.adb_run("shell", "cp", args.remote_source, remote_target, check=True)

    evidence: list[str] = []
    last_error: Exception | None = None
    for attempt in range(1, 4):
        try:
            evidence += sender.open_private("smoke_bob", f"im204-focus-{attempt}")
            open_file_picker(sender, file_name)
            last_error = None
            break
        except Exception as exc:  # navigation may retain a previous profile route
            last_error = exc
            sender.device.press("back")
            time.sleep(1)
    if last_error is not None:
        raise last_error

    if not wait_until(lambda: node_containing(sender, file_name) is not None, 8):
        raise RuntimeError("optimistic sending bubble did not appear")
    pending = node_containing(sender, file_name)
    if pending is None:
        raise RuntimeError("sending bubble disappeared before it could be cancelled")
    evidence += sender.snapshot("im204-uploading")
    long_press_node(sender, pending)
    if not sender.device(description="撤回").wait(timeout=4):
        raise RuntimeError("sending message recall action is missing")
    evidence += sender.snapshot("im204-cancel-action")
    sender.device(description="撤回").click()
    if not wait_until(lambda: node_containing(sender, file_name) is None, 8):
        raise RuntimeError("cancelled upload left a local ghost message")
    evidence += sender.snapshot("im204-sender-clean")

    server_messages = list_messages(args.base, token, chat_id, 100)
    server_has_file = any(
        file_name in json.dumps(item.get("content") or {}, ensure_ascii=False)
        for item in server_messages
    )
    if server_has_file:
        raise RuntimeError("cancelled file reached the authoritative message list")

    evidence += receiver.open_private("smoke_alice", "im204-focus-receiver")
    time.sleep(3)
    if node_containing(receiver, file_name) is not None:
        raise RuntimeError("cancelled file appeared on the receiver")
    evidence += receiver.snapshot("im204-receiver-clean")

    fatal_markers: dict[str, list[str]] = {}
    for name, harness in (("sender", sender), ("receiver", receiver)):
        logcat = harness.adb_run("logcat", "-d").stdout
        log_path = run_dir / f"{name}-logcat.txt"
        log_path.write_text(logcat, encoding="utf-8", errors="replace")
        fatal_markers[name] = [
            line
            for line in logcat.splitlines()
            if "FATAL EXCEPTION" in line or "ANR in com.genericim.app" in line
        ]
    if any(fatal_markers.values()):
        raise RuntimeError(f"Fatal/ANR found: {fatal_markers}")

    result = {
        "case_id": "IM-204",
        "status": "PASS",
        "detail": (
            "99MB upload was cancelled from the sending bubble; no local ghost, "
            "receiver message, or authoritative server message remained"
        ),
        "file_name": file_name,
        "apk_sha256": args.apk_sha256,
        "devices": {"sender": args.sender, "receiver": args.receiver},
        "fatal_or_anr": 0,
        "evidence": evidence,
    }
    (run_dir / "im204-validation-result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (run_dir / "IM204_REAL_DEVICE_VALIDATION_REPORT.md").write_text(
        "# IM-204 双真机验证报告\n\n"
        "- 结果：PASS\n"
        f"- 文件：`{file_name}`（99 MB）\n"
        "- 发送端：发送中长按撤回后气泡消失\n"
        "- 接收端：未出现该文件\n"
        "- 服务端：最近 100 条权威消息中无该文件\n"
        "- Fatal/ANR：0\n"
        f"- APK SHA256：`{args.apk_sha256}`\n",
        encoding="utf-8",
    )
    print(f"[IM-204] PASS - {result['detail']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
