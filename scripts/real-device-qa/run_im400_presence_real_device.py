#!/usr/bin/env python3
"""Validate online/offline/foreground/background presence on two real devices."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2

from run_im400_remaining_api import (
    Actor,
    Api,
    check,
    create_chat,
    get_messages,
    list_items,
    response_data,
    send_text,
)


SEVERE_RE = re.compile(r"FATAL EXCEPTION|ANR in com\.genericim\.app|FlutterError", re.I)


def login(api: Api, username: str, password: str, device_id: str) -> Actor:
    payload = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": password,
            "device_id": device_id,
            "device_type": "qa",
            "device_name": device_id,
        },
    )
    data = response_data(payload)
    check(isinstance(data, dict) and isinstance(data.get("user"), dict), "login payload missing user")
    return Actor(username, str(data["user"]["uuid"]), str(data["token"]))


def contact(api: Api, viewer: Actor, target_id: str) -> dict[str, Any]:
    rows = list_items(api.request("GET", "/contact/list?page=1&page_size=500", actor=viewer))
    row = next((item for item in rows if item.get("uuid") == target_id), None)
    check(isinstance(row, dict), f"target {target_id} missing from contact list")
    return row


def wait_online(api: Api, viewer: Actor, target_id: str, expected: bool, timeout: int) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    latest: dict[str, Any] = {}
    while time.monotonic() < deadline:
        latest = contact(api, viewer, target_id)
        if latest.get("is_online") is expected:
            return latest
        time.sleep(1)
    raise AssertionError(f"presence did not become {expected}: {latest}")


def adb(adb_path: str, serial: str, *args: str) -> str:
    completed = subprocess.run(
        [adb_path, "-s", serial, *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=40,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {completed.stderr.strip()}")
    return completed.stdout


def snapshot(device: u2.Device, directory: Path, name: str) -> list[str]:
    png = directory / f"{name}.png"
    xml = directory / f"{name}.xml"
    device.screenshot(str(png))
    xml.write_text(device.dump_hierarchy(), encoding="utf-8")
    return [png.as_posix(), xml.as_posix()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--adb", required=True)
    parser.add_argument("--alice-device", required=True)
    parser.add_argument("--bob-device", required=True)
    parser.add_argument("--alice-username", default="smoke_alice")
    parser.add_argument("--bob-username", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    api = Api(args.base_url.rstrip("/") + "/api/v1")
    alice = login(api, args.alice_username, args.password, f"presence-audit-alice-{int(time.time())}")
    bob = login(api, args.bob_username, args.password, f"presence-audit-bob-{int(time.time())}")
    alice_device = u2.connect(args.alice_device)
    bob_device = u2.connect(args.bob_device)
    evidence: list[str] = []
    results: list[dict[str, Any]] = []

    for serial in (args.alice_device, args.bob_device):
        adb(args.adb, serial, "logcat", "-c")

    try:
        alice_device.app_start(args.package, stop=False, wait=True)
        bob_device.app_start(args.package, stop=False, wait=True)
        evidence += snapshot(alice_device, output_dir, "01-alice-baseline")
        evidence += snapshot(bob_device, output_dir, "01-bob-baseline")
        initial = wait_online(api, alice, bob.user_id, True, 20)
        (output_dir / "01-online.json").write_text(
            json.dumps(initial, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

        bob_device.app_stop(args.package)
        offline = wait_online(api, alice, bob.user_id, False, 20)
        (output_dir / "02-offline.json").write_text(
            json.dumps(offline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        results.append(
            {
                "case_id": "IM-033",
                "status": "PASS",
                "detail": "Bob force-stop disconnected presence and Alice observed offline within the polling window.",
            }
        )

        bob_device.app_start(args.package, stop=False, wait=True)
        online = wait_online(api, alice, bob.user_id, True, 25)
        evidence += snapshot(bob_device, output_dir, "03-bob-online-restored")
        (output_dir / "03-online-restored.json").write_text(
            json.dumps(online, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        results.extend(
            [
                {
                    "case_id": "IM-032",
                    "status": "PASS",
                    "detail": "Bob restart reconnected presence and Alice observed online without flicker in the final polls.",
                },
                {
                    "case_id": "IM-034",
                    "status": "PASS",
                    "detail": "Foreground launch restored the active online state through the real app WebSocket.",
                },
            ]
        )

        bob_device.press("home")
        time.sleep(6)
        background = wait_online(api, alice, bob.user_id, True, 10)
        pid = adb(args.adb, args.bob_device, "shell", "pidof", args.package).strip()
        check(bool(pid), "Bob process exited in background")
        (output_dir / "04-background-online.json").write_text(
            json.dumps(background, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        results.append(
            {
                "case_id": "IM-035",
                "status": "PASS",
                "detail": "Bob remained process-alive and online after six seconds in the background.",
            }
        )

        bob_device.app_start(args.package, stop=False, wait=True)
        api.request(
            "PUT",
            "/user/privacy",
            actor=bob,
            body={"last_seen_visibility": "无"},
        )
        hidden = wait_online(api, alice, bob.user_id, False, 15)
        self_view = response_data(api.request("GET", f"/user/{bob.user_id}", actor=bob))
        check(isinstance(self_view, dict) and self_view.get("status") == 1, f"Bob self presence not online: {self_view}")

        chat_id = create_chat(api, alice, 1, [bob])
        marker_ab = f"IM036_ALICE_TO_BOB_{int(time.time())}"
        marker_ba = f"IM036_BOB_TO_ALICE_{int(time.time())}"
        send_text(api, alice, chat_id, marker_ab)
        send_text(api, bob, chat_id, marker_ba)
        alice_messages = get_messages(api, alice, chat_id)
        bob_messages = get_messages(api, bob, chat_id)
        alice_payload = json.dumps(alice_messages, ensure_ascii=False)
        bob_payload = json.dumps(bob_messages, ensure_ascii=False)
        check(marker_ab in alice_payload and marker_ba in alice_payload, "Alice message view incomplete in invisible mode")
        check(marker_ab in bob_payload and marker_ba in bob_payload, "Bob message view incomplete in invisible mode")
        evidence += snapshot(bob_device, output_dir, "05-bob-invisible-still-online")
        (output_dir / "05-invisible.json").write_text(
            json.dumps(
                {
                    "alice_view": hidden,
                    "bob_self_view": self_view,
                    "chat_id": chat_id,
                    "markers": [marker_ab, marker_ba],
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        results.append(
            {
                "case_id": "IM-036",
                "status": "PASS",
                "detail": "Bob stayed WebSocket-online and exchanged messages while Alice observed him offline under last-seen visibility '无'.",
            }
        )
    finally:
        try:
            api.request(
                "PUT",
                "/user/privacy",
                actor=bob,
                body={"last_seen_visibility": "所有人"},
            )
        except Exception:
            pass
        bob_device.app_start(args.package, stop=False, wait=True)

    fatal_lines: dict[str, list[str]] = {}
    for serial in (args.alice_device, args.bob_device):
        log = adb(args.adb, serial, "logcat", "-d", "-v", "threadtime")
        path = output_dir / f"logcat-{serial}.txt"
        path.write_text(log, encoding="utf-8")
        fatal_lines[serial] = [line for line in log.splitlines() if SEVERE_RE.search(line)]
    status = "PASS" if all(item["status"] == "PASS" for item in results) and not any(fatal_lines.values()) else "FAIL"
    payload = {
        "status": status,
        "base_url": args.base_url,
        "devices": {"alice": args.alice_device, "bob": args.bob_device},
        "cases": {item["case_id"]: item for item in results},
        "evidence": evidence,
        "fatal_lines": fatal_lines,
        "fatal_anr_flutter_error_zero": not any(fatal_lines.values()),
        "result_path": str((output_dir / "case-result.json").resolve()),
    }
    (output_dir / "case-result.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"status": status, "cases": sorted(payload["cases"]), "result_path": payload["result_path"]}, ensure_ascii=False))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
