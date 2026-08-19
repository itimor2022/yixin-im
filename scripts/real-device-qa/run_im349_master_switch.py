#!/usr/bin/env python3
"""Validate the in-app notification master switch on one authenticated device."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

import uiautomator2 as u2

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im345_im357_single_device import app_notification_keys, run_adb  # noqa: E402
from run_p1_fix_validation import find_private_chat, request_json  # noqa: E402


MASTER_LABEL = "允许应用通知"


def open_notification_settings(device: u2.Device, package: str) -> None:
    device.app_start(package, stop=True)
    time.sleep(7)
    if device(description="登录您的账号").exists:
        raise RuntimeError("device account is unauthenticated")
    if device(descriptionContains=MASTER_LABEL).exists:
        return
    settings = device(description="设置")
    if not settings.exists(timeout=3):
        raise RuntimeError("settings tab is unavailable")
    settings.click()
    tile = device(description="通知和声音")
    if not tile.exists(timeout=4):
        raise RuntimeError("notification settings entry is unavailable")
    tile.click()
    if not device(descriptionContains=MASTER_LABEL).exists(timeout=5):
        raise RuntimeError("notification master switch is unavailable")


def master_switch(device: u2.Device):
    node = device(className="android.widget.Switch", descriptionContains=MASTER_LABEL)
    if not node.exists(timeout=3):
        raise RuntimeError("notification master switch is not visible")
    return node


def set_master_enabled(device: u2.Device, enabled: bool) -> None:
    for _ in range(3):
        node = master_switch(device)
        if bool(node.info.get("checked")) == enabled:
            return
        bounds = node.info["bounds"]
        device.click(bounds["right"] - 200, (bounds["top"] + bounds["bottom"]) // 2)
        time.sleep(2)
    if bool(master_switch(device).info.get("checked")) != enabled:
        raise RuntimeError(
            f"notification master switch did not turn {'on' if enabled else 'off'}"
        )


def category_switch_snapshot(device: u2.Device) -> list[bool]:
    device.swipe(600, 2250, 600, 900, 0.5)
    time.sleep(1)
    root = ET.fromstring(device.dump_hierarchy())
    values: list[bool] = []
    for node in root.iter("node"):
        if node.attrib.get("class") != "android.widget.Switch":
            continue
        description = node.attrib.get("content-desc") or ""
        if MASTER_LABEL in description:
            continue
        values.append(node.attrib.get("checked") == "true")
    device.swipe(600, 900, 600, 2250, 0.5)
    time.sleep(1)
    return values


def save_snapshot(
    device: u2.Device,
    adb: str,
    serial: str,
    output_dir: Path,
    name: str,
) -> None:
    (output_dir / f"{name}.xml").write_text(
        device.dump_hierarchy(), encoding="utf-8"
    )


def send_text(base: str, token: str, chat_id: str, marker: str) -> str:
    response = request_json(
        base,
        "/message/send",
        token,
        {
            "chat_id": chat_id,
            "type": 1,
            "content": {"text": marker},
            "msg_id": str(uuid.uuid4()),
        },
    )
    if int(response.get("code", -1)) != 0:
        raise RuntimeError(f"message send failed: {response.get('message')}")
    return str((response.get("data") or {}).get("msg_id") or "")


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
    apk = Path(args.apk)
    if not apk.is_absolute():
        apk = repo / apk
    output_root = Path(args.output_dir)
    if not output_root.is_absolute():
        output_root = repo / output_root
    output_dir = output_root / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)

    device = u2.connect(args.serial)
    token = ""
    chat_id = ""
    sent_ids: list[str] = []
    restored = False
    try:
        login = request_json(
            args.base,
            "/auth/login",
            data={
                "username": args.username,
                "password": args.password,
                "device_id": f"im349-api-{uuid.uuid4().hex[:8]}",
                "device_type": "android",
                "device_name": "IM349 Master Switch QA",
            },
        )
        token = str((login.get("data") or {}).get("token") or "")
        if int(login.get("code", -1)) != 0 or not token:
            raise RuntimeError("API sender login failed")
        chat_id = find_private_chat(args.base, token, args.target_username)

        open_notification_settings(device, args.package)
        save_snapshot(
            device, args.adb, args.serial, output_dir, "01-settings-before"
        )
        switch = master_switch(device)
        if not bool(switch.info.get("checked")):
            set_master_enabled(device, True)
        categories_before = category_switch_snapshot(device)

        set_master_enabled(device, False)
        save_snapshot(device, args.adb, args.serial, output_dir, "02-master-off")

        device.press("home")
        time.sleep(2)
        baseline = app_notification_keys(args.adb, args.serial, args.package)
        off_marker = f"IM349_OFF_{datetime.now().strftime('%H%M%S')}"
        sent_ids.append(send_text(args.base, token, chat_id, off_marker))
        time.sleep(10)
        after_off = app_notification_keys(args.adb, args.serial, args.package)
        off_new = sorted(after_off - baseline)
        if off_new:
            raise RuntimeError(f"notification appeared while master was off: {off_new}")

        open_notification_settings(device, args.package)
        set_master_enabled(device, True)
        categories_after = category_switch_snapshot(device)
        if categories_after != categories_before:
            raise RuntimeError(
                f"category choices changed: before={categories_before} after={categories_after}"
            )
        save_snapshot(
            device, args.adb, args.serial, output_dir, "03-master-restored"
        )
        restored = True

        device.press("home")
        time.sleep(2)
        baseline_on = app_notification_keys(args.adb, args.serial, args.package)
        on_marker = f"IM349_ON_{datetime.now().strftime('%H%M%S')}"
        sent_ids.append(send_text(args.base, token, chat_id, on_marker))
        time.sleep(10)
        after_on = app_notification_keys(args.adb, args.serial, args.package)
        on_new = sorted(after_on - baseline_on)
        if not on_new:
            raise RuntimeError("notification did not recover after master was enabled")

        summary = {
            "case_id": "IM-349",
            "status": "PASS",
            "device_id": args.serial,
            "master_off_new_notification_count": len(off_new),
            "master_on_new_notification_count": len(on_new),
            "category_switches_before": categories_before,
            "category_switches_after": categories_after,
            "category_choices_preserved": True,
            "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest().upper(),
            "output_dir": str(output_dir),
        }
        (output_dir / "summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    finally:
        for msg_id in sent_ids:
            if token and chat_id and msg_id:
                try:
                    request_json(
                        args.base,
                        "/message/revoke",
                        token,
                        {"chat_id": chat_id, "msg_id": msg_id},
                    )
                except Exception:
                    pass
        if not restored:
            try:
                open_notification_settings(device, args.package)
                current = bool(master_switch(device).info.get("checked"))
                if not current:
                    set_master_enabled(device, True)
            except Exception:
                pass
        device.app_start(args.package, stop=True)


if __name__ == "__main__":
    raise SystemExit(main())
