#!/usr/bin/env python3
"""Exercise local-Docker group state changes on two authenticated devices."""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any

import uiautomator2 as u2


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_im400_remaining_api import (  # noqa: E402
    Actor,
    Api,
    create_chat,
    list_items,
    response_data,
    send_text,
)


def login(api: Api, username: str, password: str, label: str) -> Actor:
    payload = api.request(
        "POST",
        "/auth/login",
        body={
            "username": username,
            "password": password,
            "device_id": f"local-group-api-{label}-{uuid.uuid4().hex[:8]}",
            "device_type": "qa",
            "device_name": f"Local Group QA {label}",
        },
    )
    data = response_data(payload)
    if not isinstance(data, dict) or not data.get("token"):
        raise RuntimeError(f"{label} login failed")
    user = data.get("user") if isinstance(data.get("user"), dict) else {}
    actor = Actor(label, str(user.get("uuid") or ""), str(data["token"]))
    if not actor.user_id:
        profile = response_data(api.request("GET", "/user/me", actor=actor))
        if not isinstance(profile, dict) or not profile.get("uuid"):
            raise RuntimeError(f"{label} profile has no uuid")
        actor.user_id = str(profile["uuid"])
    return actor


def cleanup_owned_test_groups(api: Api, owner: Actor) -> list[str]:
    removed: list[str] = []
    items = list_items(
        api.request("GET", "/chat/list?page=1&page_size=100", actor=owner)
    )
    prefixes = ("IM347_", "LOCAL_GROUP_", "LOCAL_RENAMED_")
    for item in items:
        name = str(item.get("name") or item.get("chat_name") or "")
        chat_id = str(item.get("chat_id") or item.get("uuid") or "")
        if not chat_id or not name.startswith(prefixes):
            continue
        try:
            api.request("DELETE", f"/chat/{chat_id}", actor=owner)
            removed.append(chat_id)
        except Exception:
            # Ignore a stale membership or an already terminal test group.
            continue
    return removed


def snapshot(device: u2.Device, output_dir: Path, name: str) -> tuple[str, list[str]]:
    xml = device.dump_hierarchy()
    png = output_dir / f"{name}.png"
    xml_path = output_dir / f"{name}.xml"
    device.screenshot(str(png))
    xml_path.write_text(xml, encoding="utf-8")
    return html.unescape(xml), [str(png), str(xml_path)]


def start_main_activity(adb: str, serial: str, package: str) -> None:
    subprocess.run(
        [adb, "-s", serial, "shell", "am", "force-stop", package],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
        timeout=30,
    )
    time.sleep(1)
    subprocess.run(
        [adb, "-s", serial, "shell", "am", "start", "-W", "-n", f"{package}/.MainActivity"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
        timeout=30,
    )


def reach_message_list(
    device: u2.Device, adb: str, serial: str, package: str
) -> None:
    start_main_activity(adb, serial, package)
    time.sleep(3)
    for _ in range(12):
        current = device.app_current()
        if current.get("package") != package:
            start_main_activity(adb, serial, package)
            time.sleep(3)
        if device(description="登录您的账号").exists:
            raise RuntimeError("device is logged out")
        root = ET.fromstring(device.dump_hierarchy())
        messages_bounds: list[int] | None = None
        for node in root.iter("node"):
            if node.attrib.get("package") != package:
                continue
            description = html.unescape(node.attrib.get("content-desc", ""))
            if not description or description.splitlines()[-1].strip() != "消息":
                continue
            values = [int(value) for value in re.findall(r"\d+", node.attrib.get("bounds", ""))]
            if len(values) == 4 and values[1] >= 2200:
                messages_bounds = values
                break
        if messages_bounds:
            device.click(
                (messages_bounds[0] + messages_bounds[2]) // 2,
                (messages_bounds[1] + messages_bounds[3]) // 2,
            )
            time.sleep(2)
            return
        device.press("back")
        time.sleep(1)
    raise RuntimeError("unable to reach the authenticated message list")


def open_group(
    device: u2.Device,
    adb: str,
    serial: str,
    package: str,
    group_name: str,
    timeout: int = 20,
) -> None:
    reach_message_list(device, adb, serial, package)
    row = device(descriptionContains=group_name)
    if not row.wait(timeout=timeout):
        raise RuntimeError(f"group row did not appear: {group_name}")
    row.click()
    time.sleep(4)
    if not device(descriptionContains=group_name).exists(timeout=4):
        raise RuntimeError(f"group chat header did not appear: {group_name}")


def wait_xml_contains(device: u2.Device, markers: list[str], timeout: int = 15) -> str:
    deadline = time.monotonic() + timeout
    latest = ""
    while time.monotonic() < deadline:
        latest = html.unescape(device.dump_hierarchy())
        if all(marker in latest for marker in markers):
            return latest
        time.sleep(1)
    return latest


def app_fatal_lines(adb: str, serial: str, package: str) -> list[str]:
    completed = subprocess.run(
        [adb, "-s", serial, "logcat", "-d", "-v", "time"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        timeout=30,
    )
    pattern = re.compile(
        rf"FATAL EXCEPTION|ANR in {re.escape(package)}|FlutterError|E/flutter"
    )
    return [line for line in completed.stdout.splitlines() if pattern.search(line)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device-a", required=True)
    parser.add_argument("--device-b", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--base", default="http://127.0.0.1:8080/api/v1")
    parser.add_argument("--package", default="com.genericim.ma100")
    parser.add_argument("--password", default="Smoke123")
    args = parser.parse_args()

    run_dir = Path(args.output_dir).resolve() / datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, Any] = {
        "case_ids": [
            "IM-259",
            "IM-260",
            "IM-261",
            "IM-266",
            "IM-270",
            "IM-271",
            "IM-280",
            "IM-285",
            "IM-286",
        ],
        "status": "FAIL",
        "base": args.base,
        "devices": [args.device_a, args.device_b],
        "checks": {},
        "evidence": [],
    }
    api = Api(args.base)
    device_a = u2.connect(args.device_a)
    device_b = u2.connect(args.device_b)

    for serial in (args.device_a, args.device_b):
        subprocess.run([args.adb, "-s", serial, "logcat", "-c"], check=False)

    try:
        alice = login(api, "smoke_alice", args.password, "alice")
        bob = login(api, "smoke_bob", args.password, "bob")
        result["actors"] = [asdict(alice) | {"token": "<redacted>"}, asdict(bob) | {"token": "<redacted>"}]
        result["cleaned_test_group_ids"] = cleanup_owned_test_groups(api, alice)
        stamp = datetime.now().strftime("%H%M%S")
        initial_name = f"LOCAL_GROUP_{stamp}"
        group_id = create_chat(api, alice, 2, [bob], initial_name)
        result.update({"chat_id": group_id, "initial_name": initial_name})

        open_group(device_a, args.adb, args.device_a, args.package, initial_name)
        open_group(device_b, args.adb, args.device_b, args.package, initial_name)
        _, evidence_a = snapshot(device_a, run_dir, "01-alice-group-open")
        _, evidence_b = snapshot(device_b, run_dir, "01-bob-group-open")
        result["evidence"] += evidence_a + evidence_b

        text_a = f"GROUP_A_{stamp}"
        text_b = f"GROUP_B_{stamp}"
        send_text(api, alice, group_id, text_a)
        send_text(api, bob, group_id, text_b)
        xml_a = wait_xml_contains(device_a, [text_a, text_b])
        xml_b = wait_xml_contains(device_b, [text_a, text_b])
        realtime_messages = all(
            marker in xml
            for xml in (xml_a, xml_b)
            for marker in (text_a, text_b)
        )
        result["checks"]["two_way_realtime_messages"] = realtime_messages
        _, evidence_a = snapshot(device_a, run_dir, "02-alice-two-way-messages")
        _, evidence_b = snapshot(device_b, run_dir, "02-bob-two-way-messages")
        result["evidence"] += evidence_a + evidence_b

        renamed = f"LOCAL_RENAMED_{stamp}"
        api.request("PUT", f"/chat/{group_id}", actor=alice, body={"name": renamed})
        rename_a = wait_xml_contains(device_a, [renamed])
        rename_b = wait_xml_contains(device_b, [renamed])
        rename_synced = renamed in rename_a and renamed in rename_b
        result["checks"]["rename_realtime_both_devices"] = rename_synced

        announcement_text = f"LOCAL_NOTICE_{stamp}"
        announcement = response_data(
            api.request(
                "POST",
                f"/chat/{group_id}/announcements",
                actor=alice,
                body={"content": announcement_text},
            )
        )
        result["announcement_id"] = int(announcement.get("id", 0)) if isinstance(announcement, dict) else 0
        announcement_a = wait_xml_contains(device_a, [announcement_text])
        announcement_b = wait_xml_contains(device_b, [announcement_text])
        announcement_synced = (
            announcement_text in announcement_a and announcement_text in announcement_b
        )
        result["checks"]["announcement_realtime_both_devices"] = announcement_synced
        _, evidence_a = snapshot(device_a, run_dir, "03-alice-rename-announcement")
        _, evidence_b = snapshot(device_b, run_dir, "03-bob-rename-announcement")
        result["evidence"] += evidence_a + evidence_b

        denied = False
        try:
            send_text(api, bob, group_id, f"DENIED_ALL_{stamp}", mention_all=True)
        except Exception:
            denied = True
        api.request(
            "PUT",
            f"/chat/{group_id}/members/{bob.user_id}/role",
            actor=alice,
            body={"role": 1},
        )
        admin_marker = f"ADMIN_ALL_{stamp}"
        send_text(api, bob, group_id, admin_marker, mention_all=True)
        admin_a = wait_xml_contains(device_a, [admin_marker])
        admin_b = wait_xml_contains(device_b, [admin_marker])
        api.request(
            "PUT",
            f"/chat/{group_id}/members/{bob.user_id}/role",
            actor=alice,
            body={"role": 0},
        )
        revoked = False
        try:
            send_text(api, bob, group_id, f"REVOKED_ALL_{stamp}", mention_all=True)
        except Exception:
            revoked = True
        result["checks"]["mention_all_role_transition"] = (
            denied
            and admin_marker in admin_a
            and admin_marker in admin_b
            and revoked
        )

        api.request(
            "PUT",
            f"/chat/{group_id}",
            actor=alice,
            body={"can_send_message": False},
        )
        muted_denied = False
        try:
            send_text(api, bob, group_id, f"MUTED_DENIED_{stamp}")
        except Exception:
            muted_denied = True
        owner_marker = f"OWNER_ALLOWED_{stamp}"
        send_text(api, alice, group_id, owner_marker)
        owner_a = wait_xml_contains(device_a, [owner_marker])
        owner_b = wait_xml_contains(device_b, [owner_marker])
        api.request(
            "PUT",
            f"/chat/{group_id}",
            actor=alice,
            body={"can_send_message": True},
        )
        result["checks"]["all_member_mute_realtime"] = (
            muted_denied and owner_marker in owner_a and owner_marker in owner_b
        )

        before_dissolve = f"BEFORE_DISSOLVE_{stamp}"
        send_text(api, bob, group_id, before_dissolve)
        wait_xml_contains(device_a, [before_dissolve])
        wait_xml_contains(device_b, [before_dissolve])
        api.request("DELETE", f"/chat/{group_id}", actor=alice)
        time.sleep(4)
        dissolved_a = html.unescape(device_a.dump_hierarchy())
        dissolved_b = html.unescape(device_b.dump_hierarchy())
        history_retained = all(
            before_dissolve in xml for xml in (dissolved_a, dissolved_b)
        )
        send_rejected = False
        try:
            send_text(api, bob, group_id, f"AFTER_DISSOLVE_{stamp}")
        except Exception:
            send_rejected = True
        result["checks"]["dissolve_terminal_and_history"] = (
            history_retained and send_rejected
        )
        _, evidence_a = snapshot(device_a, run_dir, "04-alice-dissolved")
        _, evidence_b = snapshot(device_b, run_dir, "04-bob-dissolved")
        result["evidence"] += evidence_a + evidence_b

        fatal_a = app_fatal_lines(args.adb, args.device_a, args.package)
        fatal_b = app_fatal_lines(args.adb, args.device_b, args.package)
        result["fatal_lines"] = {
            args.device_a: fatal_a,
            args.device_b: fatal_b,
        }
        result["checks"]["fatal_anr_flutter_error_zero"] = not fatal_a and not fatal_b
        result["status"] = (
            "PASS" if all(result["checks"].values()) else "FAIL"
        )
    except Exception as error:  # noqa: BLE001
        result["error_type"] = type(error).__name__
        result["error"] = str(error)
    finally:
        result_path = run_dir / "case-result.json"
        result["result_path"] = str(result_path)
        result_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))

    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
