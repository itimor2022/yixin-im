#!/usr/bin/env python3
"""Simulate a seven-day offline device and validate message/presence recovery."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2

from run_im400_message_actions import MessageActionBatch
from run_im400_presence_real_device import SEVERE_RE, adb, login, snapshot, wait_online
from run_im400_remaining_api import Api, check, create_chat, get_messages, send_text


def mysql(repo: Path, sql: str) -> str:
    completed = subprocess.run(
        [
            "docker",
            "compose",
            "exec",
            "-T",
            "mysql",
            "mysql",
            "--silent",
            "--skip-column-names",
            "-ugenericim",
            "-pgenericim",
            "genericim",
            "-e",
            sql,
        ],
        cwd=repo,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"mysql failed: {completed.stderr.strip()}")
    return completed.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--viewer-device", required=True)
    parser.add_argument("--target-device", required=True)
    parser.add_argument("--viewer-username", default="smoke_alice")
    parser.add_argument("--target-username", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    api = Api(args.base_url.rstrip("/") + "/api/v1")
    viewer = login(api, args.viewer_username, args.password, f"im039-viewer-{int(time.time())}")
    target = login(api, args.target_username, args.password, f"im039-target-{int(time.time())}")
    target_device = u2.connect(args.target_device)
    batch = MessageActionBatch(repo, output_dir, args.target_device, args.package)
    evidence: list[str] = []
    checks: dict[str, Any] = {}
    fatal_lines: dict[str, list[str]] = {}
    error = ""

    for serial in (args.viewer_device, args.target_device):
        adb(args.adb, serial, "logcat", "-c")

    try:
        target_device.app_start(args.package, stop=False, wait=True)
        wait_online(api, viewer, target.user_id, True, 20)
        evidence += snapshot(target_device, output_dir, "01-target-online-before-offline")

        mobile_row = mysql(
            repo,
            "SELECT ud.id,ud.device_id FROM user_devices ud "
            "JOIN users u ON u.id=ud.user_id "
            f"WHERE u.username='{args.target_username}' AND ud.device_type='android' "
            "AND ud.device_id NOT LIKE '%:push:%' ORDER BY ud.last_active DESC LIMIT 1;",
        )
        parts = mobile_row.split("\t")
        check(len(parts) == 2 and parts[0].isdigit(), f"mobile device row missing: {mobile_row}")
        device_row_id, mobile_device_id = parts

        target_device.app_stop(args.package)
        wait_online(api, viewer, target.user_id, False, 20)
        mysql(
            repo,
            "UPDATE users SET last_seen=DATE_SUB(NOW(), INTERVAL 7 DAY) "
            f"WHERE username='{args.target_username}'; "
            "UPDATE user_devices SET last_active=DATE_SUB(NOW(), INTERVAL 7 DAY) "
            f"WHERE id={device_row_id};",
        )
        backdated = mysql(
            repo,
            "SELECT u.last_seen,ud.last_active FROM users u JOIN user_devices ud ON ud.user_id=u.id "
            f"WHERE u.username='{args.target_username}' AND ud.id={device_row_id};",
        )
        (output_dir / "02-backdated-server-state.txt").write_text(
            backdated + "\n", encoding="utf-8"
        )

        chat_id = create_chat(api, viewer, 1, [target])
        markers = [f"IM039_OFFLINE_{index}_{int(time.time())}" for index in range(1, 4)]
        for marker in markers:
            send_text(api, viewer, chat_id, marker)
            time.sleep(0.3)

        target_device.app_start(args.package, stop=False, wait=True)
        wait_online(api, viewer, target.user_id, True, 25)
        evidence += batch.open_chat("Smoke Alice")
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if all(batch.visible_outside_edit(marker) for marker in markers):
                break
            time.sleep(1)
        evidence += batch.snapshot("03-long-offline-messages-restored")
        check(all(batch.visible_outside_edit(marker) for marker in markers), "offline messages missing in target UI")

        messages = get_messages(api, target, chat_id)
        matching = [
            item
            for item in messages
            if any(marker in json.dumps(item, ensure_ascii=False) for marker in markers)
        ]
        seq_by_marker: list[int] = []
        for marker in markers:
            item = next(
                candidate
                for candidate in matching
                if marker in json.dumps(candidate, ensure_ascii=False)
            )
            seq_by_marker.append(int(item.get("seq", 0)))
        check(seq_by_marker == sorted(seq_by_marker), f"offline message sequence invalid: {seq_by_marker}")

        restored = mysql(
            repo,
            "SELECT u.last_seen,ud.last_active FROM users u JOIN user_devices ud ON ud.user_id=u.id "
            f"WHERE u.username='{args.target_username}' AND ud.id={device_row_id};",
        )
        (output_dir / "04-restored-server-state.txt").write_text(
            restored + "\n", encoding="utf-8"
        )
        check(restored != backdated, "server activity timestamps did not recover after reconnect")
        checks = {
            "mobile_device_id": mobile_device_id,
            "backdated_state": backdated,
            "restored_state": restored,
            "offline_markers": markers,
            "message_sequences": seq_by_marker,
            "presence_restored": True,
        }
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
        evidence += snapshot(target_device, output_dir, "test-failed")
    finally:
        target_device.app_start(args.package, stop=False, wait=True)

    for serial in (args.viewer_device, args.target_device):
        log = adb(args.adb, serial, "logcat", "-d", "-v", "threadtime")
        (output_dir / f"logcat-{serial}.txt").write_text(log, encoding="utf-8")
        fatal_lines[serial] = [line for line in log.splitlines() if SEVERE_RE.search(line)]

    status = "PASS" if not error and not any(fatal_lines.values()) else "FAIL"
    payload = {
        "status": status,
        "case_id": "IM-039",
        "cases": {
            "IM-039": {
                "status": status,
                "detail": error
                or "a real Android device with server activity backdated seven days restored ordered offline messages and online presence after reconnect",
            }
        },
        "checks": checks,
        "evidence": evidence,
        "fatal_lines": fatal_lines,
        "fatal_anr_flutter_error_zero": not any(fatal_lines.values()),
        "result_path": str((output_dir / "case-result.json").resolve()),
    }
    (output_dir / "case-result.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps(
            {"status": status, "case_id": "IM-039", "result_path": payload["result_path"]},
            ensure_ascii=False,
        )
    )
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
