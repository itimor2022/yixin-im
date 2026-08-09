#!/usr/bin/env python3
"""Verify IM-347 group-announcement notifications on a real Android device."""

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

from run_im400_remaining_api import (  # noqa: E402
    Actor,
    Api,
    create_chat,
    list_items,
    response_data,
)


def run_adb(adb: str, serial: str, *args: str, check: bool = True) -> str:
    completed = subprocess.run(
        [adb, "-s", serial, *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        timeout=40,
    )
    if check and completed.returncode != 0:
        raise RuntimeError(
            f"adb {' '.join(args)} failed ({completed.returncode}): {completed.stderr}"
        )
    return completed.stdout


def snapshot(adb: str, serial: str, output_dir: Path, name: str) -> str:
    remote_xml = f"/sdcard/{name}.xml"
    remote_png = f"/sdcard/{name}.png"
    run_adb(adb, serial, "shell", "uiautomator", "dump", remote_xml)
    run_adb(adb, serial, "shell", "screencap", "-p", remote_png)
    run_adb(adb, serial, "pull", remote_xml, str(output_dir / f"{name}.xml"))
    run_adb(adb, serial, "pull", remote_png, str(output_dir / f"{name}.png"))
    return (output_dir / f"{name}.xml").read_text(encoding="utf-8")


def tap_description(
    adb: str, serial: str, package: str, xml: str, description: str
) -> bool:
    root = ET.fromstring(xml)
    for node in root.iter("node"):
        if node.attrib.get("package") != package:
            continue
        if node.attrib.get("content-desc") != description:
            continue
        bounds = node.attrib.get("bounds", "")
        values = [int(value) for value in re.findall(r"\d+", bounds)]
        if len(values) != 4:
            continue
        run_adb(
            adb,
            serial,
            "shell",
            "input",
            "tap",
            str((values[0] + values[2]) // 2),
            str((values[1] + values[3]) // 2),
        )
        return True
    return False


def app_notification_keys(adb: str, serial: str, package: str) -> set[str]:
    output = run_adb(adb, serial, "shell", "cmd", "notification", "list")
    return {line.strip() for line in output.splitlines() if package in line}


def notification_blocks(dump: str) -> list[str]:
    starts = [match.start() for match in re.finditer(r"NotificationRecord\(", dump)]
    return [
        dump[start : starts[index + 1] if index + 1 < len(starts) else len(dump)]
        for index, start in enumerate(starts)
    ]


def find_new_notification_block(
    dump: str, package: str, new_keys: set[str]
) -> tuple[str, str]:
    for block in notification_blocks(dump):
        if f"pkg={package}" not in block:
            continue
        key = next((item for item in new_keys if item in block), "")
        if key:
            return key, block
    return "", ""


def wait_for_notification(
    adb: str,
    serial: str,
    package: str,
    baseline: set[str],
    timeout_seconds: int = 30,
) -> tuple[set[str], str, str]:
    deadline = time.monotonic() + timeout_seconds
    latest_dump = ""
    while time.monotonic() < deadline:
        current = app_notification_keys(adb, serial, package)
        new_keys = current - baseline
        latest_dump = run_adb(
            adb, serial, "shell", "dumpsys", "notification", "--noredact"
        )
        key, block = find_new_notification_block(latest_dump, package, new_keys)
        if key and block:
            return new_keys, latest_dump, block
        time.sleep(2)
    return app_notification_keys(adb, serial, package) - baseline, latest_dump, ""


def login(api: Api, username: str, password: str, label: str) -> Actor:
    payload = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": password,
            "device_id": f"im347-api-{label}-{uuid.uuid4().hex[:10]}",
            "device_type": "qa",
            "device_name": f"IM347 API {label}",
        },
    )
    data = response_data(payload)
    if not isinstance(data, dict) or not data.get("token"):
        raise RuntimeError(f"{label} login response has no token")
    token = str(data["token"])
    user = data.get("user") if isinstance(data.get("user"), dict) else {}
    user_id = str(user.get("uuid") or "")
    actor = Actor(label, user_id, token)
    if not actor.user_id:
        me = response_data(api.request("GET", "/user/me", actor=actor))
        if not isinstance(me, dict) or not me.get("uuid"):
            raise RuntimeError(f"{label} profile response has no uuid")
        actor.user_id = str(me["uuid"])
    return actor


def cleanup_owned_test_groups(api: Api, owner: Actor) -> list[str]:
    removed: list[str] = []
    items = list_items(
        api.request("GET", "/chat/list?page=1&page_size=100", actor=owner)
    )
    for item in items:
        name = str(item.get("name") or item.get("chat_name") or "")
        chat_id = str(item.get("chat_id") or item.get("uuid") or "")
        if not chat_id or not name.startswith("IM347_"):
            continue
        try:
            api.request("DELETE", f"/chat/{chat_id}", actor=owner)
            removed.append(chat_id)
        except Exception:
            continue
    return removed


def publish(api: Api, owner: Actor, chat_id: str, content: str) -> int:
    data = response_data(
        api.request(
            "POST",
            f"/chat/{chat_id}/announcements",
            actor=owner,
            body={"content": content},
        )
    )
    if not isinstance(data, dict) or int(data.get("id", 0)) <= 0:
        raise RuntimeError(f"announcement create response is invalid: {data}")
    return int(data["id"])


def channel_id(block: str) -> str:
    for pattern in (
        r"\bchannel=([^\s]+)",
        r"mId='([^']+)'",
        r"mId=([^,}\s]+)",
    ):
        match = re.search(pattern, block)
        if match:
            return match.group(1).strip("'\"")
    return ""


def tap_announcement_notification(adb: str, serial: str, output_dir: Path) -> str:
    run_adb(adb, serial, "shell", "cmd", "statusbar", "expand-notifications")
    time.sleep(2)
    xml = snapshot(adb, serial, output_dir, "04-notification-shade")
    root = ET.fromstring(xml)
    candidates: list[ET.Element] = []
    for node in root.iter("node"):
        description = node.attrib.get("content-desc", "")
        text = node.attrib.get("text", "")
        if "群公告" in description or "群公告" in text:
            candidates.append(node)
    for node in candidates:
        bounds = node.attrib.get("bounds", "")
        values = [int(value) for value in re.findall(r"\d+", bounds)]
        if len(values) != 4:
            continue
        x = (values[0] + values[2]) // 2
        y = (values[1] + values[3]) // 2
        # Some EMUI builds collapse the shade while uiautomator/screencap is
        # collecting evidence. Re-expand immediately before the coordinate tap.
        run_adb(adb, serial, "shell", "cmd", "statusbar", "expand-notifications")
        time.sleep(1)
        run_adb(adb, serial, "shell", "input", "tap", str(x), str(y))
        time.sleep(6)
        return snapshot(adb, serial, output_dir, "05-after-notification-click")
    run_adb(adb, serial, "shell", "cmd", "statusbar", "collapse")
    return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--base", default="https://api.example.com/api/v1")
    parser.add_argument("--package", default="com.genericim.app")
    parser.add_argument("--owner", default="smoke_alice")
    parser.add_argument("--member", default="smoke_bob")
    parser.add_argument("--password", default="Smoke123")
    args = parser.parse_args()

    output_root = Path(args.output_dir).resolve()
    output_dir = output_root / datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, Any] = {
        "case_id": "IM-347",
        "status": "FAIL",
        "base": args.base,
        "serial": args.serial,
        "output_dir": str(output_dir),
        "checks": {},
    }

    api: Api | None = None
    owner: Actor | None = None
    chat_id = ""
    try:
        api = Api(args.base)
        owner = login(api, args.owner, args.password, "owner")
        member = login(api, args.member, args.password, "member")
        result["precleaned_test_groups"] = cleanup_owned_test_groups(api, owner)
        run_id = datetime.now().strftime("%H%M%S")
        group_name = f"IM347_{run_id}"
        chat_id = create_chat(api, owner, 2, [member], group_name)
        result.update({"chat_id": chat_id, "group_name": group_name})

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
        time.sleep(4)
        member_xml = snapshot(
            args.adb, args.serial, output_dir, "00-member-launched"
        )
        # API logins can enqueue more than one new-device alert on an already
        # authenticated receiver. Drain the bounded queue before asserting the
        # main screen so the notification scenario is not mistaken for logout.
        for alert_index in range(10):
            dismissed = False
            for dismiss_label in ("我知道了", "知道了", "关闭"):
                if tap_description(
                    args.adb, args.serial, args.package, member_xml, dismiss_label
                ):
                    dismissed = True
                    time.sleep(1)
                    member_xml = snapshot(
                        args.adb,
                        args.serial,
                        output_dir,
                        f"00-member-dismiss-{alert_index + 1}",
                    )
                    break
            if not dismissed:
                break
        member_xml = snapshot(
            args.adb, args.serial, output_dir, "01-member-foreground"
        )
        if "登录您的账号" in member_xml:
            raise RuntimeError("receiver device is logged out")
        if not any(
            marker in member_xml
            for marker in (
                "消息",
                "smoke_alice",
                "Smoke Alice",
                "在线",
                "输入消息",
                "语音通话",
                "设置",
            )
        ):
            raise RuntimeError("receiver device did not reach an authenticated main screen")
        run_adb(args.adb, args.serial, "logcat", "-c")
        run_adb(args.adb, args.serial, "shell", "input", "keyevent", "KEYCODE_HOME")
        time.sleep(2)

        baseline = app_notification_keys(args.adb, args.serial, args.package)
        first_content = f"IM347_BACKGROUND_{run_id}"
        first_id = publish(api, owner, chat_id, first_content)
        first_keys, first_dump, first_block = wait_for_notification(
            args.adb, args.serial, args.package, baseline
        )
        (output_dir / "02-background-notification.txt").write_text(
            first_dump, encoding="utf-8"
        )
        first_channel = channel_id(first_block)
        result["background"] = {
            "announcement_id": first_id,
            "content": first_content,
            "new_notification_keys": sorted(first_keys),
            "delivered": bool(first_block),
            "channel_id": first_channel,
            "announcement_channel": first_channel == "genericim_announcements_v1",
        }

        clicked_xml = ""
        if first_block:
            clicked_xml = tap_announcement_notification(
                args.adb, args.serial, output_dir
            )
        click_routed = bool(
            clicked_xml
            and (
                first_content in clicked_xml
                or group_name in clicked_xml
                or "群公告" in clicked_xml
            )
        )
        result["background"]["click_routed"] = click_routed

        run_adb(
            args.adb, args.serial, "shell", "am", "force-stop", args.package
        )
        time.sleep(2)
        killed_baseline = app_notification_keys(args.adb, args.serial, args.package)
        killed_content = f"IM347_FORCE_STOP_{run_id}"
        killed_id = publish(api, owner, chat_id, killed_content)
        killed_keys, killed_dump, killed_block = wait_for_notification(
            args.adb, args.serial, args.package, killed_baseline
        )
        (output_dir / "06-force-stop-notification.txt").write_text(
            killed_dump, encoding="utf-8"
        )
        killed_channel = channel_id(killed_block)
        result["force_stop"] = {
            "announcement_id": killed_id,
            "content": killed_content,
            "new_notification_keys": sorted(killed_keys),
            "delivered": bool(killed_block),
            "channel_id": killed_channel,
            "announcement_channel": killed_channel == "genericim_announcements_v1",
        }

        logcat = run_adb(args.adb, args.serial, "logcat", "-d", "-v", "time")
        (output_dir / "07-logcat.txt").write_text(logcat, encoding="utf-8")
        fatal_pattern = re.compile(
            r"FATAL EXCEPTION|ANR in com\.genericim\.app|FlutterError|E/flutter"
        )
        fatal_lines = [line for line in logcat.splitlines() if fatal_pattern.search(line)]
        result["fatal_lines"] = fatal_lines
        result["checks"] = {
            "background_delivered": bool(first_block),
            "background_announcement_channel": first_channel
            == "genericim_announcements_v1",
            "notification_click_routed": click_routed,
            "force_stop_delivered": bool(killed_block),
            "force_stop_announcement_channel": killed_channel
            == "genericim_announcements_v1",
            "fatal_anr_flutter_error_zero": not fatal_lines,
        }
        # Background delivery, classification and click routing are the strict
        # IM-347 requirements. Force-stop delivery is reported separately because
        # Android vendors may suppress pushes after an explicit force-stop.
        required = (
            result["checks"]["background_delivered"]
            and result["checks"]["background_announcement_channel"]
            and result["checks"]["notification_click_routed"]
            and result["checks"]["fatal_anr_flutter_error_zero"]
        )
        result["status"] = "PASS" if required else "FAIL"
    except Exception as error:  # noqa: BLE001
        result["error_type"] = type(error).__name__
        result["error"] = str(error)
    finally:
        if api is not None and owner is not None and chat_id:
            try:
                api.request("DELETE", f"/chat/{chat_id}", actor=owner)
                result["test_group_cleaned"] = True
            except Exception as cleanup_error:  # noqa: BLE001
                result["test_group_cleaned"] = False
                result["cleanup_error"] = str(cleanup_error)
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
        time.sleep(3)
        result_path = output_dir / "case-result.json"
        result_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
