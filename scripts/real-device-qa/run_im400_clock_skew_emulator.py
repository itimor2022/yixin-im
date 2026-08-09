#!/usr/bin/env python3
"""Validate server-owned message ordering while the emulator clock is wrong."""

from __future__ import annotations

import argparse
import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import uiautomator2 as u2

from run_im400_account_switch_emulator import (
    Credential,
    create_credential,
    login_existing,
    logout,
    main_ui,
    open_messages,
    run_adb,
    snapshot,
)
from run_im400_message_actions import MessageActionBatch
from run_im400_remaining_api import Api, check, create_chat, get_messages, send_text


def contains_token(item: dict[str, Any], token: str) -> bool:
    return token in json.dumps(item, ensure_ascii=False, sort_keys=True)


def parse_server_time(value: Any) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def message_time(item: dict[str, Any]) -> datetime | None:
    for key in ("created_at", "createdAt", "send_time", "sent_at"):
        if key in item:
            return parse_server_time(item[key])
    return None


def wait_for_message(
    api: Api,
    credential: Credential,
    chat_id: str,
    token: str,
    timeout: int = 20,
) -> dict[str, Any] | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        match = next(
            (
                item
                for item in get_messages(api, credential.actor, chat_id)
                if contains_token(item, token)
            ),
            None,
        )
        if match is not None:
            return match
        time.sleep(1)
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--restore-username", default="demo")
    parser.add_argument("--restore-password", default="demo123")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    api = Api(args.base_url.rstrip("/") + "/api/v1")
    run_id = f"{int(time.time())}-{uuid.uuid4().hex[:6]}"
    account = create_credential(api, "Clock", run_id)
    peer = create_credential(api, "ClockPeer", run_id)
    chat_id = create_chat(api, account.actor, 1, [peer.actor])
    seed = f"IM040_SEED_{run_id}"
    outgoing = f"IM040_OUT_{run_id}"
    incoming = f"IM040_IN_{run_id}"
    send_text(api, peer.actor, chat_id, seed)

    evidence: list[str] = []
    error = ""
    checks: dict[str, Any] = {}
    fatal_lines: list[str] = []

    original_auto_time = run_adb(
        args.adb, args.serial, "shell", "settings", "get", "global", "auto_time"
    )
    run_adb(args.adb, args.serial, "root")
    run_adb(args.adb, args.serial, "wait-for-device")
    run_adb(args.adb, args.serial, "reverse", "tcp:8080", "tcp:8080")
    run_adb(args.adb, args.serial, "logcat", "-c")
    run_adb(args.adb, args.serial, "shell", "pm", "clear", args.package)
    run_adb(
        args.adb,
        args.serial,
        "shell",
        "pm",
        "grant",
        args.package,
        "android.permission.POST_NOTIFICATIONS",
    )
    device = u2.connect(args.serial)
    batch = MessageActionBatch(Path.cwd(), output_dir, args.serial, args.package)

    try:
        run_adb(
            args.adb,
            args.serial,
            "shell",
            "settings",
            "put",
            "global",
            "auto_time",
            "0",
        )
        run_adb(
            args.adb,
            args.serial,
            "shell",
            "date",
            "-s",
            "2035-07-01T12:00:00",
        )
        skewed_date = run_adb(args.adb, args.serial, "shell", "date")
        check("2035" in skewed_date, f"emulator clock was not skewed: {skewed_date}")

        login_existing(
            args.adb,
            args.serial,
            account,
            args.package,
            output_dir / "login-clock-account",
        )
        open_messages(device, args.package)
        evidence += batch.open_chat(peer.nickname)
        sent, sent_evidence = batch.send_text(outgoing, "im040-outgoing")
        evidence += sent_evidence
        check(sent, "outgoing message was not visible after send")

        outgoing_item = wait_for_message(api, account, chat_id, outgoing)
        check(outgoing_item is not None, "outgoing message did not reach local Docker")
        send_text(api, peer.actor, chat_id, incoming)

        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and not batch.visible_outside_edit(incoming):
            time.sleep(1)
        evidence += batch.snapshot("im040-bidirectional-final")
        check(batch.visible_outside_edit(incoming), "incoming message was not visible")

        incoming_item = wait_for_message(api, account, chat_id, incoming)
        seed_item = wait_for_message(api, account, chat_id, seed)
        check(incoming_item is not None and seed_item is not None, "message list was incomplete")

        items = [seed_item, outgoing_item, incoming_item]
        times = [message_time(item) for item in items if item is not None]
        check(all(value is not None for value in times), "server timestamps were missing")
        host_now = datetime.now(timezone.utc)
        max_server_delta = max(abs((value - host_now).total_seconds()) for value in times if value)
        seqs = [int(item.get("seq", 0)) for item in items if item is not None]
        check(max_server_delta < 300, f"server timestamps followed bad device clock: {times}")
        check(seqs == sorted(seqs) and len(set(seqs)) == 3, f"message sequence invalid: {seqs}")

        checks = {
            "device_time": skewed_date,
            "server_times_utc": [value.isoformat() for value in times if value],
            "max_server_time_delta_seconds": max_server_delta,
            "message_sequences": seqs,
            "login_under_clock_skew": True,
            "outgoing_visible": sent,
            "incoming_visible": True,
        }
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
        evidence += snapshot(device, output_dir, "test-failed")
    finally:
        run_adb(
            args.adb,
            args.serial,
            "shell",
            "settings",
            "put",
            "global",
            "auto_time",
            original_auto_time if original_auto_time in ("0", "1") else "1",
        )
        run_adb(
            args.adb,
            args.serial,
            "shell",
            "am",
            "broadcast",
            "-a",
            "android.intent.action.TIME_SET",
        )
        time.sleep(3)
        restored_date = run_adb(args.adb, args.serial, "shell", "date")
        checks["restored_device_time"] = restored_date
        try:
            device = u2.connect(args.serial)
            if main_ui(device):
                logout(device, args.package)
            restore = Credential(
                args.restore_username,
                args.restore_password,
                account.actor,
                args.restore_username,
            )
            login_existing(
                args.adb,
                args.serial,
                restore,
                args.package,
                output_dir / "restore-demo",
            )
            evidence += snapshot(device, output_dir, "demo-restored")
        except Exception as exc:
            (output_dir / "restore-error.txt").write_text(str(exc), encoding="utf-8")

    log = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "threadtime", timeout=60)
    (output_dir / "logcat.txt").write_text(log, encoding="utf-8")
    fatal_lines = [
        line
        for line in log.splitlines()
        if "FATAL EXCEPTION" in line
        or "ANR in com.genericim.app" in line
        or "FlutterError" in line
    ]
    status = "PASS" if not error and not fatal_lines else "FAIL"
    payload = {
        "status": status,
        "case_id": "IM-040",
        "cases": {
            "IM-040": {
                "status": status,
                "detail": error
                or "login and bidirectional messaging used server timestamps and monotonic sequences while the emulator clock was set to 2035",
            }
        },
        "checks": checks,
        "evidence": evidence,
        "fatal_lines": fatal_lines,
        "fatal_anr_flutter_error_zero": not fatal_lines,
        "result_path": str((output_dir / "case-result.json").resolve()),
    }
    (output_dir / "case-result.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps(
            {"status": status, "case_id": "IM-040", "result_path": payload["result_path"]},
            ensure_ascii=False,
        )
    )
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
